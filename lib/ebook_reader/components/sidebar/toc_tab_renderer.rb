# frozen_string_literal: true

require_relative '../base_component'
require_relative 'toc_tab_support'

module EbookReader
  module Components
    module Sidebar
      # TOC tab renderer for sidebar
      class TocTabRenderer < BaseComponent
        include Constants::UIConstants

        def initialize(state, dependencies = nil)
          super()
          @state = state
          @dependencies = dependencies
        end

        def do_render(surface, bounds)
          context = RenderContext.new(surface, bounds, @state, document)
          ComponentOrchestrator.new(context).render
        end

        private

        def document
          @document ||= DocumentResolver.new(@dependencies).resolve
        end
      end
    end
  end
end
