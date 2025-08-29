# frozen_string_literal: true

module EbookReader
  module Domain
    module Actions
      # Action for updating configuration values
      class UpdateConfigAction < BaseAction
        def initialize(config_updates)
          # Expects hash like: { view_mode: :split, line_spacing: :normal }
          super(config_updates)
        end

        def apply(state)
          payload.each do |config_field, value|
            state.update([:config, config_field], value)
          end
        end
      end
    end
  end
end