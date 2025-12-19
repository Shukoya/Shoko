# frozen_string_literal: true

require_relative 'base_service'
require_relative 'internal/absolute_page_map_builder'
require_relative 'internal/dynamic_page_map_builder'
require_relative 'internal/page_hydrator'
require_relative 'internal/pagination_workflow'
require_relative 'internal/layout_metrics_calculator'
require_relative '../../helpers/text_metrics'
require_relative '../../infrastructure/kitty_graphics'

module EbookReader
  module Domain
    module Services
      # Enhanced service for page calculations with full PageManager functionality.
      # Migrated from legacy Services::PageManager with dependency injection.
      class PageCalculatorService < BaseService
        attr_reader :pages_data

        def initialize(dependencies)
          super
          @text_wrapper = DefaultTextWrapper.new
          @pages_data = []
          @chapter_page_index = {}
          @layout_service = begin
            resolve(:layout_service)
          rescue StandardError
            nil
          end
          @metrics_calculator = Internal::LayoutMetricsCalculator.new(@state_store,
                                                                      layout_service: @layout_service)
          @pagination_cache = begin
            resolve(:pagination_cache)
          rescue StandardError
            nil
          end
          @instrumentation = begin
            resolve(:instrumentation_service)
          rescue StandardError
            nil
          end
          @pagination_workflow = Internal::PaginationWorkflow.new(
            metrics_calculator: @metrics_calculator,
            dependencies: @dependencies,
            pagination_cache: @pagination_cache
          )
          @page_hydrator = Internal::PageHydrator.new(
            state_store: @state_store,
            dependencies: @dependencies,
            text_wrapper: @text_wrapper,
            metrics_calculator: @metrics_calculator
          )
        end

        # Build complete page map (PageManager compatibility)
        def build_page_map(terminal_width, terminal_height, doc, config, &)
          return unless EbookReader::Domain::Selectors::ConfigSelectors.page_numbering_mode(config) == :dynamic

          result = @pagination_workflow.build_dynamic(doc: doc,
                                                      width: terminal_width,
                                                      height: terminal_height,
                                                      config: config,
                                                      &)
          @doc_ref = doc
          @pages_data = result.pages
          rebuild_page_index!
          @pages_data
        end

        # Get page data by index (PageManager compatibility)
        def get_page(page_index)
          return nil if @pages_data.empty?
          return @pages_data.first if page_index.negative?
          return @pages_data.last if page_index >= @pages_data.size

          page = @pages_data[page_index]
          return page if formatted_lines?(page[:lines])

          hydrated = measure_with_instrumentation('page_map.hydrate') do
            doc = resolve_document_reference
            @page_hydrator.hydrate(page, doc, prefer_formatting: true)
          rescue StandardError
            page
          end

          @pages_data[page_index] = hydrated if hydrated
          hydrated
        end

        # Find page index for chapter and line offset (PageManager compatibility)
        def find_page_index(chapter_index, line_offset)
          pages = @chapter_page_index[chapter_index]
          return 0 unless pages && !pages.empty?

          match = pages.bsearch { |page| line_offset <= page[:end_line].to_i }
          return match[:global_index] if match && match[:global_index]

          pages.last[:global_index] || 0
        end

        # Total pages built in map (PageManager compatibility)
        def total_pages
          @pages_data.size
        end

        # Build absolute mode page map (per-chapter pages) with progress callback.
        # Returns an array of pages per chapter.
        # @yield [done, total] optional progress callback
        def build_absolute_page_map(terminal_width, terminal_height, doc, state)
          # Compute layout metrics based on current config
          col_width, content_height = @metrics_calculator.layout(terminal_width, terminal_height, state)
          lines_per_page = @metrics_calculator.lines_per_page_for(content_height, state)
          wrapper = begin
            @dependencies&.resolve(:wrapping_service)
          rescue StandardError
            nil
          end

          Internal::AbsolutePageMapBuilder.build(doc, col_width, lines_per_page, wrapper) do |done, total|
            yield(done, total) if block_given?
          end
        end

        # --- Unified orchestration helpers ---
        # Build dynamic (lazy) page map and sync total to state. Accepts optional progress callback.
        def build_dynamic_map!(width, height, doc, state, &)
          build_page_map(width, height, doc, state, &)
          rebuild_page_index!
          state.dispatch(EbookReader::Domain::Actions::UpdatePaginationStateAction.new(
                           total_pages: total_pages
                         ))
        end

        # Build absolute page map and sync map/total/last dims to state. Accepts optional progress callback.
        def build_absolute_map!(width, height, doc, state, &)
          map = build_absolute_page_map(width, height, doc, state, &)
          state.dispatch(EbookReader::Domain::Actions::UpdatePaginationStateAction.new(
                           page_map: map,
                           total_pages: map.sum,
                           last_width: width,
                           last_height: height
                         ))
          map
        end

        # Apply precise pending progress (dynamic mode) if present in state
        def apply_pending_precise_restore!(state)
          pending = state.get(%i[reader pending_progress])
          return unless pending && pending[:line_offset]

          ch = pending[:chapter_index] || state.get(%i[reader current_chapter])
          idx = find_page_index(ch, pending[:line_offset].to_i)
          state.dispatch(EbookReader::Domain::Actions::UpdatePageAction.new(current_page_index: idx)) if idx && idx >= 0
          state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(pending_progress: nil))
        rescue StandardError
          # no-op on failure
        end

        def resolve_document_reference
          return @doc_ref if @doc_ref

          @dependencies&.resolve(:document)
        rescue StandardError
          nil
        end

        def formatted_lines?(lines)
          first = Array(lines).find { |ln| !ln.nil? }
          first.respond_to?(:segments) && first.respond_to?(:text)
        end

        def rebuild_page_index!
          @chapter_page_index = Hash.new { |h, k| h[k] = [] }
          @pages_data.each_with_index do |page, idx|
            ch = page[:chapter_index] || 0
            entry = page.merge(global_index: idx)
            @chapter_page_index[ch] << entry
          end
          @chapter_page_index.each_value { |arr| arr.sort_by! { |p| p[:end_line].to_i } }
        end

        # Hydrate from cached pagination without recomputation
        def hydrate_from_cache(pages, state: nil, width: nil, height: nil)
          return nil unless pages.is_a?(Array)

          @pages_data = pages
          rebuild_page_index!
          total = @pages_data.size
          state&.dispatch(EbookReader::Domain::Actions::UpdatePaginationStateAction.new(
            total_pages: total,
            last_width: width,
            last_height: height
          ))
          total
        end

        protected

        def required_dependencies
          [:state_store]
        end

        def setup_service_dependencies
          @state_store = resolve(:state_store) if @dependencies
        end

        private

        def measure_with_instrumentation(metric, &)
          if @instrumentation
            @instrumentation.time(metric, &)
          else
            yield
          end
        end
      end

      # Default text wrapping implementation
      class DefaultTextWrapper
        def wrap_chapter_lines(lines, column_width)
          return [] if lines.empty? || column_width <= 0

          wrapped = []
          lines.each do |line|
            next if line.nil?

            if line.strip.empty?
              wrapped << ''
            else
              segments = EbookReader::Helpers::TextMetrics.wrap_plain_text(line, column_width)
              wrapped.concat(segments)
            end
          end
          wrapped
        end
      end
    end
  end
end
# NOTE: Former helper that prepopulated lines for cached pages has been
# removed to avoid blocking first paint. Lines are populated lazily in
# #get_page when needed.
