# frozen_string_literal: true

require_relative 'helpers'
require_relative '../../helpers/terminal_sanitizer'

module EbookReader
  module Input
    module CommandBuilders
      # Builds key bindings for editable text fields (search, file input, editors).
      class TextInputBuilder
        include Helpers

        INPUT_PATHS = {
          search_query: %i[menu search_query],
          download_query: %i[menu download_query],
        }.freeze

        BACKSPACE_KEYS = Helpers::ACTION_CACHE[:backspace]
        DELETE_KEYS = Helpers::ACTION_CACHE[:delete]

        def initialize(input_field:, context_method: nil, cursor_field: nil)
          @input_field = input_field.to_sym
          @context_method = context_method
          @cursor_field = cursor_field
        end

        def build
          commands = {}
          configure_backspace(commands)
          configure_delete(commands)
          configure_default(commands)
          commands
        end

        private

        attr_reader :input_field, :context_method, :cursor_field

        def configure_backspace(commands)
          BACKSPACE_KEYS.each do |key|
            commands[key] = ->(ctx, _) { handle_backspace(ctx, key) }
          end
        end

        def configure_delete(commands)
          DELETE_KEYS.each do |key|
            commands[key] = lambda do |ctx, _|
              current, cursor = current_and_cursor(ctx)
              new_value = splice_delete(current, cursor)
              apply_value(ctx, new_value)
              :handled
            end
          end
        end

        def configure_default(commands)
          commands[:__default__] = lambda do |ctx, key|
            char = key.to_s
            if EbookReader::Helpers::TerminalSanitizer.printable_char?(char)
              handle_character(ctx, key)
            else
              :pass
            end
          end
        end

        def handle_backspace(ctx, key)
          if context_method
            ctx.send(context_method, key)
          elsif input_path
            current, cursor_pos = current_and_cursor(ctx)
            new_value, new_cursor = splice_backspace(current, cursor_pos)
            apply_value(ctx, new_value, new_cursor)
          end
          :handled
        end

        def handle_character(ctx, key)
          if context_method
            ctx.send(context_method, key)
          elsif input_path
            current, cursor_pos = current_and_cursor(ctx)
            new_value, new_cursor = splice_insert(current, cursor_pos, key.to_s)
            apply_value(ctx, new_value, new_cursor)
          end
          :handled
        end

        def apply_value(ctx, new_value, new_cursor = nil)
          if cursor_field && !new_cursor.nil?
            dispatch_menu(ctx, input_field => new_value, cursor_field => new_cursor)
          else
            dispatch_menu(ctx, input_field => new_value)
          end
        end

        def determine_cursor(ctx, current)
          if cursor_field
            cursor_value(ctx, cursor_field, current)
          else
            current.length
          end
        end

        def input_path
          INPUT_PATHS[input_field]
        end

        def current_and_cursor(ctx)
          return ['', 0] unless input_path

          current = current_value(ctx, input_path)
          cursor_pos = determine_cursor(ctx, current)
          [current, cursor_pos]
        end
      end
    end
  end
end
