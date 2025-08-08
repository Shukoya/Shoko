# frozen_string_literal: true

module EbookReader
  module Rendering
    # Cache for rendered regions with dirty tracking
    class RenderCache
      def initialize
        @cache = {}
        @dirty_regions = Set.new
        @last_content_hash = {}
      end

      # Retrieve cached region by id and hash, or render via block.
      # @param region_id [Symbol]
      # @param content_hash [Object]
      def get_or_render(region_id, content_hash)
        if @cache[region_id] && @last_content_hash[region_id] == content_hash &&
           !@dirty_regions.include?(region_id)
          return @cache[region_id]
        end

        rendered = yield
        @cache[region_id] = rendered
        @last_content_hash[region_id] = content_hash
        @dirty_regions.delete(region_id)
        rendered
      end

      # Mark a region as dirty forcing redraw
      def mark_dirty(region_id)
        @dirty_regions.add(region_id)
      end

      # Mark all regions as dirty
      def mark_all_dirty
        @dirty_regions.merge(@cache.keys)
      end
    end
  end
end
