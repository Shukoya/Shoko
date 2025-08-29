# frozen_string_literal: true

require_relative '../base_component'

module EbookReader
  module Components
    module Reading
      class ContentRenderer < BaseComponent
        def initialize(app_state, doc, reader_state)
          @app_state = app_state
          @doc = doc
          @state = reader_state
        end

        def render_split(surface, bounds)
          chapter = @doc.get_chapter(@state.get([:reader, :current_chapter]))
          return unless chapter

          col_width, content_height = layout_metrics(bounds.width, bounds.height, :split)
          display_height = adjust_for_line_spacing(content_height,
                                                   @app_state.config_state.get([:config, :line_spacing]))
          wrapped = wrap_lines(chapter.lines || [], col_width)

          chapter_info = "[#{@state.get([:reader, :current_chapter]) + 1}] #{chapter.title || 'Unknown'}"
          surface.write_chapter_info(bounds, 1, 1, chapter_info[0, bounds.width - 2].to_s)

          draw_column(surface, bounds,
                      lines: wrapped,
                      offset: @state.get([:reader, :left_page]) || 0,
                      col_width: col_width,
                      height: display_height,
                      row: 3, col: 1,
                      line_spacing: @app_state.config_state.get([:config, :line_spacing]))

          draw_divider(surface, bounds, col_width)

          draw_column(surface, bounds,
                      lines: wrapped,
                      offset: @state.get([:reader, :right_page]) || 0,
                      col_width: col_width,
                      height: display_height,
                      row: 3, col: col_width + 5,
                      line_spacing: @app_state.config_state.get([:config, :line_spacing]))
        end

        def render_single_absolute(surface, bounds)
          chapter = @doc.get_chapter(@state.get([:reader, :current_chapter]))
          return unless chapter

          col_width, content_height = layout_metrics(bounds.width, bounds.height, :single)
          col_start = [(bounds.width - col_width) / 2, 1].max
          displayable = adjust_for_line_spacing(content_height,
                                                @app_state.config_state.get([:config, :line_spacing]))
          wrapped = wrap_lines(chapter.lines || [], col_width)
          lines = wrapped.slice(@state.get([:reader, :single_page]) || 0, displayable) || []

          actual_lines = if @app_state.config_state.get([:config, :line_spacing]) == :relaxed
                           [(lines.size * 2) - 1,
                            0].max
                         else
                           lines.size
                         end
          padding = (content_height - actual_lines)
          start_row = [3 + (padding / 2), 3].max

          lines.each_with_index do |line, idx|
            row = start_row + (@app_state.config_state.get([:config, :line_spacing]) == :relaxed ? idx * 2 : idx)
            break if row >= (3 + displayable)

            draw_line(surface, bounds, line: line, row: row, col: col_start, width: col_width)
          end
        end

        private

        def draw_divider(surface, bounds, col_width)
          (3..[bounds.height - 1, 4].max).each do |row|
            surface.write_divider(bounds, row, col_width + 3)
          end
        end

        def draw_column(surface, bounds, lines:, offset:, col_width:, height:, row:, col:,
                        line_spacing:)
          display_lines = lines.slice(offset, height) || []
          display_lines.each_with_index do |line, idx|
            r = row + (line_spacing == :relaxed ? idx * 2 : idx)
            break if r >= bounds.height - 1

            draw_line(surface, bounds, line: line, row: r, col: col, width: col_width)
          end
        end

        def draw_line(surface, bounds, line:, row:, col:, width:)
          text = line.to_s[0, width]
          surface.write_content_text(bounds, row, col, text)
        end

        def layout_metrics(width, height, view_mode)
          col_width = if view_mode == :split
                        [(width - 3) / 2, 20].max
                      else
                        (width * 0.9).to_i.clamp(30, 120)
                      end
          content_height = [height - 2, 1].max
          [col_width, content_height]
        end

        def adjust_for_line_spacing(height, line_spacing)
          return 1 if height <= 0

          line_spacing == :relaxed ? [height / 2, 1].max : height
        end

        def wrap_lines(lines, width)
          lines.flat_map do |line|
            words = line.split
            next [+''] if words.empty?

            wrapped = words.each_with_object([+'']) do |word, result|
              # +1 only if adding a space
              projected = result.last.length + word.length + (result.last.empty? ? 0 : 1)
              if projected > width
                result << String.new(word)
              else
                result.last << ' ' unless result.last.empty?
                result.last << word
              end
            end
            wrapped
          end
        end
      end
    end
  end
end
