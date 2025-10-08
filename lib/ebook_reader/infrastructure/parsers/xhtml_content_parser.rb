# frozen_string_literal: true

require 'nokogiri'
require 'nokogiri/html5'

require_relative '../../domain/models/content_block'
require_relative '../../errors'
require_relative '../logger'

module EbookReader
  module Infrastructure
    module Parsers
      # Parses XHTML content into semantic content blocks + text segments.
      class XHTMLContentParser
        INLINE_NEWLINE = "\n"

        BLOCK_TYPES = %w[p div section article aside header footer figure figcaption main].freeze
        HEADING_TYPES = %w[h1 h2 h3 h4 h5 h6].freeze
        LIST_TYPES = %w[ul ol].freeze
        LIST_ITEM = 'li'
        BLOCKQUOTE = 'blockquote'
        PRE = 'pre'
        HR = 'hr'
        BR = 'br'
        TABLE = 'table'

        WHITESPACE_PATTERN = /\s+/

        def initialize(html)
          @html = html.to_s
        end

        def parse
          return [] if @html.strip.empty?

          document = Nokogiri::HTML5.parse(@html)
          body = document.at('body') || document.root
          return [] unless body

          blocks = []
          traverse_children(body, blocks, Context.new(list_stack: [], in_blockquote: false))
          compacted = compact_blocks(blocks)

          text_content = body.text.to_s.strip
          if !text_content.empty? && compacted.empty?
            Infrastructure::Logger.error(
              'Formatting produced no blocks',
              source: 'XHTMLContentParser',
              sample: text_content.slice(0, 120)
            )
            raise EbookReader::FormattingError.new('chapter', 'normalized block list was empty')
          end

          compacted
        rescue Nokogiri::XML::SyntaxError => e
          Infrastructure::Logger.error('Failed to parse chapter HTML', error: e.message)
          []
        end

        private

        Context = Struct.new(:list_stack, :in_blockquote, keyword_init: true)
        private_constant :Context

        ListContext = Struct.new(:ordered, :index, keyword_init: true)
        private_constant :ListContext

        def traverse_children(node, blocks, context)
          node.children.each do |child|
            case child
            when Nokogiri::XML::Element
              handle_element(child, blocks, context)
            when Nokogiri::XML::Text
              append_text_block(child, blocks)
            end
          end
        end

        def handle_element(element, blocks, context)
          name = element.name.downcase

          return if skip_element?(name)

          if HEADING_TYPES.include?(name)
            blocks << build_heading(element, name)
          elsif name == BLOCKQUOTE
            traverse_blockquote(element, blocks, context)
          elsif LIST_TYPES.include?(name)
            traverse_list(element, blocks, context, ordered: name == 'ol')
          elsif name == LIST_ITEM
            blocks << build_list_item(element, context)
          elsif name == PRE
            blocks << build_preformatted(element)
          elsif name == HR
            blocks << build_separator_block
          elsif name == TABLE
            blocks.concat(build_table_blocks(element))
          elsif BLOCK_TYPES.include?(name) || block_via_style?(element)
            paragraph = build_paragraph(element)
            blocks << paragraph if paragraph
          elsif name == BR
            blocks << build_break_block
          else
            traverse_children(element, blocks, context)
          end
        end

        def skip_element?(name)
          %w[script style].include?(name)
        end

        def append_text_block(text_node, blocks)
          content = text_node.text
          return if content.to_s.strip.empty?

          segment = text_segment(content)
          blocks << build_paragraph_from_segments([segment])
        end

        def build_heading(element, name)
          level = name.delete('h').to_i
          segments = collect_segments(element)
          EbookReader::Domain::Models::ContentBlock.new(
            type: :heading,
            segments: segments,
            level: level,
            metadata: { level: level }
          )
        end

        def traverse_blockquote(element, blocks, _context)
          segments = collect_segments(element).map do |segment|
            EbookReader::Domain::Models::TextSegment.new(
              text: segment.text,
              styles: (segment.styles || {}).merge(quote: true)
            )
          end
          blocks << EbookReader::Domain::Models::ContentBlock.new(
            type: :quote,
            segments: segments,
            metadata: { quoted: true }
          )
        end

        def traverse_list(element, blocks, context, ordered: false)
          stack = context.list_stack ||= []
          stack.push(ListContext.new(ordered:, index: 0))
          element.element_children.each do |child|
            next unless child.name&.downcase == LIST_ITEM

            blocks << build_list_item(child, context)
          end
          stack.pop
        end

        def build_list_item(element, context)
          stack = context.list_stack ||= []
          stack.last.index += 1 if stack.last
          level = stack.size
          marker = list_marker_for(stack)
          segments = collect_segments(element)
          EbookReader::Domain::Models::ContentBlock.new(
            type: :list_item,
            level: level,
            segments: segments,
            metadata: {
              marker: marker,
              ordered: stack.last&.ordered,
              quoted: context.in_blockquote || false,
            }
          )
        end

        def list_marker_for(stack)
          return '•' if stack.empty? || stack.last.nil?

          if stack.last.ordered
            "#{stack.last.index}."
          else
            '•'
          end
        end

        def build_preformatted(element)
          text = extract_raw_text(element)
          segments = [text_segment(text, code: true, preserve_whitespace: true)]
          EbookReader::Domain::Models::ContentBlock.new(
            type: :code,
            segments: segments,
            metadata: { preserve_whitespace: true }
          )
        end

        def build_separator_block
          EbookReader::Domain::Models::ContentBlock.new(
            type: :separator,
            segments: [text_segment('')]
          )
        end

        def build_break_block
          EbookReader::Domain::Models::ContentBlock.new(
            type: :break,
            segments: [text_segment('')]
          )
        end

        def build_table_blocks(element)
          rows = element.css('tr')
          return [] if rows.empty?

          lines = rows.map do |row|
            cells = row.element_children.map do |cell|
              collect_segments(cell).map(&:text).join.strip
            end
            cells.reject(&:empty?).join(' | ')
          end
          block = EbookReader::Domain::Models::ContentBlock.new(
            type: :table,
            segments: [text_segment(lines.join(INLINE_NEWLINE), preserve_whitespace: true)],
            metadata: { preserve_whitespace: true }
          )
          [block]
        end

        def build_paragraph(element)
          segments = collect_segments(element)
          return nil if segments.empty?

          EbookReader::Domain::Models::ContentBlock.new(
            type: :paragraph,
            segments: segments,
            metadata: {}
          )
        end

        def build_paragraph_from_segments(segments)
          EbookReader::Domain::Models::ContentBlock.new(
            type: :paragraph,
            segments: segments,
            metadata: {}
          )
        end

        def collect_segments(element, inherited_styles = {},
                             context = Context.new(list_stack: [], in_blockquote: false))
          segments = []
          element.children.each do |child|
            case child
            when Nokogiri::XML::Text
              text = child.text
              next if text.strip.empty?

              segments << text_segment(text, inherited_styles)
            when Nokogiri::XML::Element
              name = child.name.downcase
              if name == BR
                segments << text_segment(INLINE_NEWLINE, inherited_styles.merge(break: true))
                next
              end

              new_styles = inherited_styles.merge(styles_for(name, child))
              segments.concat(collect_segments(child, new_styles, context))
            end
          end
          segments
        end

        def text_segment(text, styles = {})
          EbookReader::Domain::Models::TextSegment.new(
            text: normalize_text(text.to_s, styles),
            styles: styles
          )
        end

        def styles_for(name, element)
          case name
          when 'strong', 'b'
            { bold: true }
          when 'em', 'i'
            { italic: true }
          when 'u'
            { underline: true }
          when 'code', 'kbd', 'samp'
            { code: true, preserve_whitespace: true }
          when 'span'
            span_styles(element)
          when 'a'
            { link: element['href'] }.merge(span_styles(element))
          else
            {}
          end
        end

        def span_styles(element)
          style_attr = element['style']
          return {} unless style_attr

          styles = {}
          styles[:bold] = true if /font-weight\s*:\s*bold/i.match?(style_attr)
          styles[:italic] = true if /font-style\s*:\s*italic/i.match?(style_attr)
          styles[:underline] = true if /text-decoration\s*:\s*underline/i.match?(style_attr)
          styles
        end

        def normalize_text(text, styles)
          return text if styles[:code] || styles[:preserve_whitespace]

          if styles[:break]
            return text == INLINE_NEWLINE ? INLINE_NEWLINE : text
          end

          text.gsub(/\r?\n/, ' ').gsub(WHITESPACE_PATTERN, ' ').strip
        end

        def extract_raw_text(element)
          element.text.to_s
        end

        def compact_blocks(blocks)
          blocks.reject do |block|
            block.nil? || block.segments.empty? || block.text.strip.empty?
          end
        end

        def block_via_style?(element)
          style = element['style'].to_s
          return true if /display\s*:\s*(block|list-item)/i.match?(style)

          false
        end
      end
    end
  end
end
