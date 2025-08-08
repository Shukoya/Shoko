# frozen_string_literal: true

require_relative 'reader_controller'
require_relative 'reader_view' # Ensure view class is loaded

module EbookReader
  # Backwards compatibility alias for the former Reader class.
  Reader = ReaderController
end
