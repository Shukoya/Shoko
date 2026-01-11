# frozen_string_literal: true

module Shoko
  module Core
    # Base validator class providing common validation patterns.
    # Subclasses should implement specific validation logic.
    #
    # @abstract
    class Validator
      # Validation errors collection
      attr_reader :errors

      def initialize
        @errors = []
      end

      # Check if validation passed
      #
      # @return [Boolean] true if no errors
      def valid?
        @errors.empty?
      end

      # Add an error message
      #
      # @param field [Symbol] Field name
      # @param message [String] Error message
      def add_error(field, message)
        @errors << { field:, message: }
      end

      # Clear all errors
      def clear_errors
        @errors = []
      end

      # Validate presence of a value
      #
      # @param value [Object] Value to check
      # @param field [Symbol] Field name for error reporting
      # @param message [String] Custom error message
      # @return [Boolean] Validation result
      def presence_valid?(value, field, message = "can't be blank")
        return true if value && !value.to_s.strip.empty?

        add_error(field, message)
        false
      end

      RangeValidationContext = Struct.new(:value, :range, :field, :message)
      FormatValidationContext = Struct.new(:value, :pattern, :field, :message)

      # Validate that a value falls within a range
      #
      # @param context [RangeValidationContext] Validation parameters
      # @return [Boolean] Validation result
      def range_valid?(context)
        return true if context.range.include?(context.value)

        add_error(context.field, context.message || 'must be between')
        false
      end

      # Validate that a value matches a regular expression pattern
      #
      # @param context [FormatValidationContext] Validation parameters
      # @return [Boolean] Validation result
      def format_valid?(context)
        return true if context.value&.match?(context.pattern)

        add_error(context.field, context.message || 'has invalid format')
        false
      end
    end
  end
end
