# frozen_string_literal: true

require 'digest/sha1'

require_relative 'base_service'
require_relative '../models/content_block'
require_relative '../../helpers/text_metrics'
require_relative '../../infrastructure/parsers/xhtml_content_parser'

module EbookReader
  module Domain
    module Services
      # Responsible for transforming chapter XHTML into semantic blocks and
      # producing display-ready wrapped lines (with style metadata) for renderers.
      class FormattingService < BaseService
        FormattedChapter = Struct.new(:blocks, :plain_lines, :checksum, keyword_init: true)
        private_constant :FormattedChapter

        def initialize(dependencies = nil)
          super(dependencies)
          @chapter_cache = {}
          @wrapped_cache = Hash.new { |h, k| h[k] = {} }
        end

        # Ensure the provided chapter has semantic blocks + plain lines.
        #
        # @param document [EPUBDocument]
        # @param chapter_index [Integer]
        # @param chapter [Domain::Models::Chapter]
        def ensure_formatted!(document, chapter_index, chapter)
          return unless chapter

          raw = chapter.respond_to?(:raw_content) ? chapter.raw_content : nil
          key = chapter_cache_key(document, chapter_index)
          checksum = checksum_for(raw)

          cached = @chapter_cache[key]
          if cached && cached.checksum == checksum
            apply_formatted_to_chapter(chapter, cached)
            return cached
          end

          return cached unless raw

          parser = EbookReader::Infrastructure::Parsers::XHTMLContentParser.new(raw)
          blocks = parser.parse
          formatted = FormattedChapter.new(
            blocks: blocks,
            plain_lines: build_plain_lines(blocks),
            checksum: checksum
          )
          @chapter_cache[key] = formatted
          @wrapped_cache.delete(key)
          apply_formatted_to_chapter(chapter, formatted)
          formatted
        rescue StandardError
          nil
        end

        # Retrieve wrapped, display-ready lines for a chapter window.
        # Returns an array of Domain::Models::DisplayLine, falling back to plain
        # strings when formatting is unavailable.
        #
        # @param document [EPUBDocument]
        # @param chapter_index [Integer]
        # @param width [Integer]
        # @param offset [Integer]
        # @param length [Integer]
        # @return [Array<Domain::Models::DisplayLine,String>]
        def wrap_window(document, chapter_index, width, offset, length)
          return [] if width.to_i <= 0 || length.to_i <= 0

          chapter = document&.get_chapter(chapter_index)
          return [] unless chapter

          formatted = ensure_formatted!(document, chapter_index, chapter)
          unless formatted
            # Fallback to plain lines when formatting unavailable
            lines = (chapter.lines || [])[offset, length] || []
            return lines
          end

          wrapped = wrapped_lines_for(document, chapter_index, formatted, width.to_i)
          wrapped[offset, length] || []
        end

        # Retrieve all wrapped lines for a chapter at the provided width.
        #
        # @return [Array<Domain::Models::DisplayLine>]
        def wrap_all(document, chapter_index, width)
          return [] if width.to_i <= 0

          chapter = document&.get_chapter(chapter_index)
          return [] unless chapter

          formatted = ensure_formatted!(document, chapter_index, chapter)
          return chapter.lines || [] unless formatted

          wrapped_lines_for(document, chapter_index, formatted, width.to_i)
        end

        private

        def wrapped_lines_for(document, chapter_index, formatted, width)
          width_key = width.to_i
          cache_key = chapter_cache_key(document, chapter_index)
          cached = @wrapped_cache[cache_key][width_key]
          return cached if cached

          assembler = LineAssembler.new(width_key)
          lines = assembler.build(formatted.blocks)
          @wrapped_cache[cache_key][width_key] = lines
          lines
        end

        def checksum_for(content)
          Digest::SHA1.hexdigest(content.to_s)
        end

        def apply_formatted_to_chapter(chapter, formatted)
          if chapter.respond_to?(:blocks=)
            chapter.blocks = formatted.blocks
          end
          if chapter.respond_to?(:lines=) && (chapter.lines.nil? || chapter.lines.empty?)
            chapter.lines = formatted.plain_lines
          end
        end

        def chapter_cache_key(document, chapter_index)
          source = document.respond_to?(:canonical_path) ? document.canonical_path : document.object_id
          "#{source}:#{chapter_index}"
        end

        def build_plain_lines(blocks)
          return [] unless blocks

          lines = []
          blocks.each do |block|
            case block.type
            when :heading
              lines << block.text
              lines << ''
            when :paragraph
              lines << block.text
              lines << ''
            when :list_item
              indent = '  ' * [block.level.to_i - 1, 0].max
              marker = block.metadata && block.metadata[:marker] || '•'
              lines << "#{indent}#{marker} #{block.text}"
            when :quote
              lines << "> #{block.text}"
              lines << ''
            when :code, :table
              block.text.split(/\r?\n/).each { |row| lines << row.rstrip }
              lines << ''
            when :separator
              lines << '╌' * 40
            end
          end
          lines.pop while lines.last&.strip&.empty?
          lines
        end

        # Helper responsible for converting semantic blocks into display-ready
        # lines, preserving inline styles and metadata.
        class LineAssembler
          include EbookReader::Domain::Models

          def initialize(width)
            @width = [width.to_i, 10].max
            @lines = []
          end

          def build(blocks)
            @lines.clear
            blocks.each_with_index do |block, index|
              case block.type
              when :paragraph
                append_wrapped_block(block, metadata_for(block))
                append_blank_line_if_needed(blocks, index)
              when :heading
                append_wrapped_block(block, metadata_for(block), prefix: '', continuation_prefix: '')
                append_blank_line_if_needed(blocks, index)
              when :list_item
                append_list_item(block)
                append_blank_line_if_needed(blocks, index)
              when :quote
                append_wrapped_block(block, metadata_for(block).merge(block_type: :quote),
                                     prefix: '│ ', continuation_prefix: '│ ')
                append_blank_line_if_needed(blocks, index)
              when :code, :table
                append_preformatted(block)
                append_blank_line_if_needed(blocks, index, force: true)
              when :separator
                append_separator
              when :break
                append_blank_line
              else
                append_wrapped_block(block, metadata_for(block))
              end
            end
            @lines
          end

          private

          def metadata_for(block)
            (block.metadata || {}).merge(block_type: block.type)
          end

          def append_wrapped_block(block, metadata, prefix: nil, continuation_prefix: nil)
            tokens = tokenize(block.segments)
            return if tokens.empty?

            first_prefix_tokens = prefix_tokens(prefix)
            continuation_tokens = prefix_tokens(continuation_prefix.nil? ? prefix_indent(prefix) : continuation_prefix)

            emit_wrapped_lines(tokens, first_prefix_tokens, continuation_tokens, metadata)
          end

          def append_list_item(block)
            indent = '  ' * [block.level.to_i - 1, 0].max
            marker = block.metadata && block.metadata[:marker] || '•'
            first_prefix = indent + marker.to_s + ' '
            continuation_prefix = indent + ' ' * (marker.to_s.length + 1)
            append_wrapped_block(block, metadata_for(block).merge(list: true),
                                 prefix: first_prefix, continuation_prefix: continuation_prefix)
          end

          def append_preformatted(block)
            text = block.segments.map(&:text).join
            lines = text.split(/\r?\n/)
            style = merge_styles(block.segments.first&.styles, code: true)
            lines.each do |line|
              plain = line.rstrip
              @lines << DisplayLine.new(
                text: plain,
                segments: [TextSegment.new(text: plain, styles: style)],
                metadata: metadata_for(block)
              )
            end
          end

          def append_separator
            bar = '─' * [@width, 40].min
            segment = TextSegment.new(text: bar, styles: { separator: true })
            @lines << DisplayLine.new(text: bar, segments: [segment], metadata: { block_type: :separator })
          end

          def append_blank_line
            @lines << DisplayLine.new(text: '', segments: [], metadata: { spacer: true })
          end

          def append_blank_line_if_needed(blocks, index, force: false)
            return if index == blocks.length - 1

            next_block = blocks[index + 1]
            return if next_block&.type == :list_item && !force

            append_blank_line if force || next_block&.type != :list_item
          end

          def prefix_indent(prefix)
            return nil unless prefix
            ' ' * prefix.to_s.length
          end

          def prefix_tokens(prefix)
            return [] unless prefix && !prefix.empty?

            [token_from_string(prefix, styles: { prefix: true })]
          end

          def emit_wrapped_lines(content_tokens, first_prefix_tokens, continuation_tokens, metadata)
            tokens = content_tokens.dup
            current_tokens = first_prefix_tokens.dup
            current_width = visible_length(current_tokens)
            prefix_for_next = continuation_tokens

            tokens.each do |token|
          if token[:newline]
            finalize_line(current_tokens, metadata)
            current_tokens = prefix_for_next.dup
            current_width = visible_length(current_tokens)
            next
          end

          token_width = EbookReader::Helpers::TextMetrics.visible_length(token[:text])

          if exceeds_width?(current_width, token_width)
            finalize_line(current_tokens, metadata)
            current_tokens = prefix_for_next.dup
            current_width = visible_length(current_tokens)
            next if token[:text].strip.empty?
          end

              next if current_tokens.empty? && token[:text].strip.empty?

              current_tokens << token
            current_width += token_width
          end

          finalize_line(current_tokens, metadata) unless current_tokens.empty?
        end

          def finalize_line(tokens, metadata)
            plain = tokens.select { |token| token[:text] }.map { |tok| tok[:text] }.join.rstrip
            segments = merge_tokens_into_segments(tokens)
            padded_segments = segments.reject { |seg| seg.text.empty? }
            @lines << DisplayLine.new(
              text: plain,
              segments: padded_segments,
              metadata: metadata
            )
          end

          def merge_tokens_into_segments(tokens)
            merged = []
            tokens.each do |token|
              next unless token[:text]

              styles = token[:styles] || {}
              if merged.empty? || merged.last.styles != styles
                merged << TextSegment.new(text: token[:text], styles: styles)
              else
                merged[-1] = TextSegment.new(text: merged[-1].text + token[:text], styles: styles)
              end
            end
            merged
          end

        def exceeds_width?(current_width, token_width)
          current_width.positive? && current_width + token_width > @width
        end

        def visible_length(tokens)
          tokens
            .select { |token| token[:text] }
            .sum { |token| EbookReader::Helpers::TextMetrics.visible_length(token[:text]) }
        end

          def tokenize(segments)
            tokens = []
            segments.to_a.each do |segment|
              text = segment.text.to_s
              styles = segment.styles || {}

              if text.include?("\n")
                text.split(/(\n)/).each do |piece|
                  if piece == "\n"
                    tokens << { newline: true }
                  elsif !piece.empty?
                    tokens.concat(split_token(piece, styles))
                  end
                end
              else
                tokens.concat(split_token(text, styles))
              end
            end
            tokens
          end

          def split_token(text, styles)
            return [] if text.nil? || text.empty?

            parts = text.scan(/\S+\s*/)
            return [{ text:, styles: styles.dup }] if parts.empty?

            parts.map { |part| { text: part, styles: styles.dup } }
          end

          def merge_styles(base, overrides)
            (base || {}).merge(overrides)
          end

          def token_from_string(text, styles: {})
            { text: text, styles: styles.dup }
          end
        end
      end
    end
  end
end
