# frozen_string_literal: true

require_relative 'base_service'

module EbookReader
  module Domain
    module Services
      # Centralizes ephemeral UI notifications (messages with auto-clear timers)
      class NotificationService < BaseService
        def initialize(dependencies)
          super
          @timer = nil
          @mutex = Mutex.new
        end

        # Show a transient message and clear it after duration seconds
        # @param state [Infrastructure::ObserverStateStore]
        # @param text [String]
        # @param duration [Integer]
        def set_message(state, text, duration = 2)
          state.dispatch(EbookReader::Domain::Actions::UpdateMessageAction.new(text))

          @mutex.synchronize do
            begin
              @timer&.kill if @timer&.alive?
            rescue StandardError
              # ignore
            end
            @timer = Thread.new do
              sleep duration
              state.dispatch(EbookReader::Domain::Actions::ClearMessageAction.new)
            end
          end
        end

        protected

        def required_dependencies
          []
        end
      end
    end
  end
end
