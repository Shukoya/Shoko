# frozen_string_literal: true

module EbookReader
  module Domain
    module Services
      module Internal
        # Encapsulates pagination building, caching, and layout concerns so the
        # main PageCalculatorService remains focused on high-level orchestration.
        class PaginationWorkflow
          Result = Struct.new(:pages, :cached, keyword_init: true)

        def initialize(metrics_calculator:, dependencies:, pagination_cache: nil)
          @metrics_calculator = metrics_calculator
          @dependencies = dependencies
          @pagination_cache = pagination_cache
        end

        def build_dynamic(doc:, width:, height:, config:, &on_progress)
          key = dynamic_cache_key(width, height, config)
          cached = key ? load_cached_pages(doc, key, config) : nil
          if cached&.any?
            annotate_profile(pagination_cache: 'hit')
            return Result.new(pages: cached, cached: true)
          end

          layout = layout_for(width, height, config)
          return Result.new(pages: [], cached: false) if layout[:lines_per_page] <= 0

          pages = Internal::DynamicPageMapBuilder.build(
              doc,
              layout[:col_width],
              layout[:lines_per_page]
            ) do |idx, total|
              on_progress&.call(idx, total)
            end

            if key
              save_cache(doc, key, pages)
              annotate_profile(pagination_cache: 'miss')
            end
            Result.new(pages: pages, cached: false)
          end

          def build_absolute(doc:, width:, height:, state:, &on_progress)
            layout = layout_for(width, height, state)
            return [] if layout[:lines_per_page] <= 0

            wrapper = resolve_wrapping_service
            Internal::AbsolutePageMapBuilder.build(
              doc,
              layout[:col_width],
              layout[:lines_per_page],
              wrapper
            ) do |done, total|
              on_progress&.call(done, total)
            end
          end

          def compact_pages(pages)
            pages.map do |p|
              {
                'chapter_index' => p[:chapter_index],
                'page_in_chapter' => p[:page_in_chapter],
                'total_pages_in_chapter' => p[:total_pages_in_chapter],
                'start_line' => p[:start_line],
                'end_line' => p[:end_line],
              }
            end
          end

          private

          def layout_for(width, height, config)
            col_width, content_height = @metrics_calculator.layout(width, height, config)
            lines_per_page = @metrics_calculator.lines_per_page_for(content_height, config)
            { col_width: col_width, lines_per_page: lines_per_page }
          end

          def dynamic_cache_key(width, height, config)
            view_mode = resolve_view_mode(config)
            line_spacing = resolve_line_spacing(config)
            return nil unless @pagination_cache

            @pagination_cache.layout_key(width, height, view_mode, line_spacing)
          end

          def load_cached_pages(doc, key, config)
            return nil unless @pagination_cache

            cached = @pagination_cache.load_for_document(doc, key)
            return cached if cached&.any?

            return nil unless config.respond_to?(:get)

            view_mode_reader = config.get(%i[reader view_mode])
            return nil unless view_mode_reader

            alt_key = @pagination_cache.layout_key(
              config.get(%i[ui terminal_width]) || 0,
              config.get(%i[ui terminal_height]) || 0,
              view_mode_reader,
              resolve_line_spacing(config)
            )
            @pagination_cache.load_for_document(doc, alt_key)
          rescue StandardError
            nil
          end

          def save_cache(doc, key, pages)
            return unless @pagination_cache

            @pagination_cache.save_for_document(doc, key, compact_pages(pages))
          rescue StandardError
            nil
          end

          def annotate_profile(payload)
            return unless defined?(EbookReader::Infrastructure::PerfTracer)

            EbookReader::Infrastructure::PerfTracer.annotate(payload)
          rescue StandardError
            nil
          end

          def resolve_wrapping_service
            return nil unless @dependencies.respond_to?(:resolve)

            @dependencies.resolve(:wrapping_service)
          rescue StandardError
            nil
          end

          def resolve_view_mode(config)
            if config.respond_to?(:dig)
              config.dig(:reader, :view_mode) || config.dig(:config, :view_mode)
            elsif config.respond_to?(:get)
              config.get(%i[config view_mode]) || config.get(%i[reader view_mode])
            else
              :split
            end || :split
          end

          def resolve_line_spacing(config)
            if config.respond_to?(:dig)
              config.dig(:config, :line_spacing)
            elsif config.respond_to?(:get)
              config.get(%i[config line_spacing])
            end || EbookReader::Constants::DEFAULT_LINE_SPACING
          end
        end
      end
    end
  end
end
