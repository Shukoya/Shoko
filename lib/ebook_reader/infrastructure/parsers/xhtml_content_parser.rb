# frozen_string_literal: true

require 'rexml/document'
require 'rexml/parsers/pullparser'

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

          document = parse_document(@html)
          return [] unless document

          body = find_body(document) || document.root
          return [] unless body

          blocks = []
          context = Context.new(list_stack: [], in_blockquote: false)
          traverse_children(body, blocks, context)
          compacted = compact_blocks(blocks)

          text_content = body.texts.join.strip
          if !text_content.empty? && compacted.empty?
            Infrastructure::Logger.error(
              'Formatting produced no blocks',
              source: 'XHTMLContentParser',
              sample: text_content.slice(0, 120)
            )
            raise EbookReader::FormattingError.new('chapter', 'normalized block list was empty')
          end

          compacted
        rescue REXML::ParseException => e
          Infrastructure::Logger.error('Failed to parse chapter HTML', error: e.message)
          []
        end

        private

        Context = Struct.new(:list_stack, :in_blockquote, keyword_init: true)
        private_constant :Context

        ListContext = Struct.new(:ordered, :index, keyword_init: true)
        private_constant :ListContext

        def parse_document(text)
          REXML::Document.new(text, ignore_whitespace_nodes: :all)
        rescue REXML::ParseException => e
          raise e
        end

        def find_body(document)
          return nil unless document&.root

          body = document.root.elements['body']
          body || document.root.elements['BODY']
        end

        def traverse_children(node, blocks, context)
          node.children.each do |child|
            case child
            when REXML::Element
              handle_element(child, blocks, context)
            when REXML::Text
              append_text_block(child, blocks, context)
            end
          end
        end

        def handle_element(element, blocks, context)
          name = element.name.downcase
          return if skip_element?(name)

          if HEADING_TYPES.include?(name)
            block = build_heading(element, name, context)
            blocks << block if block
          elsif name == BLOCKQUOTE
            block = build_quote_block(element, context)
            blocks << block if block
          elsif LIST_TYPES.include?(name)
            traverse_list(element, blocks, context, ordered: name == 'ol')
          elsif name == LIST_ITEM
            blocks << build_list_item(element, context)
          elsif name == PRE
            block = build_preformatted(element, context)
            blocks << block if block
          elsif name == HR
            blocks << build_separator_block(context)
          elsif name == TABLE
            blocks.concat(build_table_blocks(element, context))
          elsif BLOCK_TYPES.include?(name) || block_via_style?(element)
            paragraph = build_paragraph(element, context)
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

        def append_text_block(text_node, blocks, context)
          content = text_node.value
          return if content.to_s.strip.empty?

          segment = text_segment(content)
          blocks << build_paragraph_from_segments([segment], context)
        end

        def build_heading(element, name, context)
          level = name.delete('h').to_i
          segments = collect_segments(element, {}, context)
          metadata = { level: level }
          metadata[:quoted] = true if context.in_blockquote
          EbookReader::Domain::Models::ContentBlock.new(
            type: :heading,
            segments: segments,
            level: level,
            metadata: metadata
          )
        end

        def build_quote_block(element, context)
          inner_context = Context.new(list_stack: context.list_stack.dup, in_blockquote: true)
          segments = collect_segments(element, {}, inner_context)
          return nil if segments.empty?

          EbookReader::Domain::Models::ContentBlock.new(
            type: :quote,
            segments: segments,
            metadata: { quoted: true }
          )
        end

        def traverse_list(element, blocks, context, ordered:)
          list_context = ListContext.new(ordered: ordered, index: ordered ? 1 : nil)
          new_context = Context.new(list_stack: context.list_stack + [list_context],
                                    in_blockquote: context.in_blockquote)
          element.each_element do |child|
            handle_element(child, blocks, new_context)
          end
        end

        def build_list_item(element, context)
          list_context = context.list_stack.last
          segments = collect_segments(element, {}, context)
          marker = list_context&.ordered ? "#{list_context.index}." : '•'
          list_context.index += 1 if list_context&.ordered

          segments.map(&:text).join(' ').strip
          level = context.list_stack.length
          metadata = { marker: marker, level: level }
          metadata[:quoted] = true if context.in_blockquote
          EbookReader::Domain::Models::ContentBlock.new(
            type: :list_item,
            segments: segments,
            level: level,
            metadata: metadata
          )
        end

        def build_preformatted(element, context)
          code_child = element.elements.find { |child| child.is_a?(REXML::Element) && child.name.casecmp('code').zero? }
          target = code_child || element
          text = extract_raw_text(target)
          return nil if text.nil?

          metadata = { preserve_whitespace: true }
          metadata[:quoted] = true if context.in_blockquote
          EbookReader::Domain::Models::ContentBlock.new(
            type: :code,
            segments: [text_segment(text, code: true, preserve_whitespace: true)],
            metadata: metadata
          )
        end

        def build_separator_block(context)
          metadata = {}
          metadata[:quoted] = true if context.in_blockquote
          EbookReader::Domain::Models::ContentBlock.new(
            type: :separator,
            segments: [text_segment('─' * 40)],
            metadata: metadata
          )
        end

        def build_table_blocks(element, context)
          rows = collect_descendants(element, 'tr')
          return [] if rows.empty?

          lines = rows.map do |row|
            cells = row.elements.collect do |cell|
              next unless %w[td th].include?(cell.name.downcase)

              collect_segments(cell, {}, context).map(&:text).join.strip
            end
            cells.compact.reject(&:empty?).join(' | ')
          end

          metadata = { preserve_whitespace: true }
          metadata[:quoted] = true if context.in_blockquote
          block = EbookReader::Domain::Models::ContentBlock.new(
            type: :table,
            segments: [text_segment(lines.join(INLINE_NEWLINE), preserve_whitespace: true)],
            metadata: metadata
          )
          [block]
        end

        def collect_descendants(element, name)
          results = []
          element.each_element do |child|
            results << child if child.name.casecmp(name).zero?
            results.concat(collect_descendants(child, name))
          end
          results
        end

        def build_paragraph(element, context)
          segments = collect_segments(element, {}, context)
          return nil if segments.empty?

          metadata = {}
          metadata[:quoted] = true if context.in_blockquote
          EbookReader::Domain::Models::ContentBlock.new(
            type: :paragraph,
            segments: segments,
            metadata: metadata
          )
        end

        def build_paragraph_from_segments(segments, context)
          metadata = {}
          metadata[:quoted] = true if context&.in_blockquote
          EbookReader::Domain::Models::ContentBlock.new(
            type: :paragraph,
            segments: segments,
            metadata: metadata
          )
        end

        def collect_segments(element, inherited_styles = {},
                             context = Context.new(list_stack: [], in_blockquote: false))
          segments = []
          element.children.each do |child|
            case child
            when REXML::Text
              text = child.value
              next if text.strip.empty?

              segments << text_segment(text, inherited_styles)
            when REXML::Element
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
            { link: element.attributes['href'] }.merge(span_styles(element))
          else
            {}
          end
        end

        def span_styles(element)
          style_attr = element.attributes['style']
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
          element.texts.join
        end

        def compact_blocks(blocks)
          blocks.reject do |block|
            block.nil? || block.segments.empty? || block.text.strip.empty?
          end
        end

        def block_via_style?(element)
          style = element.attributes['style'].to_s
          return true if /display\s*:\s*(block|list-item)/i.match?(style)

          false
        end
      end
    end
  end
end
