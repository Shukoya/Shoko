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
        def symbol_to_command(_symbol, _context = nil)
          # Intentionally return nil for all symbols for now so Input::Commands
          # falls back to direct method calls on the reader/menu controllers.
          # This avoids state desync between GlobalState and StateStore until
          # Phase 3 unifies state updates.
          nil
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
