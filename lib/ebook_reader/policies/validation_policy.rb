# frozen_string_literal: true

module EbookReader
  module Policies
    # Simple policy object for common validation patterns
    class ValidationPolicy
      attr_reader :errors

      def initialize
        @errors = []
      end

      def range_valid?(value, range, field)
        return true if range.include?(value)

        message = "must be between #{range.min} and #{range.max}"
        @errors << { field: field, message: message }
        false
      end

      def format_valid?(value, pattern, field)
        return true if value.to_s.match?(pattern)

        @errors << { field: field, message: 'has invalid format' }
        false
      end

      def valid?
        @errors.empty?
      end
    end
  end
end
