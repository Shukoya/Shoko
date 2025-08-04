# frozen_string_literal: true

module EbookReader
  module Services
    class ReaderInputHandler
      # Handles navigation-specific input logic
      module NavigationHandlers
        def dynamic_navigation_handlers
          @dynamic_navigation_handlers ||= basic_nav_handlers
                                           .merge(chapter_nav_handlers)
                                           .merge(go_handlers)
        end

        private

        def basic_nav_handlers
          next_keys.merge(prev_keys)
        end

        def next_keys
          {
            'j' => -> { @reader.next_page },
            "\e[B" => -> { @reader.next_page },
            "\eOB" => -> { @reader.next_page },
            'l' => -> { @reader.next_page },
            ' ' => -> { @reader.next_page },
            "\e[C" => -> { @reader.next_page },
            "\eOC" => -> { @reader.next_page },
          }
        end

        def prev_keys
          {
            'k' => -> { @reader.prev_page },
            "\e[A" => -> { @reader.prev_page },
            "\eOA" => -> { @reader.prev_page },
            'h' => -> { @reader.prev_page },
            "\e[D" => -> { @reader.prev_page },
            "\eOD" => -> { @reader.prev_page },
          }
        end

        def chapter_nav_handlers
          {
            'n' => -> { @reader.next_chapter },
            'N' => -> { @reader.next_chapter },
            'p' => -> { @reader.prev_chapter },
            'P' => -> { @reader.prev_chapter },
          }
        end

        def go_handlers
          {
            'g' => -> { go_to_start_dynamic },
            'G' => -> { go_to_end_dynamic },
          }
        end

        def go_to_start_dynamic
          @reader.instance_variable_set(:@current_page_index, 0)
          @reader.send(:update_chapter_from_page_index)
        end

        def go_to_end_dynamic
          pm = @reader.instance_variable_get(:@page_manager)
          return unless pm

          @reader.instance_variable_set(:@current_page_index, pm.total_pages - 1)
          @reader.send(:update_chapter_from_page_index)
        end
      end
    end
  end
end
