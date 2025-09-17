# frozen_string_literal: true

require_relative '../../mouseable_reader'
require_relative '../../main_menu/menu_progress_presenter'

module EbookReader
  module Controllers
    module Menu
      # Handles main-menu side effects such as launching books, refreshing scans,
      # and coordinating annotation mutations.
      class StateController
        def initialize(menu)
          @menu = menu
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

          recent_repository&.add(path)
          state.dispatch(action(:update_reader_meta, book_path: path, running: true))
          state.dispatch(action(:update_reader_mode, :read))

          MouseableReader.new(path, nil, dependencies).run
        ensure
          terminal_service.setup
          menu.switch_to_mode(prior_mode || :browse)
        end

        def load_and_open_with_progress(path)
          return run_reader(path) if defined?(RSpec)

          index = selectors.browse_selected(state) || 0
          mode  = selectors.mode(state)
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

        def file_not_found
          catalog.scan_message = 'File not found'
          catalog.scan_status = :error
        end

        def handle_reader_error(path, error)
          Infrastructure::Logger.error('Failed to open book', error: error.message, path: path)
          catalog.scan_message = "Failed: #{error.class}: #{error.message[0, 60]}"
          catalog.scan_status = :error
          puts error.backtrace.join("\n") if EPUBFinder::DEBUG_MODE
        end

        def valid_cache_directory?(dir)
          return false unless dir && File.directory?(dir)

          manifest_json = File.join(dir, 'manifest.json')
          manifest_msgpack = File.join(dir, 'manifest.msgpack')
          has_manifest = File.exist?(manifest_json) || File.exist?(manifest_msgpack)
          return false unless has_manifest

          File.exist?(File.join(dir, 'META-INF', 'container.xml'))
        rescue StandardError
          false
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
          if File.exist?(path) && path.downcase.end_with?('.epub')
            recent_repository&.add(path)
            run_reader(path)
          else
            catalog.scan_message = 'Invalid file path'
            catalog.scan_status = :error
          end
        end

        def refresh_scan(force: false)
          catalog.start_scan(force: force)
        end

        def open_selected_annotation
          annotation, book_path = selected_annotation_and_path
          return unless annotation && book_path

          state.update({
                         %i[reader book_path] => book_path,
                         %i[reader pending_jump] => {
                           chapter_index: annotation[:chapter_index] || annotation['chapter_index'],
                           selection_range: annotation[:range] || annotation['range'],
                           annotation: annotation,
                         },
                       })

          run_reader(book_path)
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
            dependencies.resolve(:logger).error('Failed to delete annotation', error: e.message,
                                                                               path: book_path)
          end

          menu.annotations_screen.refresh_data
        end

        def save_current_annotation_edit
          ann = state.get(%i[menu selected_annotation]) || {}
          path = state.get(%i[menu selected_annotation_book])
          text = state.get(%i[menu annotation_edit_text]) || ''
          return unless path && ann

          ann_id = ann[:id] || ann['id']
          return unless ann_id

          service = dependencies.resolve(:annotation_service)
          begin
            service.update(path, ann_id, text)
            state.dispatch(action(:update_menu, annotations_all: service.list_all))
          rescue StandardError => e
            dependencies.resolve(:logger).error('Failed to update annotation', error: e.message,
                                                                              path: path)
          end

          menu.switch_to_mode(:annotations)
          menu.annotations_screen.refresh_data
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

        def recent_repository
          @recent_repository ||= begin
            dependencies.resolve(:recent_library_repository)
          rescue StandardError
            nil
          end
        end

        def prepare_reader_launch(path, presenter)
          width, height = terminal_service.size
          warm_launch_dependencies

          document = load_document_for(path)
          return path if document_cached?(document)

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
          dependencies.resolve(:page_calculator)
        end

        def load_document_for(path)
          factory = dependencies.resolve(:document_service_factory)
          factory.call(path).load_document
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

        def build_pagination(document, width, height, presenter)
          page_calc = dependencies.resolve(:page_calculator)
          numbering_mode = state.get(%i[config page_numbering_mode])

          if numbering_mode == :dynamic
            page_calc.build_page_map(width, height, document, state) do |done, total|
              presenter.update(done: done, total: total)
              menu.draw_screen
            end
            presenter.update(done: 1, total: 1)
          else
            page_map = page_calc.build_absolute_page_map(width, height, document, state) do |done, total|
              presenter.update(done: done, total: total)
              menu.draw_screen
            end

            state.dispatch(
              EbookReader::Domain::Actions::UpdatePaginationStateAction.new(
                page_map: page_map,
                total_pages: page_map.sum,
                last_width: width,
                last_height: height
              )
            )
          end
        end

        def selected_annotation_and_path
          screen = menu.annotations_screen
          [screen.current_annotation, screen.current_book_path]
        end
      end
    end
  end
end
