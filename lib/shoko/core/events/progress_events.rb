# frozen_string_literal: true

require_relative 'base_domain_event'

module Shoko
  module Core
    module Events
      # Domain event for reading progress updates
      class ProgressUpdated < BaseDomainEvent
        required_attributes :book_path, :chapter_index, :line_offset
        typed_attributes book_path: String, chapter_index: Integer, line_offset: Integer

        def initialize(book_path:, chapter_index:, line_offset:, previous_chapter: nil,
                       previous_line: nil, **)
          super(
            aggregate_id: book_path,
            book_path: book_path,
            chapter_index: chapter_index,
            line_offset: line_offset,
            previous_chapter: previous_chapter,
            previous_line: previous_line,
            **
          )
        end

        def book_path
          get_attribute(:book_path)
        end

        def chapter_index
          get_attribute(:chapter_index)
        end

        def line_offset
          get_attribute(:line_offset)
        end

        def previous_chapter
          get_attribute(:previous_chapter)
        end

        def previous_line
          get_attribute(:previous_line)
        end

        # Check if this represents forward progress
        def forward_progress?
          return true if previous_chapter.nil? || previous_line.nil?

          chapter_index > previous_chapter ||
            (chapter_index == previous_chapter && line_offset > previous_line)
        end
      end

      # Domain event for reading session start
      class ReadingSessionStarted < BaseDomainEvent
        required_attributes :book_path
        typed_attributes book_path: String

        def initialize(book_path:, **)
          super(
            aggregate_id: book_path,
            book_path: book_path,
            **
          )
        end

        def book_path
          get_attribute(:book_path)
        end
      end

      # Domain event for reading session end
      class ReadingSessionEnded < BaseDomainEvent
        required_attributes :book_path, :duration_seconds
        typed_attributes book_path: String, duration_seconds: Integer

        def initialize(book_path:, duration_seconds:, final_chapter: nil, final_line: nil,
                       **)
          super(
            aggregate_id: book_path,
            book_path: book_path,
            duration_seconds: duration_seconds,
            final_chapter: final_chapter,
            final_line: final_line,
            **
          )
        end

        def book_path
          get_attribute(:book_path)
        end

        def duration_seconds
          get_attribute(:duration_seconds)
        end

        def final_chapter
          get_attribute(:final_chapter)
        end

        def final_line
          get_attribute(:final_line)
        end
      end
    end
  end
end
