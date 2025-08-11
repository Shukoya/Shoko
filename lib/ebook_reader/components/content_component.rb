# frozen_string_literal: true

require_relative 'base_component'
require_relative 'surface'
require_relative '../services/layout_service'
require_relative 'reading/view_renderer_factory'
require_relative 'reading/help_renderer'
require_relative 'reading/toc_renderer'
require_relative 'reading/bookmarks_renderer'

module EbookReader
  module Components
    class ContentComponent < BaseComponent
      def initialize(controller)
        @controller = controller
        @view_renderer = nil
        @help_renderer = Reading::HelpRenderer.new
        @toc_renderer = Reading::TocRenderer.new
        @bookmarks_renderer = Reading::BookmarksRenderer.new

        state = @controller.state
        # Observe core fields that affect content rendering
        state.add_observer(self, :current_chapter, :left_page, :right_page,
                           :single_page, :current_page_index, :mode)
        @needs_redraw = true
      end

      # Observer callback triggered by ReaderState
      def state_changed(_field, _old_value, _new_value)
        @needs_redraw = true
        @view_renderer = nil # Reset renderer when state changes
      end

      # Fill remaining space after fixed components
      def preferred_height(_available_height)
        :fill
      end

      def render(surface, bounds)
        state = @controller.state

        # Reset rendered lines registry for selection/highlighting
        @controller.state.rendered_lines = {}

        case state.mode
        when :help
          @help_renderer.render(surface, bounds, @controller)
        when :toc
          @toc_renderer.render(surface, bounds, @controller)
        when :bookmarks
          @bookmarks_renderer.render(surface, bounds, @controller)
        else
          view_renderer.render(surface, bounds, @controller)
        end
        @needs_redraw = false
      end

      private

      def view_renderer
        return @view_renderer if @view_renderer

        @view_renderer = Reading::ViewRendererFactory.create(@controller.config)
      end
    end
  end
end
