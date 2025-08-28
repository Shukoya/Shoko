# frozen_string_literal: true

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
          # Reader navigation - temporarily disabled to fall back to direct method calls
          # until state synchronization between GlobalState and StateStore is resolved
          # when :next_page then navigation_command(:next_page)
          # when :prev_page then navigation_command(:prev_page)
          # when :next_chapter then navigation_command(:next_chapter)
          # when :prev_chapter then navigation_command(:prev_chapter)
          # when :scroll_up then navigation_command(:scroll_up)
          # when :scroll_down then navigation_command(:scroll_down)
          # when :go_to_start then navigation_command(:go_to_start)
          # when :go_to_end then navigation_command(:go_to_end)

          # Reader controls
          when :toggle_view_mode then application_command(:toggle_view_mode)
          when :add_bookmark then bookmark_command(:add)
          # NOTE: :toggle_page_numbering_mode, :increase_line_spacing, :decrease_line_spacing
          # fall back to direct method calls on reader controller

          # Application modes
          when :show_help then mode_switch_command(:help)
          when :open_toc then mode_switch_command(:toc)
          when :open_bookmarks then mode_switch_command(:bookmarks)

            # Application lifecycle - temporarily disabled to fall back to direct method calls
            # until state synchronization issues are resolved
            # when :quit then application_command(:quit)
            # when :quit_to_menu then application_command(:quit_to_menu)
            # when :quit_application then application_command(:quit_application)

            # Return nil for symbols that should remain as direct calls
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
