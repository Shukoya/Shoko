# frozen_string_literal: true

require_relative 'base_component'
require_relative '../domain/services/coordinate_service'
require_relative '../domain/services/clipboard_service'

module EbookReader
  module Components
    # Enhanced popup menu that uses the coordinate service for consistent positioning
    # and integrates with the clipboard service for reliable copy functionality.
    class EnhancedPopupMenu < BaseComponent
      attr_reader :visible, :selected_index, :x, :y, :width, :height

      def initialize(selection_range, available_actions = nil, coordinate_service = nil)
        @coordinate_service = coordinate_service || Domain::ContainerFactory.create_default_container.resolve(:coordinate_service)
        @clipboard_service = Domain::ContainerFactory.create_default_container.resolve(:clipboard_service)
        
        @selection_range = @coordinate_service.normalize_selection_range(selection_range)

        unless @selection_range
          @visible = false
          return
        end

        @available_actions = available_actions || default_actions
        @items = @available_actions.map { |action| action[:label] }
        @selected_index = 0
        @visible = true
        @width = calculate_width
        @height = @items.length

        # Ensure we have at least one item before proceeding
        unless @items.any?
          @visible = false
          return
        end

        # Calculate optimal position using coordinate service
        position = @coordinate_service.calculate_popup_position(@selection_range[:end], @width, @height)
        @x = position[:x]
        @y = position[:y]
      end

      def render(surface, bounds)
        return unless @visible

        @items.each_with_index do |item, i|
          render_menu_item(surface, bounds, item, i)
        end
      end

      # Legacy compatibility method for PopupOverlayComponent
      alias render_with_surface render

      def handle_key(key)
        return nil unless @visible

        if Input::KeyDefinitions::NAVIGATION[:up].include?(key)
          move_selection(-1)
          { type: :selection_change }
        elsif Input::KeyDefinitions::NAVIGATION[:down].include?(key)
          move_selection(1)
          { type: :selection_change }
        elsif Input::KeyDefinitions::ACTIONS[:confirm].include?(key)
          execute_selected_action
        elsif Input::KeyDefinitions::ACTIONS[:cancel].include?(key)
          { type: :cancel }
        else
          # Explicitly return nil for unhandled keys to allow fallthrough
          nil
        end
      end

      def handle_click(click_x, click_y)
        return nil unless @visible && contains?(click_x, click_y)

        clicked_index = click_y - @y
        return nil unless clicked_index >= 0 && clicked_index < @items.length

        @selected_index = clicked_index
        execute_selected_action
      end

      def hide
        @visible = false
      end

      def contains?(x, y)
        bounds = Components::Rect.new(x: @x, y: @y, width: @width, height: @height)
        @coordinate_service.within_bounds?(x, y, bounds)
      end

      private

      def default_actions
        actions = []

        # Always offer annotation creation
        actions << {
          label: 'Create Annotation',
          action: :create_annotation,
          icon: '📝',
        }

        # Only offer clipboard if available
        if @clipboard_service.available?
          actions << {
            label: 'Copy to Clipboard',
            action: :copy_to_clipboard,
            icon: '📋',
          }
        end

        actions
      end

      def calculate_width
        max_label_width = @items.map(&:length).max || 0
        max_label_width + 6 # Padding for icon and spacing
      end

      def move_selection(direction)
        return if @items.empty?

        @selected_index = (@selected_index + direction) % @items.length
      end

      def execute_selected_action
        action = @available_actions[@selected_index]
        return { type: :cancel } unless action

        {
          type: :action,
          action: action[:action],
          data: {
            selection_range: @selection_range,
            action_config: action,
          },
        }
      end

      def render_menu_item(surface, bounds, item, index)
        item_y = @y + index
        is_selected = (index == @selected_index)
        action = @available_actions[index]

        # Colors
        bg = is_selected ? Terminal::ANSI::BG_BRIGHT_YELLOW : Terminal::ANSI::BG_DARK
        fg = is_selected ? Terminal::ANSI::BLACK : Terminal::ANSI::WHITE

        # Background
        surface.write(bounds, item_y, @x, "#{bg}#{' ' * @width}#{Terminal::ANSI::RESET}")

        # Content with icon
        icon = action[:icon] || (is_selected ? '❯' : ' ')
        line_text = " #{icon} #{item} ".ljust(@width)
        surface.write(bounds, item_y, @x, "#{bg}#{fg}#{line_text}#{Terminal::ANSI::RESET}")
      end
    end
  end
end
