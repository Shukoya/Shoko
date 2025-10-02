# frozen_string_literal: true

require 'fileutils'
begin
  require 'json'
rescue NameError => e
  if e.name == :Fragment
    module JSON
      Fragment = Object unless const_defined?(:Fragment)
    end
    require 'json'
  else
    raise
  end
end
require_relative 'atomic_file_writer'

module EbookReader
  module Infrastructure
    # Immutable state store with event-driven updates.
    # Single source of truth for application state with validation.
    class StateStore
      attr_reader :event_bus

      def initialize(event_bus = EventBus.new)
        @event_bus = event_bus
        @state = build_initial_state
        @mutex = Mutex.new
      end

      # Get current state snapshot (immutable)
      #
      # @return [Hash] Current state
      def current_state
        @mutex.synchronize { deep_dup(@state, true) }
      end

      # Get value at specific path
      #
      # @param path [Array<Symbol>] Path to value
      # @return [Object] Value at path
      def get(path)
        @mutex.synchronize do
          path.reduce(@state) { |state, key| state&.dig(key) }
        end
      end

      # Update state and emit events
      #
      # @param updates [Hash] Hash of path => value updates
      def update(updates)
        @mutex.synchronize do
          old_state = @state
          new_state = apply_updates(old_state, updates)

          return if old_state == new_state

          @state = new_state
          emit_change_events(old_state, new_state, updates)
        end
      end

      # Update single path
      #
      # @param path [Array<Symbol>] Path to update
      # @param value [Object] New value
      def set(path, value)
        update({ path => value })
      end

      # Reset to initial state
      def reset!
        @mutex.synchronize do
          old_state = @state
          @state = build_initial_state
          @event_bus.emit_event(:state_reset, { old_state: old_state, new_state: @state })
        end
      end

      # Validate state transition (override in subclasses)
      #
      # @param old_state [Hash] Previous state
      # @param new_state [Hash] Proposed new state
      # @param updates [Hash] Applied updates
      # @return [Boolean] Whether transition is valid
      def valid_transition?(_old_state, _new_state, _updates)
        true # Base implementation allows all transitions
      end

      # Convenience methods for compatibility with legacy callers
      def terminal_size_changed?(width, height)
        last_width = get(%i[reader last_width])
        last_height = get(%i[reader last_height])
        width != last_width || height != last_height
      end

      def update_terminal_size(width, height)
        update({
                 %i[reader last_width] => width,
                 %i[reader last_height] => height,
                 %i[ui terminal_width] => width,
                 %i[ui terminal_height] => height,
               })
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
        update({
                 %i[reader current_chapter] => snapshot['current_chapter'] || 0,
                 %i[reader single_page] => snapshot['page_offset'] || 0,
                 %i[reader left_page] => snapshot['page_offset'] || 0,
                 %i[reader mode] => (snapshot['mode'] || 'read').to_sym,
               })
      end

      # Configuration persistence methods
      def save_config
        ensure_config_dir
        write_config_file
      rescue StandardError
        # Ignore save errors
      end

      def config_to_h
        get([:config])
      end

      # Dispatch Domain::Actions to update state explicitly
      def dispatch(action)
        return unless action.respond_to?(:apply)

        action.apply(self)
      end

      private

      def build_initial_state
        {
          reader: {
            # Position state
            current_chapter: 0,
            # Compatibility alias (legacy tests expect this under :reader)
            view_mode: :split,
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
            annotations_overlay: nil,
            annotation_editor_overlay: nil,

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
            # Compatibility alias (legacy tests expect selected_index)
            selected_index: 0,
            mode: :menu,
            browse_selected: 0,
            search_query: '',
            search_cursor: 0,
            file_input: '',
            search_active: false,
          },

          config: {
            view_mode: :split,
            line_spacing: :compact,
            page_numbering_mode: :absolute,
            theme: :dark,
            show_page_numbers: true,
            highlight_quotes: false,
            highlight_keywords: false,
            prefetch_pages: 20,
          },

          ui: {
            terminal_width: 80,
            terminal_height: 24,
            needs_redraw: true,
          },
        }
      end

      def apply_updates(state, updates)
        new_state = deep_dup(state, false)

        updates.each do |path, value|
          validate_update(path, value)
          set_nested(new_state, Array(path), value)
        end

        new_state
      end

      def validate_update(path, value)
        # Add validation logic here
        path_array = Array(path)

        case path_array
        when %i[reader current_chapter]
          raise ArgumentError, 'current_chapter must be non-negative' if value.negative?
        when %i[reader view_mode], %i[config view_mode]
          raise ArgumentError, 'invalid view_mode' unless %i[single split].include?(value)
        when %i[ui terminal_width], %i[ui terminal_height]
          raise ArgumentError, 'terminal dimensions must be positive' if value <= 0
        end
      end

      def set_nested(hash, path, value)
        *keys, last_key = path

        if keys.empty?
          hash[last_key] = value
        else
          # Create mutable path to target
          target = hash
          keys.each do |key|
            target[key] = {} unless target.key?(key)
            target = target[key]
          end
          target[last_key] = value
        end
      end

      def deep_dup(obj, freeze_result = false)
        case obj
        when Hash
          result = obj.transform_values { |v| deep_dup(v, freeze_result) }
          freeze_result ? result.freeze : result
        when Array
          result = obj.map { |v| deep_dup(v, freeze_result) }
          freeze_result ? result.freeze : result
        else
          begin
            obj.dup
          rescue StandardError
            obj
          end
        end
      end

      def emit_change_events(old_state, new_state, updates)
        updates.each do |path, new_value|
          arr_path = Array(path)
          old_value = get_nested_value(old_state, arr_path)
          next if old_value == new_value

          @event_bus.emit_event(:state_changed, {
                                  path: arr_path,
                                  old_value: old_value,
                                  new_value: new_value,
                                  full_state: new_state,
                                })
        end
      end

      def get_nested_value(hash, path)
        path.reduce(hash) { |h, key| h&.dig(key) }
      end

      # Configuration file management
      CONFIG_DIR = File.expand_path('~/.config/reader')
      CONFIG_FILE = File.join(CONFIG_DIR, 'config.json')
      SYMBOL_KEYS = %i[view_mode line_spacing page_numbering_mode theme].freeze
      LINE_SPACING_ALIASES = {
        tight: :compact,
        wide: :relaxed,
      }.freeze

      def ensure_config_dir
        FileUtils.mkdir_p(CONFIG_DIR)
      rescue StandardError
        nil
      end

      def write_config_file
        payload = JSON.pretty_generate(config_to_h)
        EbookReader::Infrastructure::AtomicFileWriter.write(CONFIG_FILE, payload)
      rescue StandardError
        nil
      end

      # Load config from file on initialization
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
        config_updates = {}
        data.each do |key, value|
          next unless get([:config]).key?(key)

          value = value.to_sym if SYMBOL_KEYS.include?(key)
          value = LINE_SPACING_ALIASES.fetch(value, value) if key == :line_spacing
          config_updates[[:config, key]] = value
        end
        update(config_updates) unless config_updates.empty?
      end
    end
  end
end
