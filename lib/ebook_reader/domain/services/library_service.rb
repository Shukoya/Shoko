# frozen_string_literal: true

require_relative 'base_service'
require_relative '../../infrastructure/cache_paths'
require_relative '../../infrastructure/epub_cache'
require_relative '../../serializers'
require_relative '../../helpers/opf_processor'
require_relative '../../recent_files'

module EbookReader
  module Domain
    module Services
      # Provides cached library listing, abstracting infrastructure details away from components.
      class LibraryService < BaseService
        def list_cached_books
          dir = EbookReader::Infrastructure::CachePaths.reader_root
          return [] unless File.directory?(dir)

          recent_index = index_recent_by_path

          items = []
          Dir.children(dir).sort.each do |sha|
            entry = File.join(dir, sha)
            next unless File.directory?(entry)

            data = load_manifest_data(entry)
            next unless data && Array(data['spine']).any?

            title = (data['title'] || 'Unknown').to_s
            authors = (data['author'] || '').to_s
            epub_path = (data['epub_path'] || '').to_s
            year = extract_year_from_opf(entry, data['opf_path'])
            last_accessed = recent_index[epub_path]
            size_bytes = calculate_size_bytes(epub_path, entry)

            items << {
              title: title,
              authors: authors,
              year: year,
              last_accessed: last_accessed,
              size_bytes: size_bytes,
              open_path: entry,
              epub_path: epub_path,
            }
          end
          items
        end

        protected

        def required_dependencies
          []
        end

        private

        def load_manifest_data(entry)
          mp = File.join(entry, 'manifest.msgpack')
          js = File.join(entry, 'manifest.json')
          if File.exist?(mp)
            begin
              return EbookReader::Infrastructure::MessagePackSerializer.new.load_file(mp)
            rescue StandardError
              # fall through to JSON
            end
          end
          return EbookReader::Infrastructure::JSONSerializer.new.load_file(js) if File.exist?(js)
          nil
        rescue StandardError
          nil
        end

        def extract_year_from_opf(cache_dir, opf_rel)
          return '' unless opf_rel
          opf = File.join(cache_dir, opf_rel.to_s)
          return '' unless File.exist?(opf)
          meta = EbookReader::Helpers::OPFProcessor.new(opf).extract_metadata
          (meta[:year] || '').to_s
        rescue StandardError
          ''
        end

        def calculate_size_bytes(epub_path, cache_dir)
          return File.size(epub_path) if epub_path && !epub_path.empty? && File.exist?(epub_path)
          sum = 0
          Dir.glob(File.join(cache_dir, '**', '*')).each do |p|
            sum += File.size(p) if File.file?(p)
          end
          sum
        rescue StandardError
          0
        end

        def index_recent_by_path
          items = begin
            EbookReader::RecentFiles.load
          rescue StandardError
            []
          end
          (items || []).each_with_object({}) do |it, h|
            path = it['path']
            acc = it['accessed']
            h[path] = acc if path && acc
          end
        end
      end
    end
  end
end
