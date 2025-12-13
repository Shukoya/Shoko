# frozen_string_literal: true

require_relative '../infrastructure/kitty_graphics'

module EbookReader
  module Application
    # Centralises the logic for hydrating dynamic pagination from the cache.
    class PaginationCachePreloader
      Result = Struct.new(:status, :key, keyword_init: true)
      private_constant :Result

      def initialize(state:, page_calculator:, pagination_cache:)
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

        key, view_mode, line_spacing = build_layout_key(width, height)

        unless pagination_cache.exists_for_document?(doc, key)
          fallback = find_fallback_key(doc)
          return Result.new(status: :miss, key:) unless fallback

          width = fallback[:width]
          height = fallback[:height]
          view_mode = fallback[:view_mode]
          line_spacing = fallback[:line_spacing]
          key = fallback[:key]
        end

        apply_layout_config(width, height, view_mode, line_spacing)

        cached_pages = pagination_cache.load_for_document(doc, key)
        if cached_pages && cached_pages.any?
          page_calculator.hydrate_from_cache(cached_pages, state:, width:, height:)
          page_calculator.apply_pending_precise_restore!(state)
          Result.new(status: :hit, key:)
        else
          Result.new(status: :miss, key:)
        end
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

      def build_layout_key(width, height)
        view_mode = current_view_mode
        line_spacing = current_line_spacing
        kitty_images = EbookReader::Infrastructure::KittyGraphics.enabled_for?(state)
        key = pagination_cache.layout_key(width, height, view_mode, line_spacing, kitty_images: kitty_images)
        [key, view_mode, line_spacing]
      end

      def apply_layout_config(width, height, view_mode, line_spacing)
        if state.respond_to?(:apply_terminal_dimensions)
          state.apply_terminal_dimensions(width, height)
        elsif state.respond_to?(:update)
          state.update({ %i[ui terminal_width] => width, %i[ui terminal_height] => height })
        end

        update_config(view_mode, line_spacing)
      end

      def update_config(view_mode, line_spacing)
        updates = {}
        updates[%i[config view_mode]] = view_mode if view_mode
        updates[%i[config line_spacing]] = line_spacing if line_spacing
        state.update(updates) unless updates.empty?
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

      def find_fallback_key(doc)
        keys = pagination_cache.layout_keys_for_document(doc)
        return nil if keys.empty?

        want_images = EbookReader::Infrastructure::KittyGraphics.enabled_for?(state)
        preferred = keys.find do |candidate|
          parsed = pagination_cache.parse_layout_key(candidate)
          parsed && parsed[:view_mode] == current_view_mode &&
            parsed[:line_spacing] == current_line_spacing &&
            parsed[:kitty_images] == want_images
        end
        return nil unless preferred

        parsed = pagination_cache.parse_layout_key(preferred)
        return nil unless parsed

        parsed.merge(key: preferred)
      end

      def current_view_mode
        EbookReader::Domain::Selectors::ConfigSelectors.view_mode(state)
      end

      def current_line_spacing
        EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(state)
      end
    end
  end
end
