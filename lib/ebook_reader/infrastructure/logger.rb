# frozen_string_literal: true

require 'json'
require 'time'

module EbookReader
  module Infrastructure
    # Centralized logging system for the EPUB Reader application.
    # Provides structured logging with different severity levels and
    # contextual information for debugging and monitoring.
    #
    # @example Basic usage
    #   Logger.info("Application started")
    #   Logger.error("Failed to parse EPUB", error: e, path: epub_path)
    #
    # @example With context
    #   Logger.with_context(user_id: 123) do
    #     Logger.info("Opening book", book_id: 456)
    #   end
    class Logger
      LEVELS = {
        debug: 0,
        info: 1,
        warn: 2,
        error: 3,
        fatal: 4,
      }.freeze

      class << self
        # Current logging level (default: info)
        attr_accessor :level

        # Output destination (default: STDERR)
        attr_accessor :output

        # Thread-local context storage
        def context
          Thread.current[:logger_context] ||= {}
        end

        # Add context for a block of code
        #
        # @param ctx [Hash] Context to add
        # @yield Block to execute with added context
        def with_context(ctx)
          old_context = context.dup
          context.merge!(ctx)
          yield
        ensure
          Thread.current[:logger_context] = old_context
        end

        # Log at debug level
        #
        # @param message [String] Log message
        # @param metadata [Hash] Additional metadata
        def debug(message, **metadata)
          log(:debug, message, metadata)
        end

        # Log at info level
        #
        # @param message [String] Log message
        # @param metadata [Hash] Additional metadata
        def info(message, **metadata)
          log(:info, message, metadata)
        end

        # Log at warn level
        #
        # @param message [String] Log message
        # @param metadata [Hash] Additional metadata
        def warn(message, **metadata)
          log(:warn, message, metadata)
        end

        # Log at error level
        #
        # @param message [String] Log message
        # @param metadata [Hash] Additional metadata
        def error(message, **metadata)
          log(:error, message, metadata)
        end

        # Log at fatal level
        #
        # @param message [String] Log message
        # @param metadata [Hash] Additional metadata
        def fatal(message, **metadata)
          log(:fatal, message, metadata)
        end

        private

        def log(severity, message, metadata)
          return if LEVELS[severity] < LEVELS[@level || :info]

          entry = build_log_entry(severity, message, metadata)
          (@output || $stderr).puts(entry)
        rescue StandardError
          # Logging should never crash the application
        end

        def build_log_entry(severity, message, metadata)
          {
            timestamp: Time.now.iso8601,
            severity: severity.upcase,
            message: normalize_string(message),
            context: sanitize_payload(context),
            metadata: sanitize_payload(metadata),
            thread_id: Thread.current.object_id,
          }.to_json
        end

        def sanitize_payload(value)
          case value
          when String
            normalize_string(value)
          when Hash
            value.each_with_object({}) do |(key, val), acc|
              safe_key = key.is_a?(String) ? normalize_string(key) : key
              acc[safe_key] = sanitize_payload(val)
            end
          when Array
            value.map { |item| sanitize_payload(item) }
          else
            value
          end
        end

        def normalize_string(value)
          str = value.to_s
          return str if str.encoding == Encoding::UTF_8 && str.valid_encoding?

          str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '?')
        rescue StandardError
          value.to_s
        end

        # Clear logger state (used in tests)
        def clear
          @output = nil
          @level = nil
          Thread.current[:logger_context] = {}
        end
        public :clear
      end
    end
  end
end
