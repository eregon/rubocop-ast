# encoding: utf-8

module RuboCop
  # ProcessedSource contains objects which are generated by Parser
  # and other information such as disabled lines for cops.
  # It also provides a convenient way to access source lines.
  class ProcessedSource
    attr_reader :path, :buffer, :ast, :comments, :tokens, :diagnostics,
                :parser_error

    def self.from_file(path)
      new(File.read(path), path)
    end

    def initialize(source, path = nil)
      @path = path
      @diagnostics = []
      parse(source, path)
    end

    def comment_config
      @comment_config ||= CommentConfig.new(self)
    end

    def disabled_line_ranges
      comment_config.cop_disabled_line_ranges
    end

    def lines
      if @lines
        @lines
      else
        init_lines
        @lines
      end
    end

    def raw_lines
      if @raw_lines
        @raw_lines
      else
        init_lines
        @raw_lines
      end
    end

    def [](*args)
      lines[*args]
    end

    def valid_syntax?
      return false if @parser_error
      @diagnostics.none? { |d| [:error, :fatal].include?(d.level) }
    end

    private

    def parse(source, path)
      buffer_name = path || '(string)'
      @buffer = Parser::Source::Buffer.new(buffer_name, 1)

      begin
        @buffer.source = source
      rescue Encoding::UndefinedConversionError, ArgumentError => error
        # TODO: Rescue EncodingError here once the patch in Parser is released.
        #   https://github.com/whitequark/parser/pull/156
        @parser_error = error
        return
      end

      parser = create_parser

      begin
        @ast, @comments, tokens = parser.tokenize(@buffer)
      rescue Parser::SyntaxError # rubocop:disable Lint/HandleExceptions
        # All errors are in diagnostics. No need to handle exception.
      end

      @tokens = tokens.map { |t| Token.from_parser_token(t) } if tokens
    end

    def create_parser
      Parser::CurrentRuby.new.tap do |parser|
        # On JRuby and Rubinius, there's a risk that we hang in tokenize() if we
        # don't set the all errors as fatal flag. The problem is caused by a bug
        # in Racc that is discussed in issue #93 of the whitequark/parser
        # project on GitHub.
        parser.diagnostics.all_errors_are_fatal = (RUBY_ENGINE != 'ruby')
        parser.diagnostics.ignore_warnings = false
        parser.diagnostics.consumer = lambda do |diagnostic|
          @diagnostics << diagnostic
        end
      end
    end

    def init_lines
      @raw_lines = @buffer.source.lines
      @lines = @raw_lines.map(&:chomp)
    end
  end
end
