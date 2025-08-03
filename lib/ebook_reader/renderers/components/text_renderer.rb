# frozen_string_literal: true

module EbookReader
  module Renderers
    module Components
      # Handles text rendering with advanced features like
      # syntax highlighting, word wrapping, and special formatting.
      class TextRenderer
        # Initialize text renderer
        #
        # @param config [Config] Reader configuration
        def initialize(config)
          @config = config
        end

        RenderContext = Struct.new(:line, :row, :col, :width)

        # Render a line of text with appropriate formatting
        #
        # @param context [RenderContext] Rendering context
        def render_line(context)
          return if context.line.nil? || context.row.negative? || context.col.negative?

          formatted_line = format_line(context.line, context.width)
          Terminal.write(context.row, context.col, formatted_line)
        end

        # Format a line with highlighting and truncation
        #
        # @param line [String] Text to format
        # @param width [Integer] Maximum width
        # @return [String] Formatted line
        def format_line(line, width)
          truncated = truncate_line(line, width)

          if @config.highlight_quotes && contains_special_content?(truncated)
            apply_highlighting(truncated)
          else
            Terminal::ANSI::WHITE + truncated + Terminal::ANSI::RESET
          end
        end

        private

        # Truncate line to fit width
        #
        # @param line [String] Text to truncate
        # @param width [Integer] Maximum width
        # @return [String] Truncated line
        def truncate_line(line, width)
          return '' if width <= 0
          return line if line.length <= width

          # Smart truncation - try to break at word boundary
          if width > 3 && line[width - 3] != ' ' && (space_pos = line.rindex(' ', width - 3))
            "#{line[0, space_pos]}..."
          else
            line[0, width]
          end
        end

        # Check if line contains special content to highlight
        #
        # @param line [String] Text to check
        # @return [Boolean]
        def contains_special_content?(line)
          line =~ /["']|Chinese poets|philosophers|celebrated|fragrance/
        end

        # Apply syntax highlighting to special content
        #
        # @param line [String] Text to highlight
        # @return [String] Highlighted text
        def apply_highlighting(line)
          highlighted = line.dup

          # Highlight keywords
          keywords = /Chinese poets|philosophers|celebrated|fragrance|plum-blossoms/
          highlighted.gsub!(keywords) do |match|
            Terminal::ANSI::CYAN + match + Terminal::ANSI::WHITE
          end

          # Highlight quoted text
          highlighted.gsub!(/["']([^"']+)["']/) do |match|
            Terminal::ANSI::ITALIC + match + Terminal::ANSI::RESET + Terminal::ANSI::WHITE
          end

          Terminal::ANSI::WHITE + highlighted + Terminal::ANSI::RESET
        end
      end
    end
  end
end
