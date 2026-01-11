# frozen_string_literal: true

module Shoko
  module Adapters::Output::Ui::Components
    module Reading
      # Shared helpers for resolving configuration values from the state store.
      module ConfigHelpers
        module_function

        def config_store(config)
          return config if config.respond_to?(:get)
          return config.state if config.respond_to?(:state) && config.state.respond_to?(:get)

          nil
        end

        def line_spacing(config)
          store = config_store(config)
          return Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING unless store

          Shoko::Application::Selectors::ConfigSelectors.line_spacing(store) ||
            Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
        rescue StandardError
          Shoko::Core::Models::ReaderSettings::DEFAULT_LINE_SPACING
        end

        def highlight_quotes?(store)
          value = store&.get(%i[config highlight_quotes])
          value.nil? || value
        rescue StandardError
          true
        end

        def highlight_keywords?(store)
          !!store&.get(%i[config highlight_keywords])
        rescue StandardError
          false
        end
      end
    end
  end
end
