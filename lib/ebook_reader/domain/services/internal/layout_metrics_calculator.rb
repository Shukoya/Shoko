# frozen_string_literal: true

module EbookReader
  module Domain
    module Services
      module Internal
        # Responsible for deriving layout metrics (column width, content height,
        # lines per page) from terminal dimensions and user configuration.
        class LayoutMetricsCalculator
          def initialize(state_store)
            @state_store = state_store
          end

          def layout(width, height, config)
            [column_width(width, config), content_height(height)]
          end

          def lines_per_page
            state = current_state
            terminal_height = state.dig(:ui, :terminal_height) || 24
            content = content_height(terminal_height)
            adjust_for_spacing(content, state.dig(:config, :line_spacing) || EbookReader::Constants::DEFAULT_LINE_SPACING)
          end

          def lines_per_page_for(content_height, config)
            spacing = if config.respond_to?(:dig)
                        config.dig(:config, :line_spacing) || config.dig(:reader, :line_spacing)
                      else
                        EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(config)
                      end
            adjust_for_spacing(content_height,
                               spacing || EbookReader::Constants::DEFAULT_LINE_SPACING)
          end

          def column_width_from_state
            state = current_state
            column_width(state.dig(:ui, :terminal_width) || 80, state)
          end

          private

          def current_state
            @state_store.current_state
          end

          def column_width(width, config)
            view_mode = resolve_view_mode(config)
            if view_mode == :split
              [(width - 3) / 2, 20].max
            else
              (width * 0.9).to_i.clamp(30, 120)
            end
          end

          def content_height(height)
            [height - 4, 1].max
          end

          def adjust_for_spacing(height, line_spacing)
            multiplier = resolve_multiplier(line_spacing)
            adjusted = (height * multiplier).floor
            adjusted = height if multiplier >= 1.0 && adjusted < height
            [adjusted, 1].max
          end

          def resolve_view_mode(config)
            if config.respond_to?(:dig)
              config.dig(:reader, :view_mode) || config.dig(:config, :view_mode)
            else
              EbookReader::Domain::Selectors::ConfigSelectors.view_mode(config)
            end || :split
          end

          def resolve_multiplier(line_spacing)
            key = begin
                    line_spacing&.to_sym
                  rescue StandardError
                    nil
                  end
            EbookReader::Constants::LINE_SPACING_MULTIPLIERS.fetch(key, 1.0)
          end
        end
      end
    end
  end
end
