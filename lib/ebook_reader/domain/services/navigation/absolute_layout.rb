# frozen_string_literal: true

require_relative 'context_helpers'

module EbookReader
  module Domain
    module Services
      module Navigation
        # Computes absolute-layout metrics and enriches navigation contexts.
        class AbsoluteLayout
          # Snapshot of layout-derived values for absolute navigation.
          LayoutState = Struct.new(:snapshot, :view_mode, :metrics, :stride, keyword_init: true)

          def initialize(state_store:, layout_service:)
            @state_store = state_store
            @layout_service = layout_service
          end

          def build
            snapshot = ContextHelpers.safe_snapshot(@state_store)
            view_mode = ContextHelpers.current_view_mode(snapshot)
            metrics = {
              single: lines_for(snapshot, :single),
              split: lines_for(snapshot, :split),
            }
            stride = view_mode == :split ? metrics[:split] : metrics[:single]
            stride = metrics[:single] if stride.to_i <= 0
            stride = 1 if stride.to_i <= 0
            LayoutState.new(snapshot: snapshot, view_mode: view_mode, metrics: metrics, stride: stride)
          end

          def populate_context(ctx)
            return ctx unless ctx.mode == :absolute

            layout_state = build
            ctx.lines_per_page = layout_state.metrics[:single]
            ctx.column_lines_per_page = layout_state.metrics[:split]
            ctx.max_page_in_chapter = page_count(layout_state.snapshot, ctx.current_chapter)
            ctx.max_offset_in_chapter = max_offset_for(layout_state.snapshot, ctx.current_chapter, layout_state.stride)
            ctx
          end

          def page_count(snapshot, chapter_index)
            return 0 if chapter_index.nil?

            snapshot.dig(:reader, :page_map)&.[](chapter_index) || 0
          end

          def max_offset_for(snapshot, chapter_index, stride)
            return 0 if chapter_index.nil? || stride.to_i <= 0

            pages = page_count(snapshot, chapter_index).to_i
            return 0 if pages <= 1

            (pages - 1) * stride
          end

          def column_width(snapshot, view_mode)
            return fallback_width(snapshot) unless @layout_service

            width = fallback_width(snapshot)
            height = fallback_height(snapshot)
            col_width, = @layout_service.calculate_metrics(width, height, view_mode)
            col_width = width if col_width.to_i <= 0
            col_width
          rescue StandardError
            fallback_width(snapshot)
          end

          private

          def lines_for(snapshot, view_mode)
            return fallback_lines(view_mode) unless @layout_service

            width = fallback_width(snapshot)
            height = fallback_height(snapshot)
            _, content_height = @layout_service.calculate_metrics(width, height, view_mode)
            line_spacing = snapshot.dig(:config, :line_spacing) || EbookReader::Constants::DEFAULT_LINE_SPACING
            lines = @layout_service.adjust_for_line_spacing(content_height, line_spacing)
            lines = 1 if lines.to_i <= 0
            lines
          rescue StandardError
            1
          end

          def fallback_width(snapshot)
            snapshot.dig(:ui, :terminal_width) || 80
          end

          def fallback_height(snapshot)
            snapshot.dig(:ui, :terminal_height) || 24
          end

          def fallback_lines(view_mode)
            view_mode == :split ? 2 : 1
          end
        end
      end
    end
  end
end
