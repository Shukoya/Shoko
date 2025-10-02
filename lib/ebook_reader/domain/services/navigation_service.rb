# frozen_string_literal: true

require_relative 'base_service'
require_relative 'navigation/nav_context'
require_relative 'navigation/context_builder'
require_relative 'navigation/strategy_factory'
require_relative 'navigation/dynamic_strategy'
require_relative 'navigation/absolute_strategy'

module EbookReader
  module Domain
    module Services
      # Pure business logic for book navigation.
      # Replaces the coupled NavigationService with clean domain logic.
      class NavigationService < BaseService
        class LegacyDependencyWrapper
          def initialize(state_store, page_calculator)
            @state_store = state_store
            @page_calculator = page_calculator
          end

          def resolve(name)
            case name
            when :state_store then @state_store
            when :page_calculator then @page_calculator
            else
              raise ArgumentError, "Legacy dependency :#{name} not available"
            end
          end

          def registered?(name)
            %i[state_store page_calculator].include?(name)
          end
        end

        def initialize(*args)
          if args.length == 1
            super(args.first)
          else
            super(LegacyDependencyWrapper.new(*args))
          end
        end

        # Navigate to next page
        def next_page
          ctx = build_nav_context
          dynamic_route_exec(ctx,
                             -> { apply_dynamic_changes(Navigation::DynamicStrategy.next_page(ctx)) },
                             -> do
                               populate_absolute_context(ctx)
                               apply_absolute_changes(Navigation::AbsoluteStrategy.next_page(ctx))
                             end)
        end

        # Navigate to previous page
        def prev_page
          ctx = build_nav_context
          dynamic_route_exec(ctx,
                             -> { apply_dynamic_changes(Navigation::DynamicStrategy.prev_page(ctx)) },
                             -> { apply_absolute_changes(Navigation::AbsoluteStrategy.prev_page(ctx)) })
        end

        # Navigate to specific chapter
        #
        # @param chapter_index [Integer] Zero-based chapter index
        def jump_to_chapter(chapter_index)
          validate_chapter_index(chapter_index)
          ctx = build_nav_context
          dynamic_route_exec(ctx,
                             -> do
                               page_index = @page_calculator.find_page_index(chapter_index, 0)
                               page_index = 0 if page_index.nil? || page_index.negative?
                               apply_updates({ %i[reader current_chapter] => chapter_index, %i[reader current_page_index] => page_index })
                             end,
                             -> { apply_absolute_changes(Navigation::AbsoluteStrategy.jump_to_chapter(ctx, chapter_index)) })
        end

        # Navigate to beginning of book
        def go_to_start
          ctx = build_nav_context
          dynamic_route_exec(ctx,
                             -> { apply_updates({ %i[reader current_chapter] => 0, %i[reader current_page_index] => 0 }) },
                             -> { apply_absolute_changes(Navigation::AbsoluteStrategy.go_to_start(ctx)) })
        end

        # Navigate to end of book
        def go_to_end
          ctx = build_nav_context
          dynamic_route_exec(ctx,
                             -> do
                               total = @page_calculator.total_pages
                               return if total <= 0
                               last_index = total - 1
                               page = @page_calculator.get_page(last_index)
                               updates = { %i[reader current_page_index] => last_index }
                               if page
                                 ch_idx = page[:chapter_index]
                                 updates[%i[reader current_chapter]] = ch_idx if ch_idx
                               end
                               apply_updates(updates)
                             end,
                             -> do
                               total = ctx.total_chapters
                               return if total.to_i <= 0

                               metrics = absolute_metrics
                               view_mode = ctx.view_mode
                               stride = stride_for_view(view_mode, metrics)
                               last_chapter = total - 1
                               offset = max_offset_for_chapter(last_chapter, stride)

                               changes = {
                                 current_chapter: last_chapter,
                                 current_page: offset,
                               }
                               if view_mode == :split
                                 changes[:left_page] = offset
                                 changes[:right_page] = offset + stride
                               else
                                 changes[:single_page] = offset
                               end

                               apply_absolute_changes(changes)
                             end)
        end

        # Scroll within current page/view
        #
        # @param direction [Symbol] :up or :down
        # @param lines [Integer] Number of lines to scroll
        def scroll(direction, lines = 1)
          ctx = build_nav_context
          if dynamic?(ctx)
            # No-op for dynamic; scrolling is page-based via next/prev
            return
          end
          populate_absolute_context(ctx)
          changes = Navigation::AbsoluteStrategy.scroll(ctx, direction, lines)
          apply_absolute_changes(changes)
        end

        protected

        def required_dependencies
          [:state_store]
        end

        def setup_service_dependencies
          @state_store = resolve(:state_store)
          @page_calculator = resolve(:page_calculator) if registered?(:page_calculator)
          @layout_service = resolve(:layout_service) if registered?(:layout_service)
        end

        private

        def build_nav_context
          ctx = context_builder.build
          populate_absolute_context(ctx)
          ctx
        end

        def apply_dynamic_changes(changes)
          return if changes.nil? || changes.empty?
          cpi = changes[:current_page_index]
          update_dynamic_index(cpi) if cpi
          ch = changes[:current_chapter]
          @state_store.set(%i[reader current_chapter], ch) if ch
        end

        def apply_absolute_changes(changes)
          return if changes.nil? || changes.empty?

          snapshot = safe_snapshot
          metrics = absolute_metrics(snapshot)
          view_mode = snapshot.dig(:config, :view_mode) || :split
          single_stride = metrics[:single]
          split_stride = metrics[:split]

          if (adv = changes[:advance_chapter])
            current_chapter = snapshot.dig(:reader, :current_chapter) || 0
            case adv
            when :next
              jump_to_chapter(current_chapter + 1)
              return
            when :prev
              previous = current_chapter - 1
              return if previous.negative?

              stride = view_mode == :split ? split_stride : single_stride
              offset = max_offset_for_chapter(previous, stride)
              updates = {
                %i[reader current_chapter] => previous,
                %i[reader current_page] => offset,
              }
              if view_mode == :split
                updates[%i[reader left_page]] = offset
                updates[%i[reader right_page]] = offset + stride
              else
                updates[%i[reader single_page]] = offset
              end
              apply_updates(updates)
              return
            end
          end

          updates = {}
          updates[%i[reader current_chapter]] = changes[:current_chapter] if changes.key?(:current_chapter)
          updates[%i[reader current_page]] = changes[:current_page] if changes.key?(:current_page)
          updates[%i[reader single_page]] = changes[:single_page] if changes.key?(:single_page)
          updates[%i[reader left_page]] = changes[:left_page] if changes.key?(:left_page)
          updates[%i[reader right_page]] = changes[:right_page] if changes.key?(:right_page)

          if changes[:align_to_last]
            last_chapter = (snapshot.dig(:reader, :total_chapters) || 1) - 1
            stride = view_mode == :split ? split_stride : single_stride
            offset = max_offset_for_chapter(last_chapter, stride)
            updates[%i[reader current_chapter]] = last_chapter
            updates[%i[reader current_page]] = offset
            if view_mode == :split
              updates[%i[reader left_page]] = offset
              updates[%i[reader right_page]] = offset + stride
            else
              updates[%i[reader single_page]] = offset
            end
          end

          apply_updates(updates)
        end

        def dynamic_mode?
          return false unless has_reader_get?
          EbookReader::Domain::Selectors::ConfigSelectors.page_numbering_mode(@state_store) == :dynamic
        end

        def dynamic?(ctx)
          ctx.mode == :dynamic
        end

        def has_page_calc? = !@page_calculator.nil?

        def has_reader_get? = @state_store.respond_to?(:get)

        def dynamic_route(ctx)
          if dynamic?(ctx) && has_page_calc?
            yield :dynamic
          else
            yield :absolute
          end
        end

        def dynamic_route_exec(ctx, dyn_proc, abs_proc)
          if dynamic?(ctx) && has_page_calc?
            dyn_proc.call
          else
            abs_proc.call
          end
        end

        def populate_absolute_context(ctx, snapshot = safe_snapshot)
          return ctx unless ctx.mode == :absolute

          metrics = absolute_metrics(snapshot)
          ctx.lines_per_page = metrics[:single]
          ctx.column_lines_per_page = metrics[:split]
          ctx.max_page_in_chapter = page_count_from_state(ctx.current_chapter)
          ctx.max_offset_in_chapter = max_offset_for_chapter(ctx.current_chapter,
                                                             stride_for_view(ctx.view_mode, metrics))
          ctx
        end

        def apply_updates(updates)
          return if updates.nil? || updates.empty?

          if @state_store.respond_to?(:update) && (@state_store.respond_to?(:set) ? updates.length > 1 : true)
            @state_store.update(updates)
          elsif @state_store.respond_to?(:set)
            updates.each { |path, value| @state_store.set(path, value) }
          elsif @state_store.respond_to?(:update)
            @state_store.update(updates)
          end
        end

        def clamp_index(index, total)
          index.clamp(0, total - 1)
        end

        def update_dynamic_index(new_index)
          page = @page_calculator&.get_page(new_index)
          if page
            current_chapter = page[:chapter_index]
            current_chapter ||= (@state_store.current_state.dig(:reader, :current_chapter) || 0)
            apply_updates({
                           %i[reader current_page_index] => new_index,
                           %i[reader current_chapter] => current_chapter,
                         })
          else
            if @state_store.respond_to?(:set)
              @state_store.set(%i[reader current_page_index], new_index)
            else
              apply_updates({ %i[reader current_page_index] => new_index })
            end
          end
        end

        # Navigation via internal strategies; legacy per-mode methods removed

        def absolute_metrics(state = safe_snapshot)
          {
            single: lines_for_view(state, :single),
            split: lines_for_view(state, :split),
          }
        end

        def stride_for_view(view_mode, metrics)
          stride = view_mode == :split ? metrics[:split] : metrics[:single]
          stride = metrics[:single] if stride.to_i <= 0
          stride = 1 if stride.to_i <= 0
          stride
        end

        def lines_for_view(state, view_mode)
          unless @layout_service
            return view_mode == :split ? 2 : 1
          end

          width = state.dig(:ui, :terminal_width) || 80
          height = state.dig(:ui, :terminal_height) || 24
          _, content_height = @layout_service.calculate_metrics(width, height, view_mode)
          line_spacing = state.dig(:config, :line_spacing) || EbookReader::Constants::DEFAULT_LINE_SPACING
          lines = @layout_service.adjust_for_line_spacing(content_height, line_spacing)
          lines = 1 if lines.to_i <= 0
          lines
        rescue StandardError
          1
        end

        def max_offset_for_chapter(chapter_index, stride)
          return 0 if chapter_index.nil? || stride.to_i <= 0

          pages = page_count_from_state(chapter_index).to_i
          return 0 if pages <= 1

          (pages - 1) * stride
        end

        def validate_chapter_index(index)
          raise ArgumentError, 'Chapter index must be non-negative' if index.negative?

          current_state = @state_store.current_state
          total_chapters = current_state.dig(:reader, :total_chapters) || 0

          return unless index >= total_chapters

          raise ArgumentError, "Chapter index #{index} exceeds total chapters #{total_chapters}"
        end

        def can_advance_chapter?(state)
          current_chapter = state.dig(:reader, :current_chapter) || 0
          total_chapters = state.dig(:reader, :total_chapters) || 0
          current_chapter < total_chapters - 1
        end

        def context_builder
          @context_builder ||= Navigation::ContextBuilder.new(@state_store, @page_calculator)
        end

        def safe_snapshot
          return {} unless @state_store.respond_to?(:current_state)

          @state_store.current_state || {}
        rescue StandardError
          {}
        end

        def page_count_from_state(chapter_index)
          return 0 if chapter_index.nil?

          state = safe_snapshot
          state.dig(:reader, :page_map)&.[](chapter_index) || 0
        end
      end
    end
  end
end
