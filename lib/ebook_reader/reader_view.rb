# frozen_string_literal: true

module EbookReader
  # Handles rendering responsibilities separate from the controller.
  class ReaderView
    include ReaderController::DisplayHandler

    def initialize(controller)
      @controller = controller
    end

    def draw_screen
      sync_from_controller
      # Ensure view's @mode mirrors controller's state for rendering branches
      @mode = @state&.mode if defined?(@state)
      super
      sync_to_controller
    end

    private

    def sync_from_controller
      @controller.instance_variables.each do |var|
        instance_variable_set(var, @controller.instance_variable_get(var))
      end
    end

    def sync_to_controller
      instance_variables.each do |var|
        next if var == :@controller

        @controller.instance_variable_set(var, instance_variable_get(var))
      end
    end

    def method_missing(method, *, &)
      if @controller.respond_to?(method)
        @controller.public_send(method, *, &)
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      @controller.respond_to?(method, include_private) || super
    end
  end
end
