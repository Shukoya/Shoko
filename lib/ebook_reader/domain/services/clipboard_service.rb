# frozen_string_literal: true

require_relative 'base_service'
require 'English'

module EbookReader
  module Domain
    module Services
      # Domain service for clipboard operations with dependency injection.
      # Migrated from legacy Services::ClipboardService to follow DI pattern.
      class ClipboardService < BaseService
        # Error raised when clipboard operations fail
        class ClipboardError < StandardError; end

        # Copy text to system clipboard
        def copy_text?(text)
          return false if text.nil? || text.strip.empty?

          command = detect_clipboard_command
          return false unless command

          success = execute_clipboard_command(command, text)

          if success
            log_success(text.length)
            true
          else
            log_failure
            false
          end
        end

        # Copy text with user feedback
        def copy_with_feedback(text)
          if copy_text?(text)
            yield(' Copied to clipboard!') if block_given?
            true
          else
            yield(' Failed to copy to clipboard') if block_given?
            false
          end
        rescue ClipboardError => e
          yield(" Copy failed: #{e.message}") if block_given?
          false
        end

        # Check if clipboard functionality is available
        def available?
          !detect_clipboard_command.nil?
        end

        private

        def detect_clipboard_command
          case RUBY_PLATFORM
          when /darwin/
            command_exists?('pbcopy') ? 'pbcopy' : nil
          when /linux/
            if command_exists?('xclip')
              'xclip -selection clipboard'
            elsif command_exists?('xsel')
              'xsel --clipboard --input'
            elsif command_exists?('wl-copy')
              'wl-copy'
            end
          when /mswin|mingw|cygwin/
            'clip'
          end
        end

        def command_exists?(command)
          system("which #{command} > /dev/null 2>&1")
        end

        def execute_clipboard_command(command, text)
          IO.popen(command, 'w') do |pipe|
            pipe.write(text)
          end
          $CHILD_STATUS.success?
        rescue Errno::ENOENT, Errno::EPIPE
          false
        end

        def log_success(char_count)
          return unless registered?(:logger)

          resolve(:logger).info('Text copied to clipboard', chars: char_count)
        end

        def log_failure
          return unless registered?(:logger)

          resolve(:logger).warn('Failed to copy text to clipboard')
        end

        protected

        def required_dependencies
          [] # Logger is optional
        end
      end
    end
  end
end
