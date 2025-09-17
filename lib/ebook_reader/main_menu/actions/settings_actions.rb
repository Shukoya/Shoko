# frozen_string_literal: true

require_relative '../../infrastructure/cache_paths'

module EbookReader
  class MainMenu
    module Actions
      # A module to handle settings-related actions in the main menu.
      module SettingsActions
        def toggle_view_mode(_key = nil)
          current_mode = @state.get(%i[config view_mode]) || :split
          new_mode = current_mode == :split ? :single : :split
          @state.dispatch(EbookReader::Domain::Actions::UpdateConfigAction.new(view_mode: new_mode))
          @state.save_config
        end

        def toggle_page_numbers(_key = nil)
          current = @state.get(%i[config show_page_numbers])
          @state.dispatch(EbookReader::Domain::Actions::UpdateConfigAction.new(show_page_numbers: !current))
          @state.save_config
        end

        def cycle_line_spacing(_key = nil)
          modes = %i[compact normal relaxed]
          current = modes.index(@state.get(%i[config line_spacing])) || 1
          @state.dispatch(EbookReader::Domain::Actions::UpdateConfigAction.new(line_spacing: modes[(current + 1) % 3]))
          @state.save_config
        end

        def toggle_highlight_quotes(_key = nil)
          current = @state.get(%i[config highlight_quotes])
          @state.dispatch(EbookReader::Domain::Actions::UpdateConfigAction.new(highlight_quotes: !current))
          @state.save_config
        end

        def toggle_page_numbering_mode(_key = nil)
          current = @state.get(%i[config page_numbering_mode])
          @state.dispatch(EbookReader::Domain::Actions::UpdateConfigAction.new(page_numbering_mode: (current == :absolute ? :dynamic : :absolute)))
          @state.save_config
        end

        def wipe_cache(_key = nil)
          # 1) Clear EPUBFinder scan cache (config cache file)
          EPUBFinder.clear_cache

          # 2) Remove EPUB content cache under XDG or ~/.cache/reader
          remove_epub_cache_on_disk

          # 3) Clear recent files list
          begin
            recent_repository = resolve_recent_repository
            recent_repository&.clear
          rescue StandardError
            # best effort
          end

          # 4) Reset in-memory wrapping cache via WrappingService
          begin
            @dependencies&.resolve(:wrapping_service)&.clear_cache
          rescue StandardError
            # best effort
          end

          # 5) Reset scanner state and notify user
          @catalog.update_entries([])
          @filtered_epubs = []
          @catalog.scan_status = :idle
          @catalog.scan_message = "All caches wiped. Use 'Find Book' to rescan"
        end

      private

        def resolve_recent_repository
          return unless defined?(@dependencies) && @dependencies

          @dependencies.resolve(:recent_library_repository)
        rescue StandardError
          nil
        end

        def remove_epub_cache_on_disk
          reader_cache = EbookReader::Infrastructure::CachePaths.reader_root
          return unless File.directory?(reader_cache)

          # Resolve real paths to avoid symlink shenanigans and ensure we only delete our own cache dir
          reader_real = nil
          begin
            root_real = File.realpath(File.dirname(reader_cache))
            reader_real = File.realpath(reader_cache)
            allowed = reader_real.start_with?(root_real) && File.basename(reader_real) == 'reader'
          rescue StandardError
            # Fallback when realpath is unavailable (e.g., FakeFS): ensure basename is 'reader'
            allowed = (File.basename(reader_cache) == 'reader')
            reader_real = reader_cache
          end

          return unless allowed

          FileUtils.rm_rf(reader_real)
        rescue StandardError
          # ignore failures; the cache wipe is best-effort
        end
      end
    end
  end
end
