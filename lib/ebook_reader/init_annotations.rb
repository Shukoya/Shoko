# frozen_string_literal: true

# Initialize annotation support for mouse-driven annotations
# - Extend Terminal with mouse helpers
# - Prefer MouseableReader as the default Reader implementation

require_relative 'terminal_mouse_patch'
require_relative 'mouseable_reader'

module EbookReader
  # Make MouseableReader the default Reader entrypoint
  remove_const(:Reader) if const_defined?(:Reader)
  Reader = MouseableReader
end
