# frozen_string_literal: true

require_relative '../../models/bookmark'

module EbookReader
  module Components
    module Reading
      class ProgressTracker
        def initialize(app_state, doc, reader_state)
          @app_state = app_state
          @doc = doc
          @state = reader_state
        end

        def open_toc
          switch_mode(:toc)
          @state.update([:reader, :toc_selected], @state.get([:reader, :current_chapter]))
        end

        def add_bookmark
          line_offset = @app_state.config_state.view_mode == :split ? @state.get([:reader, :left_page]) : @state.get([:reader, :single_page])
          chapter = @doc.get_chapter(@state.get([:reader, :current_chapter]))
          return unless chapter

          text_snippet = (chapter.lines[line_offset] || 'Bookmark').strip[0, 50]

          new_bookmark = Models::Bookmark.new(
            chapter_index: @state.get([:reader, :current_chapter]),
            line_offset: line_offset,
            text_snippet: text_snippet,
            created_at: Time.now
          )
          bookmarks = @state.get([:reader, :bookmarks])
          bookmarks << new_bookmark
          @state.update([:reader, :bookmarks], bookmarks)
          persist_reading_state
          set_message('Bookmark added')
        end

        def open_bookmarks
          switch_mode(:bookmarks)
          @state.update([:reader, :bookmark_selected], 0)
        end

        def switch_mode(mode)
          @state.update([:reader, :mode], mode)
        end

        def quit_to_menu
          persist_reading_state
          @app_state.update([:current_view], :main_menu)
        end

        def quit_app
          persist_reading_state
          @app_state.update([:running], false)
        end

        def set_message(text, duration = 2)
          @state.update([:reader, :message], text)
          Thread.new do
            sleep duration
            @state.update([:reader, :message], nil)
          end
        end

        def persist_reading_state
          return unless @doc

          book_id = File.basename(@doc.path)
          offset = @app_state.config_state.view_mode == :split ? @state.get([:reader, :left_page]) : @state.get([:reader, :single_page])
          @app_state.save_reading_state(book_id,
                                        chapter: @state.get([:reader, :current_chapter]),
                                        offset: offset,
                                        bookmarks: @state.get([:reader, :bookmarks]))
        end
      end
    end
  end
end
