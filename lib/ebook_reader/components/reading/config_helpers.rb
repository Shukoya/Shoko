# frozen_string_literal: true

module EbookReader
  module Components
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
          return EbookReader::Constants::DEFAULT_LINE_SPACING unless store

          EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(store) ||
            EbookReader::Constants::DEFAULT_LINE_SPACING
        rescue StandardError
          EbookReader::Constants::DEFAULT_LINE_SPACING
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
