# frozen_string_literal: true

require_relative '../commands/base_command'
require_relative '../commands/navigation_commands'
require_relative '../commands/command_factory'

module EbookReader
  module Input
    module Commands
      module_function

      # Execute a command against the given context.
      # Supports multiple command types:
      # - Symbol: calls context.public_send(symbol, key) if arity allows, else without args
      # - Proc/Lambda: calls with (context, key) if arity 2, else with (key)
      # - Array [Symbol, *args]: calls method with args splat
      # - BaseCommand instance: calls command.execute(context, key)
      def execute(command, context, key = nil)
        case command
        when EbookReader::Commands::BaseCommand
          command.execute(context, key)
        when Symbol
          return :pass unless context.respond_to?(command)
          return context.public_send(command, key) if method_accepts_arg?(context, command)

          context.public_send(command)
        when Proc
          return command.call(context, key) if command.arity.abs >= 2
          return command.call(key) if command.arity.abs >= 1

          command.call
        when Array
          sym, *args = command
          return :pass unless sym.is_a?(Symbol) && context.respond_to?(sym)

          context.public_send(sym, *args)
        else
          :pass
        end
      end

      def method_accepts_arg?(context, method)
        arity = context.method(method).arity
        arity != 0
      rescue NameError
        false
      end
    end
  end
end
