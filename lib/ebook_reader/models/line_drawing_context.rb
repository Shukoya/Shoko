# frozen_string_literal: true

module EbookReader
  module Models
    LineDrawingContext = Struct.new(:lines, :start_offset, :end_offset, :position, :dimensions,
                                    :actual_height, keyword_init: true)
  end
end
