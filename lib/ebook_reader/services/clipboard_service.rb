# frozen_string_literal: true

require 'English'
module EbookReader
  module Services
    # Centralized clipboard functionality to eliminate the scattered
    # platform detection logic and provide consistent copy operations.
    class ClipboardService
      # Error raised when clipboard operations fail
      class ClipboardError < StandardError; end

      class << self
        # Copy text to system clipboard
        # @param text [String] Text to copy
        # @return [Boolean] True if successful, false otherwise
        # @raise [ClipboardError] If clipboard command fails
        def copy(text)
          return false if text.nil? || text.strip.empty?

          command = detect_clipboard_command
          return false unless command

          success = execute_clipboard_command(command, text)

          if success
            Infrastructure::Logger.info('Text copied to clipboard', chars: text.length)
            true
          else
            Infrastructure::Logger.warn('Failed to copy text to clipboard')
            false
          end
        rescue StandardError => e
          Infrastructure::Logger.error('Clipboard operation failed', error: e.message)
          raise ClipboardError, "Failed to copy to clipboard: #{e.message}"
        end

        # Copy text with user feedback message
        # @param text [String] Text to copy
        # @param message_handler [Proc] Optional proc to call with success message
        # @return [Boolean] True if successful
        def copy_with_feedback(text, message_handler = nil)
          success = copy(text)

          if success && message_handler
            message_handler.call('Copied to clipboard!')
          elsif success
            puts 'Copied to clipboard!' # Fallback message
          end

          success
        end

        # Test if clipboard functionality is available
        # @return [Boolean] True if clipboard commands are available
        def available?
          !detect_clipboard_command.nil?
        end

        # Get information about clipboard support
        # @return [Hash] Information about clipboard availability and command
        def info
          command = detect_clipboard_command
          {
            available: !command.nil?,
            command: command,
            platform: RUBY_PLATFORM,
          }
        end

        private

        # Detect appropriate clipboard command for current platform
        # @return [String, nil] Clipboard command or nil if unavailable
        def detect_clipboard_command
          case RUBY_PLATFORM
          when /darwin/
            'pbcopy'
          when /linux/
            detect_linux_clipboard_command
          when /mingw|mswin/
            'clip'
          end
        end

        # Detect Linux clipboard command (multiple options available)
        # @return [String, nil] Best available Linux clipboard command
        def detect_linux_clipboard_command
          # Prefer wayland clipboard if available
          return 'wl-copy' if command_available?('wl-copy')

          # Fall back to X11 clipboard
          return 'xclip -selection clipboard' if command_available?('xclip')

          # Try xsel as final option
          return 'xsel --clipboard --input' if command_available?('xsel')

          nil
        end

        # Check if a command is available on the system
        # @param command [String] Command to test
        # @return [Boolean] True if command is available
        def command_available?(command)
          cmd_name = command.split.first
          system("which #{cmd_name} > /dev/null 2>&1")
        end

        # Execute clipboard command with text
        # @param command [String] Clipboard command to execute
        # @param text [String] Text to copy
        # @return [Boolean] True if successful
        def execute_clipboard_command(command, text)
          IO.popen(command, 'w') do |io|
            io.write(text)
          end
          $CHILD_STATUS.success?
        rescue StandardError
          false
        end
      end
    end
  end
end
