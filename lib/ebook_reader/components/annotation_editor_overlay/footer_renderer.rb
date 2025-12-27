# frozen_string_literal: true

require_relative '../ui/text_utils'
require_relative '../../terminal'

module EbookReader
  module Components
    # Namespace for annotation editor overlay helpers.
    module AnnotationEditorOverlay
      # Renders the footer buttons for the annotation editor overlay.
      class FooterRenderer
        ButtonSpec = Struct.new(:row, :col, :label, :background, :width, keyword_init: true)

        def initialize(background:, button_fg:, save_bg:, cancel_bg:)
          @background = background
          @button_fg = button_fg
          @save_bg = save_bg
          @cancel_bg = cancel_bg
        end

        def render(surface, bounds, geometry)
          button_row = geometry.buttons_row
          fill_footer(surface, bounds, geometry, button_row)
          save_spec, cancel_spec = button_specs(geometry, button_row)

          draw_button(surface, bounds, save_spec)
          draw_button(surface, bounds, cancel_spec)

          abs_row = geometry.button_row_abs(bounds)
          {
            save: region_for(bounds, abs_row, save_spec),
            cancel: region_for(bounds, abs_row, cancel_spec),
          }
        end

        private

        def fill_footer(surface, bounds, geometry, button_row)
          footer_bg = "#{@background}#{' ' * geometry.text_width}#{Terminal::ANSI::RESET}"
          surface.write(bounds, button_row, geometry.text_x, footer_bg)
        end

        def button_specs(geometry, button_row)
          cancel_label = 'Cancel'
          save_label = 'Save'
          cancel_width = cancel_label.length + 4
          save_width = save_label.length + 4

          cancel_col = geometry.text_x + geometry.text_width - cancel_width
          cancel_col = [cancel_col, geometry.text_x].max
          save_col = cancel_col - 2 - save_width
          save_col = [save_col, geometry.text_x].max

          save_spec = ButtonSpec.new(row: button_row, col: save_col, label: save_label,
                                     background: @save_bg, width: save_width)
          cancel_spec = ButtonSpec.new(row: button_row, col: cancel_col, label: cancel_label,
                                       background: @cancel_bg, width: cancel_width)
          [save_spec, cancel_spec]
        end

        def draw_button(surface, bounds, spec)
          text = " #{spec.label} "
          padded = UI::TextUtils.pad_right(text, spec.width)
          surface.write(bounds, spec.row, spec.col,
                        "#{spec.background}#{@button_fg}#{padded}#{Terminal::ANSI::RESET}")
        end

        def region_for(bounds, abs_row, spec)
          { row: abs_row, col: bounds.x + spec.col - 1, width: spec.width }
        end
      end
    end
  end
end
