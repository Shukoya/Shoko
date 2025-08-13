# frozen_string_literal: true

module EbookReader
  module UI
    module Components
      # Pure view component for header rendering.
      # Eliminates controller dependencies and focuses only on rendering.
      class PureHeaderComponent
        include Constants::UIConstants

        def initialize(theme = :dark)
          @theme = theme
        end

        # Render header with view model data
        #
        # @param surface [Components::Surface] Rendering surface
        # @param bounds [Components::Rect] Rendering bounds
        # @param view_model [ViewModels::ReaderViewModel] View data
        def render(surface, bounds, view_model)
          return if bounds.height < 1

          render_background(surface, bounds)
          render_title_and_progress(surface, bounds, view_model)
          render_message(surface, bounds, view_model) if view_model.has_message?
        end

        private

        def render_background(surface, bounds)
          color = theme_color(:header_bg)
          surface.fill(bounds, ' ', color)
        end

        def render_title_and_progress(surface, bounds, view_model)
          title = build_title_text(view_model)
          progress = build_progress_text(view_model)
          
          # Center title, right-align progress
          title_color = theme_color(:header_text)
          progress_color = theme_color(:header_progress)
          
          title_x = calculate_centered_x(bounds.width, title.length)
          progress_x = bounds.width - progress.length - 1
          
          surface.write(bounds.x + title_x, bounds.y, title, title_color)
          surface.write(bounds.x + progress_x, bounds.y, progress, progress_color) if progress_x > title_x + title.length
        end

        def render_message(surface, bounds, view_model)
          return unless view_model.message && bounds.height > 1
          
          message_bounds = Components::Rect.new(
            x: bounds.x,
            y: bounds.y + 1,
            width: bounds.width,
            height: 1
          )
          
          message_color = theme_color(:message)
          truncated_message = truncate_text(view_model.message, bounds.width - 2)
          centered_x = calculate_centered_x(bounds.width, truncated_message.length)
          
          surface.write(message_bounds.x + centered_x, message_bounds.y, truncated_message, message_color)
        end

        def build_title_text(view_model)
          if view_model.chapter_title && !view_model.chapter_title.empty?
            truncate_text(view_model.chapter_title, 40)
          else
            "Chapter #{view_model.current_chapter + 1}"
          end
        end

        def build_progress_text(view_model)
          case view_model.mode
          when :read
            "#{view_model.chapter_progress} | #{view_model.page_progress} (#{view_model.progress_percentage}%)"
          when :toc
            "Table of Contents"
          when :bookmarks
            "Bookmarks (#{view_model.bookmarks.size})"
          when :help
            "Help"
          else
            view_model.mode.to_s.capitalize
          end
        end

        def calculate_centered_x(width, text_length)
          [(width - text_length) / 2, 0].max
        end

        def truncate_text(text, max_length)
          return text if text.length <= max_length
          return "" if max_length < 3
          
          "#{text[0...(max_length - 3)]}..."
        end

        def theme_color(element)
          case @theme
          when :dark
            case element
            when :header_bg then Terminal::ANSI::BG_GRAY
            when :header_text then Terminal::ANSI::WHITE
            when :header_progress then Terminal::ANSI::CYAN
            when :message then Terminal::ANSI::YELLOW
            else Terminal::ANSI::WHITE
            end
          when :light
            case element
            when :header_bg then Terminal::ANSI::BG_WHITE
            when :header_text then Terminal::ANSI::BLACK
            when :header_progress then Terminal::ANSI::BLUE
            when :message then Terminal::ANSI::RED
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