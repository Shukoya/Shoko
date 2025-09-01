# frozen_string_literal: true

require_relative 'base_service'

module EbookReader
  module Domain
    module Services
      # Terminal interaction service for mouse and rendering coordination
      class TerminalService < BaseService
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
          Terminal.setup
        end

        def cleanup
          Terminal.cleanup
        end

        def start_frame
          Terminal.start_frame
        end

        def read_key_blocking
          Terminal.read_key_blocking
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