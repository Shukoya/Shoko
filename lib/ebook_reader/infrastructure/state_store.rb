# frozen_string_literal: true

module EbookReader
  module Infrastructure
    # Immutable state store with event-driven updates.
    # Replaces the problematic GlobalState with proper immutability and validation.
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
      def valid_transition?(old_state, new_state, updates)
        true # Base implementation allows all transitions
      end

      private

      def build_initial_state
        {
          reader: {
            current_chapter: 0,
            current_page: 0,
            view_mode: :split,
            sidebar_visible: false,
            mode: :read,
            running: true
          },
          menu: {
            selected_index: 0,
            mode: :main,
            search_query: '',
            search_active: false
          },
          config: {
            line_spacing: :normal,
            page_numbering_mode: :absolute,
            theme: :dark,
            show_page_numbers: true
          },
          ui: {
            terminal_width: 80,
            terminal_height: 24,
            needs_redraw: true
          }
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
        when [:reader, :current_chapter]
          raise ArgumentError, "current_chapter must be non-negative" if value < 0
        when [:reader, :view_mode]
          raise ArgumentError, "invalid view_mode" unless [:single, :split].include?(value)
        when [:ui, :terminal_width], [:ui, :terminal_height]
          raise ArgumentError, "terminal dimensions must be positive" if value <= 0
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
          obj.dup rescue obj # For immutable objects
        end
      end

      def emit_change_events(old_state, new_state, updates)
        updates.each do |path, new_value|
          old_value = get_nested_value(old_state, Array(path))
          next if old_value == new_value
          
          @event_bus.emit_event(:state_changed, {
            path: Array(path),
            old_value: old_value,
            new_value: new_value,
            full_state: new_state
          })
        end
      end

      def get_nested_value(hash, path)
        path.reduce(hash) { |h, key| h&.dig(key) }
      end
    end
  end
end