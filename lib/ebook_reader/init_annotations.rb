# frozen_string_literal: true

# Initialize annotation support for mouse-driven annotations.
# Mouse helpers are available via Terminal facade; MouseableReader is
# already the default Reader as defined in reader.rb. This file remains
# to preserve require order and avoid breaking existing requires.

require_relative 'terminal_mouse_patch'
require_relative 'mouseable_reader'
