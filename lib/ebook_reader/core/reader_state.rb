# frozen_string_literal: true

module EbookReader
  module Core
    # Manages the state of the reader including current position,
    # view settings, and navigation history.
    #
    # This class encapsulates all mutable state for the Reader,
    # making it easier to test and reason about state changes.
    class ReaderState
      # Lightweight observable implementation tailored for field changes
      def self.attr_state(*fields)
        fields.each do |field|
          define_method(field) do
            instance_variable_get(:"@#{field}")
          end

          define_method(:"#{field}=") do |value|
            update(field, value)
          end
        end
      end

      def initialize
        @observers_by_field = Hash.new { |h, k| h[k] = [] }
        @observers_all = []
        reset_to_defaults
      end

      # Register an observer for specific fields (or all if none given)
      # Observer should respond to `state_changed(field, old, new)`
      def add_observer(observer, *fields)
        if fields.nil? || fields.empty?
          @observers_all << observer unless @observers_all.include?(observer)
        else
          fields.each do |f|
            list = @observers_by_field[f]
            list << observer unless list.include?(observer)
          end
        end
      end

      def remove_observer(observer)
        @observers_all.delete(observer)
        @observers_by_field.each_value { |list| list.delete(observer) }
      end

      # Update a field and notify observers if changed
      def update(field, value)
        iv = :"@#{field}"
        old_value = instance_variable_get(iv)
        return value if old_value == value

        instance_variable_set(iv, value)
        notify_observers(field, old_value, value)
        value
      end

      def notify_observers(field, old_value, new_value)
        # Specific field observers first
        @observers_by_field[field].each do |obs|
          safe_notify(obs, field, old_value, new_value)
        end
        # Then general observers
        @observers_all.each do |obs|
          safe_notify(obs, field, old_value, new_value)
        end
      end

      def safe_notify(observer, field, old_value, new_value)
        return unless observer.respond_to?(:state_changed)

        observer.state_changed(field, old_value, new_value)
      rescue StandardError
        # Swallow notifications errors to avoid breaking app flow
        nil
      end

      # === State fields ===
      # Core reading fields
      attr_state :current_chapter, :left_page, :right_page, :single_page, :mode, :selection
      # Selections / lists
      attr_state :toc_selected, :bookmark_selected
      # Messaging & running
      attr_state :message, :running
      # Pagination maps
      attr_state :page_map, :total_pages, :current_page_index, :pages_per_chapter
      # Terminal sizing
      attr_state :last_width, :last_height
      # Dynamic pagination caches/state
      attr_state :dynamic_page_map, :dynamic_total_pages, :dynamic_chapter_starts,
                 :last_dynamic_width, :last_dynamic_height
      # UI state (centralized from scattered instance variables)
      attr_state :rendered_lines, :bookmarks, :annotations, :popup_menu

      # Reset all state to initial values
      def reset_to_defaults
        reset_position_state
        reset_navigation_state
        reset_system_state
      end

      private

      def reset_position_state
        @current_chapter = 0
        @left_page = 0
        @right_page = 0
        @single_page = 0
        @current_page_index = 0
      end

      def reset_navigation_state
        @mode = :read
        @toc_selected = 0
        @bookmark_selected = 0
        @pages_per_chapter = []
      end

      def reset_system_state
        @message = nil
        @running = true
        @page_map = []
        @total_pages = 0
        @last_width = 0
        @last_height = 0
        @dynamic_page_map = nil
        @dynamic_total_pages = 0
        @dynamic_chapter_starts = []
        @last_dynamic_width = 0
        @last_dynamic_height = 0
        # UI state initialization
        @rendered_lines = {}
        @bookmarks = []
        @annotations = []
        @popup_menu = nil
      end

      # Get current page offset based on view mode
      #
      # @param view_mode [Symbol] :split or :single
      # @return [Integer] Current page offset
      def current_page_offset(view_mode)
        view_mode == :split ? @left_page : @single_page
      end

      # Set page offset for all view modes
      #
      # @param offset [Integer] New page offset
      def page_offset=(offset)
        @single_page = offset
        @left_page = offset
        @right_page = offset
      end

      # Check if terminal size changed
      #
      # @param width [Integer] Current width
      # @param height [Integer] Current height
      # @return [Boolean] true if size changed
      def terminal_size_changed?(width, height)
        width != @last_width || height != @last_height
      end

      # Update last known terminal size
      #
      # @param width [Integer] New width
      # @param height [Integer] New height
      def update_terminal_size(width, height)
        self.last_width = width
        self.last_height = height
      end

      # Create a snapshot of current state for persistence
      #
      # @return [Hash] State snapshot
      def to_h
        {
          current_chapter: @current_chapter,
          page_offset: @single_page,
          mode: @mode,
          timestamp: Time.now.iso8601,
        }
      end

      # Restore state from a snapshot
      #
      # @param snapshot [Hash] State snapshot
      def restore_from(snapshot)
        self.current_chapter = snapshot['current_chapter'] || 0
        self.page_offset = snapshot['page_offset'] || 0
        self.mode = (snapshot['mode'] || 'read').to_sym
      end

      # Determine if reader is using dynamic page mode
      #
      # @param config [Config] reader configuration
      # @return [Boolean] true if dynamic mode
      def dynamic_page_mode?(config)
        config.page_numbering_mode == :dynamic
      end

      public :current_page_offset,
             :page_offset=,
             :terminal_size_changed?,
             :update_terminal_size,
             :to_h,
             :restore_from,
             :dynamic_page_mode?
    end
  end
end
