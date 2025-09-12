# frozen_string_literal: true

require_relative 'base_service'

module EbookReader
  module Domain
    module Services
      # Terminal interaction service for mouse and rendering coordination
      class TerminalService < BaseService
        # Maintain a global session depth so nested setup/cleanup calls
        # (e.g., menu -> reader) don't flicker or drop to shell.
        class << self
          attr_accessor :session_depth
        end
        @session_depth = 0

        def enable_mouse
          Terminal.enable_mouse
        end

        def disable_mouse
          Terminal.disable_mouse
        end

        def read_input_with_mouse
          Terminal.read_input_with_mouse
        end

        def read_key
          Terminal.read_key
        end

        def size
          Terminal.size
        end

        def end_frame
          Terminal.end_frame
        end

        def setup
          sd = TerminalService.session_depth || 0
          sd += 1
          TerminalService.session_depth = sd
          return if sd > 1

          Terminal.setup
        end

        def cleanup
          sd = TerminalService.session_depth
          if sd && sd.positive?
            sd -= 1
            TerminalService.session_depth = sd
          end
          return if sd&.positive?

          Terminal.cleanup
        end

        def start_frame
          Terminal.start_frame
        end

        def read_key_blocking
          Terminal.read_key_blocking
        end

        # Read one blocking key, then drain a few non-blocking extras.
        # Returns an array of keys, or [] if nothing was read.
        #
        # @param limit [Integer] maximum total keys to return
        # @return [Array<String>]
        def read_keys_blocking(limit: 10)
          first = read_key_blocking
          return [] unless first

          keys = [first]
          while (extra = read_key)
            keys << extra
            break if keys.size >= limit
          end
          keys
        end

        # Create a surface for component rendering
        def create_surface
          Components::Surface.new(Terminal)
        end

        protected

        def required_dependencies
          [] # No dependencies required
        end
      end
    end
  end
end
