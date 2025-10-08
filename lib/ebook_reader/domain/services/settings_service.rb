# frozen_string_literal: true

require 'fileutils'

require_relative 'base_service'
require_relative '../actions/update_config_action'
require_relative '../selectors/config_selectors'
require_relative '../../infrastructure/cache_paths'

module EbookReader
  module Domain
    module Services
      # Centralises configuration toggles and cache maintenance for menu settings flows.
      class SettingsService < BaseService
        WIPE_CACHE_MESSAGE = "All caches wiped. Use 'Find Book' to rescan"

        def initialize(dependencies)
          super
          @state_store = resolve(:state_store)
          @terminal_service = resolve(:terminal_service)
          @wrapping_service = resolve(:wrapping_service) if registered?(:wrapping_service)
          @recent_repository = resolve(:recent_library_repository) if registered?(:recent_library_repository)
        end

        # Toggle split/single view mode and persist the change.
        def toggle_view_mode
          current = ConfigSelectors.view_mode(@state_store) || :split
          new_mode = current == :split ? :single : :split
          dispatch_config(view_mode: new_mode)
          new_mode
        end

        # Toggle whether page numbers are displayed.
        def toggle_page_numbers
          current = ConfigSelectors.show_page_numbers(@state_store)
          dispatch_config(show_page_numbers: !current)
        end

        # Cycle through line spacing options (compact → normal → relaxed → ...).
        def cycle_line_spacing
          modes = %i[compact normal relaxed]
          current = ConfigSelectors.line_spacing(@state_store) || EbookReader::Constants::DEFAULT_LINE_SPACING
          next_mode = modes[(modes.index(current) || 1) + 1] || modes.first
          dispatch_config(line_spacing: next_mode)
          next_mode
        end

        # Toggle quote highlighting preference.
        def toggle_highlight_quotes
          current = ConfigSelectors.highlight_quotes(@state_store)
          dispatch_config(highlight_quotes: !current)
        end

        # Toggle dynamic/absolute page numbering mode.
        def toggle_page_numbering_mode
          current = ConfigSelectors.page_numbering_mode(@state_store) || :absolute
          next_mode = current == :absolute ? :dynamic : :absolute
          dispatch_config(page_numbering_mode: next_mode)
          next_mode
        end

        # Wipe cached EPUB data, recent file history, and wrapping caches.
        # Returns the status message applied to the catalog.
        def wipe_cache(catalog: nil)
          EPUBFinder.clear_cache
          remove_epub_cache_on_disk
          @recent_repository&.clear
          @wrapping_service&.clear_cache

          target_catalog = catalog || resolve(:catalog_service)
          if target_catalog
            target_catalog.update_entries([])
            target_catalog.scan_status = :idle
            target_catalog.scan_message = WIPE_CACHE_MESSAGE
          end

          WIPE_CACHE_MESSAGE
        end

        private

        def required_dependencies
          %i[state_store terminal_service]
        end

        def dispatch_config(payload)
          @state_store.dispatch(EbookReader::Domain::Actions::UpdateConfigAction.new(payload))
          @state_store.save_config if @state_store.respond_to?(:save_config)
        end

        def remove_epub_cache_on_disk
          reader_cache = EbookReader::Infrastructure::CachePaths.reader_root
          return unless File.directory?(reader_cache)

          reader_real = safe_realpath(reader_cache)
          return unless reader_real

          FileUtils.rm_rf(reader_real)
        rescue StandardError
          nil
        end

        def safe_realpath(path)
          root_real = File.realpath(File.dirname(path))
          cache_real = File.realpath(path)
          return cache_real if cache_real.start_with?(root_real) && File.basename(cache_real) == 'reader'

          nil
        rescue StandardError
          File.basename(path) == 'reader' ? path : nil
        end
      end
    end
  end
end
