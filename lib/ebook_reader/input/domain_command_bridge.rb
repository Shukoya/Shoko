# frozen_string_literal: true

require_relative '../domain/commands/sidebar_commands'
require_relative '../domain/commands/conditional_navigation_commands'
require_relative '../domain/commands/menu_commands'

module EbookReader
  module Input
    # Bridge to create Domain commands for Input system usage.
    # Provides a clean interface for the Input system to use Domain commands
    # while maintaining backward compatibility during the migration.
    class DomainCommandBridge
      class << self
        # Create navigation commands for reader movement
        #
        # @param action [Symbol] Navigation action (:next_page, :prev_page, etc.)
        # @return [Domain::Commands::NavigationCommand]
        def navigation_command(action)
          Domain::Commands::NavigationCommand.new(action)
        end

        # Create application lifecycle commands
        #
        # @param action [Symbol] Application action (:quit, :switch_mode, etc.)
        # @return [Domain::Commands::ApplicationCommand]
        def application_command(action)
          Domain::Commands::ApplicationCommand.new(action)
        end

        # Create bookmark operation commands
        #
        # @param action [Symbol] Bookmark action (:add, :remove, :navigate, etc.)
        # @param params [Hash] Bookmark parameters
        # @return [Domain::Commands::BookmarkCommand]
        def bookmark_command(action, params = {})
          Domain::Commands::BookmarkCommand.new(action, params)
        end

        # Create sidebar navigation commands
        #
        # @param action [Symbol] Sidebar action (:up, :down, :select)
        # @return [Domain::Commands::SidebarCommand]
        def sidebar_command(action)
          Domain::Commands::SidebarCommand.new(action)
        end

        # Create conditional navigation commands
        #
        # @param type [Symbol] Type of conditional navigation
        # @return [Domain::Commands::ConditionalNavigationCommand]
        def conditional_navigation_command(type)
          case type
          when :up_or_sidebar then Domain::Commands::ConditionalNavigationCommand.up_or_sidebar
          when :down_or_sidebar then Domain::Commands::ConditionalNavigationCommand.down_or_sidebar
          when :select_or_sidebar then Domain::Commands::ConditionalNavigationCommand.select_or_sidebar
          else
            raise ArgumentError, "Unknown conditional navigation type: #{type}"
          end
        end

        # Create mode switching command (common application pattern)
        #
        # @param mode [Symbol] Target mode (:help, :toc, :bookmarks, etc.)
        # @return [Domain::Commands::ApplicationCommand]
        def mode_switch_command(mode)
          case mode
          when :help then application_command(:show_help)
          when :toc then application_command(:show_toc)
          when :bookmarks then application_command(:show_bookmarks)
          else
            application_command(:switch_mode)
          end
        end

        # Convert Input system symbols to appropriate Domain commands
        # This method helps during migration by automatically routing
        # common input symbols to their Domain command equivalents.
        #
        # @param symbol [Symbol] Input symbol
        # @param context [Object] Execution context
        # @return [Domain::Commands::BaseCommand, nil] Command or nil if no mapping
        def symbol_to_command(symbol, _context = nil)
          case symbol
          # Navigation commands - now use Domain commands
          when :next_page then navigation_command(:next_page)
          when :prev_page then navigation_command(:prev_page)
          when :next_chapter then navigation_command(:next_chapter)
          when :prev_chapter then navigation_command(:prev_chapter)
          when :scroll_up then Domain::Commands::NavigationCommandFactory.scroll_up
          when :scroll_down then Domain::Commands::NavigationCommandFactory.scroll_down
          when :go_to_start then navigation_command(:go_to_start)
          when :go_to_end then navigation_command(:go_to_end)
          # Application commands
          when :toggle_view_mode then application_command(:toggle_view_mode)
          when :show_help then application_command(:show_help)
          when :open_toc then application_command(:show_toc)
          when :open_bookmarks then application_command(:show_bookmarks)
          when :open_annotations then application_command(:show_annotations)
          when :quit_to_menu then application_command(:quit_to_menu)
          # Conditional navigation commands
          when :conditional_up then conditional_navigation_command(:up_or_sidebar)
          when :conditional_down then conditional_navigation_command(:down_or_sidebar)
          when :conditional_select then conditional_navigation_command(:select_or_sidebar)
          # Direct sidebar commands
          when :sidebar_up then sidebar_command(:up)
          when :sidebar_down then sidebar_command(:down)
          when :sidebar_select then sidebar_command(:select)
          # Menu commands
          when :menu_up then Domain::Commands::MenuCommand.new(:menu_up)
          when :menu_down then Domain::Commands::MenuCommand.new(:menu_down)
          when :menu_select then Domain::Commands::MenuCommand.new(:menu_select)
          when :menu_quit then Domain::Commands::MenuCommand.new(:menu_quit)
          when :back_to_menu then Domain::Commands::MenuCommand.new(:back_to_menu)
          when :browse_up then Domain::Commands::MenuCommand.new(:browse_up)
          when :browse_down then Domain::Commands::MenuCommand.new(:browse_down)
          when :browse_select then Domain::Commands::MenuCommand.new(:browse_select)
          # recent_* commands removed
          when :start_search then Domain::Commands::MenuCommand.new(:start_search)
          when :exit_search then Domain::Commands::MenuCommand.new(:exit_search)
          # Annotations-related menu commands
          when :annotations_up then Domain::Commands::MenuCommand.new(:annotations_up)
          when :annotations_down then Domain::Commands::MenuCommand.new(:annotations_down)
          when :annotations_select then Domain::Commands::MenuCommand.new(:annotations_select)
          when :annotations_edit then Domain::Commands::MenuCommand.new(:annotations_edit)
          when :annotations_delete then Domain::Commands::MenuCommand.new(:annotations_delete)
          when :annotation_detail_open then Domain::Commands::MenuCommand.new(:annotation_detail_open)
          when :annotation_detail_edit then Domain::Commands::MenuCommand.new(:annotation_detail_edit)
          when :annotation_detail_delete then Domain::Commands::MenuCommand.new(:annotation_detail_delete)
          when :annotation_detail_back then Domain::Commands::MenuCommand.new(:annotation_detail_back)
          end
        end

        # Check if a symbol can be converted to a Domain command
        #
        # @param symbol [Symbol] Input symbol to check
        # @return [Boolean] True if symbol has Domain command equivalent
        def has_domain_command?(symbol)
          !symbol_to_command(symbol).nil?
        end
      end
    end
  end
end
