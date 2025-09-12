# frozen_string_literal: true

require_relative 'nav_context'

module EbookReader
  module Domain
    module Services
      module Navigation
        module StrategyFactory
          module_function

          def select(context)
            context.mode == :dynamic ? DynamicStrategy : AbsoluteStrategy
          end
        end
      end
    end
  end
end

