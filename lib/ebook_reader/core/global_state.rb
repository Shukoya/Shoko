# frozen_string_literal: true

require 'fileutils'
require 'json'

module EbookReader
  module Core
    # Unified state store with observers for the entire application.
    # Replaces scattered state management across ReaderState and MainMenuState.
    #
    # This implements a Redux-like pattern where all application state is centralized,
    # observable, and immutable except through controlled updates.
    #
    # @example Basic usage
    #   state = GlobalState.new
    #   state.add_observer(self, :reader, :menu)
    #   state.update([:reader, :current_chapter], 5)
    #
    # @example Observing specific paths
    #   state.add_observer(self, :reader, :current_chapter)
    #   # Will only notify on reader.current_chapter changes
    class GlobalState
      CONFIG_DIR = File.expand_path('~/.config/reader')
      CONFIG_FILE = File.join(CONFIG_DIR, 'config.json')
      SYMBOL_KEYS = %i[view_mode line_spacing page_numbering_mode theme].freeze

      def initialize
        @observers_by_path = Hash.new { |h, k| h[k] = [] }
        @observers_all = []
        reset_to_defaults
        load_config_from_file
      end

      # Register an observer for specific state paths
      # Observer should respond to `state_changed(path, old_value, new_value)`
      #
      # @param observer [Object] Object implementing state_changed method
      # @param *paths [Array<Symbol|Array>] State paths to observe
      def add_observer(observer, *paths)
        if paths.empty?
          @observers_all << observer unless @observers_all.include?(observer)
        else
          paths.each do |path|
            normalized_path = normalize_path(path)
            unless @observers_by_path[normalized_path].include?(observer)
              @observers_by_path[normalized_path] << observer
            end
          end
        end
      end

      # Remove observer from all paths
      #
      # @param observer [Object] Observer to remove
      def remove_observer(observer)
        @observers_all.delete(observer)
        @observers_by_path.each_value { |list| list.delete(observer) }
      end

      # Update state at given path and notify observers
      #
      # @param path [Array<Symbol>|Symbol] Path to state value
      # @param value [Object] New value
      # @return [Object] The new value
      def update(path, value)
        normalized_path = normalize_path(path)
        old_value = get(path)
        return value if old_value == value

        set_nested(@state, normalized_path, value)
        notify_observers(normalized_path, old_value, value)
        value
      end

      # Get state value at path
      #
      # @param path [Array<Symbol>|Symbol] Path to state value
      # @return [Object] State value
      def get(path)
        normalized_path = normalize_path(path)
        get_nested(@state, normalized_path)
      end

      # Get the entire state tree (read-only)
      #
      # @return [Hash] Complete state tree
      def to_h
        @state.dup
      end

      # Reset all state to initial values
      def reset_to_defaults
        @state = {
          reader: {
            # Position state
            current_chapter: 0,
            left_page: 0,
            right_page: 0,
            single_page: 0,
            current_page_index: 0,

            # Mode and UI state
            mode: :read,
            selection: nil,
            message: nil,
            running: true,

            # Lists and selections
            toc_selected: 0,
            bookmark_selected: 0,
            bookmarks: [],
            annotations: [],

            # Pagination state
            page_map: [],
            total_pages: 0,
            pages_per_chapter: [],

            # Terminal sizing
            last_width: 0,
            last_height: 0,
            page_offset: 0,

            # Dynamic pagination
            dynamic_page_map: nil,
            dynamic_total_pages: 0,
            dynamic_chapter_starts: [],
            last_dynamic_width: 0,
            last_dynamic_height: 0,

            # UI state
            rendered_lines: {},
            popup_menu: nil,

            # Sidebar state
            sidebar_visible: false,
            sidebar_active_tab: :toc,
            sidebar_width_percent: 30,
            sidebar_toc_selected: 0,
            sidebar_annotations_selected: 0,
            sidebar_bookmarks_selected: 0,
            sidebar_toc_filter: nil,
            sidebar_toc_filter_active: false,
          },

          menu: {
            selected: 0,
            mode: :menu,
            browse_selected: 0,
            search_query: '',
            search_cursor: 0,
            file_input: '',
            search_active: false,
          },

          config: {
            view_mode: :split,
            line_spacing: :normal,
            page_numbering_mode: :absolute,
            theme: :dark,
            show_page_numbers: true,
            highlight_quotes: false,
            highlight_keywords: false,
          },
        }
      end

      # Experimental: dispatch Domain::Actions to update state explicitly
      def dispatch(action)
        return unless action && action.respond_to?(:apply)

        action.apply(self)
      end

      # Core state management methods only
      # All convenience methods removed - use selectors and actions instead
      
      # Legacy support methods for persistence (will be refactored in Phase 3.3)
      def terminal_size_changed?(width, height)
        last_width = get(%i[reader last_width])
        last_height = get(%i[reader last_height])
        width != last_width || height != last_height
      end

      def update_terminal_size(width, height)
        update(%i[reader last_width], width)
        update(%i[reader last_height], height)
      end

      # State snapshot for persistence
      def reader_snapshot
        {
          current_chapter: get(%i[reader current_chapter]),
          page_offset: get(%i[reader single_page]),
          mode: get(%i[reader mode]).to_s,
          timestamp: Time.now.iso8601,
        }
      end

      # Restore reader state from snapshot
      def restore_reader_from(snapshot)
        update(%i[reader current_chapter], snapshot['current_chapter'] || 0)
        update(%i[reader single_page], snapshot['page_offset'] || 0)
        update(%i[reader left_page], snapshot['page_offset'] || 0)
        update(%i[reader mode], (snapshot['mode'] || 'read').to_sym)
      end

      # Configuration persistence methods
      def save_config
        ensure_config_dir
        write_config_file
      end

      def config_to_h
        get([:config])
      end

      private

      def load_config_from_file
        return unless File.exist?(CONFIG_FILE)

        data = parse_config_file
        apply_config_data(data) if data
      rescue StandardError
        # Use defaults on error
      end

      def parse_config_file
        JSON.parse(File.read(CONFIG_FILE), symbolize_names: true)
      rescue StandardError
        nil
      end

      def apply_config_data(data)
        data.each do |key, value|
          next unless get([:config]).key?(key)

          value = value.to_sym if SYMBOL_KEYS.include?(key)
          update([:config, key], value)
        end
      end

      def ensure_config_dir
        FileUtils.mkdir_p(CONFIG_DIR)
      rescue StandardError
        nil
      end

      def write_config_file
        File.write(CONFIG_FILE, JSON.pretty_generate(config_to_h))
      rescue StandardError
        nil
      end

      # Normalize path to array format
      def normalize_path(path)
        case path
        when Array then path
        when Symbol then [path]
        else [path.to_sym]
        end
      end

      # Get nested value from hash using path array
      def get_nested(hash, path)
        path.reduce(hash) { |h, key| h&.dig(key) }
      end

      # Set nested value in hash using path array
      def set_nested(hash, path, value)
        *keys, last_key = path
        target = keys.reduce(hash) { |h, key| h[key] ||= {} }
        target[last_key] = value
      end

      # Notify observers of state change
      def notify_observers(path, old_value, new_value)
        # Notify path-specific observers
        @observers_by_path[path].each do |observer|
          safe_notify(observer, path, old_value, new_value)
        end

        # Notify observers watching parent paths
        notify_parent_path_observers(path, old_value, new_value)

        # Notify global observers
        @observers_all.each do |observer|
          safe_notify(observer, path, old_value, new_value)
        end
      end

      # Notify observers watching parent paths (e.g., [:reader] when [:reader, :mode] changes)
      def notify_parent_path_observers(path, old_value, new_value)
        return if path.length <= 1

        (1...path.length).each do |i|
          parent_path = path[0, i]
          @observers_by_path[parent_path].each do |observer|
            safe_notify(observer, path, old_value, new_value)
          end
        end
      end

      # Safely notify observer, catching any exceptions
      def safe_notify(observer, path, old_value, new_value)
        return unless observer.respond_to?(:state_changed)

        observer.state_changed(path, old_value, new_value)
      rescue StandardError
        # Silently ignore observer errors to prevent breaking application flow
        nil
      end
    end
  end
end
