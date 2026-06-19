module Crux::Git
  # Raised when the inputs to a conventional commit are invalid.
  class CommitError < Exception
  end

  # A validated conventional-commit message.
  #
  # Holds the structured pieces (type, scope, subject, body, breaking change,
  # optional ticket) and renders them into the canonical text form:
  #
  #   <type>(<scope>)!: <TICKET> <subject>
  #
  #   <body>
  #
  #   BREAKING CHANGE: <description>
  #
  # The struct is pure and deterministic: all interactive IO lives in the
  # command, so this is the unit that carries the test coverage.
  struct ConventionalCommit
    # The conventional-commit types crux offers by default, in prompt order.
    DEFAULT_TYPES = %w(feat fix docs style refactor perf test build ci chore revert)

    # Soft limit on the header line length, matching the common 72-column guide.
    SUBJECT_MAX = 72

    getter type : String
    getter scope : String?
    getter subject : String
    getter body : String?
    getter ticket : String?
    getter? breaking : Bool
    getter breaking_description : String?

    def initialize(
      @type : String,
      @subject : String,
      *,
      @scope : String? = nil,
      @body : String? = nil,
      @ticket : String? = nil,
      @breaking : Bool = false,
      @breaking_description : String? = nil,
    )
    end

    # Validates the structured fields.
    #
    # `allowed_types`, when non-empty, constrains the accepted type. Raises
    # CommitError describing the first problem found.
    def validate!(allowed_types : Array(String) = DEFAULT_TYPES) : Nil
      if type.strip.empty?
        raise CommitError.new("commit type is required")
      end

      unless allowed_types.empty? || allowed_types.includes?(type)
        raise CommitError.new("unknown commit type '#{type}'. Allowed: #{allowed_types.join(", ")}")
      end

      if subject.strip.empty?
        raise CommitError.new("commit subject is required")
      end

      if header_line.size > SUBJECT_MAX
        raise CommitError.new("subject line exceeds #{SUBJECT_MAX} characters (#{header_line.size})")
      end
    end

    # Renders just the first line of the commit (type/scope/ticket/subject).
    def header_line : String
      String.build do |io|
        io << type
        if s = scope
          io << '(' << s << ')' unless s.empty?
        end
        io << '!' if breaking?
        io << ": "
        if t = ticket
          io << t << ' ' unless t.empty?
        end
        io << subject.strip
      end
    end

    # Renders the full commit message including body and breaking-change footer.
    def render : String
      String.build do |io|
        io << header_line

        if b = body
          stripped = b.strip
          io << "\n\n" << stripped unless stripped.empty?
        end

        if breaking?
          description = breaking_description.try(&.strip)
          detail = description && !description.empty? ? description : subject.strip
          io << "\n\n" << "BREAKING CHANGE: " << detail
        end
      end
    end
  end
end
