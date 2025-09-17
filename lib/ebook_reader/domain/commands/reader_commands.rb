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
            select_chapter(state_store, deps)
          else
            raise ExecutionError.new("Unknown reader TOC action: #{@action}", command_name: name)
          end
        end

        private

        def resolve_state_store(deps, context)
          return deps.resolve(:state_store) if deps&.respond_to?(:resolve)

          context.respond_to?(:state) ? context.state : nil
        rescue StandardError
          nil
        end

        def resolve_document(deps, context)
          if deps&.respond_to?(:resolve)
            begin
              return deps.resolve(:document)
            rescue StandardError
              # fallback
            end
          end

          context.respond_to?(:doc) ? context.doc : nil
        end

        def resolve_navigation_service(deps)
          return deps.resolve(:navigation_service) if deps&.respond_to?(:resolve)

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

        def select_chapter(state_store, deps)
          navigation = resolve_navigation_service(deps)
          return :pass unless navigation

          index = state_store.get(%i[reader toc_selected]) || 0
          navigation.jump_to_chapter(index)
        end

        def navigable_indices(doc)
          return @cached_indices if defined?(@cached_indices) && @cached_indices

          entries = if doc&.respond_to?(:toc_entries)
                      Array(doc.toc_entries)
                    else
                      []
                    end

          indices = entries.map(&:chapter_index).compact.uniq.sort
          if indices.empty?
            chapters_count = doc&.chapters&.length.to_i
            @cached_indices = (0...chapters_count).to_a
          else
            @cached_indices = indices
          end
        end
      end
    end
  end
end
