# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../constants/ui_constants'
require_relative '../../helpers/text_metrics'

module EbookReader
  module Components
    module Screens
      # Settings screen component for configuration management
      class SettingsScreenComponent < BaseComponent
        include Constants::UIConstants

        SettingsItem = Struct.new(:action, :icon, :label, keyword_init: true)

        SETTINGS_ITEMS = [
          SettingsItem.new(action: :back_to_menu, icon: '', label: 'Go Back'),
          SettingsItem.new(action: :toggle_view_mode, icon: '', label: 'View Mode'),
          SettingsItem.new(action: :cycle_line_spacing, icon: '', label: 'Line Spacing'),
          SettingsItem.new(action: :toggle_page_numbering_mode, icon: '', label: 'Page Numbering Mode'),
          SettingsItem.new(action: :toggle_page_numbers, icon: '', label: 'Page Numbers'),
          SettingsItem.new(action: :toggle_highlight_quotes, icon: '', label: 'Text Highlighting'),
          SettingsItem.new(action: :toggle_kitty_images, icon: '', label: 'Kitty Images'),
          SettingsItem.new(action: :wipe_cache, icon: '', label: 'Wipe Cache'),
        ].freeze

        ItemCtx = Struct.new(:row, :item, :value_text, :value_color, :index, :selected, :indent, keyword_init: true)

        def initialize(state, catalog_service = nil)
          super()
          @state = state
          @catalog = catalog_service
        end

        def do_render(surface, bounds)
          surface.write(bounds, 1, 2, "#{COLOR_TEXT_ACCENT}Settings#{Terminal::ANSI::RESET}")

          selected = @state.get(%i[menu settings_selected]) || 1
          text_values = setting_value_map
          render_settings(surface, bounds, selected, text_values)
        end

        def preferred_height(_available_height)
          :fill
        end

        private

        def render_settings(surface, bounds, selected, text_values)
          metrics = layout_metrics(bounds, text_values)
          max_index = SETTINGS_ITEMS.length - 1
          cursor = selected.clamp(0, max_index)
          row = metrics[:start_row]
          insert_toggle_gap = false

          SETTINGS_ITEMS.each_with_index do |item, index|
            break if row >= metrics[:max_row]

            case item.action
            when :toggle_view_mode
              row = render_button_group(surface, bounds, item, row, metrics[:indent], cursor == index,
                                        current_view_mode, view_mode_buttons)
              insert_toggle_gap = false
            when :cycle_line_spacing
              row = render_button_group(surface, bounds, item, row, metrics[:indent], cursor == index,
                                        current_line_spacing, line_spacing_buttons)
              insert_toggle_gap = false
            when :toggle_page_numbering_mode
              row = render_button_group(surface, bounds, item, row, metrics[:indent], cursor == index,
                                        current_page_numbering_mode, page_numbering_buttons)
              insert_toggle_gap = true
            else
              if toggled_action?(item.action) && insert_toggle_gap
                row += 1
                insert_toggle_gap = false
              end
              value_text, value_color = text_values[item.action]
              ctx = ItemCtx.new(row: row, item: item, value_text: value_text, value_color: value_color,
                                index: index, selected: cursor == index, indent: metrics[:indent])
              row = render_text_item(surface, bounds, ctx)
            end
          end
        end

        def render_text_item(surface, bounds, ctx)
          text = formatted_row(ctx.item, ctx.value_text, ctx.value_color, ctx.selected)
          surface.write(bounds, ctx.row, ctx.indent, text)
          ctx.row + 2
        end

        def formatted_row(item, value_text, value_color, selected)
          label = label_text(item)
          colors = row_colors(selected)
          line = "#{colors[:prefix]}#{colors[:fg]}#{label}"
          if value_text && !value_text.to_s.empty?
            line = "#{line}#{Terminal::ANSI::RESET}  #{value_color}#{value_text}"
          end
          "#{line}#{Terminal::ANSI::RESET}"
        end

        def row_colors(selected)
          if selected
            { prefix: Terminal::ANSI::BOLD, fg: COLOR_TEXT_ACCENT }
          else
            { prefix: '', fg: COLOR_TEXT_PRIMARY }
          end
        end

        def label_text(item)
          "#{item.icon}  #{item.label}"
        end

        def layout_metrics(bounds, text_values)
          width = bounds.width
          label_width = SETTINGS_ITEMS.map { |item| display_width(label_text(item)) }.max || 0
          text_value_width = text_values.values.map { |value| display_width(Array(value).first) }.max || 0
          button_width = [
            button_group_width(view_mode_buttons),
            button_group_width(line_spacing_buttons),
            button_group_width(page_numbering_buttons),
          ].max || 0
          content_width = label_width + 2 + [text_value_width, button_width].max
          indent = ((width - content_width) / 2).floor
          indent = indent.clamp(2, [width - content_width, 0].max)
          {
            indent: indent,
            start_row: [(bounds.height - 16) / 2, 4].max,
            max_row: bounds.height - 3,
          }
        end

        def display_width(text)
          EbookReader::Helpers::TextMetrics.visible_length(text.to_s)
        end

        def setting_value_map
          {
            back_to_menu: ['Return to main menu', COLOR_TEXT_DIM],
            toggle_page_numbers: toggle_page_number_value,
            toggle_highlight_quotes: toggle_highlight_value,
            toggle_kitty_images: toggle_kitty_images_value,
            wipe_cache: ['Removes EPUB + scan caches', COLOR_TEXT_WARNING],
          }
        end

        def render_button_group(surface, bounds, item, row, indent, selected, current_value, buttons)
          colors = row_colors(selected)
          label = "#{colors[:prefix]}#{colors[:fg]}#{label_text(item)}#{Terminal::ANSI::RESET}"
          surface.write(bounds, row, indent, label)
          buttons_line = button_row(buttons, current_value)
          surface.write(bounds, row + 1, indent, buttons_line) if row + 1 < bounds.height
          row + 3
        end

        def button_row(buttons, current_value)
          buttons.map { |value, label| button_string(label, value == current_value) }.join(' ')
        end

        def button_string(label, active)
          bg = active ? BUTTON_BG_ACTIVE : BUTTON_BG_INACTIVE
          fg = active ? BUTTON_FG_ACTIVE : BUTTON_FG_INACTIVE
          "#{bg}#{fg} #{label} #{Terminal::ANSI::RESET}"
        end

        def button_group_width(buttons)
          buttons.sum { |_value, label| EbookReader::Helpers::TextMetrics.visible_length(label) + 2 } + (buttons.length - 1)
        end

        def toggled_action?(action)
          %i[toggle_page_numbers toggle_highlight_quotes toggle_kitty_images].include?(action)
        end

        def view_mode_buttons
          [[:split, 'Split'], [:single, 'Single']]
        end

        def line_spacing_buttons
          [[:normal, 'Normal'], [:relaxed, 'Relaxed'], [:compact, 'Compact']]
        end

        def page_numbering_buttons
          [[:absolute, 'Absolute'], [:dynamic, 'Dynamic']]
        end

        def current_view_mode
          @state.get(%i[config view_mode]) || :split
        end

        def current_line_spacing
          @state.get(%i[config line_spacing]) || :compact
        end

        def current_page_numbering_mode
          @state.get(%i[config page_numbering_mode]) || :dynamic
        end

        def toggle_page_number_value
          text = format_page_numbers
          color = text == 'Enabled' ? COLOR_TEXT_SUCCESS : COLOR_TEXT_WARNING
          [text, color]
        end

        def toggle_highlight_value
          text = format_highlight_quotes
          color = text == 'On' ? COLOR_TEXT_SUCCESS : COLOR_TEXT_WARNING
          [text, color]
        end

        def format_page_numbers
          @state.get(%i[config show_page_numbers]) ? 'Enabled' : 'Disabled'
        end

        def format_highlight_quotes
          value = @state.get(%i[config highlight_quotes])
          (value.nil? ? true : !!value) ? 'On' : 'Off'
        end

        def toggle_kitty_images_value
          enabled = !!@state.get(%i[config kitty_images])
          text = enabled ? 'Enabled' : 'Disabled'
          color = enabled ? COLOR_TEXT_SUCCESS : COLOR_TEXT_DIM
          [text, color]
        end
      end
    end
  end
end
