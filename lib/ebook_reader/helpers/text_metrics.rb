# frozen_string_literal: true

require 'unicode/display_width'

module EbookReader
  module Helpers
    # Utility helpers for measuring and truncating strings (with ANSI support)
    # while respecting grapheme clusters and terminal cell widths.
    module TextMetrics
      TAB_SIZE = 4
      ANSI_REGEX = /\[[0-9;]*[A-Za-z]/
      TOKEN_REGEX = /\[[0-9;]*[A-Za-z]|./m

      module_function

      def visible_length(text)
        cell_data_for(strip_ansi(text.to_s)).sum { |cell| cell[:display_width] }
      end

      def truncate_to(text, width)
        return '' if width.to_i <= 0

        str = text.to_s
        max_width = width.to_i
        return str if max_width >= visible_length(str)

        buffer = +''
        current_width = 0

        str.scan(TOKEN_REGEX).each do |token|
          if token.start_with?("\e[")
            buffer << token
            next
          end

          token_cells = cell_data_for(token)
          token_width = token_cells.sum { |cell| cell[:display_width] }

          if current_width + token_width <= max_width
            buffer << token
            current_width += token_width
          else
            remaining = max_width - current_width
            slice = slice_by_cells(token_cells, token, remaining)
            buffer << slice unless slice.empty?
            break
          end
        end

        buffer
      end

      def cell_data_for(text)
        expanded = expand_tabs(text.to_s)
        cells = []
        char_index = 0
        screen_x = 0

        expanded.each_grapheme_cluster do |cluster|
          grapheme_length = cluster.length
          display_width = display_width_for(cluster)

          cells << {
            cluster: cluster,
            char_start: char_index,
            char_end: char_index + grapheme_length,
            display_width: display_width,
            screen_x: screen_x,
          }

          char_index += grapheme_length
          screen_x += display_width
        end

        cells
      end

      def strip_ansi(text)
        text.to_s.gsub(ANSI_REGEX, '')
      end

      def display_width_for(cluster)
        return TAB_SIZE if cluster == "\t"
        return 0 if cluster == "\u00AD"

        width = Unicode::DisplayWidth.of(cluster, ambiguous: 1)
        width = 1 if width <= 0 && !cluster.empty?
        width
      rescue StandardError
        cluster.length
      end

      def expand_tabs(text, tab_size: TAB_SIZE)
        column = 0
        buffer = +''
        text.to_s.each_grapheme_cluster do |cluster|
          if cluster == "\t"
            spaces = tab_size - (column % tab_size)
            buffer << (' ' * spaces)
            column += spaces
          else
            buffer << cluster
            column += display_width_for(cluster)
          end
        end
        buffer
      end

      def wrap_plain_text(line, width)
        normalized = expand_tabs(line.to_s)
        return [''] if normalized.empty?
        return [normalized] if width.to_i <= 0

        wrapped = []
        current_line = +''
        current_width = 0

        normalized.split(/\s+/).each do |word|
          next if word.nil? || word.empty?

          word_width = visible_length(word)

          if current_width.zero?
            current_line.replace(word)
            current_width = word_width
          elsif current_width + 1 + word_width <= width
            current_line << ' ' unless current_line.empty?
            current_line << word
            current_width += 1 + word_width
          else
            wrapped << current_line.dup unless current_line.empty?
            current_line.replace(word)
            current_width = word_width
          end
        end

        wrapped << current_line.dup unless current_line.empty?
        wrapped = [''] if wrapped.empty?
        wrapped
      end

      def slice_by_cells(cells, token, target_width)
        return '' if target_width <= 0

        consumed = 0
        limit = 0

        cells.each do |cell|
          break if consumed >= target_width

          consumed += cell[:display_width]
          limit = cell[:char_end]
        end

        token[0, limit]
      end
      private_class_method :slice_by_cells
    end
  end
end
