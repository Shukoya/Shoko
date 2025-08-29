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
          if @app_state.config_state.get([:config, :view_mode]) == :split
            @state.update([:reader, :left_page], @state.get([:reader, :left_page]) + 1)
            @state.update([:reader, :right_page], @state.get([:reader, :right_page]) + 1)
          else
            @state.update([:reader, :single_page], @state.get([:reader, :single_page]) + 1)
          end
        end

        def scroll_up
          if @app_state.config_state.get([:config, :view_mode]) == :split
            @state.update([:reader, :left_page], [@state.get([:reader, :left_page]) - 1, 0].max)
            @state.update([:reader, :right_page], [@state.get([:reader, :right_page]) - 1, 0].max)
          else
            @state.update([:reader, :single_page], [@state.get([:reader, :single_page]) - 1, 0].max)
          end
        end

        def next_page
          scroll_down
        end

        def prev_page
          scroll_up
        end

        def next_chapter
          return unless @state.get([:reader, :current_chapter]) < @doc.chapter_count - 1

          current = @state.get([:reader, :current_chapter])
          @state.dispatch(EbookReader::Domain::Actions::UpdateChapterAction.new(current + 1))
          reset_pages
        end

        def prev_chapter
          return unless @state.get([:reader, :current_chapter]).positive?

          current = @state.get([:reader, :current_chapter])
          @state.dispatch(EbookReader::Domain::Actions::UpdateChapterAction.new(current - 1))
          reset_pages
        end

        def go_to_start
          reset_pages
        end

        def go_to_end
          @state.dispatch(EbookReader::Domain::Actions::UpdateChapterAction.new(@doc.chapter_count - 1))
          reset_pages
        end

        def toggle_view_mode
          new_mode = @app_state.config_state.get([:config, :view_mode]) == :split ? :single : :split
          @app_state.config_state.update([:config, :view_mode], new_mode)
          reset_pages
        end

        def toggle_page_numbering_mode
          current = @app_state.config_state.get([:config, :page_numbering_mode])
          @app_state.config_state.update([:config, :page_numbering_mode], (current == :absolute ? :dynamic : :absolute))
        end

        def increase_line_spacing
          modes = %i[compact normal relaxed]
          current = modes.index(@app_state.config_state.get([:config, :line_spacing])) || 1
          return unless current < 2

          @app_state.config_state.update([:config, :line_spacing], modes[current + 1])
        end

        def decrease_line_spacing
          modes = %i[compact normal relaxed]
          current = modes.index(@app_state.config_state.get([:config, :line_spacing])) || 1
          return unless current.positive?

          @app_state.config_state.update([:config, :line_spacing], modes[current - 1])
        end

        def reset_pages
          @state.update([:reader, :single_page], 0)
          @state.update([:reader, :left_page], 0)
          @state.update([:reader, :right_page], 0)
        end
      end
    end
  end
end
