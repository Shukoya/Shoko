# frozen_string_literal: true

module EbookReader
  module Core
    # Centralized, observable state for MainMenu
    class MainMenuState
      def self.attr_state(*fields)
        fields.each do |field|
          define_method(field) { instance_variable_get(:"@#{field}") }
          define_method(:"#{field}=") { |v| update(field, v) }
        end
      end

      def initialize
        @observers_by_field = Hash.new { |h, k| h[k] = [] }
        @observers_all = []
        reset!
      end

      def reset!
        @selected = 0
        @mode = :menu
        @browse_selected = 0
        @search_query = ''
        @search_cursor = 0
        @file_input = ''
      end

      attr_state :selected, :mode, :browse_selected, :search_query, :search_cursor, :file_input

      def add_observer(observer, *fields)
        if fields.nil? || fields.empty?
          @observers_all << observer unless @observers_all.include?(observer)
        else
          fields.each { |f| @observers_by_field[f] << observer unless @observers_by_field[f].include?(observer) }
        end
      end

      def remove_observer(observer)
        @observers_all.delete(observer)
        @observers_by_field.each_value { |l| l.delete(observer) }
      end

      def update(field, value)
        iv = :"@#{field}"
        old = instance_variable_get(iv)
        return value if old == value
        instance_variable_set(iv, value)
        notify(field, old, value)
        value
      end

      def notify(field, old, new)
        @observers_by_field[field].each { |o| safe_notify(o, field, old, new) }
        @observers_all.each { |o| safe_notify(o, field, old, new) }
      end

      def safe_notify(observer, field, old, new)
        return unless observer.respond_to?(:state_changed)
        observer.state_changed(field, old, new)
      rescue StandardError
        nil
      end
    end
  end
end

