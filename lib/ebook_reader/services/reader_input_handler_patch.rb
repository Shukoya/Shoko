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
    end
  end
end
