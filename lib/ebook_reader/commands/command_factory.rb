# frozen_string_literal: true

require_relative 'base_command'
require_relative 'navigation_commands'
require_relative 'sidebar_commands'

module EbookReader
  module Commands
    # Factory for creating command instances based on action names and parameters
    class CommandFactory
      class << self
        # Create a command instance for the given action
        #
        # @param action [Symbol] The action to create a command for
        # @param *args [Array] Additional arguments for the command
        # @return [BaseCommand] A command instance
        def create(action, *args)
          case action
          # Navigation commands
          when :next_page, :prev_page, :next_chapter, :prev_chapter,
               :go_to_start, :go_to_end, :scroll_up, :scroll_down
            NavigationCommand.new(action)
            
          # Mode switching
          when :show_help
            ModeCommand.new(:help, *args)
          when :open_toc
            ModeCommand.new(:toc, *args)
          when :open_bookmarks
            ModeCommand.new(:bookmarks, *args)
          when :open_annotations
            ModeCommand.new(:annotations, *args)
            
          # Sidebar commands
          when :toggle_sidebar, :sidebar_switch_to_toc, :sidebar_switch_to_annotations, 
               :sidebar_switch_to_bookmarks, :sidebar_navigate_up, :sidebar_navigate_down,
               :sidebar_activate_item, :sidebar_cycle_tab_forward, :sidebar_cycle_tab_backward,
               :sidebar_start_filter, :sidebar_edit_annotation, :sidebar_delete_item
            SidebarCommand.new(action)
            
          # Bookmark actions
          when :add_bookmark, :open_bookmarks, :delete_selected_bookmark
            BookmarkCommand.new(action)
            
          # Application control
          when :quit_application, :quit_to_menu, :toggle_view_mode
            ApplicationCommand.new(action)
            
          # Menu actions
          when :navigate_up, :navigate_down, :select, :cancel, :browse, :search,
               :recent, :settings, :annotations, :open_file
            MenuCommand.new(action, *args)
            
          # Popup actions
          when :handle_popup_navigation, :handle_popup_action_key, :handle_popup_cancel
            PopupCommand.new(action)
            
          else
            # For unknown actions, create a generic method call command
            MethodCallCommand.new(action, *args)
          end
        end

        # Create command bindings for a specific mode
        #
        # @param mode [Symbol] The mode to create bindings for
        # @return [Hash] Key bindings mapped to commands
        def create_bindings_for_mode(mode)
          case mode
          when :read
            create_reader_bindings
          when :menu
            create_menu_bindings
          when :browse
            create_browse_bindings
          when :popup_menu
            create_popup_bindings
          when :search
            create_search_bindings
          when :recent
            create_recent_bindings
          when :settings
            create_settings_bindings
          when :open_file
            create_open_file_bindings
          when :annotations
            create_annotations_bindings
          when :annotation_editor
            create_annotation_editor_bindings
          else
            {}
          end
        end

        private

        def create_reader_bindings
          bindings = {}
          
          # Navigation keys (context-dependent for sidebar vs content)
          Input::KeyDefinitions::NAVIGATION[:down].each do |k| 
            bindings[k] = create_context_dependent_navigation(:sidebar_navigate_down, :scroll_down)
          end
          Input::KeyDefinitions::NAVIGATION[:up].each do |k|
            bindings[k] = create_context_dependent_navigation(:sidebar_navigate_up, :scroll_up)
          end
          Input::KeyDefinitions::READER[:next_page].each { |k| bindings[k] = create(:next_page) }
          Input::KeyDefinitions::READER[:prev_page].each { |k| bindings[k] = create(:prev_page) }
          
          # Enter key for sidebar item activation when sidebar visible
          Input::KeyDefinitions::ACTIONS[:confirm].each do |k|
            bindings[k] = create_context_dependent_binding(:sidebar_activate_item, nil)
          end
          
          # Chapter navigation
          bindings['n'] = create(:next_chapter)
          bindings['p'] = create(:prev_chapter)
          
          # Mode switches
          bindings['h'] = create(:show_help)
          bindings['t'] = create(:toggle_sidebar)
          bindings['B'] = create(:open_bookmarks)  # Keep legacy for full-screen mode
          bindings['A'] = create(:open_annotations)  # Keep legacy for full-screen mode
          
          # Bookmarks
          bindings['b'] = create(:add_bookmark)
          
          # Application control
          bindings['v'] = create(:toggle_view_mode)
          bindings['q'] = create(:quit_to_menu)
          Input::KeyDefinitions::ACTIONS[:quit].each { |k| bindings[k] = create(:quit_application) }
          
          # Position and sidebar navigation (context-dependent)
          bindings['g'] = create_context_dependent_binding(:sidebar_switch_to_toc, :go_to_start)
          bindings['a'] = create_context_dependent_binding(:sidebar_switch_to_annotations, nil)
          bindings['G'] = create(:go_to_end)
          
          # Sidebar navigation when visible
          bindings["\t"] = create(:sidebar_cycle_tab_forward)  # Tab key
          bindings["\e[Z"] = create(:sidebar_cycle_tab_backward)  # Shift+Tab
          bindings['/'] = create(:sidebar_start_filter)
          bindings['e'] = create(:sidebar_edit_annotation)
          bindings['d'] = create(:sidebar_delete_item)
          
          bindings
        end

        def create_menu_bindings
          bindings = {}
          
          Input::KeyDefinitions::NAVIGATION[:up].each { |k| bindings[k] = create(:navigate_up) }
          Input::KeyDefinitions::NAVIGATION[:down].each { |k| bindings[k] = create(:navigate_down) }
          Input::KeyDefinitions::ACTIONS[:confirm].each { |k| bindings[k] = create(:select) }
          Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = create(:cancel) }
          
          # Direct mode switches
          bindings['b'] = create(:browse)
          bindings['r'] = create(:recent)
          bindings['o'] = create(:open_file)
          bindings['s'] = create(:settings)
          bindings['a'] = create(:annotations)
          bindings['q'] = create(:cancel)
          
          bindings
        end

        def create_browse_bindings
          bindings = {}
          
          # Use lambda for browse navigation since it needs key parameter
          Input::KeyDefinitions::NAVIGATION[:up].each do |k| 
            bindings[k] = lambda { |ctx, key| ctx.handle_browse_navigation(key); :handled }
          end
          Input::KeyDefinitions::NAVIGATION[:down].each do |k|
            bindings[k] = lambda { |ctx, key| ctx.handle_browse_navigation(key); :handled }
          end
          
          Input::KeyDefinitions::ACTIONS[:confirm].each { |k| bindings[k] = MethodCallCommand.new(:open_selected_book) }
          Input::KeyDefinitions::ACTIONS[:cancel].each do |k|
            bindings[k] = lambda { |ctx, _| ctx.switch_to_mode(:menu); :handled }
          end
          
          bindings['s'] = lambda { |ctx, _| ctx.switch_to_search; :handled }
          bindings['r'] = MethodCallCommand.new(:refresh_scan)
          
          bindings
        end

        def create_popup_bindings
          bindings = {}
          
          Input::KeyDefinitions::NAVIGATION[:up].each { |k| bindings[k] = create(:handle_popup_navigation) }
          Input::KeyDefinitions::NAVIGATION[:down].each { |k| bindings[k] = create(:handle_popup_navigation) }
          Input::KeyDefinitions::ACTIONS[:confirm].each { |k| bindings[k] = create(:handle_popup_action_key) }
          Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = create(:handle_popup_cancel) }
          
          # Catch-all for other keys
          bindings[:__default__] = MethodCallCommand.new(:handle_popup_key)
          
          bindings
        end

        def create_search_bindings
          bindings = {}
          
          Input::KeyDefinitions::ACTIONS[:confirm].each { |k| bindings[k] = lambda { |ctx, _| ctx.switch_to_browse; :handled } }
          Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = lambda { |ctx, _| ctx.switch_to_browse; :handled } }
          Input::KeyDefinitions::NAVIGATION[:left].each { |k| bindings[k] = MethodCallCommand.new(:move_search_cursor, -1) }
          Input::KeyDefinitions::NAVIGATION[:right].each { |k| bindings[k] = MethodCallCommand.new(:move_search_cursor, 1) }
          Input::KeyDefinitions::ACTIONS[:delete].each { |k| bindings[k] = MethodCallCommand.new(:handle_delete) }
          Input::KeyDefinitions::ACTIONS[:backspace].each { |k| bindings[k] = MethodCallCommand.new(:handle_backspace_input) }

          # Text input handler
          bindings[:__default__] = lambda { |ctx, key|
            char = key.to_s
            if char.length == 1 && char.ord >= 32
              ctx.add_to_search(key)
              :handled
            else
              :pass
            end
          }

          bindings
        end

        def create_recent_bindings
          bindings = {}
          
          Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = lambda { |ctx, _| ctx.switch_to_mode(:menu); :handled } }
          Input::KeyDefinitions::NAVIGATION[:up].each do |k| 
            bindings[k] = lambda { |ctx, key| ctx.input_handler.handle_recent_input(key); :handled }
          end
          Input::KeyDefinitions::NAVIGATION[:down].each do |k|
            bindings[k] = lambda { |ctx, key| ctx.input_handler.handle_recent_input(key); :handled }
          end
          Input::KeyDefinitions::ACTIONS[:confirm].each do |k|
            bindings[k] = lambda { |ctx, key| ctx.input_handler.handle_recent_input(key); :handled }
          end

          bindings
        end

        def create_settings_bindings
          bindings = {}
          
          Input::KeyDefinitions::ACTIONS[:cancel].each do |k|
            bindings[k] = lambda { |ctx, _| ctx.switch_to_mode(:menu); ctx.state.save_config; :handled }
          end

          # Number key handlers
          %w[1 2 3 4 5 6].each do |k|
            bindings[k] = MethodCallCommand.new(:handle_settings_input)
          end

          bindings
        end

        def create_open_file_bindings
          bindings = {}
          
          Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = MethodCallCommand.new(:handle_escape) }
          Input::KeyDefinitions::ACTIONS[:confirm].each { |k| bindings[k] = MethodCallCommand.new(:handle_enter) }
          Input::KeyDefinitions::ACTIONS[:backspace].each { |k| bindings[k] = MethodCallCommand.new(:handle_backspace_input) }

          # Text input handler
          bindings[:__default__] = MethodCallCommand.new(:handle_character_input)

          bindings
        end

        def create_annotations_bindings
          bindings = {}
          
          Input::KeyDefinitions::ACTIONS[:cancel].each { |k| bindings[k] = lambda { |ctx, _| ctx.switch_to_mode(:menu); :handled } }
          Input::KeyDefinitions::NAVIGATION[:up].each do |k|
            bindings[k] = lambda { |ctx, _| ctx.input_handler.navigate_annotations_up(ctx.annotations_screen); :handled }
          end
          Input::KeyDefinitions::NAVIGATION[:down].each do |k|
            bindings[k] = lambda { |ctx, _| ctx.input_handler.navigate_annotations_down(ctx.annotations_screen); :handled }
          end
          Input::KeyDefinitions::ACTIONS[:confirm].each do |k|
            bindings[k] = lambda do |ctx, _|
              screen = ctx.annotations_screen
              annotation = screen.current_annotation
              book_path = screen.current_book_path
              ctx.switch_to_edit_annotation(annotation, book_path) if annotation && book_path
              :handled
            end
          end
          bindings['d'] = lambda { |ctx, _| ctx.input_handler.delete_annotation(ctx.annotations_screen); :handled }

          bindings
        end

        def create_annotation_editor_bindings
          bindings = {}
          
          bindings[:__default__] = lambda { |ctx, key|
            screen = ctx.instance_variable_get(:@annotation_editor_screen)
            result = screen.handle_input(key)
            if %i[saved cancelled].include?(result)
              # Refresh annotations data to show any changes
              ctx.instance_variable_get(:@annotations_screen).refresh_data
              ctx.switch_to_mode(:annotations)
            end
            :handled
          }

          bindings
        end

        # Create a context-dependent command that chooses action based on sidebar visibility
        def create_context_dependent_binding(sidebar_action, default_action)
          lambda { |context, key|
            if context.state.sidebar_visible
              create(sidebar_action).execute(context, key)
            elsif default_action
              create(default_action).execute(context, key)
            else
              :pass
            end
          }
        end

        # Create context-dependent navigation (sidebar takes priority when visible)
        def create_context_dependent_navigation(sidebar_action, content_action)
          lambda { |context, key|
            if context.state.sidebar_visible
              create(sidebar_action).execute(context, key)
            else
              create(content_action).execute(context, key)
            end
          }
        end
      end
    end

    # Generic command for method calls that don't fit specific command types
    class MethodCallCommand < BaseCommand
      def initialize(method_name, *args)
        @method_name = method_name
        @args = args
      end

      def can_execute?(context)
        context.respond_to?(@method_name)
      end

      def description
        "Call: #{@method_name}"
      end

      protected

      def perform(context, key = nil)
        if @args.empty?
          context.public_send(@method_name)
        else
          context.public_send(@method_name, *@args)
        end
        :handled
      end
    end
  end
end