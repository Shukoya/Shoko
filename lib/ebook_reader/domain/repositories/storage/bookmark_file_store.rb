# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative '../../../constants'
require_relative '../../models/bookmark'
require_relative '../../models/bookmark_data'
require_relative 'file_store_utils'
# Domain storage helpers should operate via injected services to avoid reaching into infrastructure.

module EbookReader
  module Domain
    module Repositories
      module Storage
        # File-backed bookmark storage isolated under Domain.
        # Persists bookmarks to ${XDG_CONFIG_HOME:-~/.config}/reader/bookmarks.json
        class BookmarkFileStore
          def initialize(file_writer:, path_service:)
            @file_writer = file_writer
            @path_service = path_service
          end

          def add(bookmark_data)
            unless bookmark_data.is_a?(EbookReader::Domain::Models::BookmarkData)
              raise ArgumentError, 'bookmark_data must be BookmarkData'
            end

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
            predicate = if bookmark.respond_to?(:to_h)
                          target = bookmark.to_h
                          ->(h) { equivalent?(h, target) }
                        else
                          # Best-effort: match by position
                          chapter = bookmark.respond_to?(:chapter_index) ? bookmark.chapter_index : bookmark[:chapter_index]
                          offset = bookmark.respond_to?(:line_offset) ? bookmark.line_offset : bookmark[:line_offset]
                          ->(h) { h['chapter'] == chapter && h['line_offset'] == offset }
                        end
            list.reject!(&predicate)
            list.empty? ? all.delete(key) : all[key] = list
            save_all(all)
            true
          rescue StandardError
            false
          end

          private

          attr_reader :file_writer, :path_service

          def equivalent?(h, target)
            h['chapter'] == target['chapter'] &&
              h['line_offset'] == target['line_offset'] &&
              (h['text'].to_s == target['text'].to_s)
          end

          def load_all
            FileStoreUtils.load_json_or_empty(file_path)
          end

          def save_all(data)
            payload = JSON.pretty_generate(data)
            file_writer.write(file_path, payload)
          end

          def file_path
            path_service.reader_config_path(EbookReader::Constants::BOOKMARKS_FILE)
          end
        end
      end
    end
  end
end
