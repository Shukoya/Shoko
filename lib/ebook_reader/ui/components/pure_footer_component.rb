# frozen_string_literal: true

module EbookReader
  module UI
    module Components
      # Pure view component for footer rendering.
      class PureFooterComponent
        def initialize(theme = :dark)
          @theme = theme
        end

        # Render footer with view model data
        #
        # @param surface [Components::Surface] Rendering surface
        # @param bounds [Components::Rect] Rendering bounds
        # @param view_model [ViewModels::ReaderViewModel] View data
        def render(surface, bounds, view_model)
          return if bounds.height < 1

          render_background(surface, bounds)
          render_mode_info(surface, bounds, view_model)
          render_help_hint(surface, bounds, view_model)
        end

        private

        def render_background(surface, bounds)
          color = theme_color(:footer_bg)
          surface.fill(bounds, ' ', color)
        end

        def render_mode_info(surface, bounds, view_model)
          mode_text = build_mode_text(view_model)
          color = theme_color(:footer_text)
          
          surface.write(bounds.x + 1, bounds.y, mode_text, color)
        end

        def render_help_hint(surface, bounds, view_model)
          return if view_model.mode == :help
          
          help_text = "Press ? for help"
          color = theme_color(:footer_hint)
          
          help_x = bounds.x + bounds.width - help_text.length - 1
          return if help_x <= 10 # Not enough space
          
          surface.write(help_x, bounds.y, help_text, color)
        end

        def build_mode_text(view_model)
          case view_model.mode
          when :read
            if view_model.split_mode?
              "Split View"
            else
              "Single View"
            end
          when :toc
            "Table of Contents - Use j/k to navigate, Enter to select"
          when :bookmarks
            "Bookmarks - Use j/k to navigate, Enter to jump, d to delete"
          when :help
            "Help - Press any key to return to reading"
          else
            view_model.mode.to_s.capitalize
          end
        end

        def theme_color(element)
          case @theme
          when :dark
            case element
            when :footer_bg then Terminal::ANSI::BG_GRAY
            when :footer_text then Terminal::ANSI::WHITE
            when :footer_hint then Terminal::ANSI::CYAN
            else Terminal::ANSI::WHITE
            end
          when :light
            case element
            when :footer_bg then Terminal::ANSI::BG_WHITE
            when :footer_text then Terminal::ANSI::BLACK
            when :footer_hint then Terminal::ANSI::BLUE
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