# frozen_string_literal: true

require_relative 'base_component'
require_relative 'surface'
require_relative 'reading/view_renderer_factory'
require_relative 'reading/help_renderer'
require_relative 'reading/toc_renderer'
require_relative 'reading/bookmarks_renderer'

module EbookReader
  module Components
    class ContentComponent < BaseComponent
      def initialize(controller)
        super(controller&.dependencies) # Initialize BaseComponent with dependencies
        @controller = controller
        @view_renderer = nil
        @help_renderer = Reading::HelpRenderer.new(nil, controller)
        @toc_renderer = Reading::TocRenderer.new(nil, controller)
        @bookmarks_renderer = Reading::BookmarksRenderer.new(nil, controller)

        state = @controller.state
        # Observe core fields that affect content rendering via StateStore paths
        state.add_observer(self, %i[reader current_chapter], %i[reader left_page], %i[reader right_page],
                           %i[reader single_page], %i[reader current_page_index], %i[reader mode], %i[config view_mode])
        @needs_redraw = true
      end

      # Observer callback triggered by ObserverStateStore
      def state_changed(path, old_value, new_value)
        # Reset renderer for mode changes or view mode changes
        @view_renderer = nil if [%i[reader mode], %i[config view_mode]].include?(path)

        # Call parent invalidate to properly trigger re-rendering
        super

        # Keep legacy @needs_redraw for backward compatibility
        @needs_redraw = true
      end

      # Fill remaining space after fixed components
      def preferred_height(_available_height)
        :fill
      end

      def do_render(surface, bounds)
        state = @controller.state

        # Reset rendered lines registry for selection/highlighting
        @controller.state.dispatch(EbookReader::Domain::Actions::UpdateRenderedLinesAction.new({}))

        case state.get(%i[reader mode])
        when :help
          @help_renderer.render(surface, bounds)
        when :toc
          @toc_renderer.render(surface, bounds)
        when :bookmarks
          @bookmarks_renderer.render(surface, bounds)
        else
          view_renderer.render(surface, bounds)
        end
        @needs_redraw = false
      end

      private

      def view_renderer
        return @view_renderer if @view_renderer

        @view_renderer = Reading::ViewRendererFactory.create(@controller.state, @controller)
      end
    end
  end
end
