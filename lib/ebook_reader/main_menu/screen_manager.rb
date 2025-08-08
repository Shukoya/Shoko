# frozen_string_literal: true

module EbookReader
  class MainMenu
    # Handles drawing of different main menu screens
    class ScreenManager
      def initialize(menu)
        @menu = menu
      end

      def draw_screen
        Terminal.start_frame
        height, width = Terminal.size

        case @menu.instance_variable_get(:@mode)
        when :menu then draw_main_menu(height, width)
        when :browse then draw_browse_screen(height, width)
        when :recent then draw_recent_screen(height, width)
        when :settings then draw_settings_screen(height, width)
        when :open_file then draw_open_file_screen(height, width)
        when :annotations then draw_annotations_screen(height, width)
        when :annotation_editor then draw_annotation_editor_screen(height, width)
        end

        Terminal.end_frame
      end

      private

      def draw_annotation_editor_screen(height, width)
        @menu.instance_variable_get(:@annotation_editor_screen).draw(height, width)
      end

      def draw_annotations_screen(height, width)
        @menu.instance_variable_get(:@annotations_screen).draw(height, width)
      end

      def draw_main_menu(height, width)
        screen = @menu.instance_variable_get(:@menu_screen)
        screen.selected = @menu.instance_variable_get(:@selected)
        screen.draw(height, width)
      end

      def draw_browse_screen(height, width)
        screen = @menu.instance_variable_get(:@browse_screen)
        screen.selected = @menu.instance_variable_get(:@browse_selected)
        screen.search_query = @menu.instance_variable_get(:@search_query)
        screen.search_cursor = @menu.instance_variable_get(:@search_cursor)
        screen.filtered_epubs = @menu.instance_variable_get(:@filtered_epubs)
        screen.draw(height, width)
      end

      def draw_recent_screen(height, width)
        screen = @menu.instance_variable_get(:@recent_screen)
        screen.selected = @menu.instance_variable_get(:@browse_selected)
        screen.draw(height, width)
      end

      def draw_settings_screen(height, width)
        @menu.instance_variable_get(:@settings_screen).draw(height, width)
      end

      def draw_open_file_screen(height, width)
        @menu.instance_variable_get(:@open_file_screen).draw(height, width)
      end
    end
  end
end
