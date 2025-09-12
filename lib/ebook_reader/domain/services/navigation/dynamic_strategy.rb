# frozen_string_literal: true

require_relative 'nav_context'

module EbookReader
  module Domain
    module Services
      module Navigation
        # Computes dynamic-mode navigation targets from an immutable context.
        # Returns simple hashes describing state changes; facade applies them.
        module DynamicStrategy
          module_function

          def next_page(context)
            inc = context.view_mode == :split ? 2 : 1
            total = context.dynamic_total_pages.to_i
            return {} if total <= 0

            new_index = [[context.current_page_index + inc, 0].max, total - 1].min
            { current_page_index: new_index }
          end

          def prev_page(context)
            dec = context.view_mode == :split ? 2 : 1
            total = context.dynamic_total_pages.to_i
            return {} if total <= 0

            new_index = [[context.current_page_index - dec, 0].max, total - 1].min
            { current_page_index: new_index }
          end

          def go_to_start(_context)
            { current_chapter: 0, current_page_index: 0 }
          end

          def go_to_end(context)
            total = context.dynamic_total_pages.to_i
            return {} if total <= 0

            { current_page_index: total - 1 }
          end

          def jump_to_chapter(context, index)
            # Facade will map chapter -> page index precisely; here provide chapter intent.
            { current_chapter: index, current_page_index: 0 }
          end
        end
      end
    end
  end
end

