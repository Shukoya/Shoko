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

      # Convenience methods for common state paths

      # Reader state accessors
      def current_chapter
        get(%i[reader current_chapter])
      end

      def current_chapter=(value)
        update(%i[reader current_chapter], value)
      end

      def left_page
        get(%i[reader left_page])
      end

      def left_page=(value)
        update(%i[reader left_page], value)
      end

      def right_page
        get(%i[reader right_page])
      end

      def right_page=(value)
        update(%i[reader right_page], value)
      end

      def single_page
        get(%i[reader single_page])
      end

      def single_page=(value)
        update(%i[reader single_page], value)
      end

      def current_page_index
        get(%i[reader current_page_index])
      end

      def current_page_index=(value)
        update(%i[reader current_page_index], value)
      end

      def current_page
        current_page_index + 1
      end

      def current_page=(value)
        self.current_page_index = value - 1
      end

      def mode
        get(%i[reader mode])
      end

      def mode=(value)
        update(%i[reader mode], value)
      end

      def message
        get(%i[reader message])
      end

      def message=(value)
        update(%i[reader message], value)
      end

      def running
        get(%i[reader running])
      end

      def running=(value)
        update(%i[reader running], value)
      end

      # Menu state accessors
      def selected
        get(%i[menu selected])
      end

      def selected=(value)
        update(%i[menu selected], value)
      end

      def browse_selected
        get(%i[menu browse_selected])
      end

      def browse_selected=(value)
        update(%i[menu browse_selected], value)
      end

      def search_active
        get(%i[menu search_active])
      end

      def search_active=(value)
        update(%i[menu search_active], value)
      end

      def search_query
        get(%i[menu search_query])
      end

      def search_query=(value)
        update(%i[menu search_query], value)
      end

      def file_input
        get(%i[menu file_input])
      end

      def file_input=(value)
        update(%i[menu file_input], value)
      end

      def search_cursor
        get(%i[menu search_cursor])
      end

      def search_cursor=(value)
        update(%i[menu search_cursor], value)
      end

      def menu_mode
        get(%i[menu mode])
      end

      def menu_mode=(value)
        update(%i[menu mode], value)
      end

      # Config accessors
      def view_mode
        get(%i[config view_mode])
      end

      def view_mode=(value)
        update(%i[config view_mode], value)
      end

      def page_numbering_mode
        get(%i[config page_numbering_mode])
      end

      def page_numbering_mode=(value)
        update(%i[config page_numbering_mode], value)
      end

      def line_spacing
        get(%i[config line_spacing])
      end

      def line_spacing=(value)
        update(%i[config line_spacing], value)
      end

      def theme
        get(%i[config theme])
      end

      def theme=(value)
        update(%i[config theme], value)
      end

      def show_page_numbers
        get(%i[config show_page_numbers])
      end

      def show_page_numbers=(value)
        update(%i[config show_page_numbers], value)
      end

      def highlight_quotes
        get(%i[config highlight_quotes])
      end

      def highlight_quotes=(value)
        update(%i[config highlight_quotes], value)
      end

      def highlight_keywords
        get(%i[config highlight_keywords])
      end

      def highlight_keywords=(value)
        update(%i[config highlight_keywords], value)
      end

      # Missing reader state accessors
      def bookmarks
        get(%i[reader bookmarks])
      end

      def bookmarks=(value)
        update(%i[reader bookmarks], value)
      end

      def rendered_lines
        get(%i[reader rendered_lines])
      end

      def rendered_lines=(value)
        update(%i[reader rendered_lines], value)
      end

      def last_width
        get(%i[reader last_width])
      end

      def last_width=(value)
        update(%i[reader last_width], value)
      end

      def last_height
        get(%i[reader last_height])
      end

      def last_height=(value)
        update(%i[reader last_height], value)
      end

      def dynamic_page_map
        get(%i[reader dynamic_page_map])
      end

      def dynamic_page_map=(value)
        update(%i[reader dynamic_page_map], value)
      end

      def dynamic_total_pages
        get(%i[reader dynamic_total_pages])
      end

      def dynamic_total_pages=(value)
        update(%i[reader dynamic_total_pages], value)
      end

      def last_dynamic_width
        get(%i[reader last_dynamic_width])
      end

      def last_dynamic_width=(value)
        update(%i[reader last_dynamic_width], value)
      end

      def last_dynamic_height
        get(%i[reader last_dynamic_height])
      end

      def last_dynamic_height=(value)
        update(%i[reader last_dynamic_height], value)
      end

      def page_map
        get(%i[reader page_map])
      end

      def page_map=(value)
        update(%i[reader page_map], value)
      end

      def total_pages
        get(%i[reader total_pages])
      end

      def total_pages=(value)
        update(%i[reader total_pages], value)
      end

      def toc_selected
        get(%i[reader toc_selected])
      end

      def toc_selected=(value)
        update(%i[reader toc_selected], value)
      end

      def bookmark_selected
        get(%i[reader bookmark_selected])
      end

      def bookmark_selected=(value)
        update(%i[reader bookmark_selected], value)
      end

      def popup_menu
        get(%i[reader popup_menu])
      end

      def popup_menu=(value)
        update(%i[reader popup_menu], value)
      end

      def selection
        get(%i[reader selection])
      end

      def selection=(value)
        update(%i[reader selection], value)
      end

      def pages_per_chapter
        get(%i[reader pages_per_chapter])
      end

      def pages_per_chapter=(value)
        update(%i[reader pages_per_chapter], value)
      end

      def dynamic_chapter_starts
        get(%i[reader dynamic_chapter_starts])
      end

      def dynamic_chapter_starts=(value)
        update(%i[reader dynamic_chapter_starts], value)
      end

      def annotations
        get(%i[reader annotations])
      end

      def annotations=(value)
        update(%i[reader annotations], value)
      end

      # Sidebar state accessors
      def sidebar_visible
        get(%i[reader sidebar_visible])
      end

      def sidebar_visible=(value)
        update(%i[reader sidebar_visible], value)
      end

      def sidebar_active_tab
        get(%i[reader sidebar_active_tab])
      end

      def sidebar_active_tab=(value)
        update(%i[reader sidebar_active_tab], value)
      end

      def sidebar_width_percent
        get(%i[reader sidebar_width_percent])
      end

      def sidebar_width_percent=(value)
        update(%i[reader sidebar_width_percent], value)
      end

      def sidebar_toc_selected
        get(%i[reader sidebar_toc_selected])
      end

      def sidebar_toc_selected=(value)
        update(%i[reader sidebar_toc_selected], value)
      end

      def sidebar_annotations_selected
        get(%i[reader sidebar_annotations_selected])
      end

      def sidebar_annotations_selected=(value)
        update(%i[reader sidebar_annotations_selected], value)
      end

      def sidebar_bookmarks_selected
        get(%i[reader sidebar_bookmarks_selected])
      end

      def sidebar_bookmarks_selected=(value)
        update(%i[reader sidebar_bookmarks_selected], value)
      end

      def sidebar_toc_filter
        get(%i[reader sidebar_toc_filter])
      end

      def sidebar_toc_filter=(value)
        update(%i[reader sidebar_toc_filter], value)
      end

      def sidebar_toc_filter_active
        get(%i[reader sidebar_toc_filter_active])
      end

      def sidebar_toc_filter_active=(value)
        update(%i[reader sidebar_toc_filter_active], value)
      end

      # Terminal size tracking methods
      def terminal_size_changed?(width, height)
        width != last_width || height != last_height
      end

      def update_terminal_size(width, height)
        self.last_width = width
        self.last_height = height
      end

      # Legacy compatibility method
      def page_offset=(value)
        update(%i[reader single_page], value)
        update(%i[reader left_page], value)
      end

      # State snapshot for persistence
      def reader_snapshot
        {
          current_chapter: current_chapter,
          page_offset: single_page,
          mode: mode.to_s,
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
