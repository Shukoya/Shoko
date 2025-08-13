# frozen_string_literal: true

require_relative 'base_command'

module EbookReader
  module Commands
    # Navigation commands for reader movement
    class NavigationCommand < BaseCommand
      ACTIONS = {
        next_page: :next_page,
        prev_page: :prev_page,
        next_chapter: :next_chapter,
        prev_chapter: :prev_chapter,
        go_to_start: :go_to_start,
        go_to_end: :go_to_end,
        scroll_up: :scroll_up,
        scroll_down: :scroll_down
      }.freeze

      def initialize(action)
        @action = action
        raise ArgumentError, "Unknown navigation action: #{action}" unless ACTIONS.key?(action)
      end

      def can_execute?(context)
        context.respond_to?(@action)
      end

      def description
        "Navigate: #{@action}"
      end

      protected

      def perform(context, key = nil)
        context.clear_selection! if context.respond_to?(:clear_selection!)
        context.public_send(@action)
        :handled
      end
    end

    # Mode switching commands
    class ModeCommand < BaseCommand
      MODES = %i[read help toc bookmarks annotations annotation_editor].freeze

      def initialize(mode, **options)
        @mode = mode
        @options = options
        raise ArgumentError, "Unknown mode: #{mode}" unless MODES.include?(mode)
      end

      def can_execute?(context)
        context.respond_to?(:switch_mode)
      end

      def description
        "Switch to mode: #{@mode}"
      end

      protected

      def perform(context, key = nil)
        if @options.empty?
          context.switch_mode(@mode)
        else
          context.switch_mode(@mode, @options)
        end
        :handled
      end
    end

    # Bookmark management commands
    class BookmarkCommand < BaseCommand
      ACTIONS = %i[add_bookmark open_bookmarks delete_selected_bookmark].freeze

      def initialize(action)
        @action = action
        raise ArgumentError, "Unknown bookmark action: #{action}" unless ACTIONS.include?(action)
      end

      def can_execute?(context)
        context.respond_to?(@action)
      end

      def description
        "Bookmark: #{@action}"
      end

      protected

      def perform(context, key = nil)
        context.clear_selection! if context.respond_to?(:clear_selection!)
        context.public_send(@action)
        :handled
      end
    end

    # Application control commands
    class ApplicationCommand < BaseCommand
      ACTIONS = %i[quit_application quit_to_menu toggle_view_mode].freeze

      def initialize(action)
        @action = action
        raise ArgumentError, "Unknown application action: #{action}" unless ACTIONS.include?(action)
      end

      def can_execute?(context)
        context.respond_to?(@action)
      end

      def description
        "Application: #{@action}"
      end

      protected

      def perform(context, key = nil)
        context.public_send(@action)
        :handled
      end
    end

    # Menu navigation commands
    class MenuCommand < BaseCommand
      ACTIONS = {
        navigate_up: :handle_navigation,
        navigate_down: :handle_navigation,
        select: :handle_selection,
        cancel: :handle_cancel,
        browse: :switch_to_browse,
        search: :switch_to_search,
        recent: :switch_to_mode,
        settings: :switch_to_mode,
        annotations: :switch_to_mode,
        open_file: :open_file_dialog
      }.freeze

      def initialize(action, *args)
        @action = action
        @args = args
        raise ArgumentError, "Unknown menu action: #{action}" unless ACTIONS.key?(action)
      end

      def can_execute?(context)
        method_name = ACTIONS[@action]
        context.respond_to?(method_name)
      end

      def description
        "Menu: #{@action}"
      end

      protected

      def perform(context, key = nil)
        method_name = ACTIONS[@action]
        
        case @action
        when :navigate_up
          context.public_send(method_name, :up)
        when :navigate_down
          context.public_send(method_name, :down)
        when :recent, :settings, :annotations
          context.public_send(method_name, @action)
        else
          if @args.empty?
            context.public_send(method_name)
          else
            context.public_send(method_name, *@args)
          end
        end
        :handled
      end
    end

    # Popup menu commands
    class PopupCommand < BaseCommand
      ACTIONS = %i[handle_popup_navigation handle_popup_action_key handle_popup_cancel].freeze

      def initialize(action)
        @action = action
        raise ArgumentError, "Unknown popup action: #{action}" unless ACTIONS.include?(action)
      end

      def can_execute?(context)
        context.respond_to?(@action) && context.respond_to?(:state) && 
        context.state.respond_to?(:get) && context.state.get([:reader, :popup_menu])
      end

      def description
        "Popup: #{@action}"
      end

      protected

      def perform(context, key = nil)
        result = context.public_send(@action, key)
        result == :handled ? :handled : :pass
      end
    end
  end
end