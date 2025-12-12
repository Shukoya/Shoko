# frozen_string_literal: true

require 'cgi'
require 'rexml/document'
require 'rexml/parsers/pullparser'

require_relative '../../domain/models/content_block'
require_relative '../../helpers/html_processor'
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
        IMG = 'img'
        TABLE = 'table'

        WHITESPACE_PATTERN = /\s+/
        XML_ENTITY_NAMES = %w[amp lt gt apos quot].freeze
        BLOCK_LEVEL_ELEMENTS = (
          BLOCK_TYPES +
          HEADING_TYPES +
          LIST_TYPES +
          [
            LIST_ITEM,
            BLOCKQUOTE,
            PRE,
            HR,
            TABLE,
          ]
        ).freeze

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
          fallback_blocks
        end

        private

        Context = Struct.new(:list_stack, :in_blockquote, keyword_init: true)
        private_constant :Context

        ListContext = Struct.new(:ordered, :index, keyword_init: true)
        private_constant :ListContext

        def parse_document(text)
          sanitized = sanitize_for_xml(text.to_s)
          REXML::Document.new(sanitized, ignore_whitespace_nodes: :all)
        end

        def sanitize_for_xml(text)
          text.gsub(/&([A-Za-z][A-Za-z0-9]+);/) do |match|
            name = Regexp.last_match(1)
            next match if XML_ENTITY_NAMES.include?(name)

            decoded = EbookReader::Helpers::HTMLProcessor.decode_entities(match)
            decoded == match ? "&amp;#{name};" : decoded
          end
        end

        def find_body(document)
          return nil unless document&.root

          document.root.elements['*[local-name()="body"]'] ||
            document.root.elements['body'] ||
            document.root.elements['BODY']
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
          elsif name == IMG
            block = build_image_block(element, context)
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
            if contains_block_children?(element)
              traverse_children(element, blocks, context)
            else
              paragraph = build_paragraph(element, context)
              blocks << paragraph if paragraph
            end
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
          paragraph = build_paragraph_from_segments(finalize_segments([segment]), context)
          blocks << paragraph if paragraph
        end

        def build_heading(element, name, context)
          level = name.delete('h').to_i
          segments = finalize_segments(collect_segments(element, {}, context))
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
          segments = finalize_segments(collect_segments(element, {}, inner_context))
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
          segments = finalize_segments(collect_segments(element, {}, context))
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
          segments = finalize_segments(collect_segments(element, {}, context))
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
          return nil if segments.nil? || segments.empty?

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
              segment = text_segment(text, inherited_styles)
              segments << segment if segment.text && !segment.text.empty?
            when REXML::Element
              name = child.name.downcase
              if name == BR
                segments << text_segment(INLINE_NEWLINE, inherited_styles.merge(break: true))
                next
              end
              if name == IMG
                segments << image_placeholder_segment(child, inherited_styles)
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
          decoded = EbookReader::Helpers::HTMLProcessor.decode_entities(text.to_s)
          return decoded if styles[:code] || styles[:preserve_whitespace]

          if styles[:break]
            return text == INLINE_NEWLINE ? INLINE_NEWLINE : text
          end

          decoded.delete("\r").gsub(/\n/, ' ').gsub(WHITESPACE_PATTERN, ' ')
        end

        def extract_raw_text(element)
          element.texts.join
        end

        def compact_blocks(blocks)
          blocks.reject do |block|
            next false if block&.type == :break

            block.nil? || block.segments.empty? || block.text.strip.empty?
          end
        end

        def block_via_style?(element)
          style = element.attributes['style'].to_s
          return true if /display\s*:\s*(block|list-item)/i.match?(style)

          false
        end

        def contains_block_children?(element)
          element.children.any? do |child|
            next false unless child.is_a?(REXML::Element)

            name = child.name.to_s.downcase
            BLOCK_LEVEL_ELEMENTS.include?(name) || block_via_style?(child)
          end
        end

        def build_image_block(element, context)
          segment = image_placeholder_segment(element, {})
          segments = finalize_segments([segment])
          return nil if segments.empty?

          src = element.attributes['src']
          alt = element.attributes['alt']
          metadata = { image: { src: src, alt: alt } }
          metadata[:quoted] = true if context.in_blockquote

          EbookReader::Domain::Models::ContentBlock.new(
            type: :image,
            segments: segments,
            metadata: metadata
          )
        end

        def build_break_block
          EbookReader::Domain::Models::ContentBlock.new(
            type: :break,
            segments: [],
            metadata: { spacer: true }
          )
        end

        def image_placeholder_segment(element, inherited_styles)
          src = element.attributes['src'].to_s
          alt = element.attributes['alt'].to_s.strip
          label = alt.empty? ? image_label_from_src(src) : alt
          text = label.empty? ? '[Image]' : "[Image: #{label}]"
          text_segment(" #{text} ", inherited_styles.merge(dim: true))
        end

        def image_label_from_src(src)
          return '' if src.nil? || src.empty?

          path = src.split('?', 2).first.to_s
          File.basename(path)
        rescue StandardError
          ''
        end

        def finalize_segments(segments)
          segs = Array(segments).compact
          segs = segs.reject { |seg| seg.text.to_s.empty? }
          return [] if segs.empty?

          segs = collapse_boundary_spaces(segs)
          segs = trim_edge_whitespace(segs)
          segs.reject { |seg| seg.text.to_s.empty? }
        end

        def collapse_boundary_spaces(segments)
          out = [segments.first]
          segments.drop(1).each do |seg|
            prev = out.last
            prev_text = prev.text.to_s
            cur_text = seg.text.to_s
            if prev_text.end_with?(' ') && cur_text.start_with?(' ')
              cur_text = cur_text.sub(/\A +/, '')
              seg = EbookReader::Domain::Models::TextSegment.new(text: cur_text, styles: seg.styles)
            end
            out << seg unless seg.text.to_s.empty?
          end
          out
        end

        def trim_edge_whitespace(segments)
          segs = segments.dup
          return [] if segs.empty?

          first = segs.first
          first_text = first.text.to_s.sub(/\A\s+/, '')
          segs[0] = EbookReader::Domain::Models::TextSegment.new(text: first_text, styles: first.styles)

          last = segs.last
          last_text = last.text.to_s.sub(/\s+\z/, '')
          segs[-1] = EbookReader::Domain::Models::TextSegment.new(text: last_text, styles: last.styles)

          segs.reject { |seg| seg.text.to_s.empty? }
        end

        def fallback_blocks
          text = EbookReader::Helpers::HTMLProcessor.html_to_text(@html)
          return [] if text.to_s.strip.empty?

          paragraphs = text.split(/\n{2,}/).map(&:strip).reject(&:empty?)
          paragraphs.map do |para|
            EbookReader::Domain::Models::ContentBlock.new(
              type: :paragraph,
              segments: [text_segment(para, {})],
              metadata: {}
            )
          end
        rescue StandardError
          []
        end
      end
    end
  end
end
