# frozen_string_literal: true

module Shoko
  module Adapters::Output::Ui::Components
    module Reading
      # Factory for creating appropriate view renderers based on configuration
      class ViewRendererFactory
        def self.create(state, dependencies)
          case Application::Selectors::ConfigSelectors.view_mode(state)
          when :split
            SplitViewRenderer.new(dependencies)
          else
            mode = Application::Selectors::ConfigSelectors.page_numbering_mode(state)
            SingleViewRenderer.new(dependencies, page_numbering_mode: mode)
          end
        end
      end
    end
  end
end
