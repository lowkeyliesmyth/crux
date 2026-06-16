require "http/client"
require "socket"
require "uri"

module Crux::Commands
  class Ysplit < Kube
    # Base domain exception
    class YsplitError < Exception
      # Just use standard YAML::ParseException when YAML parsing fails.
    end

    #
    def setup : Nil
      @name = "ysplit"
      @summary = "split multi-doc YAML manifests into one file per object"
      @description = <<-DESC
        Splits multi-document Kubernetes YAML manifests into multiple separate local files.
        Outputs one valid YAML manifest file per detected K8s object.
        DESC

      add_usage "crux kube ysplit <outdir> [options]"
      add_usage ""
      add_usage "EXAMPLES"
      add_usage "crux kube ysplit . -f megafile.yaml"
      add_usage "crux kube ysplit ~/Desktop -r https://example.com/somefiles.yaml"

      add_argument "outdir", description: "path to save generated output files", required: true

      add_option 'f', "file", description: "the local path to a source YAML mega-manifest file", type: :single
      add_option 'p', "prefix", description: "custom prefix added to each output filename", type: :single
      add_option 'r', "remote", description: "the HTTP/S URL to fetch a remote YAML manifest from", type: :single
    end

    def command_pre_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      # Handle the required but mutual-exclusivity of file and remote options early
      has_file = options.has?("file")
      has_remote = options.has?("remote")

      if has_file && has_remote
        error "Options are mutually exclusive:"
        error "\t#{"-f|--file".colorize.red} and #{"-r|--remote".colorize.red}"
        error "See #{"'crux kube ysplit --help'".colorize.blue.bold} for more help \n"
        exit_program 1
      end

      unless has_file || has_remote
        error "Missing required option:"
        error "\t#{"-f|--file".colorize.red} or #{"-r|--remote".colorize.red}"
        error "See #{"'crux kube ysplit --help'".colorize.blue.bold} for more help \n"
        exit_program 1
      end
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      outdir = arguments.get("outdir").as_s
      prefix = options.get?("prefix").try(&.as_s?)
      path = options.get?("file").try(&.as_s?)
      remote = options.get?("remote").try(&.as_s?)

      content = if path
                  read_local_file(path)
                elsif remote
                  url = URI.parse(remote)
                  validate_yaml_url(url)

                  fetch_remote(url)
                else
                  exit_program 1
                end
      processor = Crux::Kube::ManifestSplitter.new(outdir, prefix)
      result = processor.process(content, stdout, stderr)

      write_provenance(outdir, path, remote, prefix)
      count_label = result[:written] == 1 ? "1 file" : "#{result[:written]} files"
      info "#{"Complete:".colorize.bold.green} #{count_label} written, #{result[:skipped]} skipped."
    rescue ex : YsplitError
      error "#{"Processing Error:".colorize.bold}"
      error "\t#{ex.message}"
      exit_program 1
    end

    def post_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
    end

    # Validate that the user-provided URL is an HTTPS endpoint and likely contains YAML
    # Returns string if valid, raises YsplitError if invalid.
    def validate_yaml_url(url : URI) : String
      if url.scheme == "https" &&
         url.host &&
         (["yaml", "yml"].includes?(url.path.split(".").last.downcase))
        url.to_s
      else
        raise YsplitError.new("'#{url.to_s.colorize.red}' is not a valid HTTPS url containing YAML")
      end
    end

    # Resolve remote `host` to IP address to prevent SSRF or DNS rebinding.
    #
    # Written as a seam so tests can mock host resolution without calling out.
    protected def resolve_host(host : String) : Array(Socket::IPAddress)
      Socket::Addrinfo.resolve(host, "http", type: Socket::Type::STREAM).map(&.ip_address)
    end

    # Checks if IPs are on an exclusion list (loopback, link-local, unspecified) that shouldn't be reached.
    #
    # Returns true if the IP is on the exclusion list, otherwise false.
    protected def disallowed_ip?(ip : Socket::IPAddress) : Bool
      ip.loopback? || ip.link_local? || ip.unspecified?
    end

    # Resolves the URL host to IP and rejects addresses that are on the exclusion list.
    protected def validate_url_dest(url : URI) : Nil
      host = url.host
      raise YsplitError.new("'#{url}' has no host defined") unless host

      ips = resolve_host(host)
      raise YsplitError.new("Could not resolve host: '#{host}'") if ips.empty?

      if disallowed = ips.find { |ip| disallowed_ip?(ip) }
        raise YsplitError.new("#{host} resolves to disallowed address (loopback, link-local, or unspecified): #{disallowed}")
      end
    end

    # Reads YAML content from a local file path (supports ~/ homedir expansion), streaming with MAX_BYTES enforced during read.
    #
    # Returns the file contents as a String.
    protected def read_local_file(path : String) : String
      expanded = File.expand_path(path)
      File.open(expanded) do |io|
        sink = IO::Memory.new
        copied = IO.copy(io, sink, MAX_BYTES + 1)
        if copied > MAX_BYTES
          raise YsplitError.new("File '#{path}' exceeds #{MAX_BYTES // 1024 // 1024}MB limit")
        end
        sink.to_s
      end
    rescue ex : YsplitError
      raise ex
    rescue File::NotFoundError
      error "File not found: #{path}"
      exit_program 1
    rescue ex : Exception
      error "Could not read file: '#{path}': #{ex.message}"
      exit_program 1
    end

    # Max response body size in MB
    # Manifest retrieval from remote URLs rarely exceeds a few MB. Bound the request size with sufficient headroom while guarding against crazy large responses.
    MAX_BYTES = 50 * 1024 * 1024

    # Required for retrieval from Github Releases, which use redirects.
    # Guard against processing too many redirects causing infinite loops.
    MAX_REDIRECTS = 5

    # HTTP timeouts to prevent hanging on slow or unreachable servers.
    HTTP_CONN_TIMEOUT = 10.seconds
    HTTP_READ_TIMEOUT = 30.seconds

    # Ceiling on response body shown during debugging
    MAX_DEBUG_BODY_BYTES = 256

    # Fetches YAML content from a remote HTTPS URL.
    # Validates dest IP and follows up to MAX_REDIRECTS redirects (3xx in header).
    # Streams up to MAX_BYTES size limit on the response body.
    # Returns the HTTP response body.
    # Exits with an error on network failure, non-2XX status code, disallowed destination, or exceeded limits.
    protected def fetch_remote(url : URI, redirects_remaining : Int32 = MAX_REDIRECTS) : String # ameba:disable Metrics/CyclomaticComplexity

      validate_url_dest(url)

      client = HTTP::Client.new(url)
      client.connect_timeout = HTTP_CONN_TIMEOUT
      client.read_timeout = HTTP_READ_TIMEOUT

      result : String? = nil
      redirect_uri : URI? = nil

      client.get(url.request_target) do |resp|
        if resp.status.redirection?
          location = resp.headers["Location"]?
          unless location
            raise YsplitError.new("HTTP #{resp.status_code}: Redirect with no Location header from '#{url}'")
          end
          parsed = URI.parse(location)
          redirect_uri = parsed.absolute? ? parsed : url.resolve(parsed)
        elsif resp.success?
          # Annoyingly, fall back to body wrapped in an io for Webmock, since it doesn't support body_io
          # Real clients will use body_io, but this is semantically equivalent for testing
          io = resp.body_io? || IO::Memory.new(resp.body)
          sink = IO::Memory.new
          copied = IO.copy(io, sink, MAX_BYTES + 1)
          if copied > MAX_BYTES
            raise YsplitError.new("Response body exceeds #{MAX_BYTES / 1024 / 1024}MB limit")
          end
          result = sink.to_s
        else
          # Drain a small slice of the body for debug only diagnostics
          io = resp.body_io? || IO::Memory.new(resp.body)
          sink = IO::Memory.new
          IO.copy(io, sink, MAX_DEBUG_BODY_BYTES + 1)
          debug "HTTP #{resp.status_code} truncated to #{MAX_DEBUG_BODY_BYTES}B: #{sink}"
          raise YsplitError.new("HTTP #{resp.status_code} from '#{url}'")
        end
      end

      if redirect = redirect_uri
        raise YsplitError.new("Max #{MAX_REDIRECTS} redirects exceeded: Redirect loop detected") if redirects_remaining <= 0
        validate_yaml_url(redirect)
        return fetch_remote(redirect, redirects_remaining - 1)
      end

      # ameba:disable Lint/NotNil
      result.not_nil!
    rescue ex : YsplitError
      raise ex
    rescue ex : Exception
      raise YsplitError.new("Network error fetching '#{url}': #{ex.message}")
    end

    private def write_provenance(outdir : String, path : String?, url : String?, prefix : String?)
      # parts = ["crux kube helmsplit <OUTDIR>", chart]
      parts = ["crux kube ysplit", outdir]
      parts << "-f #{path}" if path
      parts << "-r #{url}" if url
      parts << "-p #{prefix}" if prefix
      command = parts.join(' ')

      content = <<-MD
      ### AUTOGENERATED BY crux
      ```sh
      #{command}
      ```
      MD

      File.write("#{outdir}/_PROVENANCE.md", content)
    end
  end
end
