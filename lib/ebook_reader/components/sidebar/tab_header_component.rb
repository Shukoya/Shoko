# frozen_string_literal: true

require_relative '../base_component'

module EbookReader
  module Components
    module Sidebar
      # Modern bottom tab navigation for sidebar
      class TabHeaderComponent < BaseComponent
        TABS = %i[toc annotations bookmarks].freeze
        TAB_INFO = {
          toc: { label: 'Contents', icon: '◉', key: 'g' },
          annotations: { label: 'Notes', icon: '◈', key: 'a' },
          bookmarks: { label: 'Bookmarks', icon: '◆', key: 'b' }
        }.freeze

        def initialize(controller)
          super()  # Call BaseComponent constructor with no services
          @controller = controller
        end

        def render(surface, bounds)
          state = @controller.state
          
          # Draw separator line
          draw_separator(surface, bounds)
          
          # Render tab navigation
          render_tab_navigation(surface, bounds)
        end

        private

        def draw_separator(surface, bounds)
          # Draw subtle separator line at top
          separator_char = "#{Terminal::ANSI::DIM}─#{Terminal::ANSI::RESET}"
          (1..bounds.width-1).each do |x|
            surface.write(bounds, 1, x, separator_char)
          end
        end

        def render_tab_navigation(surface, bounds)
          state = @controller.state
          
          # Calculate tab positions
          tab_width = (bounds.width - 2) / TABS.length
          start_y = bounds.y + 1
          
          TABS.each_with_index do |tab, index|
            x_pos = bounds.x + 1 + (index * tab_width)
            render_tab_button(surface, bounds, tab, x_pos, start_y, tab_width, state.sidebar_active_tab == tab)
          end
        end

        def render_tab_button(surface, bounds, tab, x_pos, y_pos, width, is_active)
          info = TAB_INFO[tab]
          icon = info[:icon]
          label = info[:label]
          key = info[:key]
          
          if is_active
            # Active tab styling - modern and clean
            icon_text = "#{Terminal::ANSI::BRIGHT_CYAN}#{icon}#{Terminal::ANSI::RESET}"
            label_text = "#{Terminal::ANSI::BRIGHT_WHITE}#{label}#{Terminal::ANSI::RESET}"
            
            # Center the content
            content = "#{icon} #{label}"
            padding = [(width - content.length) / 2, 0].max
            
            surface.write(bounds, y_pos + 1, x_pos + padding, icon_text)
            surface.write(bounds, y_pos + 1, x_pos + padding + 2, label_text)
            
            # Active indicator line
            indicator_char = "#{Terminal::ANSI::BRIGHT_CYAN}▬#{Terminal::ANSI::RESET}"
            indicator_width = [content.length, width - 2].min
            indicator_start = x_pos + [(width - indicator_width) / 2, 0].max
            
            (0...indicator_width).each do |i|
              surface.write(bounds, y_pos + 2, indicator_start + i, indicator_char)
            end
          else
            # Inactive tab styling
            icon_text = "#{Terminal::ANSI::DIM}#{icon}#{Terminal::ANSI::RESET}"
            
            # Show key hint for inactive tabs
            key_hint = "#{Terminal::ANSI::DIM}[#{key}]#{Terminal::ANSI::RESET}"
            
            # Center the icon
            content_width = 1  # Just icon for inactive
            padding = [(width - content_width) / 2, 0].max
            
            surface.write(bounds, y_pos + 1, x_pos + padding, icon_text)
            
            # Show key hint at bottom for inactive tabs
            key_padding = [(width - 3) / 2, 0].max
            surface.write(bounds, y_pos + 2, x_pos + key_padding, key_hint)
          end
        end
      end
    end
  end
end