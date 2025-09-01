# frozen_string_literal: true

module EbookReader
  module Controllers
    # Handles all navigation-related functionality: pages, chapters, positioning
    class NavigationController
      def initialize(state, doc, page_manager, dependencies)
        @state = state
        @doc = doc
        @page_manager = page_manager
        @dependencies = dependencies
      end

      def next_page
        clear_selection!

        # Use page manager if available and in dynamic mode
        if @page_manager && Domain::Selectors::ConfigSelectors.page_numbering_mode(@state) == :dynamic
          max_pages = @page_manager.total_pages

          new_index = if Domain::Selectors::ConfigSelectors.view_mode(@state) == :split
                        [@state.get([:reader, :current_page_index]) + 2, max_pages - 1].min
                      else
                        [@state.get([:reader, :current_page_index]) + 1, max_pages - 1].min
                      end
          @state.update({[:reader, :current_page_index] => new_index})
        else
          # Fall back to absolute mode navigation
          new_index = if Domain::Selectors::ConfigSelectors.view_mode(@state) == :split
                        [@state.get([:reader, :current_page_index]) + 2, @state.get([:reader, :total_pages]) - 1].min
                      else
                        [@state.get([:reader, :current_page_index]) + 1, @state.get([:reader, :total_pages]) - 1].min
                      end
          @state.update({[:reader, :current_page_index] => new_index})

          # Check if we need to advance to next chapter
          if (@state.get([:reader, :current_page_index]) >= @state.get([:reader, :total_pages]) - 1) && 
             (@state.get([:reader, :current_chapter]) < (@doc&.chapters&.length || 1) - 1)
            next_chapter
          end
        end
      end

      def prev_page
        clear_selection!

        # Use page manager if available and in dynamic mode
        new_index = if Domain::Selectors::ConfigSelectors.view_mode(@state) == :split
                      [@state.get([:reader, :current_page_index]) - 2, 0].max
                    else
                      [@state.get([:reader, :current_page_index]) - 1, 0].max
                    end
        @state.update({[:reader, :current_page_index] => new_index})
        
        if !(@page_manager && Domain::Selectors::ConfigSelectors.page_numbering_mode(@state) == :dynamic) && 
           (@state.get([:reader, :current_page_index]) <= 0) && @state.get([:reader, :current_chapter]).positive?
          # Fall back to absolute mode navigation - check if we need to go to previous chapter
          prev_chapter
        end
      end

      def next_chapter
        clear_selection!
        max_chapter = (@doc&.chapters&.length || 1) - 1
        return unless @state.get([:reader, :current_chapter]) < max_chapter

        @state.update({
          [:reader, :current_chapter] => @state.get([:reader, :current_chapter]) + 1,
          [:reader, :current_page_index] => 0
        })
      end

      def prev_chapter
        clear_selection!
        return unless @state.get([:reader, :current_chapter]).positive?

        @state.update({
          [:reader, :current_chapter] => @state.get([:reader, :current_chapter]) - 1,
          [:reader, :current_page_index] => 0
        })
      end

      def go_to_start
        clear_selection!
        @state.update({
          [:reader, :current_chapter] => 0,
          [:reader, :current_page_index] => 0
        })
      end

      def go_to_end
        clear_selection!
        @state.update({
          [:reader, :current_chapter] => (@doc&.chapters&.length || 1) - 1,
          [:reader, :current_page_index] => @state.get([:reader, :total_pages]) - 1
        })
      end

      def jump_to_chapter(chapter_index)
        clear_selection!
        if Domain::Selectors::ConfigSelectors.page_numbering_mode(@state) == :dynamic && @page_manager
          # Rebuild page map for current config and terminal size to ensure indices are correct
          term = @dependencies.resolve(:terminal_service)
          height, width = term.size
          @page_manager.build_page_map(width, height, @doc, @state)
          # In dynamic mode, current_page_index is global across the book
          page_index = @page_manager.find_page_index(chapter_index, 0)
          page_index = 0 if page_index.nil? || page_index.negative?
          @state.update({
            [:reader, :current_chapter] => chapter_index,
            [:reader, :current_page_index] => page_index
          })
        else
          # Absolute mode uses per-chapter offsets
          @state.update({
            [:reader, :current_chapter] => chapter_index,
            [:reader, :single_page] => 0,
            [:reader, :left_page] => 0
          })
        end
      end

      def scroll_down
        clear_selection!
        # Scroll down is implemented as page navigation for consistency
        next_page
      end

      def scroll_up
        clear_selection!
        # Scroll up is implemented as page navigation for consistency
        prev_page
      end

      private

      # Hook for subclasses to override
      def clear_selection!
        # Clear any active selection state
        @state.update({
          [:reader, :selection] => nil,
          [:reader, :popup_menu] => nil
        })
      end
    end
  end
end
