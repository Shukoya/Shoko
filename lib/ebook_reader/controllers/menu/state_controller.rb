# frozen_string_literal: true

require_relative '../../mouseable_reader'
require_relative '../../application/pagination_orchestrator'
require_relative '../../main_menu/menu_progress_presenter'

module EbookReader
  module Controllers
    module Menu
      # Handles main-menu side effects such as launching books, refreshing scans,
      # and coordinating annotation mutations.
      class StateController
        def initialize(menu)
          @menu = menu
          @pagination_orchestrator = Application::PaginationOrchestrator.new(menu.dependencies)
        end

        def open_selected_book
          book = menu.selected_book
          book ||= begin
            idx = selectors.browse_selected(state)
            menu.filtered_epubs && menu.filtered_epubs[idx]
          end

          return unless book

          path = book['path']
          if path && File.exist?(path)
            load_and_open_with_progress(path)
          else
            catalog.scan_message = 'File not found'
            catalog.scan_status = :error
          end
        end

        def open_book(path)
          return file_not_found unless File.exist?(path)

          load_and_open_with_progress(path)
        rescue StandardError => e
          handle_reader_error(path, e)
        end

        def run_reader(path)
          prior_mode = selectors.mode(state)

          return unless ensure_reader_document_for(path)

          recent_path = canonical_recent_path(path)
          recent_repository&.add(recent_path) if recent_path
          state.dispatch(action(:update_reader_meta, book_path: path, running: true))
          state.dispatch(action(:update_reader_mode, :read))

          MouseableReader.new(path, nil, dependencies).run
        ensure
          menu.switch_to_mode(prior_mode || :browse)
        end

        def load_and_open_with_progress(path)
          return launch_without_overlay(path) if skip_progress_overlay?

          launch_with_overlay(path)
        end

        def file_not_found
          catalog.scan_message = 'File not found'
          catalog.scan_status = :error
        end

        def handle_reader_error(path, error)
          logger&.error('Failed to open book', error: error.message, path: path)
          catalog.scan_message = "Failed: #{error.class}: #{error.message[0, 60]}"
          catalog.scan_status = :error

          return unless EPUBFinder::DEBUG_MODE

          logger&.debug('Reader error backtrace',
                        path: path,
                        backtrace: Array(error.backtrace).join("\n"))
        end

        def valid_cache_path?(path)
          cache_service&.valid_cache?(path) || false
        end

        def sanitize_input_path(input)
          return '' unless input

          path = input.chomp.strip
          if (path.start_with?("'") && path.end_with?("'")) ||
             (path.start_with?('"') && path.end_with?('"'))
            path = path[1..-2]
          end
          path = path.delete('"')
          File.expand_path(path)
        end

        def handle_file_path(path)
          return invalid_file_path unless File.exist?(path)

          if path.downcase.end_with?('.epub') || cache_service&.cache_file?(path)
            recent_path = canonical_recent_path(path)
            recent_repository&.add(recent_path) if recent_path
            run_reader(path)
          else
            invalid_file_path
          end
        end

        def invalid_file_path
          catalog.scan_message = 'Invalid file path'
          catalog.scan_status = :error
        end

        def refresh_scan(force: false)
          catalog.start_scan(force: force)
        end

        def open_selected_annotation
          annotation_actions.open_selected_annotation
        end

        def open_selected_annotation_for_edit
          annotation_actions.open_selected_annotation_for_edit
        end

        def delete_selected_annotation
          annotation_actions.delete_selected_annotation
        end

        def save_current_annotation_edit
          annotation_actions.save_current_annotation_edit
        end

        private

        attr_reader :menu

        def state
          menu.state
        end

        def dependencies
          menu.dependencies
        end

        def catalog
          menu.catalog
        end

        def terminal_service
          menu.terminal_service
        end

        def selectors
          EbookReader::Domain::Selectors::MenuSelectors
        end

        def action(type, payload = nil)
          case type
          when :update_reader_meta
            EbookReader::Domain::Actions::UpdateReaderMetaAction.new(payload)
          when :update_reader_mode
            EbookReader::Domain::Actions::UpdateReaderModeAction.new(payload)
          when :update_menu
            EbookReader::Domain::Actions::UpdateMenuAction.new(payload)
          else
            raise ArgumentError, "Unknown action #{type}"
          end
        end

        def progress_presenter
          @progress_presenter ||= EbookReader::MainMenu::MenuProgressPresenter.new(state)
        end

        def cache_service
          @cache_service ||= resolve_optional(:cache_service)
        end

        def logger
          @logger ||= resolve_optional(:logger)
        end

        def resolve_optional(name)
          dependencies.resolve(name)
        rescue StandardError
          nil
        end

        def build_background_worker(name:)
          factory = resolve_optional(:background_worker_factory)
          return nil unless factory.respond_to?(:call)

          factory.call(name:)
        rescue StandardError
          nil
        end

        def recent_repository
          @recent_repository ||= begin
            dependencies.resolve(:recent_library_repository)
          rescue StandardError
            nil
          end
        end

        def canonical_recent_path(path)
          cache_service&.canonical_source_path(path) || path
        end

        def prepare_reader_launch(path, presenter)
          height, width = terminal_service.size
          warm_launch_dependencies

          document = load_document_for(path)
          if document_cached?(document)
            register_document(document)
            update_total_chapters(document)
            preload_cached_pagination(document, width, height)
            return path
          end

          register_document(document)
          update_total_chapters(document)
          build_pagination(document, width, height, presenter)
          nil
        rescue StandardError => e
          handle_reader_error(path, e)
          nil
        end

        def warm_launch_dependencies
          dependencies.resolve(:layout_service)
          dependencies.resolve(:wrapping_service) if dependencies.registered?(:wrapping_service)
          page_calculator
          ensure_background_worker
        end

        def load_document_for(path)
          factory = dependencies.resolve(:document_service_factory)
          factory.call(path).load_document
        end

        def ensure_reader_document_for(path)
          return true unless valid_cache_path?(path)

          document = load_document_for(path)
          register_document(document)
          update_total_chapters(document)
          true
        rescue StandardError => e
          handle_reader_error(path, e)
          false
        end

        def document_cached?(document)
          document.respond_to?(:cached?) && document.cached?
        end

        def register_document(document)
          dependencies.register(:document, document)
        end

        def update_total_chapters(document)
          total = document&.chapter_count || 0
          state.dispatch(EbookReader::Domain::Actions::UpdatePaginationStateAction.new(total_chapters: total))
        end

        def ensure_background_worker
          return if resolve_optional(:background_worker)

          worker = build_background_worker(name: 'document-preload')
          dependencies.register(:background_worker, worker) if worker
        rescue StandardError
          nil
        end

        def build_pagination(document, width, height, presenter)
          calculator = page_calculator
          return unless calculator
          return unless width && height

          @pagination_orchestrator.build_full_map!(document, state, calculator, [width, height]) do |done, total|
            presenter.update(done: done, total: total)
            menu.draw_screen
          end
          presenter.update(done: 1, total: 1)
        end

        def skip_progress_overlay?
          ENV['READER_SKIP_PROGRESS_OVERLAY'] == '1'
        end

        def annotation_actions
          @annotation_actions ||= AnnotationActions.new(self)
        end

        def page_calculator
          @page_calculator ||= dependencies.resolve(:page_calculator)
        rescue StandardError
          nil
        end

        def preload_cached_pagination(document, width, height)
          preloader = resolve_optional(:pagination_cache_preloader)
          return unless preloader

          preloader.preload(document, width:, height:)
        rescue StandardError => e
          begin
            logger&.debug('StateController: cached pagination preload failed',
                          error: e.message, path: @path)
          rescue StandardError
            nil
          end
          nil
        end

        def launch_without_overlay(path)
          warm_launch_dependencies
          target_path = prepare_reader_launch(path, null_presenter)
          run_reader(target_path || path)
        rescue StandardError => e
          handle_reader_error(path, e)
        end

        def launch_with_overlay(path)
          index = selectors.browse_selected(state) || 0
          mode = selectors.mode(state)
          presenter = progress_presenter
          presenter.show(path: path, index: index, mode: mode)

          target_path = nil
          begin
            target_path = prepare_reader_launch(path, presenter)
          ensure
            presenter.clear
          end

          run_reader(target_path || path)
        end

        def null_presenter
          @null_presenter ||= NullProgressPresenter.new
        end
      end
    end
  end
end

module EbookReader
  module Controllers
    module Menu
      # Collection of annotation-related behaviours factored out of StateController.
      class AnnotationActions
        def initialize(controller)
          @controller = controller
        end

        def open_selected_annotation
          annotation, book_path = selected_annotation_and_path
          return unless annotation && book_path

          normalized = normalize_annotation(annotation)
          state.dispatch(EbookReader::Domain::Actions::UpdateReaderMetaAction.new(book_path: book_path))
          pending_payload = {
            chapter_index: normalized[:chapter_index],
            selection_range: normalized[:range],
            annotation: annotation,
            edit: false,
          }
          state.dispatch(EbookReader::Domain::Actions::UpdateSelectionsAction.new(pending_jump: pending_payload))

          controller.run_reader(book_path)
        end

        def open_selected_annotation_for_edit
          annotation, book_path = selected_annotation_and_path
          return unless annotation && book_path

          note_text = annotation[:note] || annotation['note'] || ''
          state.dispatch(action(:update_menu,
                                selected_annotation: annotation,
                                selected_annotation_book: book_path,
                                annotation_edit_text: note_text,
                                annotation_edit_cursor: note_text.length))
          menu.switch_to_mode(:annotation_editor)
        end

        def delete_selected_annotation
          annotation, book_path = selected_annotation_and_path
          return unless annotation && book_path

          ann_id = annotation[:id] || annotation['id']
          return unless ann_id

          service = dependencies.resolve(:annotation_service)
          begin
            service.delete(book_path, ann_id)
            state.dispatch(action(:update_menu, annotations_all: service.list_all))
          rescue StandardError => e
            logger&.error('Failed to delete annotation', error: e.message, path: book_path)
          end

          menu.annotations_screen.refresh_data
        end

        def save_current_annotation_edit
          context = current_annotation_edit_context
          return unless context

          with_annotation_service do |service|
            service.update(context[:path], context[:id], context[:text])
            state.dispatch(action(:update_menu, annotations_all: service.list_all))
          end

          menu.switch_to_mode(:annotations)
          menu.annotations_screen.refresh_data
        end

        private

        attr_reader :controller

        def menu
          controller.send(:menu)
        end

        def state
          controller.send(:state)
        end

        def dependencies
          controller.send(:dependencies)
        end

        def action(type, payload = nil)
          controller.send(:action, type, payload)
        end

        def logger
          dependencies.resolve(:logger)
        rescue StandardError
          nil
        end

        def selected_annotation_and_path
          screen = menu.annotations_screen
          [screen.current_annotation, screen.current_book_path]
        end

        def normalize_annotation(annotation)
          return {} unless annotation.is_a?(Hash)

          annotation.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }
        end

        def current_annotation_edit_context
          annotation = state.get(%i[menu selected_annotation]) || {}
          path = state.get(%i[menu selected_annotation_book])
          text = state.get(%i[menu annotation_edit_text]) || ''
          return unless path && annotation

          ann_id = annotation[:id] || annotation['id']
          return unless ann_id

          { path: path, id: ann_id, text: text }
        end

        def with_annotation_service
          service = dependencies.resolve(:annotation_service)
          yield(service)
        rescue StandardError => e
          logger&.error('Annotation service failure', error: e.message)
        end
      end

      # No-op progress presenter used when the overlay is skipped.
      class NullProgressPresenter
        def show(*) end

        def update(*) end

        def clear(*) end
      end
    end
  end
end
