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
      TAB_NAMES = { toc: 'TOC', annotations: 'Notes', bookmarks: 'Marks' }.freeze
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
        return unless state.get(%i[reader sidebar_visible]) && bounds.width >= MIN_WIDTH

        # Draw modern border
        draw_border(surface, bounds)

        # Calculate layout areas - tabs now at bottom
        header_height = 2
        tab_height = 3
        help_height = 1
        content_height = bounds.height - header_height - tab_height - help_height

        return if content_height <= 0

        # Render minimal header with title only
        header_bounds = Rect.new(x: bounds.x, y: bounds.y, width: bounds.width,
                                 height: header_height)
        render_header(surface, header_bounds)

        # Render active tab content
        content_bounds = Rect.new(x: bounds.x, y: bounds.y + header_height,
                                  width: bounds.width, height: content_height)
        render_active_tab(surface, content_bounds)

        # Render help text
        help_bounds = Rect.new(x: bounds.x, y: bounds.y + header_height + content_height,
                               width: bounds.width, height: help_height)
        render_help(surface, help_bounds)

        # Render tab navigation at bottom
        tab_bounds = Rect.new(x: bounds.x, y: bounds.y + bounds.height - tab_height,
                              width: bounds.width, height: tab_height)
        @tab_header.render(surface, tab_bounds)

        @needs_redraw = false
      end

      private

      def draw_border(surface, bounds)
        # Draw modern vertical border on the right edge
        (1..bounds.height).each do |y|
          surface.write(bounds, y, bounds.width, "#{COLOR_TEXT_DIM}│#{Terminal::ANSI::RESET}")
        end
      end

      def render_header(surface, bounds)
        state = @controller.state

        # Simple clean title
        active_tab = EbookReader::Domain::Selectors::ReaderSelectors.sidebar_active_tab(state)
        title = get_clean_title(active_tab)
        surface.write(bounds, 1, 2, "#{SELECTION_HIGHLIGHT}#{title}#{Terminal::ANSI::RESET}")

        # Close indicator
        close_text = "#{COLOR_TEXT_DIM}[t]#{Terminal::ANSI::RESET}"
        surface.write(bounds, 1, bounds.width - 5, close_text)
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
        help_text = case active_tab
                    when :toc
                      "#{COLOR_TEXT_DIM}↑↓ Navigate • ⏎ Jump • / Filter#{Terminal::ANSI::RESET}"
                    when :annotations
                      "#{COLOR_TEXT_DIM}↑↓ Navigate • ⏎ Jump • e Edit • d Delete#{Terminal::ANSI::RESET}"
                    when :bookmarks
                      "#{COLOR_TEXT_DIM}↑↓ Navigate • ⏎ Jump • d Delete#{Terminal::ANSI::RESET}"
                    else
                      ''
                    end

        # Truncate to fit width
        if help_text.length > bounds.width - 4
          visible_length = bounds.width - 7
          help_text = "#{help_text[0, visible_length]}..."
        end

        surface.write(bounds, 1, 2, help_text)
      end

      def render_active_tab(surface, bounds)
        state = @controller.state

        active_tab = EbookReader::Domain::Selectors::ReaderSelectors.sidebar_active_tab(state)
        case active_tab
        when :toc
          @toc_renderer.render(surface, bounds)
        when :annotations
          @annotations_renderer.render(surface, bounds)
        when :bookmarks
          @bookmarks_renderer.render(surface, bounds)
        end
      end
    end
  end
end
