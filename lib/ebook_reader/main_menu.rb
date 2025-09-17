# frozen_string_literal: true

require_relative 'controllers/menu_controller'

module EbookReader
  # Thin facade that preserves the historical MainMenu API while delegating
  # real behaviour to Controllers::MenuController.
  class MainMenu
    def initialize(dependencies = nil)
      @controller = Controllers::MenuController.new(dependencies)
      @dispatcher = @controller.input_controller.dispatcher
      @scanner = @controller.catalog.instance_variable_get(:@scanner)
    end

    def run
      @controller.run
    end

    private

    attr_reader :controller

    def method_missing(method_name, *args, &block)
      if controller.respond_to?(method_name)
        controller.public_send(method_name, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      controller.respond_to?(method_name, include_private) || super
    end
  end
end
