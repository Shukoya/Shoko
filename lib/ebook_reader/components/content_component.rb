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
        # Observe core fields that affect content rendering with GlobalState paths
        state.add_observer(self, [:reader, :current_chapter], [:reader, :left_page], [:reader, :right_page],
                           [:reader, :single_page], [:reader, :current_page_index], [:reader, :mode], [:config, :view_mode])
        @needs_redraw = true
      end

      # Observer callback triggered by GlobalState
      def state_changed(path, _old_value, _new_value)
        @needs_redraw = true
        # Reset renderer for mode changes or view mode changes
        @view_renderer = nil if path == [:reader, :mode] || path == [:config, :view_mode]
      end

      # Fill remaining space after fixed components
      def preferred_height(_available_height)
        :fill
      end

      def do_render(surface, bounds)
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
