# frozen_string_literal: true

require 'optparse'
require 'fileutils'

module EbookReader
  # The command-line interface for the Ebook Reader application.
  class CLI
    class << self
      def run(argv = ARGV)
        options, args = parse_options(argv)
        setup_logger(options)

        Application::UnifiedApplication.new(args.first).run
      end

      private

      def parse_options(argv)
        options = default_options
        parser = OptionParser.new
        configure_parser(parser, options)
        parser.parse!(argv)
        [options, argv]
      end

      def default_options
        { debug: false, log_path: nil, log_level: nil }
      end

      def configure_parser(parser, options)
        parser.banner = 'Usage: ebook_reader [options] [file]'
        parser.on('-d', '--debug', 'Enable debug logging') { options[:debug] = true }
        parser.on('--log PATH', 'Write JSON logs to PATH instead of discarding output') do |path|
          options[:log_path] = path
        end
        parser.on('--log-level LEVEL', 'Set log level (debug, info, warn, error, fatal)') do |level|
          options[:log_level] = level
        end
        parser.on('-h', '--help', 'Prints this help') do
          puts parser
          exit
        end
      end

      def setup_logger(options)
        debug = debug_enabled?(options)
        log_path = options[:log_path] || env_log_path
        log_level = options[:log_level] || env_log_level

        output, log_file = logger_output(debug, log_path)
        Infrastructure::Logger.output = output
        Infrastructure::Logger.level = logger_level(debug, log_level)

        at_exit do
          next unless log_file && !log_file.closed?

          begin
            log_file.close
          rescue StandardError
            # ignore close errors on shutdown
          end
        end
      end

      def logger_output(debug, log_path)
        return [$stdout, nil] if debug

        path = log_path.to_s.strip
        return [File.open(File::NULL, 'w'), nil] if path.empty?

        ensure_log_directory(path)
        file = File.open(path, 'a')
        file.sync = true
        [file, file]
      rescue StandardError
        [File.open(File::NULL, 'w'), nil]
      end

      def ensure_log_directory(path)
        FileUtils.mkdir_p(File.dirname(path))
      rescue StandardError
        # best effort; fall back to File::NULL if mkdir fails later
      end

      def logger_level(debug, configured_level)
        return :debug if debug

        normalize_log_level(configured_level) || :error
      end

      def normalize_log_level(level)
        value = level.to_s.strip.downcase
        return nil if value.empty?

        %w[debug info warn error fatal].include?(value) ? value.to_sym : nil
      end

      def debug_enabled?(options)
        return true if options[:debug]

        raw = ENV.fetch('DEBUG', nil)
        return false if raw.nil?

        value = raw.to_s.strip.downcase
        %w[0 false off no].exclude?(value)
      end

      def env_log_path
        ENV.fetch('READER_LOG_PATH', '').strip
      end

      def env_log_level
        ENV.fetch('READER_LOG_LEVEL', '').strip
      end
    end
  end
end
