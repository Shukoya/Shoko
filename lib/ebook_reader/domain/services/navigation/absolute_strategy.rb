# frozen_string_literal: true

require_relative 'nav_context'

module EbookReader
  module Domain
    module Services
      module Navigation
        # Computes absolute-mode navigation offsets for single and split view.
        # Returns hashes describing desired state field updates; facade applies.
        module AbsoluteStrategy
          module_function

          def next_page(context)
            if context.view_mode == :split
              next_page_split(context)
            else
              next_page_single(context)
            end
          end

          def prev_page(context)
            if context.view_mode == :split
              prev_page_split(context)
            else
              prev_page_single(context)
            end
          end

          def scroll(context, direction, lines)
            lines = lines.to_i
            return {} if lines <= 0
            split = (context.view_mode == :split)
            cur = split ? (context.left_page || 0) : (context.single_page || 0)
            case direction
            when :up
              new_page = [cur - lines, 0].max
            when :down
              maxp = context.max_page_in_chapter || 0
              new_page = [cur + lines, maxp].min
            else
              return {}
            end

            return {} if new_page == cur

            if split
              { left_page: new_page, right_page: new_page + 1, current_page: new_page }
            else
              { single_page: new_page, current_page: new_page }
            end
          end

          def go_to_start(_context)
            { current_chapter: 0, current_page: 0, single_page: 0, left_page: 0, right_page: 1 }
          end

          def go_to_end(context)
            # Facade will compute last_page for last chapter; provide intent only.
            last_chapter = [context.total_chapters - 1, 0].max
            { current_chapter: last_chapter, align_to_last: true }
          end

          def jump_to_chapter(_context, index)
            { current_chapter: index, current_page: 0, single_page: 0, left_page: 0, right_page: 1 }
          end

          # --- helpers ---
          def next_page_single(context)
            cur = context.single_page || 0
            maxp = context.max_page_in_chapter || 0
            if cur < maxp
              { single_page: cur + 1, current_page: cur + 1 }
            elsif context.current_chapter < context.total_chapters - 1
              { advance_chapter: :next }
            else
              {}
            end
          end

          def prev_page_single(context)
            cur = context.single_page || 0
            if cur.positive?
              { single_page: cur - 1, current_page: cur - 1 }
            elsif context.current_chapter.positive?
              { advance_chapter: :prev, align: :single }
            else
              {}
            end
          end

          def next_page_split(context)
            left = context.left_page || 0
            maxp = context.max_page_in_chapter || 0
            step = 2
            next_left = left + step
            if next_left <= maxp
              { left_page: next_left, right_page: next_left + 1, current_page: next_left }
            elsif context.current_chapter < context.total_chapters - 1
              { advance_chapter: :next }
            else
              {}
            end
          end

          def prev_page_split(context)
            left = context.left_page || 0
            step = 2
            prev_left = left - step
            if prev_left >= 0
              { left_page: prev_left, right_page: prev_left + 1, current_page: prev_left }
            elsif context.current_chapter.positive?
              { advance_chapter: :prev, align: :split }
            else
              {}
            end
          end
        end
      end
    end
  end
end
