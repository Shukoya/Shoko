# frozen_string_literal: true

module EbookReader
  module Infrastructure
    # Thread-safe event bus for application-wide event handling.
    # Replaces the problematic observer pattern in GlobalState.
    class EventBus
      def initialize
        @subscribers = Hash.new { |h, k| h[k] = [] }
        @mutex = Mutex.new
      end

      # Subscribe to specific event types
      #
      # @param subscriber [Object] Object responding to #handle_event(event)
      # @param *event_types [Array<Symbol>] Event types to subscribe to
      def subscribe(subscriber, *event_types)
        @mutex.synchronize do
          event_types.each do |event_type|
            @subscribers[event_type] << subscriber unless @subscribers[event_type].include?(subscriber)
          end
        end
      end

      # Unsubscribe from all events
      #
      # @param subscriber [Object] Subscriber to remove
      def unsubscribe(subscriber)
        @mutex.synchronize do
          @subscribers.each_value { |list| list.delete(subscriber) }
        end
      end

      # Emit an event to all subscribers
      #
      # @param event [Event] Event to emit
      def emit(event)
        subscribers = @mutex.synchronize { @subscribers[event.type].dup }
        
        subscribers.each do |subscriber|
          safely_notify(subscriber, event)
        end
      end

      # Create and emit an event
      #
      # @param type [Symbol] Event type
      # @param data [Hash] Event data
      def emit_event(type, data = {})
        event = Event.new(type: type, data: data, timestamp: Time.now)
        emit(event)
      end

      private

      def safely_notify(subscriber, event)
        subscriber.handle_event(event)
      rescue StandardError => e
        Infrastructure::Logger.error(
          "Event subscriber error",
          subscriber: subscriber.class.name,
          event_type: event.type,
          error: e.message
        )
        # Unlike GlobalState, we log errors but don't silently ignore them in development
        # Only re-raise in tests if explicitly expected
        raise e if defined?(RSpec) && !Thread.current[:suppress_event_errors]
      end
    end

    # Immutable event object
    Event = Struct.new(:type, :data, :timestamp, keyword_init: true) do
      def initialize(**args)
        super
        freeze
      end
    end
  end
end