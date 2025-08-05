# frozen_string_literal: true

# Monkey patch to add mouse support to Reader
require_relative 'annotations/mouse_handler'
require_relative 'annotations/annotation_store'
require_relative 'ui/components/popup_menu'
require_relative 'reader_modes/annotation_editor_mode'
require_relative 'reader_modes/annotations_mode'
require_relative 'terminal_mouse_patch'
require_relative 'reader_mouse_extension'

module EbookReader
  class Reader
    include ReaderMouseExtension

    # Override switch_mode to support annotation modes
    alias_method :switch_mode_original, :switch_mode
    def switch_mode(mode, **options)
      case mode
      when :annotation_editor
        @mode = :annotation_editor
        @current_mode = ReaderModes::AnnotationEditorMode.new(self, **options)
      when :annotations
        @mode = :annotations
        @current_mode = ReaderModes::AnnotationsMode.new(self)
      else
        switch_mode_original(mode)
      end
    end

    # Override run to enable mouse
    alias_method :run_original, :run
    def run
      Terminal.enable_mouse
      run_original
    ensure
      Terminal.disable_mouse
    end

    # Override main_loop to handle mouse input
    alias_method :read_input_keys_original, :read_input_keys
    def read_input_keys
      key = Terminal.read_input_with_mouse
      return [] unless key

      # Check if it's a mouse event
      if key.start_with?("\e[<")
        handle_mouse_input(key)
        return [] # Don't process mouse events as keyboard input
      end

      keys = [key]
      while (extra = Terminal.read_key)
        keys << extra
        break if keys.size > 10
      end
      keys
    end
  end
end
