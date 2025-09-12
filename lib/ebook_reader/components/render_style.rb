# frozen_string_literal: true

module EbookReader
  module Components
    # Small helper for composing styled strings and common UI elements.
    module RenderStyle
      module_function

      def primary(text)
        EbookReader::Constants::UIConstants::COLOR_TEXT_PRIMARY + text.to_s + Terminal::ANSI::RESET
      end

      def accent(text)
        EbookReader::Constants::UIConstants::COLOR_TEXT_ACCENT + text.to_s + Terminal::ANSI::RESET
      end

      def dim(text)
        EbookReader::Constants::UIConstants::COLOR_TEXT_DIM + text.to_s + Terminal::ANSI::RESET
      end

      def selection_pointer
        EbookReader::Constants::UIConstants::SELECTION_POINTER
      end

      def selection_pointer_colored
        EbookReader::Constants::UIConstants::SELECTION_POINTER_COLOR + selection_pointer + Terminal::ANSI::RESET
      end
    end
  end
end
