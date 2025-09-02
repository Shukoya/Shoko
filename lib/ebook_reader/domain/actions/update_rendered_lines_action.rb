# frozen_string_literal: true

module EbookReader
  module Domain
    module Actions
      # Action for updating rendered lines cache
      class UpdateRenderedLinesAction < BaseAction
        def initialize(rendered_lines)
          super(rendered_lines: rendered_lines)
        end

        def apply(state)
          state.update({ %i[reader rendered_lines] => payload[:rendered_lines] })
        end
      end

      # Convenience action for clearing rendered lines
      class ClearRenderedLinesAction < UpdateRenderedLinesAction
        def initialize
          super({})
        end
      end
    end
  end
end
