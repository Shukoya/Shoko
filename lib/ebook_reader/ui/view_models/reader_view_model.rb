# frozen_string_literal: true

module EbookReader
  module UI
    module ViewModels
      # Pure data structure for reader view rendering.
      # Eliminates component coupling to controllers and services.
      class ReaderViewModel
        attr_reader :current_chapter, :total_chapters, :current_page, :total_pages,
                    :chapter_title, :view_mode, :sidebar_visible, :mode, :message,
                    :bookmarks, :toc_entries, :content_lines, :page_info

        def initialize(
          current_chapter: 0,
          total_chapters: 0,
          current_page: 0,
          total_pages: 0,
          chapter_title: '',
          view_mode: :split,
          sidebar_visible: false,
          mode: :read,
          message: nil,
          bookmarks: [],
          toc_entries: [],
          content_lines: [],
          page_info: {}
        )
          @current_chapter = current_chapter
          @total_chapters = total_chapters
          @current_page = current_page
          @total_pages = total_pages
          @chapter_title = chapter_title
          @view_mode = view_mode
          @sidebar_visible = sidebar_visible
          @mode = mode
          @message = message
          @bookmarks = bookmarks
          @toc_entries = toc_entries
          @content_lines = content_lines
          @page_info = page_info
          freeze
        end

        # Derived properties
        def progress_percentage
          return 0 if total_pages == 0
          ((current_page.to_f / total_pages) * 100).round(1)
        end

        def chapter_progress
          return "0/0" if total_chapters == 0
          "#{current_chapter + 1}/#{total_chapters}"
        end

        def page_progress
          return "0/0" if total_pages == 0
          "#{current_page + 1}/#{total_pages}"
        end

        def split_mode?
          view_mode == :split
        end

        def single_mode?
          view_mode == :single
        end

        def has_message?
          !message.nil? && !message.empty?
        end

        def has_bookmarks?
          !bookmarks.empty?
        end

        def has_toc?
          !toc_entries.empty?
        end

        # Create new instance with updates
        def with(**changes)
          current_attributes = {
            current_chapter: current_chapter,
            total_chapters: total_chapters,
            current_page: current_page,
            total_pages: total_pages,
            chapter_title: chapter_title,
            view_mode: view_mode,
            sidebar_visible: sidebar_visible,
            mode: mode,
            message: message,
            bookmarks: bookmarks,
            toc_entries: toc_entries,
            content_lines: content_lines,
            page_info: page_info
          }
          
          self.class.new(**current_attributes.merge(changes))
        end
      end

      class MenuViewModel
        attr_reader :mode, :selected_index, :items, :search_query, :search_active,
                    :message, :title

        def initialize(
          mode: :main,
          selected_index: 0,
          items: [],
          search_query: '',
          search_active: false,
          message: nil,
          title: 'EBook Reader'
        )
          @mode = mode
          @selected_index = selected_index
          @items = items
          @search_query = search_query
          @search_active = search_active
          @message = message
          @title = title
          freeze
        end

        def selected_item
          items[selected_index]
        end

        def has_items?
          !items.empty?
        end

        def has_message?
          !message.nil? && !message.empty?
        end

        def searching?
          search_active
        end

        def with(**changes)
          current_attributes = {
            mode: mode,
            selected_index: selected_index,
            items: items,
            search_query: search_query,
            search_active: search_active,
            message: message,
            title: title
          }
          
          self.class.new(**current_attributes.merge(changes))
        end
      end
    end
  end
end