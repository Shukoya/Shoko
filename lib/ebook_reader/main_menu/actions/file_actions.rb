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
            (@filtered_epubs && @filtered_epubs[idx])
          end
          return unless book

          path = book['path']
          if path && File.exist?(path)
            open_book(path)
          else
            @scanner.scan_message = 'File not found'
            @scanner.scan_status = :error
          end
        end

        # Open the currently selected recent book (uses RecentFiles list)
        def open_selected_recent_book
          items = RecentFiles.load.select { |r| r && r['path'] && File.exist?(r['path']) }
          return unless items && !items.empty?

          index = EbookReader::Domain::Selectors::MenuSelectors.browse_selected(@state) || 0
          index = [[index, 0].max, items.length - 1].min
          path = items[index]['path']
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
          @terminal_service.setup
          # Return cleanly to the browse screen with active bindings
          switch_to_mode(:browse) if respond_to?(:switch_to_mode)
        end

        def run_reader(path)
          # Keep the app in the alternate screen; show an in-app loading overlay
          begin
            height, width = @terminal_service.size
            @terminal_service.start_frame
            surface = @terminal_service.create_surface
            bounds = Components::Rect.new(x: 1, y: 1, width: width, height: height)
            surface.fill(bounds, ' ')
            msg = 'Opening book… Please wait'
            row = [height / 2, 1].max
            col = [[(width - msg.length) / 2, 1].max, width - msg.length + 1].min
            surface.write(bounds, row, col, msg)
            @terminal_service.end_frame
          rescue StandardError
            # Best-effort: if we cannot paint, continue silently
          end

          RecentFiles.add(path)
          # Ensure reader loop runs even if a previous session set running=false
          if instance_variable_defined?(:@state) && @state
            @state.update({ %i[reader book_path] => path, %i[reader running] => true,
                            %i[reader mode] => :read })
          end
          # Pass dependencies to MouseableReader
          dependencies = @dependencies || Domain::ContainerFactory.create_default_container
          MouseableReader.new(path, nil, dependencies).run
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
            # Pass dependencies to MouseableReader
            dependencies = @dependencies || Domain::ContainerFactory.create_default_container
            MouseableReader.new(path, nil, dependencies).run
          else
            @scanner.scan_message = 'Invalid file path'
            @scanner.scan_status = :error
          end
        end
      end
    end
  end
end
