# frozen_string_literal: true

module EbookReader
  module Infrastructure
    # Clean input dispatcher using only command pattern.
    # Replaces the mixed paradigms with consistent command execution.
    class InputDispatcher
      def initialize(context)
        @context = context
        @bindings = {}
        @default_handler = nil
      end

      # Register key bindings with commands
      #
      # @param bindings [Hash<String, Command>] Key to command mapping
      def register_bindings(bindings)
        bindings.each do |key, command|
          @bindings[key] = command
        end
      end

      # Register default handler for unbound keys
      #
      # @param handler [Command, Proc] Default handler
      def register_default_handler(handler)
        @default_handler = handler
      end

      # Handle key input
      #
      # @param key [String] Input key
      # @return [Symbol] :handled, :pass, or :error
      def handle_key(key)
        command = @bindings[key]
        
        if command
          execute_command(command, key)
        elsif @default_handler
          execute_handler(@default_handler, key)
        else
          :pass
        end
      end

      # Clear all bindings
      def clear_bindings
        @bindings.clear
        @default_handler = nil
      end

      # Get all registered keys
      #
      # @return [Array<String>]
      def registered_keys
        @bindings.keys
      end

      # Check if key is bound
      #
      # @param key [String] Key to check
      # @return [Boolean]
      def bound?(key)
        @bindings.key?(key)
      end

      private

      def execute_command(command, key)
        if command.respond_to?(:execute)
          command.execute(@context, { key: key })
        else
          Infrastructure::Logger.error(
            "Invalid command object",
            command: command.class.name,
            key: key
          )
          :error
        end
      rescue StandardError => e
        Infrastructure::Logger.error(
          "Command execution failed",
          command: command.class.name,
          key: key,
          error: e.message
        )
        :error
      end

      def execute_handler(handler, key)
        if handler.respond_to?(:call)
          handler.call(@context, key)
        elsif handler.respond_to?(:execute)
          handler.execute(@context, { key: key })
        else
          Infrastructure::Logger.error(
            "Invalid default handler",
            handler: handler.class.name,
            key: key
          )
          :error
        end
      rescue StandardError => e
        Infrastructure::Logger.error(
          "Default handler execution failed",
          handler: handler.class.name,
          key: key,
          error: e.message
        )
        :error
      end
    end
  end
end