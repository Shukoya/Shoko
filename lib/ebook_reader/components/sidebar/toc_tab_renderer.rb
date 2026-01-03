# frozen_string_literal: true

require_relative '../base_component'
require_relative 'toc_tab_support'

module EbookReader
  module Components
    module Sidebar
      # TOC tab renderer for sidebar
      class TocTabRenderer < BaseComponent
        include Constants::UIConstants

        NullSurface = Struct.new(:_noop) do
          def write(*_args); end
        end
        private_constant :NullSurface

        def initialize(state, dependencies = nil)
          super()
          @state = state
          @dependencies = dependencies
          @wrap_cache = {}
          @cache_document_id = nil
        end

        def do_render(surface, bounds)
          doc = document
          refresh_wrap_cache(doc)
          context = RenderContext.new(surface, bounds, @state, doc, wrap_cache: @wrap_cache)
          @last_bounds_signature = bounds_signature(bounds)
          @last_scroll_metrics = context.scroll_metrics
          ComponentOrchestrator.new(context).render
        end

        def entry_at(bounds, col, row)
          return nil unless bounds

          local_row = row.to_i - bounds.y + 1
          local_col = col.to_i - bounds.x + 1
          return nil unless local_row.between?(1, bounds.height)
          return nil unless local_col.between?(1, bounds.width)

          doc = document
          refresh_wrap_cache(doc)
          context = RenderContext.new(NullSurface.new, bounds, @state, doc, wrap_cache: @wrap_cache)
          context.entries_layout.item_at(local_row)
        end

        def scroll_metrics(bounds)
          return nil unless bounds

          signature = bounds_signature(bounds)
          if @last_scroll_metrics && @last_bounds_signature == signature
            return @last_scroll_metrics
          end

          doc = document
          refresh_wrap_cache(doc)
          context = RenderContext.new(NullSurface.new, bounds, @state, doc, wrap_cache: @wrap_cache)
          @last_bounds_signature = signature
          @last_scroll_metrics = context.scroll_metrics
        end

        private

        def document
          @document ||= DocumentResolver.new(@dependencies).resolve
        end

        def bounds_signature(bounds)
          [bounds.x, bounds.y, bounds.width, bounds.height]
        end

        def refresh_wrap_cache(doc)
          doc_id = doc&.object_id
          return if doc_id == @cache_document_id

          @cache_document_id = doc_id
          @wrap_cache.clear
        end
      end
    end
  end
end
