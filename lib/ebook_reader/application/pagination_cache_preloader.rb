# frozen_string_literal: true

require_relative '../infrastructure/pagination_cache'

module EbookReader
  module Application
    # Centralises the logic for hydrating dynamic pagination from the cache.
    class PaginationCachePreloader
      Result = Struct.new(:status, :key, keyword_init: true)
      private_constant :Result

      def initialize(state:, page_calculator:, pagination_cache: Infrastructure::PaginationCache)
        @state = state
        @page_calculator = page_calculator
        @pagination_cache = pagination_cache
      end

      def preload(doc, width:, height:)
        return Result.new(status: :invalid) unless doc
        return Result.new(status: :unavailable) unless dynamic_mode?
        width = resolve_width(width)
        height = resolve_height(height)
        return Result.new(status: :no_calculator) unless page_calculator

        key = layout_key(width, height)
        return Result.new(status: :miss, key:) unless pagination_cache.exists_for_document?(doc, key)

        apply_layout_config(width, height)

        page_calculator.build_dynamic_map!(width, height, doc, state)
        page_calculator.apply_pending_precise_restore!(state)
        Result.new(status: :hit, key:)
      rescue StandardError => e
        log_failure(e)
        Result.new(status: :error)
      end

      private

      attr_reader :state, :page_calculator, :pagination_cache

      def resolve_width(width)
        width || state.get(%i[ui terminal_width]) || 80
      end

      def resolve_height(height)
        height || state.get(%i[ui terminal_height]) || 24
      end

      def dynamic_mode?
        EbookReader::Domain::Selectors::ConfigSelectors.page_numbering_mode(state) == :dynamic
      end

      def layout_key(width, height)
        view_mode = EbookReader::Domain::Selectors::ConfigSelectors.view_mode(state)
        line_spacing = EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(state)
        pagination_cache.layout_key(width, height, view_mode, line_spacing)
      end

      def apply_layout_config(width, height)
        if state.respond_to?(:apply_terminal_dimensions)
          state.apply_terminal_dimensions(width, height)
        elsif state.respond_to?(:update)
          state.update({ %i[ui terminal_width] => width, %i[ui terminal_height] => height })
        end
      end

      def log_failure(error)
        logger = begin
          if state.respond_to?(:resolve)
            state.resolve(:logger)
          end
        rescue StandardError
          nil
        end
        logger&.debug('PaginationCachePreloader: failed', error: error.message)
      end
    end
  end
end
