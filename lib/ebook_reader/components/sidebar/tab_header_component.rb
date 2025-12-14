# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../helpers/text_metrics'

module EbookReader
  module Components
    module Sidebar
      # Modern bottom tab navigation for sidebar
      class TabHeaderComponent < BaseComponent
        include Constants::UIConstants

        TABS = %i[toc annotations bookmarks].freeze
        TAB_INFO = {
          toc: { label: 'Contents', icon: '◉', key: 'g' },
          annotations: { label: 'Notes', icon: '◈', key: 'a' },
          bookmarks: { label: 'Bookmarks', icon: '◆', key: 'b' },
        }.freeze

        def initialize(state)
          super() # Call BaseComponent constructor with no services
          @state = state
        end

        def do_render(surface, bounds)
          # Draw separator line
          draw_separator(surface, bounds)

          # Render tab navigation
          render_tab_navigation(surface, bounds)
        end

        private

        def draw_separator(surface, bounds)
          # Draw subtle separator line at top
          separator_char = "#{COLOR_TEXT_DIM}─#{Terminal::ANSI::RESET}"
          (1..(bounds.width - 1)).each do |x|
            surface.write(bounds, 1, x, separator_char)
          end
        end

        def render_tab_navigation(surface, bounds)
          # Calculate tab positions
          tab_width = (bounds.width - 2) / TABS.length
          start_y = 1

          active_tab = EbookReader::Domain::Selectors::ReaderSelectors.sidebar_active_tab(@state)
          TABS.each_with_index do |tab, index|
            x_pos = 2 + (index * tab_width)
            ctx = TabButtonCtx.new(tab: tab, x: x_pos, y: start_y, width: tab_width, active: (active_tab == tab))
            render_tab_button(surface, bounds, ctx)
          end
        end

        TabButtonCtx = Struct.new(:tab, :x, :y, :width, :active, keyword_init: true)

        def render_tab_button(surface, bounds, ctx)
          info = TAB_INFO[ctx.tab]
          icon = info[:icon]
          label = info[:label]
          key = info[:key]
          reset = Terminal::ANSI::RESET
          x = ctx.x
          y = ctx.y
          w = ctx.width

          y1 = y + 1
          y2 = y + 2
          return render_active(surface, bounds, x, y1, y2, w, icon, label, reset) if ctx.active

          render_inactive(surface, bounds, x, y1, y2, w, icon, key, reset)
        end

        def write_at(surface, bounds, y, x, text)
          surface.write(bounds, y, x, text)
        end

        def write_pair(surface, bounds, y, x, left_text, right_text)
          write_at(surface, bounds, y, x, left_text)
          write_at(surface, bounds, y, x + 2, right_text)
        end

        def xpad_for(x, padding)
          x + padding
        end

        def render_active(surface, bounds, x, y1, y2, w, icon, label, reset)
          icon_text = "#{COLOR_TEXT_ACCENT}#{icon}#{reset}"
          label_text = "#{COLOR_TEXT_PRIMARY}#{label}#{reset}"
          content = "#{icon} #{label}"
          content_len = EbookReader::Helpers::TextMetrics.visible_length(content)
          padding = [(w - content_len) / 2, 0].max
          xpad = xpad_for(x, padding)
          write_pair(surface, bounds, y1, xpad, icon_text, label_text)
          indicator_char = "#{COLOR_TEXT_ACCENT}▬#{reset}"
          indicator_width = [content_len, w - 2].min
          indicator_start = x + [(w - indicator_width) / 2, 0].max
          (0...indicator_width).each { |i| write_at(surface, bounds, y2, indicator_start + i, indicator_char) }
        end

        def render_inactive(surface, bounds, x, y1, y2, w, icon, key, reset)
          icon_text = "#{COLOR_TEXT_DIM}#{icon}#{reset}"
          key_hint = "#{COLOR_TEXT_DIM}[#{key}]#{reset}"
          content_width = 1
          padding = [(w - content_width) / 2, 0].max
          xpad = xpad_for(x, padding)
          write_at(surface, bounds, y1, xpad, icon_text)
          key_padding = [(w - 3) / 2, 0].max
          write_at(surface, bounds, y2, x + key_padding, key_hint)
        end
      end
    end
  end
end
