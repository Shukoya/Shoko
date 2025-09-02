# frozen_string_literal: true

module EbookReader
  module Domain
    module Selectors
      # Selectors for configuration state
      module ConfigSelectors
        def self.view_mode(state)
          state.get(%i[config view_mode])
        end

        def self.line_spacing(state)
          state.get(%i[config line_spacing])
        end

        def self.page_numbering_mode(state)
          state.get(%i[config page_numbering_mode])
        end

        def self.theme(state)
          state.get(%i[config theme])
        end

        def self.show_page_numbers(state)
          state.get(%i[config show_page_numbers])
        end

        def self.show_page_numbers?(state)
          show_page_numbers(state)
        end

        def self.highlight_quotes(state)
          state.get(%i[config highlight_quotes])
        end

        def self.highlight_quotes?(state)
          highlight_quotes(state)
        end

        def self.highlight_keywords(state)
          state.get(%i[config highlight_keywords])
        end

        def self.highlight_keywords?(state)
          highlight_keywords(state)
        end

        def self.config_hash(state)
          state.get([:config])
        end
      end
    end
  end
end
