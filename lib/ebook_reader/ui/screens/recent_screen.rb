# frozen_string_literal: true

module EbookReader
  module UI
    module Screens
      # Screen that lists recently opened books and allows
      # quick navigation back to them.
      class RecentScreen
        attr_accessor :selected

        RenderContext = Struct.new(:recent_files, :params, :height, :width)
        private_constant :RenderContext

        def initialize(menu)
          @menu = menu
          @selected = 0
        end

        def draw(height, width)
          render_header(width)
          recent = load_recent_books

          if recent.empty?
            render_empty(height, width)
          else
            render_list(recent, height, width)
          end

          render_footer(height)
        end

        private

        def render_header(width)
          Terminal.write(1, 2, "#{Terminal::ANSI::BRIGHT_CYAN}🕒 Recent Books#{Terminal::ANSI::RESET}")
          Terminal.write(1, [width - 20, 60].max, "#{Terminal::ANSI::DIM}[ESC] Back#{Terminal::ANSI::RESET}")
        end

        def load_recent_books
          recent = RecentFiles.load.select { |r| r && r['path'] && File.exist?(r['path']) }
          @selected = 0 if @selected >= recent.length
          recent
        end

        def render_empty(height, width)
          Terminal.write(height / 2, [(width - 20) / 2, 1].max,
                         "#{Terminal::ANSI::DIM}No recent books#{Terminal::ANSI::RESET}")
        end

        def render_list(recent, height, width)
          list_params = calculate_list_params(height)
          context = RenderContext.new(recent, list_params, height, width)
          render_recent_items(context)
        end

        def calculate_list_params(height)
          {
            start: 4,
            max_items: [(height - 6) / 2, 10].min,
          }
        end

        def render_recent_items(context)
          context.recent_files.take(context.params[:max_items]).each_with_index do |book, i|
            renderer = UI::RecentItemRenderer.new(book: book, index: i, menu: @menu)
            renderer_context = build_renderer_context(context.params[:start], context.height,
                                                      context.width)
            renderer.render(renderer_context)
          end
        end

        def build_renderer_context(list_start, height, width)
          UI::RecentItemRenderer::Context.new(
            list_start: list_start,
            height: height,
            width: width,
            selected_index: @selected
          )
        end

        def render_footer(height)
          Terminal.write(height - 1, 2,
                         "#{Terminal::ANSI::DIM}↑↓ Navigate • Enter Open • ESC Back#{Terminal::ANSI::RESET}")
        end
      end
    end
  end
end
