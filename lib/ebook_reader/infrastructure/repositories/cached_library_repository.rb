# frozen_string_literal: true

require_relative '../cache_paths'
require_relative '../../serializers'
require_relative '../../helpers/opf_processor'

module EbookReader
  module Infrastructure
    module Repositories
      # Provides read-only access to cached library metadata on disk.
      class CachedLibraryRepository
        def initialize(cache_root: Infrastructure::CachePaths.reader_root)
          @cache_root = cache_root
        end

        def list_entries
          return [] unless File.directory?(@cache_root)

          Dir.children(@cache_root).sort.each_with_object([]) do |sha, acc|
            entry_path = File.join(@cache_root, sha)
            next unless File.directory?(entry_path)

            manifest = load_manifest_data(entry_path)
            next unless manifest && Array(manifest['spine']).any?

            acc << build_entry(entry_path, manifest)
          end
        end

        private

        def build_entry(entry_path, manifest)
          epub_path = (manifest['epub_path'] || '').to_s

          {
            title: (manifest['title'] || 'Unknown').to_s,
            authors: (manifest['author'] || '').to_s,
            year: extract_year_from_opf(entry_path, manifest['opf_path']),
            size_bytes: calculate_size_bytes(epub_path, entry_path),
            open_path: entry_path,
            epub_path: epub_path,
          }
        end

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

          Dir.glob(File.join(cache_dir, '**', '*')).sum do |path|
            File.file?(path) ? File.size(path) : 0
          end
        rescue StandardError
          0
        end
      end
    end
  end
end
