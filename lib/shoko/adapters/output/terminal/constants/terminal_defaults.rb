# frozen_string_literal: true

module Shoko
  module Adapters::Output::Terminal
    # Default terminal dimensions used when IO.console is unavailable.
    module TerminalDefaults
      DEFAULT_ROWS = 24
      DEFAULT_COLUMNS = 80
    end
  end
end
