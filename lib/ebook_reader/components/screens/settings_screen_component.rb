# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'

module EbookReader
  module Components
    module Screens
      # Settings screen component for configuration management
      class SettingsScreenComponent < BaseComponent
        include Constants::UIConstants

        def initialize(state, scanner)
          super()
          @state = state
          @scanner = scanner
        end

        def do_render(surface, bounds)
          height = bounds.height
          width = bounds.width

          # Header
          surface.write(bounds, 1, 2, "#{COLOR_TEXT_ACCENT}⚙️ Settings#{Terminal::ANSI::RESET}")
          surface.write(bounds, 1, width - 20, "#{COLOR_TEXT_DIM}[ESC] Back#{Terminal::ANSI::RESET}")

          # Settings options
          render_setting_option(surface, bounds, 3, '1', 'View Mode', format_view_mode)
          render_setting_option(surface, bounds, 4, '2', 'Line Spacing', format_line_spacing)
          render_setting_option(surface, bounds, 5, '3', 'Page Numbers', format_page_numbers)
          render_setting_option(surface, bounds, 6, '4', 'Page Numbering Mode',
                                format_page_numbering_mode)
          render_setting_option(surface, bounds, 7, '5', 'Theme', format_theme)
          render_setting_option(surface, bounds, 8, '6', 'Highlighting', format_highlighting)

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

        def render_setting_option(surface, bounds, row, key, name, value)
          key_text = "#{COLOR_TEXT_ACCENT}[#{key}]#{Terminal::ANSI::RESET}"
          name_text = "#{COLOR_TEXT_PRIMARY}#{name}:#{Terminal::ANSI::RESET}"
          value_text = "#{COLOR_TEXT_SUCCESS}#{value}#{Terminal::ANSI::RESET}"

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

        def format_theme
          case @state.get(%i[config theme])
          when :dark then 'Dark'
          when :light then 'Light'
          else 'Unknown'
          end
        end

        def format_highlighting
          quotes = @state.get(%i[config highlight_quotes]) ? 'Quotes' : ''
          keywords = @state.get(%i[config highlight_keywords]) ? 'Keywords' : ''

          highlights = [quotes, keywords].compact.reject(&:empty?)
          highlights.empty? ? 'None' : highlights.join(', ')
        end
      end
    end
  end
end
