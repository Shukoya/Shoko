# frozen_string_literal: true

module EbookReader
  module Domain
    module Services
      # Pure business logic for book navigation.
      # Replaces the coupled NavigationService with clean domain logic.
      class NavigationService
        def initialize(state_store, page_calculator = nil)
          @state_store = state_store
          @page_calculator = page_calculator
        end

        # Navigate to next page
        def next_page
          current_state = @state_store.current_state
          view_mode = current_state.dig(:reader, :view_mode)
          
          case view_mode
          when :single
            next_page_single(current_state)
          when :split  
            next_page_split(current_state)
          else
            raise ArgumentError, "Unknown view mode: #{view_mode}"
          end
        end

        # Navigate to previous page
        def prev_page
          current_state = @state_store.current_state
          view_mode = current_state.dig(:reader, :view_mode)
          
          case view_mode
          when :single
            prev_page_single(current_state)
          when :split
            prev_page_split(current_state)
          else
            raise ArgumentError, "Unknown view mode: #{view_mode}"
          end
        end

        # Navigate to specific chapter
        #
        # @param chapter_index [Integer] Zero-based chapter index
        def jump_to_chapter(chapter_index)
          validate_chapter_index(chapter_index)
          
          @state_store.update({
            [:reader, :current_chapter] => chapter_index,
            [:reader, :current_page] => 0
          })
        end

        # Navigate to beginning of book
        def go_to_start
          @state_store.update({
            [:reader, :current_chapter] => 0,
            [:reader, :current_page] => 0
          })
        end

        # Navigate to end of book
        def go_to_end
          current_state = @state_store.current_state
          total_chapters = current_state.dig(:reader, :total_chapters) || 0
          return if total_chapters == 0
          
          last_chapter = total_chapters - 1
          @state_store.update({
            [:reader, :current_chapter] => last_chapter,
            [:reader, :current_page] => calculate_last_page(last_chapter)
          })
        end

        # Scroll within current page/view
        #
        # @param direction [Symbol] :up or :down
        # @param lines [Integer] Number of lines to scroll
        def scroll(direction, lines = 1)
          current_state = @state_store.current_state
          current_page = current_state.dig(:reader, :current_page) || 0
          
          case direction
          when :up
            new_page = [current_page - lines, 0].max
          when :down
            max_page = calculate_max_page_for_chapter(current_state)
            new_page = [current_page + lines, max_page].min
          else
            raise ArgumentError, "Invalid scroll direction: #{direction}"
          end
          
          @state_store.set([:reader, :current_page], new_page) if new_page != current_page
        end

        private

        def next_page_single(state)
          current_chapter = state.dig(:reader, :current_chapter) || 0
          current_page = state.dig(:reader, :current_page) || 0
          max_page = calculate_max_page_for_chapter(state)
          
          if current_page < max_page
            @state_store.set([:reader, :current_page], current_page + 1)
          elsif can_advance_chapter?(state)
            jump_to_chapter(current_chapter + 1)
          end
        end

        def prev_page_single(state)
          current_chapter = state.dig(:reader, :current_chapter) || 0
          current_page = state.dig(:reader, :current_page) || 0
          
          if current_page > 0
            @state_store.set([:reader, :current_page], current_page - 1)
          elsif current_chapter > 0
            prev_chapter_index = current_chapter - 1
            last_page = calculate_last_page(prev_chapter_index)
            @state_store.update({
              [:reader, :current_chapter] => prev_chapter_index,
              [:reader, :current_page] => last_page
            })
          end
        end

        def next_page_split(state)
          # Split mode shows two pages at once
          current_chapter = state.dig(:reader, :current_chapter) || 0
          current_page = state.dig(:reader, :current_page) || 0
          max_page = calculate_max_page_for_chapter(state)
          
          if current_page + 2 <= max_page
            @state_store.set([:reader, :current_page], current_page + 2)
          elsif can_advance_chapter?(state)
            jump_to_chapter(current_chapter + 1)
          end
        end

        def prev_page_split(state)
          current_chapter = state.dig(:reader, :current_chapter) || 0
          current_page = state.dig(:reader, :current_page) || 0
          
          if current_page >= 2
            @state_store.set([:reader, :current_page], current_page - 2)
          elsif current_chapter > 0
            prev_chapter_index = current_chapter - 1
            last_page = calculate_last_page(prev_chapter_index)
            # Align to even page for split mode
            aligned_page = (last_page / 2) * 2
            @state_store.update({
              [:reader, :current_chapter] => prev_chapter_index,
              [:reader, :current_page] => aligned_page
            })
          end
        end

        def validate_chapter_index(index)
          raise ArgumentError, "Chapter index must be non-negative" if index < 0
          
          current_state = @state_store.current_state
          total_chapters = current_state.dig(:reader, :total_chapters) || 0
          
          if index >= total_chapters
            raise ArgumentError, "Chapter index #{index} exceeds total chapters #{total_chapters}"
          end
        end

        def can_advance_chapter?(state)
          current_chapter = state.dig(:reader, :current_chapter) || 0
          total_chapters = state.dig(:reader, :total_chapters) || 0
          current_chapter < total_chapters - 1
        end

        def calculate_max_page_for_chapter(state)
          return 0 unless @page_calculator
          
          current_chapter = state.dig(:reader, :current_chapter) || 0
          @page_calculator.calculate_pages_for_chapter(current_chapter)
        end

        def calculate_last_page(chapter_index)
          return 0 unless @page_calculator
          
          @page_calculator.calculate_pages_for_chapter(chapter_index)
        end
      end
    end
  end
end