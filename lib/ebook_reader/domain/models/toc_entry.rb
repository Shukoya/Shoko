# frozen_string_literal: true

module EbookReader
  module Domain
    module Models
      # Represents a Table-of-Contents entry.
      TOCEntry = Struct.new(:title, :href, :level, :chapter_index, :navigable, keyword_init: true) do
        def initialize(title:, href:, level:, chapter_index: nil, navigable: true)
          super
        end
      end
    end
  end
end
