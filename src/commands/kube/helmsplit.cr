module Crux::Commands
  class Helmsplit < Kube
    class HelmsplitError < Exception
    end

    def setup : Nil
      @name = "helmsplit"
      @summary = "render a helm chart and split YAML manifests into one file per object"
      @description = <<-DESC
        Renders a Helm chart and splits the resulting multi-doc output into separate local files.

        Outputs one valid YAML manifest file per detected K8s object.
        DESC

      add_usage "crux kube helmsplit <outdir> <chart> [options]"
      add_usage ""
      add_usage "EXAMPLES"
      add_usage "crux kube helmsplit . jetstack/cert-manager -v 1.20"
      add_usage "crux kube helmsplit . jetstack/cert-manager -v 1.20 -f base.yaml -f prod.yaml -p cm"

      add_argument "outdir", description: "path to save generated output files", required: true
      add_argument "chart", description: "chart reference (repo/chart), or path to local chart", required: true

      add_option 'f', "file", description: "path to values file passed through to helm", type: :multiple, default: [] of String
      add_option 'p', "prefix", description: "custom prefix added to each output filename", type: :single
      add_option 'v', "version", description: "helm chart version to use", type: :single
    end

    def pre_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      if options.has? "help"
        stdout.puts help_template
        exit_program 0
      end
      @debug = true if options.has? "debug"
      Colorize.enabled = false if options.has? "no-color"

      # fail early if helm is not installed
      unless Process.find_executable("helm")
        error "'helm' executable not found on PATH"
        error "Install helm and try again"
        exit_program 1
      end
    end

    def run(arguments : Cling::Arguments, options : Cling::Options) : Nil
      outdir = arguments.get("outdir").as_s
      chart = resolve_chart(arguments.get("chart").as_s)
      prefix = options.get?("prefix").try(&.as_s?)
      version = options.get?("version").try(&.as_s?)
      values = options.get?("file").try(&.as_a) || [] of String

      rendered = render_chart(chart, version, values)
      rendered = sanitize_rendered(rendered)

      processor = Ysplit::YsplitProcessor.new(outdir, prefix)
      result = processor.process(rendered, stdout, stderr)

      count_label = result[:written] == 1 ? "1 file" : "#{result[:written]} files"
      info "#{"Complete:".colorize.bold.green} #{count_label} written, #{result[:skipped]} skipped."
    rescue ex : HelmsplitError
      error "#{"Helm Error:".colorize.bold}"
      error "\t#{ex.message}"
      exit_program 1
    end

    def post_run(arguments : Cling::Arguments, options : Cling::Options) : Nil
    end

    # Renders a helm chart via `helm template` and returns the rendered manifest as a String.
    # Raises HelmsplitError on non-zero exit.
    private def render_chart(chart : String, version : String?, values : Array(String)) : String
      args = ["template", chart, "--include-crds"]
      args.concat(["--version", version]) if version
      values.each { |v| args << "--values=#{v}" }

      stdout_io = IO::Memory.new
      stderr_io = IO::Memory.new
      status = Process.run("helm", args, output: stdout_io, error: stderr_io)
      unless status.success?
        raise HelmsplitError.new("helm template failed with exit code #{status.exit_code}:\n#{stderr_io.to_s.strip}")
      end
      stdout_io.to_s
    end

    # Returns the chart reference to pass to helm as either an expanded local path or the original 'repo/chart' string.
    # Increases confidence that the user-submitted string is a valid local chart path before deferring to remote resolution.
    # Used to reduce confusing errors or misinterpretations between chart path vs 'repo/chart' collisions
    private def resolve_chart(chart : String) : String
      looks_local = chart.starts_with?('.') || chart.starts_with?('/') || chart.starts_with?('~')
      expanded = File.expand_path(chart)

      if File.directory?(expanded)
        unless File.file?(File.join(expanded, "Chart.yaml"))
          raise HelmsplitError.new("Missing Chart.yaml, not a helm chart: #{chart}")
        end
        expanded
      elsif looks_local
        raise HelmsplitError.new("Chart path not found: #{chart}")
      else
        chart
      end
    end

    # Substrings to remove from YAML output to clean up release-name prefixes
    YAML_PRUNE_SUBSTRINGS = [
      "RELEASE-NAME-",
      "release-name-",
      # "release-name:",
      # "RELEASE-NAME:",
    ]

    # Tokens which when matched will drop entire lines from YAML output to clean up lingering helm release-name prefixes
    YAML_DROP_LINE_TOKENS = [
      # "RELEASE-NAME",
      "helm",
      "Helm",
      "# Source",
      # "chart: ",
      "release-name",
    ]

    # Applies two passes, in order:
    #   1. Strip every YAML_PRUNE_SUBSTRINGS token from the body of YAML output
    #   2. Drop any line containing any YAML_DROP_LINE_TOKENS token
    #
    # Returns sanitized YAML output
    private def sanitize_rendered(rendered : String) : String
      pruned = YAML_PRUNE_SUBSTRINGS.reduce(rendered) { |acc, substr| acc.gsub(substr, "") }
      pruned.split('\n').reject do |line|
        YAML_DROP_LINE_TOKENS.any? do |token|
          line.includes?(token)
        end
      end.join('\n')
    end
  end
end
