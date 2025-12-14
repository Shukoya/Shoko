# frozen_string_literal: true

require_relative '../base_component'
require_relative '../../models/rendering_context'
require_relative '../../models/render_params'
require_relative '../../models/line_geometry'
require_relative '../../helpers/text_metrics'
require_relative '../../helpers/kitty_unicode_placeholders'
require_relative '../render_style'
require 'digest/sha1'

module EbookReader
  module Components
    module Reading
      # Base class for all view renderers
      class BaseViewRenderer < BaseComponent
        def initialize(dependencies)
          super()
          @dependencies = dependencies
          unless @dependencies
            raise ArgumentError,
                  'Dependencies must be provided to BaseViewRenderer'
          end

          @layout_service = @dependencies.resolve(:layout_service)
        end

        # Standard ComponentInterface implementation
        def do_render(surface, bounds)
          context = create_rendering_context
          return unless context

          # Collect rendered lines for a single, consistent state update per frame
          @rendered_lines_buffer = {}
          @placed_kitty_images = {}
          render_with_context(surface, bounds, context)
          begin
            state = context.state
            state&.dispatch(EbookReader::Domain::Actions::UpdateRenderedLinesAction.new(@rendered_lines_buffer))
          rescue StandardError
            # best-effort; avoid crashing render on bookkeeping
          ensure
            @rendered_lines_buffer = nil
            @placed_kitty_images = nil
          end
        end

        # New rendering interface using context
        def render_with_context(surface, bounds, context)
          raise NotImplementedError, 'Subclasses must implement render_with_context method'
        end

        protected

        def layout_metrics(width, height, view_mode)
          @layout_service.calculate_metrics(width, height, view_mode)
        end

        def adjust_for_line_spacing(height, line_spacing = :normal)
          @layout_service.adjust_for_line_spacing(height, line_spacing)
        end

        def calculate_center_start_row(content_height, lines_count, line_spacing)
          @layout_service.calculate_center_start_row(content_height, lines_count, line_spacing)
        end

        # Compute common layout values for a given view mode
        # Returns [col_width, content_height, spacing, displayable]
        def compute_layout(bounds, view_mode, config)
          col_width, content_height = layout_metrics(bounds.width, bounds.height, view_mode)
          spacing = resolve_line_spacing(config)
          displayable = adjust_for_line_spacing(content_height, spacing)
          [col_width, content_height, spacing, displayable]
        end

        # Draw a vertical divider between columns (shared helper)
        def draw_divider(surface, bounds, divider_col, start_row = 3)
          col = divider_col.to_i
          return if col <= 0

          (start_row..[bounds.height - 1, start_row + 1].max).each do |row|
            surface.write(
              bounds,
              row,
              col,
              "#{EbookReader::Constants::UIConstants::BORDER_PRIMARY}│#{Terminal::ANSI::RESET}"
            )
          end
        end

        # Shared helpers for common renderer patterns
        def center_start_col(total_width, col_width)
          [(total_width - col_width) / 2, 1].max
        end

        def fetch_wrapped_lines(document, chapter_index, col_width, offset, length)
          chapter = document&.get_chapter(chapter_index)
          return [] unless chapter

          if @dependencies&.registered?(:formatting_service)
            begin
              formatting = @dependencies.resolve(:formatting_service)
              config = safe_resolve(:global_state)
              lines = formatting.wrap_window(document, chapter_index, col_width, offset, length,
                                             config: config, lines_per_page: length)
              return lines unless lines.nil? || lines.empty?
            rescue StandardError
              # fall through to wrapping service fallback
            end
          end

          if @dependencies&.registered?(:wrapping_service)
            ws = @dependencies.resolve(:wrapping_service)
            return ws.wrap_window(chapter.lines || [], chapter_index, col_width, offset, length)
          end

          (chapter.lines || [])[offset, length] || []
        end

        # Fetch wrapped lines and return [lines, effective_offset].
        #
        # When Kitty image rendering is enabled, images are represented as a block of
        # empty lines where only the first line triggers the Kitty "place" command.
        # If a page offset lands inside the image block, the terminal frame clear will
        # erase the image and the renderer won't re-place it, resulting in blank space.
        #
        # To keep rendering stable across redraws (mouse selection, overlays, etc.),
        # we snap offsets that point inside an image block back to that block's first
        # line and re-fetch the window.
        def fetch_wrapped_lines_with_offset(document, chapter_index, col_width, offset, length)
          offset_i = offset.to_i
          lines = fetch_wrapped_lines(document, chapter_index, col_width, offset_i, length)
          snapped = snap_offset_to_image_start(lines, offset_i)
          return [lines, offset_i] if snapped == offset_i

          [fetch_wrapped_lines(document, chapter_index, col_width, snapped, length), snapped]
        end

        # Shared helper to draw a list of lines with spacing and clipping considerations.
        # Computes row progression based on current line spacing and stops at bounds.
        def draw_lines(surface, bounds, lines, params)
          ctx = params.context
          spacing = ctx ? resolve_line_spacing(ctx.config) : :normal
          lines.each_with_index do |line, idx|
            row = params.start_row + (spacing == :relaxed ? idx * 2 : idx)
            break if row > bounds.height - 1

            draw_line(surface, bounds,
                      line: line,
                      row: row,
                      col: params.col_start,
                      width: params.col_width,
                      context: ctx,
                      column_id: params.column_id,
                      line_offset: params.line_offset + idx,
                      page_id: params.page_id)
          end
        end

        private

        def snap_offset_to_image_start(lines, offset)
          offset_i = offset.to_i
          return offset_i if offset_i <= 0

          first = Array(lines).first
          return offset_i unless first && first.respond_to?(:metadata)

          meta = first.metadata
          return offset_i unless meta.is_a?(Hash)

          render = meta[:image_render] || meta['image_render']
          return offset_i unless render.is_a?(Hash)

          render_line = meta.key?(:image_render_line) ? meta[:image_render_line] : meta['image_render_line']
          return offset_i if render_line == true

          idx = meta.key?(:image_line_index) ? meta[:image_line_index] : meta['image_line_index']
          return offset_i unless idx

          snapped = offset_i - idx.to_i
          snapped.negative? ? 0 : snapped
        rescue StandardError
          offset.to_i
        end

        def create_rendering_context
          state = @dependencies.resolve(:global_state)
          Models::RenderingContext.new(
            document: safe_resolve(:document),
            page_calculator: safe_resolve(:page_calculator),
            state: state,
            config: state,
            view_model: nil
          )
        end

        def draw_line(surface, bounds, line:, row:, col:, width:, context:, column_id:, line_offset:,
                      page_id:)
          if kitty_image_line?(line, context)
            image_text, image_col_offset = render_kitty_image(line, context)
            surface.write(bounds, row, col + image_col_offset.to_i, image_text) if image_text && !image_text.empty?
            return
          end

          plain_text, styled_text = renderable_line_content(line, width, context)
          abs_row, abs_col = absolute_cell(bounds, row, col)
          max_width = [width.to_i, bounds.right - abs_col + 1].min
          max_width = 0 if max_width.negative?
          start_column = [abs_col - 1, 0].max

          # Ensure geometry matches what will actually be displayed after Surface clipping:
          # - tabs expanded relative to absolute column
          # - newlines normalized to spaces
          # - non-CSI ESC dropped
          clipped_styled = if max_width.positive?
                             EbookReader::Helpers::TextMetrics.truncate_to(
                               styled_text.to_s,
                               max_width,
                               start_column: start_column
                             )
                           else
                             ''
                           end
          clipped_plain = EbookReader::Helpers::TextMetrics.strip_ansi(clipped_styled)

          geometry = build_line_geometry(page_id, column_id, abs_row, abs_col, line_offset,
                                         clipped_plain, clipped_styled)
          record_rendered_line(geometry)
          surface.write(bounds, row, col, clipped_styled)
        end

        def renderable_line_content(line, width, context)
          store = config_store(context&.config)
          highlight_setting = store&.get(%i[config highlight_quotes])
          highlight_enabled = highlight_setting.nil? ? true : !!highlight_setting

          if line.respond_to?(:segments) && line.respond_to?(:text)
            return styled_text_for_display_line(line, width, highlight_enabled:)
          end

          text = EbookReader::Helpers::TextMetrics.truncate_to(line.to_s, width)
          if store
            text = highlight_keywords(text) if store.get(%i[config highlight_keywords])
            text = highlight_quotes(text) if highlight_enabled
          end
          styled = Components::RenderStyle.primary(text)
          [text, styled]
        end

        def absolute_cell(bounds, row, col)
          [bounds.y + row - 1, bounds.x + col - 1]
        end

        def record_rendered_line(geometry)
          return unless @rendered_lines_buffer.is_a?(Hash)

          width = geometry.visible_width
          return if width <= 0 && geometry.plain_text.empty?

          end_col = geometry.column_origin + width - 1
          line_key = geometry.key
          @rendered_lines_buffer[line_key] = {
            row: geometry.row,
            col: geometry.column_origin,
            col_end: end_col,
            text: geometry.plain_text,
            width: width,
            geometry: geometry,
          }

          dump_geometry(geometry) if geometry_debug_enabled?
        end

        def highlight_keywords(line)
          accent = Components::RenderStyle.color(:accent)
          base = Components::RenderStyle.color(:primary)
          line.gsub(Constants::HIGHLIGHT_PATTERNS) do |match|
            accent + match + Terminal::ANSI::RESET + base
          end
        end

        def highlight_quotes(line)
          quote_color = Components::RenderStyle.color(:quote)
          base = Components::RenderStyle.color(:primary)
          line.gsub(Constants::QUOTE_PATTERNS) do |match|
            quote_color + Terminal::ANSI::ITALIC + match + Terminal::ANSI::RESET + base
          end
        end

        def styled_text_for_display_line(line, width, highlight_enabled: true)
          metadata = (line.metadata || {}).dup
          metadata[:highlight_enabled] = highlight_enabled
          plain_builder = +''
          styled_builder = +''
          remaining = width.to_i

          line.segments.each do |segment|
            break if remaining <= 0

            raw_text = segment.text.to_s
            next if raw_text.empty?

            visible_len = EbookReader::Helpers::TextMetrics.visible_length(raw_text)
            text_for_display = if visible_len > remaining
                                 EbookReader::Helpers::TextMetrics.truncate_to(raw_text, remaining)
                               else
                                 raw_text
                               end

            next if text_for_display.empty?

            plain_builder << text_for_display
            styled_builder << Components::RenderStyle.styled_segment(text_for_display,
                                                                     segment.styles || {},
                                                                     metadata: metadata)
            remaining -= EbookReader::Helpers::TextMetrics.visible_length(text_for_display)
          end

          if styled_builder.empty?
            plain_text = plain_builder.empty? ? line.text.to_s[0, width] : plain_builder
            return [plain_text, Components::RenderStyle.primary(plain_text)]
          end

          plain = plain_builder.empty? ? line.text.to_s[0, width] : plain_builder
          [plain, styled_builder]
        end

        def safe_resolve(name)
          return @dependencies.resolve(name) if @dependencies.registered?(name)

          nil
        end

        def kitty_image_line?(line, context)
          return false unless line.respond_to?(:metadata)
          return false unless line.metadata.is_a?(Hash)

          enabled = begin
            renderer = kitty_image_renderer
            renderer && renderer.enabled?(config_store(context&.config))
          rescue StandardError
            false
          end
          return false unless enabled

          meta = line.metadata
          render = meta[:image_render] || meta['image_render']
          return false unless render.is_a?(Hash)

          image = meta[:image] || meta['image'] || {}
          src = image[:src] || image['src']
          !src.to_s.strip.empty?
        end

        def render_kitty_image(line, context)
          renderer = kitty_image_renderer
          return [nil, 0] unless renderer

          meta = line.metadata || {}
          image = meta[:image] || meta['image'] || {}
          src = image[:src] || image['src']
          alt = image[:alt] || image['alt']
          chapter_entry = meta[:chapter_source_path] || meta['chapter_source_path']
          render_opts = meta[:image_render] || meta['image_render'] || {}

          cols = render_opts[:cols] || render_opts['cols'] || 0
          rows = render_opts[:rows] || render_opts['rows'] || 0
          placement_id = render_opts[:placement_id] || render_opts['placement_id']
          col_offset = render_opts[:col_offset] || render_opts['col_offset'] || 0
          line_index = meta[:image_line_index] || meta['image_line_index'] || 0

          core_src = begin
            src.to_s.split(/[?#]/, 2).first.to_s
          rescue StandardError
            src.to_s
          end

          placement_id = begin
            raw = placement_id.to_i
            if raw <= 0
              seed = "#{chapter_entry}|#{core_src}|#{cols.to_i}|#{rows.to_i}"
              raw = Digest::SHA1.digest(seed).unpack1('N')
            end
            raw &= 0xFF_FF_FF
            raw = 1 if raw.zero?
            raw
          rescue StandardError
            1
          end

          dedupe_key = begin
            "#{chapter_entry}|#{core_src}|#{cols.to_i}|#{rows.to_i}|p=#{placement_id}"
          rescue StandardError
            nil
          end

          prepared_id = nil
          if dedupe_key && @placed_kitty_images.is_a?(Hash)
            cached = @placed_kitty_images[dedupe_key]
            prepared_id = cached if cached.is_a?(Integer)
            prepared_id = nil if cached == false
          end

          unless prepared_id
            doc = context&.document
            epub_path = doc&.respond_to?(:canonical_path) ? doc.canonical_path : nil
            book_sha = doc&.respond_to?(:cache_sha) ? doc.cache_sha : nil

            prepared_id = renderer.prepare_virtual(
              output: Terminal,
              book_sha: book_sha,
              epub_path: epub_path,
              chapter_entry_path: chapter_entry,
              src: src,
              cols: cols,
              rows: rows,
              placement_id: placement_id,
              z: -1
            )

            if dedupe_key && @placed_kitty_images.is_a?(Hash)
              @placed_kitty_images[dedupe_key] = prepared_id || false
            end
          end

          if prepared_id && cols.to_i.between?(1, 255) && line_index.to_i.between?(0, 255)
            placeholder = EbookReader::Helpers::KittyUnicodePlaceholders.line(
              image_id: prepared_id,
              placement_id: placement_id,
              row: line_index,
              cols: cols
            )
            return [placeholder, col_offset.to_i]
          end

          render_line = meta.key?(:image_render_line) ? meta[:image_render_line] : meta['image_render_line']
          return ['', col_offset.to_i] unless render_line == true

          plain = '[Image]'
          clipped = cols.to_i.positive? ? EbookReader::Helpers::TextMetrics.truncate_to(plain, cols.to_i) : plain
          [Components::RenderStyle.dim(clipped), col_offset.to_i]
        rescue StandardError
          [nil, 0]
        end

        def kitty_image_renderer
          return @kitty_image_renderer if defined?(@kitty_image_renderer)

          @kitty_image_renderer = begin
            @dependencies.resolve(:kitty_image_renderer)
          rescue StandardError
            nil
          end
        end

        def resolve_line_spacing(config)
          store = config_store(config)
          return EbookReader::Constants::DEFAULT_LINE_SPACING unless store

          EbookReader::Domain::Selectors::ConfigSelectors.line_spacing(store) ||
            EbookReader::Constants::DEFAULT_LINE_SPACING
        rescue StandardError
          EbookReader::Constants::DEFAULT_LINE_SPACING
        end

        def config_store(config)
          return config if config.respond_to?(:get)
          return config.state if config.respond_to?(:state) && config.state.respond_to?(:get)

          nil
        end

        private

        def build_line_geometry(page_id, column_id, abs_row, abs_col, line_offset, plain_text, styled_text)
          cell_data = EbookReader::Helpers::TextMetrics.cell_data_for(plain_text)
          cells = cell_data.map do |cell|
            EbookReader::Models::LineCell.new(
              cluster: cell[:cluster],
              char_start: cell[:char_start],
              char_end: cell[:char_end],
              display_width: cell[:display_width],
              screen_x: cell[:screen_x]
            )
          end

          EbookReader::Models::LineGeometry.new(
            page_id: page_id,
            column_id: column_id,
            row: abs_row,
            column_origin: abs_col,
            line_offset: line_offset,
            plain_text: plain_text,
            styled_text: styled_text,
            cells: cells
          )
        end

        def geometry_debug_enabled?
          ENV['READER_DEBUG_GEOMETRY']&.to_s == '1'
        end

        def dump_geometry(geometry)
          logger = begin
            @dependencies.resolve(:logger)
          rescue StandardError
            nil
          end
          payload = geometry.to_h
          if logger
            logger.debug('geometry.line', payload)
          else
            warn("[geometry] #{payload}")
          end
        end
      end
    end
  end
end
