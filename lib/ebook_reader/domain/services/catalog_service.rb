# frozen_string_literal: true

require_relative 'base_service'
require_relative '../../helpers/metadata_extractor'

module EbookReader
  module Domain
    module Services
      # Facade providing catalog data (cached books, scan status, metadata) to higher layers.
      # Wraps the infrastructure scanner/metadata helpers so presentation never touches them directly.
      class CatalogService < BaseService
        def initialize(dependencies)
          super
          @scanner = resolve(:library_scanner)
          @library_service = resolve(:library_service) if registered?(:library_service)
          @metadata_cache = {}
        end

        def required_dependencies
          [:library_scanner]
        end

        def load_cached
          @scanner.load_cached
        end

        def cached_library_entries
          return [] unless @library_service

          @library_service.list_cached_books || []
        rescue StandardError
          []
        end

        def start_scan(force: false)
          @scanner.start_scan(force: force)
        end

        def process_results
          @scanner.process_results
        end

        def entries
          @scanner.epubs || []
        end

        def update_entries(entries)
          @scanner.epubs = entries
          clear_metadata_cache
        end

        def scan_status
          @scanner.scan_status
        end

        def scan_status=(value)
          @scanner.scan_status = value
        end

        def scan_message
          @scanner.scan_message
        end

        def scan_message=(value)
          @scanner.scan_message = value
        end

        def cleanup
          @scanner.cleanup if @scanner.respond_to?(:cleanup)
        end

        def metadata_for(path)
          return {} unless path

          @metadata_cache[path] ||= begin
            Helpers::MetadataExtractor.from_epub(path)
          rescue StandardError
            {}
          end
        end

        def size_for(path)
          return 0 unless path

          File.size(path)
        rescue StandardError
          0
        end

        def clear_metadata_cache
          @metadata_cache.clear
        end
      end
    end
  end
end
