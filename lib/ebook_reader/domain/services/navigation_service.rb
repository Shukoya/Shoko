# frozen_string_literal: true

require_relative 'base_service'

module EbookReader
  module Domain
    module Services
      # Pure business logic for book navigation.
      # Replaces the coupled NavigationService with clean domain logic.
      class NavigationService < BaseService
        def initialize(dependencies_or_state_store, page_calculator = nil)
          # Support both DI container and legacy (state_store, page_calculator) signature
          if dependencies_or_state_store.respond_to?(:resolve)
            super(dependencies_or_state_store)
          else
            @dependencies = nil
            @state_store = dependencies_or_state_store
            @page_calculator = page_calculator
          end
        end

        # Navigate to next page
        def next_page
          current_state = @state_store.current_state
          view_mode = current_state.dig(:config, :view_mode)

          if dynamic_mode?
            return unless @page_calculator

            increment = view_mode == :split ? 2 : 1
            current_index = current_state.dig(:reader, :current_page_index) || 0
            total = @page_calculator.total_pages
            return if total <= 0

            new_index = clamp_index(current_index + increment, total)
            update_dynamic_index(new_index)
          else
            case view_mode
            when :single then next_page_single(current_state)
            when :split then next_page_split(current_state)
            else raise ArgumentError, "Unknown view mode: #{view_mode}"
            end
          end
        end

        # Navigate to previous page
        def prev_page
          current_state = @state_store.current_state
          view_mode = current_state.dig(:config, :view_mode)

          if dynamic_mode?
            return unless @page_calculator

            decrement = view_mode == :split ? 2 : 1
            current_index = current_state.dig(:reader, :current_page_index) || 0
            total = @page_calculator.total_pages
            return if total <= 0

            new_index = clamp_index(current_index - decrement, total)
            update_dynamic_index(new_index)
          else
            case view_mode
            when :single then prev_page_single(current_state)
            when :split then prev_page_split(current_state)
            else raise ArgumentError, "Unknown view mode: #{view_mode}"
            end
          end
        end

        # Navigate to specific chapter
        #
        # @param chapter_index [Integer] Zero-based chapter index
        def jump_to_chapter(chapter_index)
          validate_chapter_index(chapter_index)

          if dynamic_mode? && @page_calculator
            page_index = @page_calculator.find_page_index(chapter_index, 0)
            page_index = 0 if page_index.nil? || page_index.negative?
            @state_store.update({
              %i[reader current_chapter] => chapter_index,
              %i[reader current_page_index] => page_index,
            })
          else
            @state_store.update({
              %i[reader current_chapter] => chapter_index,
              %i[reader single_page] => 0,
              %i[reader left_page] => 0,
              %i[reader right_page] => 1,
            })
          end
        end

        # Navigate to beginning of book
        def go_to_start
          if dynamic_mode? && @page_calculator
            @state_store.update({
              %i[reader current_chapter] => 0,
              %i[reader current_page_index] => 0,
            })
          else
            @state_store.update({
              %i[reader current_chapter] => 0,
              %i[reader single_page] => 0,
              %i[reader left_page] => 0,
              %i[reader right_page] => 1,
            })
          end
        end

        # Navigate to end of book
        def go_to_end
          if dynamic_mode? && @page_calculator
            total = @page_calculator.total_pages
            return if total <= 0
            last_index = total - 1
            page = @page_calculator.get_page(last_index)
            updates = { %i[reader current_page_index] => last_index }
            updates[%i[reader current_chapter]] = page[:chapter_index] if page && page[:chapter_index]
            @state_store.update(updates)
          else
            current_state = @state_store.current_state
            total_chapters = current_state.dig(:reader, :total_chapters) || 0
            return if total_chapters.zero?

            last_chapter = total_chapters - 1
            last_page = calculate_last_page(last_chapter)
            @state_store.update({
              %i[reader current_chapter] => last_chapter,
              %i[reader single_page] => last_page,
              %i[reader left_page] => last_page,
              %i[reader right_page] => last_page + 1,
            })
          end
        end

        # Scroll within current page/view
        #
        # @param direction [Symbol] :up or :down
        # @param lines [Integer] Number of lines to scroll
        def scroll(direction, lines = 1)
          current_state = @state_store.current_state
          view_mode = current_state.dig(:config, :view_mode)
          
          # Use the appropriate page field based on view mode
          page_field = view_mode == :split ? :left_page : :single_page
          current_page = current_state.dig(:reader, page_field) || 0

          case direction
          when :up
            new_page = [current_page - lines, 0].max
          when :down
            max_page = calculate_max_page_for_chapter(current_state)
            new_page = [current_page + lines, max_page].min
          else
            raise ArgumentError, "Invalid scroll direction: #{direction}"
          end

          if new_page != current_page
            if view_mode == :split
              @state_store.update({
                %i[reader left_page] => new_page,
                %i[reader right_page] => new_page + 1,
              })
            else
              @state_store.set(%i[reader single_page], new_page)
            end
          end
        end

        protected

        def required_dependencies
          [:state_store]
        end

        def setup_service_dependencies
          @state_store = resolve(:state_store)
          @page_calculator = resolve(:page_calculator) if registered?(:page_calculator)
        end

        private

        def dynamic_mode?
          EbookReader::Domain::Selectors::ConfigSelectors.page_numbering_mode(@state_store) == :dynamic
        end

        def clamp_index(index, total)
          [[index, total - 1].min, 0].max
        end

        def update_dynamic_index(new_index)
          page = @page_calculator&.get_page(new_index)
          if page
            @state_store.update({
              %i[reader current_page_index] => new_index,
              %i[reader current_chapter] => page[:chapter_index] || (@state_store.current_state.dig(:reader, :current_chapter) || 0),
            })
          else
            @state_store.set(%i[reader current_page_index], new_index)
          end
        end

        def next_page_single(state)
          current_chapter = state.dig(:reader, :current_chapter) || 0
          current_page = state.dig(:reader, :single_page) || 0
          max_page = calculate_max_page_for_chapter(state)
          
          # DEBUG: Log navigation attempts
          File.open('/tmp/nav_debug.log', 'a') do |f|
            f.puts "Navigation: ch=#{current_chapter}, pg=#{current_page}, max=#{max_page}, calc=#{@page_calculator ? 'YES' : 'NO'} at #{Time.now.strftime('%H:%M:%S')}"
          end
          
          if current_page < max_page
            @state_store.set(%i[reader single_page], current_page + 1)
            File.open('/tmp/nav_debug.log', 'a') do |f|
              f.puts "  -> Updated to page #{current_page + 1}"
            end
          elsif can_advance_chapter?(state)
            jump_to_chapter(current_chapter + 1)
            File.open('/tmp/nav_debug.log', 'a') do |f|
              f.puts "  -> Advanced to chapter #{current_chapter + 1}"
            end
          else
            File.open('/tmp/nav_debug.log', 'a') do |f|
              f.puts "  -> No navigation possible (at end)"
            end
          end
        end

        def prev_page_single(state)
          current_chapter = state.dig(:reader, :current_chapter) || 0
          current_page = state.dig(:reader, :single_page) || 0

          if current_page.positive?
            @state_store.set(%i[reader single_page], current_page - 1)
          elsif current_chapter.positive?
            prev_chapter_index = current_chapter - 1
            last_page = calculate_last_page(prev_chapter_index)
            @state_store.update({
                                  %i[reader current_chapter] => prev_chapter_index,
                                  %i[reader single_page] => last_page,
                                })
          end
        end

        def next_page_split(state)
          # Split mode shows two pages at once
          current_chapter = state.dig(:reader, :current_chapter) || 0
          current_left_page = state.dig(:reader, :left_page) || 0
          max_page = calculate_max_page_for_chapter(state)
          
          File.open('/tmp/nav_debug.log', 'a') do |f|
            f.puts "SPLIT Navigation: ch=#{current_chapter}, left_pg=#{current_left_page}, max=#{max_page}, calc=#{@page_calculator ? 'YES' : 'NO'}"
          end

          if current_left_page + 2 <= max_page
            File.open('/tmp/nav_debug.log', 'a') do |f|
              f.puts "  -> Updating split pages to #{current_left_page + 2}, #{current_left_page + 3}"
            end
            @state_store.update({
              %i[reader left_page] => current_left_page + 2,
              %i[reader right_page] => current_left_page + 3,
            })
          elsif can_advance_chapter?(state)
            File.open('/tmp/nav_debug.log', 'a') do |f|
              f.puts "  -> Advancing to next chapter"
            end
            jump_to_chapter(current_chapter + 1)
          else
            File.open('/tmp/nav_debug.log', 'a') do |f|
              f.puts "  -> Cannot navigate (at end)"
            end
          end
        end

        def prev_page_split(state)
          current_chapter = state.dig(:reader, :current_chapter) || 0
          current_left_page = state.dig(:reader, :left_page) || 0

          if current_left_page >= 2
            @state_store.update({
              %i[reader left_page] => current_left_page - 2,
              %i[reader right_page] => current_left_page - 1,
            })
          elsif current_chapter.positive?
            prev_chapter_index = current_chapter - 1
            last_page = calculate_last_page(prev_chapter_index)
            # Align to even page for split mode
            aligned_left_page = (last_page / 2) * 2
            @state_store.update({
              %i[reader current_chapter] => prev_chapter_index,
              %i[reader left_page] => aligned_left_page,
              %i[reader right_page] => aligned_left_page + 1,
            })
          end
        end

        def validate_chapter_index(index)
          raise ArgumentError, 'Chapter index must be non-negative' if index.negative?

          current_state = @state_store.current_state
          total_chapters = current_state.dig(:reader, :total_chapters) || 0

          return unless index >= total_chapters

          raise ArgumentError, "Chapter index #{index} exceeds total chapters #{total_chapters}"
        end

        def can_advance_chapter?(state)
          current_chapter = state.dig(:reader, :current_chapter) || 0
          total_chapters = state.dig(:reader, :total_chapters) || 0
          current_chapter < total_chapters - 1
        end

        def calculate_max_page_for_chapter(state)
          return 0 unless @page_calculator

          current_chapter = state.dig(:reader, :current_chapter) || 0
          result = @page_calculator.calculate_pages_for_chapter(current_chapter)
          
          File.open('/tmp/nav_debug.log', 'a') do |f|
            f.puts "    calc_max_page: chapter=#{current_chapter}, result=#{result}, calc_class=#{@page_calculator.class}"
          end
          
          result
        end

        def calculate_last_page(chapter_index)
          return 0 unless @page_calculator

          @page_calculator.calculate_pages_for_chapter(chapter_index)
        end
      end
    end
  end
end
