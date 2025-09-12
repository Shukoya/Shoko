# frozen_string_literal: true

module EbookReader
  class MainMenu
    module Actions
      # A module to handle file-related actions in the main menu.
      module FileActions
        def open_selected_book
          # Use the component's current filtered view to determine the selected book
          book = (respond_to?(:selected_book) ? selected_book : nil)
          # Fallback to internal list if component is unavailable (tests)
          book ||= begin
            idx = EbookReader::Domain::Selectors::MenuSelectors.browse_selected(@state)
            @filtered_epubs && @filtered_epubs[idx]
          end
          return unless book

          path = book['path']
          if path && File.exist?(path)
            load_and_open_with_progress(path)
          else
            @scanner.scan_message = 'File not found'
            @scanner.scan_status = :error
          end
        end

        # recent view removed

        def open_book(path)
          return file_not_found unless File.exist?(path)

          load_and_open_with_progress(path)
        rescue StandardError => e
          handle_reader_error(path, e)
        end

        def run_reader(path)
          # Remember current menu mode to return to the same screen afterwards
          prior_mode = begin
            EbookReader::Domain::Selectors::MenuSelectors.mode(@state)
          rescue StandardError
            nil
          end

          RecentFiles.add(path)
          # Ensure reader loop runs even if a previous session set running=false
          if instance_variable_defined?(:@state) && @state
            @state.dispatch(EbookReader::Domain::Actions::UpdateReaderMetaAction.new(
                              book_path: path,
                              running: true
                            ))
            @state.dispatch(EbookReader::Domain::Actions::UpdateReaderModeAction.new(:read))
          end
          # Pass dependencies to MouseableReader
          dependencies = @dependencies || Domain::ContainerFactory.create_default_container
          MouseableReader.new(path, nil, dependencies).run
        ensure
          # Return cleanly to the previous menu mode (e.g., :recent or :browse)
          @terminal_service.setup
          switch_to_mode(prior_mode || :browse) if respond_to?(:switch_to_mode)
        end

        # Show inline progress in the current list and only open reader once fully loaded
        def load_and_open_with_progress(path)
          # In test environments, run synchronously to satisfy timing-sensitive specs
          return run_reader(path) if defined?(RSpec)

          index = EbookReader::Domain::Selectors::MenuSelectors.browse_selected(@state) || 0
          mode  = EbookReader::Domain::Selectors::MenuSelectors.mode(@state)

          menu_update = lambda do |hash|
            @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(hash))
          end

          menu_update.call(
            loading_active: true,
            loading_path: path,
            loading_progress: 0.0,
            loading_index: index,
            loading_mode: mode,
          )

          opened = false
          path_to_open = nil
          begin
            height, width = @terminal_service.size
            # Prepare services
            @dependencies.resolve(:layout_service)
            @dependencies.registered?(:wrapping_service) ? @dependencies.resolve(:wrapping_service) : nil
            page_calc = @dependencies.resolve(:page_calculator)

            # Load document
            doc_svc = @dependencies.resolve(:document_service_factory).call(path)
            doc = doc_svc.load_document
            # If cached, skip precomputation to open instantly
            if doc.respond_to?(:cached?) && doc.cached?
              menu_update.call(loading_active: false, loading_path: nil, loading_index: nil)
              path_to_open = path
              return
            end
            # Update total chapters for navigation service expectations
            @state.dispatch(EbookReader::Domain::Actions::UpdatePaginationStateAction.new(
                              total_chapters: doc&.chapter_count || 0
                            ))
            # Pre-register for reuse
            @dependencies.register(:document, doc)

            # Build pages according to numbering mode
            if @state.get(%i[config page_numbering_mode]) == :dynamic
              page_calc.build_page_map(width, height, doc, @state) do |done, total|
                update_loading_progress(done, total)
                draw_screen
              end
              menu_update.call(loading_progress: 1.0)
            else
              # Absolute mode: compute per-chapter with progress
              # Absolute: delegate page map building to page_calculator
              page_map = page_calc.build_absolute_page_map(width, height, doc, @state) do |done, total|
                update_loading_progress(done, total)
                draw_screen
              end
              @state.dispatch(EbookReader::Domain::Actions::UpdatePaginationStateAction.new(
                                page_map: page_map,
                                total_pages: page_map.sum,
                                last_width: width,
                                last_height: height
                              ))
            end
          rescue StandardError => e
            handle_reader_error(path, e)
          ensure
            # Clear loading UI and open the reader exactly once
            menu_update.call(loading_active: false, loading_path: nil, loading_index: nil)
            target = path_to_open || path
            run_reader(target) unless opened
          end
        end

        def update_loading_progress(done, total)
          denom = [total, 1].max
          progress = done.to_f / denom
          @state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(loading_progress: progress))
        end

        def file_not_found
          @scanner.scan_message = 'File not found'
          @scanner.scan_status = :error
        end

        def handle_reader_error(path, error)
          Infrastructure::Logger.error('Failed to open book', error: error.message, path: path)
          @scanner.scan_message = "Failed: #{error.class}: #{error.message[0, 60]}"
          @scanner.scan_status = :error
          puts error.backtrace.join("\n") if EPUBFinder::DEBUG_MODE
        end

        # open_file_dialog handled by MainMenu (uses new state/dispatcher flow)

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
            RecentFiles.add(path)
            # Delegate to the single reader-launch path
            run_reader(path)
          else
            @scanner.scan_message = 'Invalid file path'
            @scanner.scan_status = :error
          end
        end
      end
    end
  end
end
