# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'

module EbookReader
  module Components
    module Screens
      # Settings screen component for configuration management
      class SettingsScreenComponent < BaseComponent
        include Constants::UIConstants

        OptionCtx = Struct.new(:row, :key, :name, :value, keyword_init: true)

        def initialize(state, catalog_service = nil)
          super()
          @state = state
          @catalog = catalog_service
        end

        def do_render(surface, bounds)
          height = bounds.height
          width = bounds.width

          # Header
          surface.write(bounds, 1, 2, "#{COLOR_TEXT_ACCENT}⚙️ Settings#{Terminal::ANSI::RESET}")
          surface.write(bounds, 1, width - 20, "#{COLOR_TEXT_DIM}[ESC] Back#{Terminal::ANSI::RESET}")

          # Settings options
          render_setting_option(surface, bounds,
                                OptionCtx.new(row: 3,  key: '1', name: 'View Mode',            value: format_view_mode))
          render_setting_option(surface, bounds,
                                OptionCtx.new(row: 4,  key: '2', name: 'Line Spacing',         value: format_line_spacing))
          render_setting_option(surface, bounds,
                                OptionCtx.new(row: 5,  key: '3', name: 'Page Numbers',         value: format_page_numbers))
          render_setting_option(surface, bounds,
                                OptionCtx.new(row: 6,  key: '4', name: 'Page Numbering Mode',  value: format_page_numbering_mode))
          render_setting_option(surface, bounds,
                                OptionCtx.new(row: 7,  key: '5', name: 'Highlight Quotes',     value: format_highlight_quotes))
          render_setting_option(surface, bounds,
                                OptionCtx.new(row: 8,  key: '6', name: 'Wipe Cache',           value: 'Removes EPUB + scan caches'))

          # Instructions
          surface.write(bounds, height - 3, 2,
                        "#{COLOR_TEXT_DIM}Press number keys to change settings#{Terminal::ANSI::RESET}")
          surface.write(bounds, height - 2, 2,
                        "#{COLOR_TEXT_DIM}Changes are saved automatically#{Terminal::ANSI::RESET}")
        end

        def preferred_height(_available_height)
          :fill
        end

        private

        def render_setting_option(surface, bounds, ctx)
          key_text = "#{COLOR_TEXT_ACCENT}[#{ctx.key}]#{Terminal::ANSI::RESET}"
          name_text = "#{COLOR_TEXT_PRIMARY}#{ctx.name}:#{Terminal::ANSI::RESET}"
          value_text = "#{COLOR_TEXT_SUCCESS}#{ctx.value}#{Terminal::ANSI::RESET}"

          row = ctx.row
          surface.write(bounds, row, 2, "#{key_text} #{name_text}")
          surface.write(bounds, row, 25, value_text)
        end

        def format_view_mode
          case @state.get(%i[config view_mode])
          when :split then 'Split View'
          when :single then 'Single Page'
          else 'Unknown'
          end
        end

        def format_line_spacing
          case @state.get(%i[config line_spacing])
          when :compact then 'Compact'
          when :normal then 'Normal'
          when :relaxed then 'Relaxed'
          else 'Unknown'
          end
        end

        def format_page_numbers
          @state.get(%i[config show_page_numbers]) ? 'Enabled' : 'Disabled'
        end

        def format_page_numbering_mode
          case @state.get(%i[config page_numbering_mode])
          when :absolute then 'Absolute'
          when :dynamic then 'Dynamic'
          else 'Unknown'
          end
        end

        def format_highlight_quotes
          @state.get(%i[config highlight_quotes]) ? 'On' : 'Off'
        end
      end
    end
  end
end
