# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative '../../../constants'
require_relative '../../models/bookmark'
require_relative '../../models/bookmark_data'

module EbookReader
  module Domain
    module Repositories
      module Storage
        # File-backed bookmark storage isolated under Domain.
        # Persists bookmarks to ~/.config/reader/bookmarks.json
        class BookmarkFileStore

          def add(bookmark_data)
            raise ArgumentError, 'bookmark_data must be BookmarkData' unless bookmark_data.is_a?(EbookReader::Domain::Models::BookmarkData)

            all = load_all
            path = bookmark_data.path.to_s
            list = all[path] || []
            entry = {
              'chapter' => bookmark_data.chapter,
              'line_offset' => bookmark_data.line_offset,
              'text' => bookmark_data.text.to_s,
              'timestamp' => Time.now.iso8601,
            }
            list << entry
            all[path] = list
            save_all(all)
            true
          end

          def get(path)
            all = load_all
            list = all[path.to_s] || []
            list.map { |h| EbookReader::Domain::Models::Bookmark.from_h(h) }
          rescue StandardError
            []
          end

          def delete(path, bookmark)
            all = load_all
            key = path.to_s
            list = all[key] || []
            # Delete by matching serialized representation
            if bookmark.respond_to?(:to_h)
              target = bookmark.to_h
              list.reject! { |h| equivalent?(h, target) }
            else
              # Best-effort: match by position
              chapter = bookmark.respond_to?(:chapter_index) ? bookmark.chapter_index : bookmark[:chapter_index]
              offset = bookmark.respond_to?(:line_offset) ? bookmark.line_offset : bookmark[:line_offset]
              list.reject! { |h| h['chapter'] == chapter && h['line_offset'] == offset }
            end
            list.empty? ? all.delete(key) : all[key] = list
            save_all(all)
            true
          rescue StandardError
            false
          end

          private

          def equivalent?(h, target)
            h['chapter'] == target['chapter'] &&
              h['line_offset'] == target['line_offset'] &&
              (h['text'].to_s == target['text'].to_s)
          end

          def load_all
            return {} unless File.exist?(file_path)
            JSON.parse(File.read(file_path))
          rescue StandardError
            {}
          end

          def save_all(data)
            FileUtils.mkdir_p(File.dirname(file_path))
            File.write(file_path, JSON.pretty_generate(data))
          end

          def file_path
            File.join(File.expand_path('~/.config/reader'), EbookReader::Constants::BOOKMARKS_FILE)
          end
        end
      end
    end
  end
end
