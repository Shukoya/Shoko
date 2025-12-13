# frozen_string_literal: true

module EbookReader
  module Application
    # Computes reader page information (current/total pages) for single and split view modes.
    # Encapsulates sizing logic so ReaderController can delegate without duplicating calculations.
    class PageInfoCalculator
      def initialize(state:, doc:, page_calculator:, layout_service:, terminal_service:, pagination_orchestrator:, defer_page_map:)
        @state = state
        @doc = doc
        @page_calculator = page_calculator
        @layout_service = layout_service
        @terminal_service = terminal_service
        @pagination_orchestrator = pagination_orchestrator
        @defer_page_map = defer_page_map
      end

      def calculate
        return default_single unless show_page_numbers?

        view_mode = current_view_mode
        if view_mode == :split
          calculate_split_info
        else
          calculate_single_info
        end
      end

      private

      attr_reader :state, :doc, :page_calculator, :layout_service,
                  :terminal_service, :pagination_orchestrator, :defer_page_map

      def calculate_single_info
        if dynamic_mode?
          calculate_dynamic_single
        else
          calculate_absolute_single
        end
      end

      def calculate_split_info
        if dynamic_mode?
          calculate_dynamic_split
        else
          calculate_absolute_split
        end
      end

      def calculate_dynamic_single
        return default_single unless page_calculator

        current_index = (state.get(%i[reader current_page_index]) || 0).to_i
        total_pages = page_calculator.total_pages.to_i
        current_page = current_index + 1
        total_pages = 0 if total_pages <= 0

        {
          type: :single,
          current: current_page,
          total: total_pages,
        }
      end

      def calculate_dynamic_split
        return default_split unless page_calculator

        left_page = (state.get(%i[reader current_page_index]) || 0).to_i + 1
        total_pages = page_calculator.total_pages.to_i
        right_page = [left_page + 1, total_pages].min

        {
          type: :split,
          left: { current: left_page, total: total_pages },
          right: { current: right_page, total: total_pages },
        }
      end

      def calculate_absolute_single
        height, width = terminal_size
        _, content_height = layout_service.calculate_metrics(width, height, current_view_mode)
        lines_per_page = layout_service.adjust_for_line_spacing(content_height, current_line_spacing)
        return default_single if lines_per_page <= 0

        ensure_absolute_page_map(width, height) unless defer_page_map

        current_chapter = (state.get(%i[reader current_chapter]) || 0).to_i
        page_map = Array(state.get(%i[reader page_map]) || [])
        pages_before = page_map[0...current_chapter].sum

        line_offset = if current_view_mode == :split
                        state.get(%i[reader left_page]) || 0
                      else
                        state.get(%i[reader single_page]) || 0
                      end
        page_in_chapter = (line_offset.to_f / lines_per_page).floor + 1
        current_global_page = pages_before + page_in_chapter
        total_pages = state.get(%i[reader total_pages]).to_i

        {
          type: :single,
          current: current_global_page,
          total: total_pages.positive? ? total_pages : 0,
        }
      end

      def calculate_absolute_split
        height, width = terminal_size
        _, content_height = layout_service.calculate_metrics(width, height, :split)
        lines_per_page = layout_service.adjust_for_line_spacing(content_height, current_line_spacing)
        return default_split if lines_per_page <= 0

        ensure_absolute_page_map(width, height) unless defer_page_map

        page_map = Array(state.get(%i[reader page_map]) || [])
        total_pages = state.get(%i[reader total_pages]).to_i
        return default_split unless total_pages.positive?

        current_chapter = (state.get(%i[reader current_chapter]) || 0).to_i
        pages_before = page_map[0...current_chapter].sum

        left_line_offset = state.get(%i[reader left_page]) || 0
        left_page_in_chapter = (left_line_offset.to_f / lines_per_page).floor + 1
        left_current = pages_before + left_page_in_chapter

        right_line_offset = state.get(%i[reader right_page]) || lines_per_page
        right_page_in_chapter = (right_line_offset.to_f / lines_per_page).floor + 1
        right_current = [pages_before + right_page_in_chapter, total_pages].min

        {
          type: :split,
          left: { current: left_current, total: total_pages },
          right: { current: right_current, total: total_pages },
        }
      end

      def ensure_absolute_page_map(width, height)
        page_map = Array(state.get(%i[reader page_map]) || [])
        return if defer_page_map
        return unless page_calculator

        if page_map.empty? || size_changed?(width, height)
          pagination_orchestrator.build_full_map!(doc, state, page_calculator, [width, height])
        end
      end

      def default_single
        { type: :single, current: 0, total: 0 }
      end

      def default_split
        {
          type: :split,
          left: { current: 0, total: 0 },
          right: { current: 0, total: 0 },
        }
      end

      def dynamic_mode?
        (state.get(%i[config page_numbering_mode]) || :dynamic) == :dynamic
      end

      def show_page_numbers?
        state.get(%i[config show_page_numbers])
      end

      def current_view_mode
        state.get(%i[config view_mode]) || :split
      end

      def current_line_spacing
        state.get(%i[config line_spacing]) || EbookReader::Constants::DEFAULT_LINE_SPACING
      end

      def terminal_size
        terminal_service.size
      end

      def size_changed?(width, height)
        return false unless state.respond_to?(:terminal_size_changed?)

        state.terminal_size_changed?(width, height)
      end
    end
  end
end
