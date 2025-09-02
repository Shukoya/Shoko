# frozen_string_literal: true

module EbookReader
  module Domain
    module Models
      # Data object for adding bookmarks
      BookmarkData = Struct.new(:path, :chapter, :line_offset, :text, keyword_init: true)
    end
  end
end
