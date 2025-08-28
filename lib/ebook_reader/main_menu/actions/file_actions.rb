# frozen_string_literal: true

module EbookReader
  class MainMenu
    module Actions
      # A module to handle file-related actions in the main menu.
      module FileActions
        def open_selected_book
          return unless @filtered_epubs[@state.browse_selected]

          path = @filtered_epubs[@state.browse_selected]['path']
          if path && File.exist?(path)
            open_book(path)
          else
            @scanner.scan_message = 'File not found'
            @scanner.scan_status = :error
          end
        end

        def open_book(path)
          return file_not_found unless File.exist?(path)

          run_reader(path)
        rescue StandardError => e
          handle_reader_error(path, e)
        ensure
          Terminal.setup
          # Reset menu mode to browse after returning from reader
          @state.menu_mode = :browse if @state
          # Reactivate main menu input dispatcher after returning from reader
          if respond_to?(:setup_input_dispatcher)
            setup_input_dispatcher
          elsif @dispatcher && respond_to?(:setup_consolidated_input_bindings)
            # Alternative: reinitialize dispatcher and bindings manually
            setup_consolidated_input_bindings
            @dispatcher.activate(:browse)
          end
        end

        def run_reader(path)
          Terminal.cleanup
          RecentFiles.add(path)
          MouseableReader.new(path).run
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

        def open_file_dialog
          @file_input = ''
          @open_file_screen.input = ''
          @mode = :open_file
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
            RecentFiles.add(path)
            MouseableReader.new(path).run
          else
            @scanner.scan_message = 'Invalid file path'
            @scanner.scan_status = :error
          end
        end
      end
    end
  end
end
