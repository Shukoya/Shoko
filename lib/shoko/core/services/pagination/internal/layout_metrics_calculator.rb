# frozen_string_literal: true

require_relative '../../pagination'
require_relative '../../layout_service'

module Shoko::Core::Services::Pagination::Internal
        # Responsible for deriving layout metrics (column width, content height,
        # lines per page) from terminal dimensions and user configuration.
        class LayoutMetricsCalculator
          def initialize(state_store, layout_service: nil)
            @state_store = state_store
            @layout_service = layout_service || Shoko::Core::Services::LayoutService.new(nil)
          end

          def layout(width, height, config)
            view_mode = resolve_view_mode(config)
            @layout_service.calculate_metrics(width, height, view_mode)
          end

          def lines_per_page
            state = current_state
            width = state.dig(:ui, :terminal_width) || 80
            height = state.dig(:ui, :terminal_height) || 24
            view_mode = resolve_view_mode(state)
            _, content = @layout_service.calculate_metrics(width, height, view_mode)
            spacing = state.dig(:config, :line_spacing) || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
            @layout_service.adjust_for_line_spacing(content, spacing)
          end

          def lines_per_page_for(content_height, config)
            spacing = if config.respond_to?(:dig)
                        config.dig(:config, :line_spacing)
                      else
                        Shoko::Application::Selectors::ConfigSelectors.line_spacing(config)
                      end
            @layout_service.adjust_for_line_spacing(content_height,
                                                    spacing || Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING)
          end

          def column_width_from_state
            state = current_state
            width = state.dig(:ui, :terminal_width) || 80
            column_width(width, state)
          end

          private

          def current_state
            @state_store.current_state
          end

          def column_width(width, config)
            view_mode = resolve_view_mode(config)
            if view_mode == :split
              @layout_service.split_column_width(width)
            else
              @layout_service.single_column_width(width)
            end
          end

          def content_height(height)
            @layout_service.content_area_height(height)
          end

          def resolve_view_mode(config)
            if config.respond_to?(:dig)
              config.dig(:config, :view_mode)
            else
              Shoko::Application::Selectors::ConfigSelectors.view_mode(config)
            end || :split
          end
        end
end
