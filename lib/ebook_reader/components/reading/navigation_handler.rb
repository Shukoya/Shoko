# frozen_string_literal: true

module EbookReader
  module Components
    module Reading
      class NavigationHandler
        def initialize(app_state, doc, reader_state)
          @app_state = app_state
          @doc = doc
          @state = reader_state
        end

        def scroll_down
          if @app_state.config_state.view_mode == :split
            @state.left_page += 1
            @state.right_page += 1
          else
            @state.single_page += 1
          end
        end

        def scroll_up
          if @app_state.config_state.view_mode == :split
            @state.left_page = [@state.left_page - 1, 0].max
            @state.right_page = [@state.right_page - 1, 0].max
          else
            @state.single_page = [@state.single_page - 1, 0].max
          end
        end

        def next_page
          scroll_down
        end

        def prev_page
          scroll_up
        end

        def next_chapter
          return unless @state.current_chapter < @doc.chapter_count - 1

          @state.current_chapter += 1
          reset_pages
        end

        def prev_chapter
          return unless @state.current_chapter.positive?

          @state.current_chapter -= 1
          reset_pages
        end

        def go_to_start
          reset_pages
        end

        def go_to_end
          @state.current_chapter = @doc.chapter_count - 1
          reset_pages
        end

        def toggle_view_mode
          new_mode = @app_state.config_state.view_mode == :split ? :single : :split
          @app_state.config_state.view_mode = new_mode
          reset_pages
        end

        def toggle_page_numbering_mode
          current = @app_state.config_state.page_numbering_mode
          @app_state.config_state.page_numbering_mode = (current == :absolute ? :dynamic : :absolute)
        end

        def increase_line_spacing
          modes = %i[compact normal relaxed]
          current = modes.index(@app_state.config_state.line_spacing) || 1
          return unless current < 2

          @app_state.config_state.line_spacing = modes[current + 1]
        end

        def decrease_line_spacing
          modes = %i[compact normal relaxed]
          current = modes.index(@app_state.config_state.line_spacing) || 1
          return unless current.positive?

          @app_state.config_state.line_spacing = modes[current - 1]
        end

        def reset_pages
          @state.single_page = 0
          @state.left_page = 0
          @state.right_page = 0
        end
      end
    end
  end
end
