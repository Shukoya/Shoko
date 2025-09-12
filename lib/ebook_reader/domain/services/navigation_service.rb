# frozen_string_literal: true

require_relative 'base_service'
require_relative 'navigation/nav_context'
require_relative 'navigation/strategy_factory'
require_relative 'navigation/dynamic_strategy'
require_relative 'navigation/absolute_strategy'

module EbookReader
  module Domain
    module Services
      # Pure business logic for book navigation.
      # Replaces the coupled NavigationService with clean domain logic.
      class NavigationService < BaseService
        def initialize(dependencies_or_state_store, page_calculator = nil)
          # Support both DI container and legacy (state_store, page_calculator) signature
          if dependencies_or_state_store.respond_to?(:resolve)
            super(dependencies_or_state_store)
          else
            @dependencies = nil
            @state_store = dependencies_or_state_store
            @page_calculator = page_calculator
          end
        end

        # Navigate to next page
        def next_page
          ctx = build_nav_context
          dynamic_route_exec(ctx,
                             -> { apply_dynamic_changes(Navigation::DynamicStrategy.next_page(ctx)) },
                             -> { apply_absolute_changes(Navigation::AbsoluteStrategy.next_page(ctx)) })
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
                               @state_store.update({ %i[reader current_chapter] => chapter_index, %i[reader current_page_index] => page_index })
                             end,
                             -> { apply_absolute_changes(Navigation::AbsoluteStrategy.jump_to_chapter(ctx, chapter_index)) })
        end

        # Navigate to beginning of book
        def go_to_start
          ctx = build_nav_context
          dynamic_route_exec(ctx,
                             -> { @state_store.update({ %i[reader current_chapter] => 0, %i[reader current_page_index] => 0 }) },
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
                               @state_store.update(updates)
                             end,
                             -> do
                               total = ctx.total_chapters
                               return if total.to_i <= 0
                               last_chapter = total - 1
                               last_page = calculate_last_page(last_chapter)
                               apply_absolute_changes({ current_chapter: last_chapter, single_page: last_page, left_page: last_page, right_page: last_page + 1, current_page: last_page })
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
        end

        private

        def build_nav_context
          cs = @state_store.current_state
          view_mode = cs.dig(:config, :view_mode) || cs.dig(:reader, :view_mode) || :split
          mode = dynamic_mode? ? :dynamic : :absolute
          total_chapters = cs.dig(:reader, :total_chapters) || 0
          current_page_fallback = cs.dig(:reader, :current_page) || 0
          ctx = Navigation::NavContext.new(
            mode: mode,
            view_mode: view_mode,
            current_chapter: (cs.dig(:reader, :current_chapter) || 0),
            total_chapters: total_chapters,
            current_page_index: (cs.dig(:reader, :current_page_index) || 0),
            dynamic_total_pages: (@page_calculator&.total_pages || 0),
            single_page: (cs.dig(:reader, :single_page) || current_page_fallback),
            left_page: (cs.dig(:reader, :left_page) || current_page_fallback),
            right_page: (cs.dig(:reader, :right_page) || 0),
            max_page_in_chapter: (mode == :absolute ? calculate_max_page_for_chapter(cs) : 0),
          )
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
          cs = @state_store.current_state
          supports_get = has_reader_get?
          if supports_get
            split_updater = method(:apply_split_alignment_with_get)
            last_page_updater = method(:apply_last_page_with_get)
            align_last_updater = method(:apply_align_to_last_with_get)
            non_adv_updater = method(:apply_non_advancing_with_get)
          else
            split_updater = method(:apply_split_alignment_without_get)
            last_page_updater = method(:apply_last_page_without_get)
            align_last_updater = method(:apply_align_to_last_without_get)
            non_adv_updater = method(:apply_non_advancing_without_get)
          end

          adv = changes[:advance_chapter]
          if adv
            cur_ch = cs.dig(:reader, :current_chapter) || 0
            if adv == :next
              jump_to_chapter(cur_ch + 1)
              return
            elsif adv == :prev
              prev = cur_ch - 1
              last_page = calculate_last_page(prev)
              # Align for split if needed
              if changes[:align] == :split
                aligned = (last_page / 2) * 2
                split_updater.call(prev, aligned)
              else
                last_page_updater.call(prev, last_page)
              end
              return
            end
          end

          # Non-advancing updates
          updates = {}
          ch = changes[:current_chapter]
          updates[%i[reader current_chapter]] = ch if ch
          cp = changes[:current_page]
          updates[%i[reader current_page]] = cp if cp

          non_adv_updater.call(updates, changes, cp)

          # Align to last chapter intent
          if changes[:align_to_last]
            last_chapter = (cs.dig(:reader, :total_chapters) || 1) - 1
            last_page = calculate_last_page(last_chapter)
            updates[%i[reader current_chapter]] = last_chapter
            updates[%i[reader current_page]] = last_page
            supports_get = has_reader_get?
            align_last_updater.call(updates, last_page)
          end

          @state_store.update(updates) unless updates.empty?
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

        def apply_split_alignment_with_get(prev_chapter, aligned)
          @state_store.update({ %i[reader current_chapter] => prev_chapter,
                                %i[reader left_page] => aligned,
                                %i[reader right_page] => aligned + 1,
                                %i[reader current_page] => aligned })
        end

        def apply_split_alignment_without_get(prev_chapter, aligned)
          @state_store.update({ %i[reader current_chapter] => prev_chapter,
                                %i[reader current_page] => aligned })
        end

        def apply_last_page_with_get(prev_chapter, last_page)
          @state_store.update({ %i[reader current_chapter] => prev_chapter,
                                %i[reader single_page] => last_page,
                                %i[reader current_page] => last_page })
        end

        def apply_last_page_without_get(prev_chapter, last_page)
          @state_store.update({ %i[reader current_chapter] => prev_chapter,
                                %i[reader current_page] => last_page })
        end

        def apply_align_to_last_with_get(updates, last_page)
          updates[%i[reader single_page]] = last_page
          updates[%i[reader left_page]] = last_page
          updates[%i[reader right_page]] = last_page + 1
        end

        def apply_align_to_last_without_get(_updates, _last_page)
          # no-op
        end

        def apply_non_advancing_with_get(updates, changes, cp)
          sp = changes[:single_page]
          updates[%i[reader single_page]] = sp if sp
          lp = changes[:left_page]
          if lp
            updates[%i[reader left_page]] = lp
            updates[%i[reader right_page]] = (changes[:right_page] || (lp.to_i + 1))
            updates[%i[reader current_page]] = (cp || lp)
          end
        end

        def apply_non_advancing_without_get(_updates, _changes, _cp)
          # no-op
        end

        def clamp_index(index, total)
          index.clamp(0, total - 1)
        end

        def update_dynamic_index(new_index)
          page = @page_calculator&.get_page(new_index)
          if page
            current_chapter = page[:chapter_index]
            current_chapter ||= (@state_store.current_state.dig(:reader, :current_chapter) || 0)
            @state_store.update({
                                  %i[reader current_page_index] => new_index,
                                  %i[reader current_chapter] => current_chapter,
                                })
          else
            @state_store.set(%i[reader current_page_index], new_index)
          end
        end

        # Navigation via internal strategies; legacy per-mode methods removed

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

        def calculate_max_page_for_chapter(state)
          current_chapter = state.dig(:reader, :current_chapter) || 0
          if @page_calculator
            pages = @page_calculator.calculate_pages_for_chapter(current_chapter)
            return pages if pages.positive?
          end
          # Fallback to state page_map (page count)
          state.dig(:reader, :page_map)&.[](current_chapter) || 0
        end

        def calculate_last_page(chapter_index)
          if @page_calculator
            pages = @page_calculator.calculate_pages_for_chapter(chapter_index)
            return pages if pages.positive?
          end
          # Fallback to state page_map for absolute mode
          state = @state_store.current_state
          state.dig(:reader, :page_map)&.[](chapter_index) || 0
        end
      end
    end
  end
end
