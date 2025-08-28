# frozen_string_literal: true

module EbookReader
  module UI
    module Components
      # Pure view component for content rendering.
      # Handles different view modes without controller dependencies.
      class PureContentComponent
        def initialize(theme = :dark)
          @theme = theme
        end

        # Render content with view model data
        #
        # @param surface [Components::Surface] Rendering surface
        # @param bounds [Components::Rect] Rendering bounds
        # @param view_model [ViewModels::ReaderViewModel] View data
        def render(surface, bounds, view_model)
          return if bounds.height < 1 || bounds.width < 1

          case view_model.mode
          when :read
            render_reading_content(surface, bounds, view_model)
          when :toc
            render_toc_content(surface, bounds, view_model)
          when :bookmarks
            render_bookmarks_content(surface, bounds, view_model)
          when :help
            render_help_content(surface, bounds, view_model)
          else
            render_placeholder(surface, bounds, "Unknown mode: #{view_model.mode}")
          end
        end

        private

        def render_reading_content(surface, bounds, view_model)
          if view_model.split_mode?
            render_split_view(surface, bounds, view_model)
          else
            render_single_view(surface, bounds, view_model)
          end
        end

        def render_split_view(surface, bounds, view_model)
          return if bounds.width < 10 # Need minimum width for split view

          left_width = bounds.width / 2
          right_width = bounds.width - left_width - 1 # -1 for separator

          # Left column
          left_bounds = Components::Rect.new(
            x: bounds.x,
            y: bounds.y,
            width: left_width,
            height: bounds.height
          )

          # Right column
          right_bounds = Components::Rect.new(
            x: bounds.x + left_width + 1,
            y: bounds.y,
            width: right_width,
            height: bounds.height
          )

          # Separator
          separator_x = bounds.x + left_width
          (0...bounds.height).each do |row|
            surface.write(separator_x, bounds.y + row, '│', theme_color(:separator))
          end

          # Render content in each column
          left_content = get_page_content(view_model, :left)
          right_content = get_page_content(view_model, :right)

          render_text_in_bounds(surface, left_bounds, left_content)
          render_text_in_bounds(surface, right_bounds, right_content)
        end

        def render_single_view(surface, bounds, view_model)
          content = get_page_content(view_model, :single)
          render_text_in_bounds(surface, bounds, content)
        end

        def render_toc_content(surface, bounds, view_model)
          if view_model.toc_entries.empty?
            render_placeholder(surface, bounds, 'No table of contents available')
            return
          end

          view_model.toc_entries.each_with_index do |entry, index|
            next if index >= bounds.height

            prefix = index == view_model.current_chapter ? '► ' : '  '
            text = "#{prefix}#{entry[:title]}"
            color = index == view_model.current_chapter ? theme_color(:selected) : theme_color(:text)

            truncated = truncate_text(text, bounds.width)
            surface.write(bounds.x, bounds.y + index, truncated, color)
          end
        end

        def render_bookmarks_content(surface, bounds, view_model)
          if view_model.bookmarks.empty?
            render_placeholder(surface, bounds, 'No bookmarks')
            return
          end

          view_model.bookmarks.each_with_index do |bookmark, index|
            next if index >= bounds.height

            prefix = '📖 '
            text = "#{prefix}#{bookmark.text_snippet || 'Bookmark'}"
            color = theme_color(:text)

            truncated = truncate_text(text, bounds.width)
            surface.write(bounds.x, bounds.y + index, truncated, color)
          end
        end

        def render_help_content(surface, bounds, _view_model)
          help_lines = [
            'Navigation:',
            '  j/↓     - Next page',
            '  k/↑     - Previous page',
            '  n       - Next chapter',
            '  p       - Previous chapter',
            '  g       - Go to start',
            '  G       - Go to end',
            '',
            'Bookmarks:',
            '  b       - Add bookmark',
            '  B       - View bookmarks',
            '',
            'Other:',
            '  t       - Table of contents',
            '  v       - Toggle view mode',
            '  q       - Quit to menu',
            '  Q       - Quit application',
            '  ?       - Show/hide help',
          ]

          help_lines.each_with_index do |line, index|
            next if index >= bounds.height

            color = line.start_with?(' ') ? theme_color(:help_detail) : theme_color(:help_header)
            truncated = truncate_text(line, bounds.width)
            surface.write(bounds.x, bounds.y + index, truncated, color)
          end
        end

        def render_placeholder(surface, bounds, message)
          centered_y = bounds.height / 2
          centered_x = calculate_centered_x(bounds.width, message.length)

          surface.write(bounds.x + centered_x, bounds.y + centered_y, message,
                        theme_color(:placeholder))
        end

        def render_text_in_bounds(surface, bounds, content_lines)
          content_lines.each_with_index do |line, index|
            next if index >= bounds.height

            truncated = truncate_text(line, bounds.width)
            surface.write(bounds.x, bounds.y + index, truncated, theme_color(:text))
          end
        end

        def get_page_content(view_model, column)
          # This would be provided by the view model based on current page/column
          # For now return sample content
          case column
          when :left
            view_model.content_lines[0...(view_model.content_lines.size / 2)]
          when :right
            view_model.content_lines[(view_model.content_lines.size / 2)..] || []
          when :single
            view_model.content_lines
          else
            []
          end
        end

        def calculate_centered_x(width, text_length)
          [(width - text_length) / 2, 0].max
        end

        def truncate_text(text, max_length)
          return text if text.length <= max_length
          return '' if max_length < 3

          "#{text[0...(max_length - 3)]}..."
        end

        def theme_color(element)
          case @theme
          when :dark
            case element
            when :text then Terminal::ANSI::WHITE
            when :selected then Terminal::ANSI::CYAN
            when :separator then Terminal::ANSI::GRAY
            when :placeholder then Terminal::ANSI::GRAY
            when :help_header then Terminal::ANSI::YELLOW
            when :help_detail then Terminal::ANSI::WHITE
            else Terminal::ANSI::WHITE
            end
          when :light
            case element
            when :text then Terminal::ANSI::BLACK
            when :selected then Terminal::ANSI::BLUE
            when :separator then Terminal::ANSI::GRAY
            when :placeholder then Terminal::ANSI::GRAY
            when :help_header then Terminal::ANSI::RED
            when :help_detail then Terminal::ANSI::BLACK
            else Terminal::ANSI::BLACK
            end
          else
            Terminal::ANSI::WHITE
          end
        end
      end
    end
  end
end
