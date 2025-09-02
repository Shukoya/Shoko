# frozen_string_literal: true

require_relative 'config_loader'
require_relative 'commands'

module EbookReader
  module Input
    # Generates input binding maps from declarative configuration
    class BindingGenerator
      def self.generate_for_mode(mode, context_methods = {})
        config = ConfigLoader.load_bindings
        mode_config = config[mode.to_sym] || {}

        bindings = {}

        # Handle nested configuration structure
        flatten_config(mode_config).each do |action, keys|
          command = create_command_for_action(action, context_methods[action])

          keys.each do |key|
            if key == '__any__'
              bindings[:__default__] = command
            else
              bindings[key] = command
            end
          end
        end

        bindings
      end

      def self.flatten_config(config)
        flattened = {}

        config.each do |key, value|
          if value.is_a?(Hash)
            # Nested structure - flatten it
            value.each do |nested_key, nested_value|
              flattened[nested_key] = nested_value
            end
          else
            # Direct key-value pair
            flattened[key] = value
          end
        end

        flattened
      end

      def self.create_command_for_action(action, custom_method = nil)
        return custom_method if custom_method

        # Default command mapping based on action name
        case action
        when :next_page, :prev_page, :scroll_down, :scroll_up,
             :next_chapter, :prev_chapter, :go_to_start, :go_to_end,
             :toggle_view, :toggle_page_mode, :increase_spacing, :decrease_spacing,
             :show_toc, :add_bookmark, :show_bookmarks, :show_help,
             :quit_to_menu, :quit_application
          action

        when :up, :down
          lambda do |ctx, _|
            current = EbookReader::Domain::Selectors::MenuSelectors.selected(ctx.state)
            max_val = ctx.respond_to?(:max_selection) ? ctx.max_selection : 5

            new_val = case action
                      when :up then [current - 1, 0].max
                      when :down then [current + 1, max_val].min
                      end

            ctx.state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(selected: new_val))
            :handled
          end

        when :confirm
          lambda { |ctx, _|
            ctx.handle_selection
            :handled
          }

        when :cancel
          lambda { |ctx, _|
            ctx.handle_cancel
            :handled
          }

        when :browse, :recent, :open_file, :settings, :annotations
          lambda { |ctx, _|
            ctx.public_send("switch_to_#{action}")
            :handled
          }

        when :quit
          lambda { |ctx, _|
            ctx.cleanup_and_exit(0, '')
            :handled
          }

        when :select
          lambda { |ctx, _|
            ctx.handle_menu_selection
            :handled
          }

        when :exit
          lambda { |ctx, _|
            ctx.exit_current_mode
            :handled
          }

        when :delete
          lambda { |ctx, _|
            ctx.delete_selected_item
            :handled
          }

        when :handle_popup_key
          ->(ctx, key) { ctx.handle_popup_key(key) }

        when :handle_popup_navigation
          ->(ctx, key) { ctx.handle_popup_navigation(key) }

        when :handle_popup_action_key
          ->(ctx, key) { ctx.handle_popup_action_key(key) }

        when :handle_popup_cancel
          ->(ctx, key) { ctx.handle_popup_cancel(key) }

        else
          ->(_ctx, _) { :pass }
        end
      end
    end
  end
end
