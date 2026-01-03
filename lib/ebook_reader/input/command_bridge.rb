# frozen_string_literal: true

require_relative '../application/commands/application_commands'
require_relative '../application/commands/navigation_commands'
require_relative '../application/commands/sidebar_commands'
require_relative '../application/commands/conditional_navigation_commands'
require_relative '../application/commands/menu_commands'
require_relative '../application/commands/bookmark_commands'
require_relative '../application/commands/reader_commands'

module EbookReader
  module Input
    # Bridge to create Application commands for Input system usage.
    # Provides a clean interface for the Input system to use Application commands
    # while maintaining backward compatibility during the migration.
    class CommandBridge
      class << self
        # Create navigation commands for reader movement
        #
        # @param action [Symbol] Navigation action (:next_page, :prev_page, etc.)
        # @return [Application::Commands::NavigationCommand]
        def navigation_command(action)
          Application::Commands::NavigationCommand.new(action)
        end

        # Create application lifecycle commands
        #
        # @param action [Symbol] Application action (:quit, :switch_mode, etc.)
        # @return [Application::Commands::ApplicationCommand]
        def application_command(action)
          Application::Commands::ApplicationCommand.new(action)
        end

        # Create bookmark operation commands
        #
        # @param action [Symbol] Bookmark action (:add, :remove, :navigate, etc.)
        # @return [Application::Commands::BookmarkCommand]
        def bookmark_command(action)
          Application::Commands::BookmarkCommand.new(action)
        end

        # Create sidebar navigation commands
        #
        # @param action [Symbol] Sidebar action (:up, :down, :select)
        # @return [Application::Commands::SidebarCommand]
        def sidebar_command(action)
          Application::Commands::SidebarCommand.new(action)
        end

        # Create conditional navigation commands
        #
        # @param type [Symbol] Type of conditional navigation
        # @return [Application::Commands::ConditionalNavigationCommand]
        def conditional_navigation_command(type)
          case type
          when :up_or_sidebar then Application::Commands::ConditionalNavigationCommand.up_or_sidebar
          when :down_or_sidebar then Application::Commands::ConditionalNavigationCommand.down_or_sidebar
          when :select_or_sidebar then Application::Commands::ConditionalNavigationCommand.select_or_sidebar
          else
            raise ArgumentError, "Unknown conditional navigation type: #{type}"
          end
        end

        # Convert Input system symbols to appropriate Application commands
        # This method helps during migration by automatically routing
        # common input symbols to their Application command equivalents.
        #
        # @param symbol [Symbol] Input symbol
        # @param context [Object] Execution context
        # @return [Application::Commands::BaseCommand, nil] Command or nil if no mapping
        def symbol_to_command(symbol, _context = nil)
          case symbol
          # Navigation commands - now use Application commands
          when :next_page then navigation_command(:next_page)
          when :prev_page then navigation_command(:prev_page)
          when :next_chapter then navigation_command(:next_chapter)
          when :prev_chapter then navigation_command(:prev_chapter)
          when :scroll_up then Application::Commands::NavigationCommandFactory.scroll_up
          when :scroll_down then Application::Commands::NavigationCommandFactory.scroll_down
          when :go_to_start then navigation_command(:go_to_start)
          when :go_to_end then navigation_command(:go_to_end)
          # Application commands
          when :show_help then application_command(:show_help)
          when :open_toc then application_command(:show_toc)
          when :open_bookmarks then application_command(:show_bookmarks)
          when :open_annotations then application_command(:show_annotations)
          when :quit_to_menu then application_command(:quit_to_menu)
          when :add_bookmark then Application::Commands::BookmarkCommandFactory.add_bookmark
          # Conditional navigation commands
          when :conditional_up then conditional_navigation_command(:up_or_sidebar)
          when :conditional_down then conditional_navigation_command(:down_or_sidebar)
          when :conditional_select then conditional_navigation_command(:select_or_sidebar)
          # Direct sidebar commands
          when :sidebar_up then sidebar_command(:up)
          when :sidebar_down then sidebar_command(:down)
          when :sidebar_select then sidebar_command(:select)
          # Menu commands
          when :menu_up then Application::Commands::MenuCommand.new(:menu_up)
          when :menu_down then Application::Commands::MenuCommand.new(:menu_down)
          when :menu_select then Application::Commands::MenuCommand.new(:menu_select)
          when :menu_quit then Application::Commands::MenuCommand.new(:menu_quit)
          when :back_to_menu then Application::Commands::MenuCommand.new(:back_to_menu)
          when :browse_up then Application::Commands::MenuCommand.new(:browse_up)
          when :browse_down then Application::Commands::MenuCommand.new(:browse_down)
          when :browse_select then Application::Commands::MenuCommand.new(:browse_select)
          when :library_up then Application::Commands::MenuCommand.new(:library_up)
          when :library_down then Application::Commands::MenuCommand.new(:library_down)
          when :library_select then Application::Commands::MenuCommand.new(:library_select)
          when :settings_up then Application::Commands::MenuCommand.new(:settings_up)
          when :settings_down then Application::Commands::MenuCommand.new(:settings_down)
          when :settings_select then Application::Commands::MenuCommand.new(:settings_select)
          # recent_* commands removed
          when :start_search then Application::Commands::MenuCommand.new(:start_search)
          when :exit_search then Application::Commands::MenuCommand.new(:exit_search)
          # Annotations-related menu commands
          when :annotations_up then Application::Commands::MenuCommand.new(:annotations_up)
          when :annotations_down then Application::Commands::MenuCommand.new(:annotations_down)
          when :annotations_select then Application::Commands::MenuCommand.new(:annotations_select)
          when :annotations_edit then Application::Commands::MenuCommand.new(:annotations_edit)
          when :annotations_delete then Application::Commands::MenuCommand.new(:annotations_delete)
          when :annotation_detail_open then Application::Commands::MenuCommand.new(:annotation_detail_open)
          when :annotation_detail_edit then Application::Commands::MenuCommand.new(:annotation_detail_edit)
          when :annotation_detail_delete then Application::Commands::MenuCommand.new(:annotation_detail_delete)
          when :annotation_detail_back then Application::Commands::MenuCommand.new(:annotation_detail_back)
          # Settings actions
          when :toggle_view_mode then Application::Commands::MenuCommand.new(:toggle_view_mode)
          when :cycle_line_spacing then Application::Commands::MenuCommand.new(:cycle_line_spacing)
          when :toggle_page_numbers then Application::Commands::MenuCommand.new(:toggle_page_numbers)
          when :toggle_page_numbering_mode then Application::Commands::MenuCommand.new(:toggle_page_numbering_mode)
          when :toggle_highlight_quotes then Application::Commands::MenuCommand.new(:toggle_highlight_quotes)
          when :toggle_kitty_images then Application::Commands::MenuCommand.new(:toggle_kitty_images)
          when :wipe_cache then Application::Commands::MenuCommand.new(:wipe_cache)
          # Reader mode transitions
          when :exit_help then Application::Commands::ReaderModeCommand.new(:exit_help)
          end
        end

        # Check if a symbol can be converted to an Application command
        #
        # @param symbol [Symbol] Input symbol to check
        # @return [Boolean] True if symbol has Application command equivalent
        def command?(symbol)
          !symbol_to_command(symbol).nil?
        end
      end
    end
  end
end
