# frozen_string_literal: true

require_relative 'base_component'
require_relative 'surface'
require_relative 'rect'
require_relative 'sidebar/tab_header_component'
require_relative 'sidebar/toc_tab_renderer'
require_relative 'sidebar/annotations_tab_renderer'
require_relative 'sidebar/bookmarks_tab_renderer'

module EbookReader
  module Components
    # Collapsible sidebar panel with tabbed interface for TOC, Annotations, and Bookmarks
    class SidebarPanelComponent < BaseComponent
      include Constants::UIConstants

      TABS = %i[toc annotations bookmarks].freeze
      TAB_TITLES = { toc: 'Contents', annotations: 'Annotations', bookmarks: 'Bookmarks' }.freeze
      HELP_TEXTS = {
        toc: "↑↓ Navigate • ⏎ Jump • / Filter",
        annotations: "↑↓ Navigate • ⏎ Jump • e Edit • d Delete",
        bookmarks: "↑↓ Navigate • ⏎ Jump • d Delete",
      }.freeze
      DEFAULT_WIDTH_PERCENT = 30
      MIN_WIDTH = 24

      def initialize(controller)
        super() # Call BaseComponent constructor
        @controller = controller
        @tab_header = Sidebar::TabHeaderComponent.new(controller)
        @toc_renderer = Sidebar::TocTabRenderer.new(controller)
        @annotations_renderer = Sidebar::AnnotationsTabRenderer.new(controller)
        @bookmarks_renderer = Sidebar::BookmarksTabRenderer.new(controller)

        # Observe sidebar state changes
        state = @controller.state
        state.add_observer(self,
                           %i[reader sidebar_visible],
                           %i[reader sidebar_active_tab],
                           %i[reader sidebar_toc_selected],
                           %i[reader sidebar_annotations_selected],
                           %i[reader sidebar_bookmarks_selected])
        @needs_redraw = true
      end

      def state_changed(path, old_value, new_value)
        # Call parent invalidate to properly trigger re-rendering
        super

        # Keep legacy @needs_redraw for backward compatibility
        @needs_redraw = true
      end

      def preferred_width(total_width)
        state = @controller.state
        return :hidden unless state.get(%i[reader sidebar_visible])

        # Calculate width as percentage of total, with minimum
        preferred = (total_width * DEFAULT_WIDTH_PERCENT / 100.0).round
        [preferred, MIN_WIDTH].max
      end

      def do_render(surface, bounds)
        state = @controller.state
        bw = bounds.width
        bh = bounds.height
        return unless state.get(%i[reader sidebar_visible]) && bw >= MIN_WIDTH

        # Cache frequently-used bounds values
        bx = bounds.x
        by = bounds.y
        # bw, bh already cached above

        # Draw modern border
        draw_border(surface, bounds)

        # Calculate layout areas - tabs now at bottom
        header_height = 2
        tab_height = 3
        help_height = 1
        content_height = bh - header_height - tab_height - help_height

        return if content_height <= 0

        # Render minimal header with title only
        header_bounds = Rect.new(x: bx, y: by, width: bw,
                                 height: header_height)
        render_header(surface, header_bounds)

        # Render active tab content
        y_header = by + header_height
        content_bounds = Rect.new(x: bx, y: y_header,
                                  width: bw, height: content_height)
        render_active_tab(surface, content_bounds)

        # Render help text
        help_bounds = Rect.new(x: bx, y: y_header + content_height,
                               width: bw, height: help_height)
        render_help(surface, help_bounds)

        # Render tab navigation at bottom
        tab_bounds = Rect.new(x: bx, y: by + bh - tab_height,
                              width: bw, height: tab_height)
        @tab_header.render(surface, tab_bounds)

        @needs_redraw = false
      end

      private

      def draw_border(surface, bounds)
        # Draw modern vertical border on the right edge
        h = bounds.height
        w = bounds.width
        reset = Terminal::ANSI::RESET
        dim = COLOR_TEXT_DIM
        (1..h).each do |y|
          surface.write(bounds, y, w, "#{dim}│#{reset}")
        end
      end

      def render_header(surface, bounds)
        state = @controller.state

        # Simple clean title
        active_tab = EbookReader::Domain::Selectors::ReaderSelectors.sidebar_active_tab(state)
        title = TAB_TITLES[active_tab] || 'Sidebar'
        reset = Terminal::ANSI::RESET
        surface.write(bounds, 1, 2, "#{SELECTION_HIGHLIGHT}#{title}#{reset}")

        # Close indicator
        w = bounds.width
        close_text = "#{COLOR_TEXT_DIM}[t]#{reset}"
        surface.write(bounds, 1, w - 5, close_text)
      end

      def get_clean_title(active_tab)
        case active_tab
        when :toc
          'Contents'
        when :annotations
          'Annotations'
        when :bookmarks
          'Bookmarks'
        else
          'Sidebar'
        end
      end

      def render_help(surface, bounds)
        state = @controller.state

        active_tab = EbookReader::Domain::Selectors::ReaderSelectors.sidebar_active_tab(state)
        reset = Terminal::ANSI::RESET
        width = bounds.width
        hint = HELP_TEXTS[active_tab]
        help_text = hint ? "#{COLOR_TEXT_DIM}#{hint}#{reset}" : ''

        # Truncate to fit width
        if help_text.length > width - 4
          visible_length = width - 7
          help_text = "#{help_text[0, visible_length]}..."
        end

        surface.write(bounds, 1, 2, help_text)
      end

      def render_active_tab(surface, bounds)
        state = @controller.state

        active_tab = EbookReader::Domain::Selectors::ReaderSelectors.sidebar_active_tab(state)
        renderer = { toc: @toc_renderer, annotations: @annotations_renderer, bookmarks: @bookmarks_renderer }[active_tab]
        renderer&.render(surface, bounds)
      end
    end
  end
end
