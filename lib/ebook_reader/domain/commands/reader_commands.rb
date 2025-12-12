# frozen_string_literal: true

module EbookReader
  module Domain
    module Commands
      # Handles reader mode transitions (help/toc/bookmarks) via domain command flow.
      class ReaderModeCommand < BaseCommand
        def initialize(action)
          @action = action
          super(name: "reader_mode_#{action}", description: "Reader mode action #{action}")
        end

        protected

        def perform(context, _params = {})
          ui_controller = resolve_ui_controller(context)
          return :pass unless ui_controller

          case @action
          when :exit_help, :exit_toc, :exit_bookmarks
            ui_controller.switch_mode(:read)
          else
            raise ExecutionError.new("Unknown reader mode action: #{@action}", command_name: name)
          end
        end

        private

        def resolve_ui_controller(context)
          if context.respond_to?(:dependencies)
            begin
              deps = context.dependencies
              return deps.resolve(:ui_controller) if deps.respond_to?(:resolve)
            rescue StandardError
              # fall through
            end
          end

          context.respond_to?(:ui_controller) ? context.ui_controller : nil
        end
      end

      # Navigation commands for the reader TOC view.
      class ReaderTocCommand < BaseCommand
        def initialize(action)
          @action = action
          super(name: "reader_toc_#{action}", description: "Reader TOC action #{action}")
        end

        protected

        def perform(context, _params = {})
          deps = context.dependencies if context.respond_to?(:dependencies)
          state_store = resolve_state_store(deps, context)
          return :pass unless state_store

          case @action
          when :up
            navigate(state_store, deps, context, direction: :up)
          when :down
            navigate(state_store, deps, context, direction: :down)
          when :select
            select_chapter(state_store, deps, context)
          else
            raise ExecutionError.new("Unknown reader TOC action: #{@action}", command_name: name)
          end
        end

        private

        def resolve_state_store(deps, context)
          return deps.resolve(:state_store) if deps.respond_to?(:resolve)

          context.respond_to?(:state) ? context.state : nil
        rescue StandardError
          nil
        end

        def resolve_document(deps, context)
          if deps.respond_to?(:resolve)
            begin
              return deps.resolve(:document)
            rescue StandardError
              # fallback
            end
          end

          context.respond_to?(:doc) ? context.doc : nil
        end

        def resolve_navigation_service(deps)
          return deps.resolve(:navigation_service) if deps.respond_to?(:resolve)

          nil
        rescue StandardError
          nil
        end

        def navigate(state_store, deps, context, direction:)
          current = state_store.get(%i[reader toc_selected]) || 0
          doc = resolve_document(deps, context)
          indices = navigable_indices(doc)
          target = if direction == :down
                     indices.find { |idx| idx > current } || indices.last || current
                   else
                     indices.reverse.find { |idx| idx < current } || indices.first || current
                   end

          return if target == current

          updates = {
            toc_selected: target,
            sidebar_toc_selected: target,
          }
          state_store.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(updates))
        end

        def select_chapter(state_store, deps, context)
          navigation = resolve_navigation_service(deps)
          return :pass unless navigation

          doc = resolve_document(deps, context)
          entries = toc_entries_for(doc)
          selected_entry_index = (state_store.get(%i[reader toc_selected]) || 0).to_i
          selected_entry_index = selected_entry_index.clamp(0, [entries.length - 1, 0].max)
          chapter_index = entries[selected_entry_index]&.chapter_index
          return :pass unless chapter_index

          navigation.jump_to_chapter(chapter_index)
        end

        def navigable_indices(doc)
          return @cached_indices if defined?(@cached_indices) && @cached_indices

          entries = toc_entries_for(doc)

          indices = []
          entries.each_with_index do |entry, idx|
            indices << idx if entry&.chapter_index
          end

          if indices.empty?
            fallback_count = entries.empty? ? doc&.chapters&.length.to_i : entries.length
            @cached_indices = (0...fallback_count).to_a
          else
            @cached_indices = indices
          end
        end

        def toc_entries_for(doc)
          entries = doc.respond_to?(:toc_entries) ? Array(doc.toc_entries) : []
          return entries unless entries.empty?

          chapters = doc.respond_to?(:chapters) ? Array(doc.chapters) : []
          chapters.each_with_index.map do |chapter, idx|
            Domain::Models::TOCEntry.new(
              title: chapter&.title || "Chapter #{idx + 1}",
              href: nil,
              level: 0,
              chapter_index: idx,
              navigable: true
            )
          end
        end
      end
    end
  end
end
