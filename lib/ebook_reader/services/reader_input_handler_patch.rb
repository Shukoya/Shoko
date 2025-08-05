# Patch to add annotation shortcuts
module EbookReader
  module Services
    class ReaderInputHandler
      alias_method :reading_input_handlers_original, :reading_input_handlers

      def reading_input_handlers
        handlers = reading_input_handlers_original
        handlers.merge!({
          'a' => -> { @reader.switch_mode(:annotations) },
          'A' => -> { @reader.switch_mode(:annotations) }
        })
        handlers
      end

      def handle_annotations_mode(key)
        mode = @reader.instance_variable_get(:@current_mode)
        mode&.handle_input(key)
      end

      def handle_annotation_editor_mode(key)
        mode = @reader.instance_variable_get(:@current_mode)
        mode&.handle_input(key)
      end
    end
  end
end
