# frozen_string_literal: true

module EbookReader
  module Domain
    module Repositories
      # Facade for recent-library persistence to keep presentation layer
      # decoupled from the concrete RecentFiles implementation.
      class RecentLibraryRepository
        def initialize(_dependencies = nil)
          # No injected dependencies yet; hook retained for symmetry with other repositories.
        end

        def add(path)
          EbookReader::RecentFiles.add(path)
        end

        def all
          EbookReader::RecentFiles.load
        end

        def clear
          EbookReader::RecentFiles.clear
        end
      end
    end
  end
end
