# frozen_string_literal: true

module EbookReader
  module Commands
    # Base class for all application commands.
    # Implements the Command pattern for consistent input handling across the application.
    #
    # Commands encapsulate actions that can be triggered by user input, menu selections,
    # or programmatic calls. They provide a uniform interface for undo/redo capability,
    # validation, and execution logging.
    #
    # @example Creating a custom command
    #   class MyCommand < BaseCommand
    #     def initialize(my_param)
    #       @my_param = my_param
    #     end
    #
    #     def execute(context)
    #       context.do_something(@my_param)
    #       :handled
    #     end
    #   end
    #
    # @example Using with key input
    #   command = NavigationCommand.new(:next_page)
    #   result = command.execute(reader_context)
    class BaseCommand
      # Execute the command with the given context
      #
      # @param context [Object] The execution context (ReaderController, MainMenu, etc.)
      # @param key [String, nil] The key that triggered this command (optional)
      # @return [Symbol] :handled if command was processed, :pass if it should fall through
      def execute(context, key = nil)
        return :pass unless can_execute?(context)

        begin
          perform(context, key)
        rescue StandardError => e
          handle_error(context, e)
          :pass
        end
      end

      # Check if this command can be executed in the current context
      #
      # @param context [Object] The execution context
      # @return [Boolean] true if command can execute
      def can_execute?(context)
        true
      end

      # Describe this command for logging/debugging
      #
      # @return [String] Human-readable description
      def description
        self.class.name.split('::').last
      end

      protected

      # Perform the actual command execution
      # Subclasses must implement this method
      #
      # @param context [Object] The execution context
      # @param key [String, nil] The triggering key
      # @return [Symbol] :handled or :pass
      def perform(context, key = nil)
        raise NotImplementedError, "#{self.class} must implement #perform"
      end

      # Handle any errors that occur during execution
      #
      # @param context [Object] The execution context
      # @param error [StandardError] The error that occurred
      def handle_error(context, error)
        Infrastructure::Logger.error("Command #{description} failed", error: error.message)
      end
    end
  end
end