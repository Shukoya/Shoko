# frozen_string_literal: true

module EbookReader
  module Application
    # Computes reader page information (current/total pages) for single and split view modes.
    # Encapsulates sizing logic so ReaderController can delegate without duplicating calculations.
    class PageInfoCalculator
      # Bundles dependencies to keep initialization concise.
      Dependencies = Struct.new(
        :state,
        :doc,
        :page_calculator,
        :layout_service,
        :terminal_service,
        :pagination_orchestrator,
        keyword_init: true
      )

      def initialize(dependencies:, defer_page_map:)
        @dependencies = dependencies
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

      attr_reader :dependencies, :defer_page_map

      def state
        dependencies.state
      end

      def doc
        dependencies.doc
      end

      def page_calculator
        dependencies.page_calculator
      end

      def layout_service
        dependencies.layout_service
      end

      def terminal_service
        dependencies.terminal_service
      end

      def pagination_orchestrator
        dependencies.pagination_orchestrator
      end

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

        current_page = current_page_index + 1
        total_pages = total_pages_from_calculator

        {
          type: :single,
          current: current_page,
          total: total_pages,
        }
      end

      def calculate_dynamic_split
        return default_split unless page_calculator

        left_page = current_page_index + 1
        total_pages = total_pages_from_calculator
        right_page = [left_page + 1, total_pages].min

        {
          type: :split,
          left: { current: left_page, total: total_pages },
          right: { current: right_page, total: total_pages },
        }
      end

      def calculate_absolute_single
        layout = absolute_layout(current_view_mode)
        lines_per_page = layout[:lines_per_page]
        return default_single if lines_per_page <= 0

        ensure_absolute_page_map(layout[:width], layout[:height])

        page_map = page_map_from_state
        pages_before = pages_before_current_chapter(page_map)
        line_offset = line_offset_for_view(current_view_mode)
        page_in_chapter = page_in_chapter_for_offset(line_offset, lines_per_page)
        current_global_page = pages_before + page_in_chapter
        total_pages = total_pages_from_state

        {
          type: :single,
          current: current_global_page,
          total: total_pages.positive? ? total_pages : 0,
        }
      end

      def calculate_absolute_split
        layout = absolute_layout(:split)
        lines_per_page = layout[:lines_per_page]
        return default_split if lines_per_page <= 0

        ensure_absolute_page_map(layout[:width], layout[:height])

        page_map = page_map_from_state
        total_pages = total_pages_from_state
        return default_split unless total_pages.positive?

        pages_before = pages_before_current_chapter(page_map)

        left_line_offset = state.get(%i[reader left_page]) || 0
        left_page_in_chapter = page_in_chapter_for_offset(left_line_offset, lines_per_page)
        left_current = pages_before + left_page_in_chapter

        right_line_offset = state.get(%i[reader right_page]) || lines_per_page
        right_page_in_chapter = page_in_chapter_for_offset(right_line_offset, lines_per_page)
        right_current = [pages_before + right_page_in_chapter, total_pages].min

        {
          type: :split,
          left: { current: left_current, total: total_pages },
          right: { current: right_current, total: total_pages },
        }
      end

      def ensure_absolute_page_map(width, height)
        return if defer_page_map
        return unless page_calculator

        return unless page_map_empty? || size_changed?(width, height)

        pagination_orchestrator.build_full_map!(doc, state, page_calculator, [width, height])
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
        state.terminal_size_changed?(width, height)
      end

      def current_page_index
        (state.get(%i[reader current_page_index]) || 0).to_i
      end

      def total_pages_from_calculator
        total = page_calculator.total_pages.to_i
        total.positive? ? total : 0
      end

      def total_pages_from_state
        state.get(%i[reader total_pages]).to_i
      end

      def page_map_from_state
        Array(state.get(%i[reader page_map]) || [])
      end

      def pages_before_current_chapter(page_map)
        current_chapter = (state.get(%i[reader current_chapter]) || 0).to_i
        page_map[0...current_chapter].sum
      end

      def page_in_chapter_for_offset(line_offset, lines_per_page)
        (line_offset.to_f / lines_per_page).floor + 1
      end

      def line_offset_for_view(view_mode)
        if view_mode == :split
          state.get(%i[reader left_page]) || 0
        else
          state.get(%i[reader single_page]) || 0
        end
      end

      def absolute_layout(view_mode)
        height, width = terminal_size
        _, content_height = layout_service.calculate_metrics(width, height, view_mode)
        lines_per_page = layout_service.adjust_for_line_spacing(content_height, current_line_spacing)
        { width: width, height: height, lines_per_page: lines_per_page }
      end

      def page_map_empty?
        page_map_from_state.empty?
      end
    end
  end
end
