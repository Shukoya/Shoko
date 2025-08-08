# frozen_string_literal: true

require_relative 'reader_controller'
require_relative 'mouseable_reader'

module EbookReader
  # Single, authoritative Reader entrypoint for the application.
  # We expose the mouse-enabled reader implementation as the default.
  Reader = MouseableReader
end
