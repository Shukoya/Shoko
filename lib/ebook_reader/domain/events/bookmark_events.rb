# frozen_string_literal: true

require_relative 'base_domain_event'

module EbookReader
  module Domain
    module Events
      # Domain event for bookmark creation
      class BookmarkAdded < BaseDomainEvent
        required_attributes :book_path, :bookmark
        typed_attributes book_path: String

        def initialize(book_path:, bookmark:, **)
          super(
            aggregate_id: book_path,
            book_path: book_path,
            bookmark: bookmark,
            **
          )
        end

        def book_path
          get_attribute(:book_path)
        end

        def bookmark
          get_attribute(:bookmark)
        end
      end

      # Domain event for bookmark removal
      class BookmarkRemoved < BaseDomainEvent
        required_attributes :book_path, :bookmark
        typed_attributes book_path: String

        def initialize(book_path:, bookmark:, **)
          super(
            aggregate_id: book_path,
            book_path: book_path,
            bookmark: bookmark,
            **
          )
        end

        def book_path
          get_attribute(:book_path)
        end

        def bookmark
          get_attribute(:bookmark)
        end
      end

      # Domain event for bookmark navigation
      class BookmarkNavigated < BaseDomainEvent
        required_attributes :book_path, :bookmark
        typed_attributes book_path: String

        def initialize(book_path:, bookmark:, **)
          super(
            aggregate_id: book_path,
            book_path: book_path,
            bookmark: bookmark,
            **
          )
        end

        def book_path
          get_attribute(:book_path)
        end

        def bookmark
          get_attribute(:bookmark)
        end
      end
    end
  end
end
