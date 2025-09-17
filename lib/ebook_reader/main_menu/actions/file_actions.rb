# frozen_string_literal: true

module EbookReader
  class MainMenu
    module Actions
      # A module to handle file-related actions in the main menu.
      module FileActions
        def open_selected_book
          state_controller.open_selected_book
        end

        def open_book(path)
          state_controller.open_book(path)
        end

        def run_reader(path)
          state_controller.run_reader(path)
        end

        def load_and_open_with_progress(path)
          state_controller.load_and_open_with_progress(path)
        end

        def file_not_found
          state_controller.file_not_found
        end

        def handle_reader_error(path, error)
          state_controller.handle_reader_error(path, error)
        end

        def valid_cache_directory?(dir)
          state_controller.valid_cache_directory?(dir)
        end

        def sanitize_input_path(input)
          state_controller.sanitize_input_path(input)
        end

        def handle_file_path(path)
          state_controller.handle_file_path(path)
        end

        private

        def state_controller
          @state_controller
        end
      end
    end
  end
end
