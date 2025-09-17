# frozen_string_literal: true

require_relative 'base_service'

module EbookReader
  module Domain
    module Services
      # Provides cached library listing, abstracting infrastructure details away from components.
      class LibraryService < BaseService
        def initialize(dependencies)
          super
          @recent_repository = resolve(:recent_library_repository) if registered?(:recent_library_repository)
          @library_repository = resolve(:cached_library_repository) if registered?(:cached_library_repository)
        end

        def list_cached_books
          return [] unless @library_repository

          entries = @library_repository.list_entries
          return [] if entries.empty?

          recent_index = index_recent_by_path
          entries.each do |entry|
            entry[:last_accessed] = recent_index[entry[:epub_path]]
          end
          entries
        end

        protected

        def required_dependencies
          []
        end

        private

        def index_recent_by_path
          return {} unless @recent_repository

          items = @recent_repository.all
          Array(items).each_with_object({}) do |it, acc|
            path = it['path']
            accessed = it['accessed']
            acc[path] = accessed if path && accessed
          end
        end
      end
    end
  end
end
