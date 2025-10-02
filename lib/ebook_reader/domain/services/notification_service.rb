# frozen_string_literal: true

require_relative 'base_service'

module EbookReader
  module Domain
    module Services
      # Centralizes ephemeral UI notifications (messages with auto-clear timers)
      class NotificationService < BaseService
        def initialize(dependencies)
          super
          @mutex = Mutex.new
          @clear_deadline = nil
        end

        # Show a transient message and clear it after duration seconds
        # @param state [Infrastructure::ObserverStateStore]
        # @param text [String]
        # @param duration [Numeric]
        def set_message(state, text, duration = 2)
          state.dispatch(EbookReader::Domain::Actions::UpdateMessageAction.new(text))

          duration_seconds = duration ? duration.to_f : 0.0
          if duration_seconds <= 0
            state.dispatch(EbookReader::Domain::Actions::ClearMessageAction.new)
            @mutex.synchronize { @clear_deadline = nil }
            return
          end

          cutoff = Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration_seconds

          @mutex.synchronize do
            @clear_deadline = cutoff
          end
        end

        # Clear the active message when the deadline has elapsed.
        # Call on each render tick to avoid background threads.
        def tick(state)
          should_clear = false

          @mutex.synchronize do
            if @clear_deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @clear_deadline
              @clear_deadline = nil
              should_clear = true
            end
          end

          state.dispatch(EbookReader::Domain::Actions::ClearMessageAction.new) if should_clear
        end

        protected

        def required_dependencies
          []
        end
      end
    end
  end
end
