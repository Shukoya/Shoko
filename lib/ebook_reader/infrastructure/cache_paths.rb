# frozen_string_literal: true

module EbookReader
  module Infrastructure
    module CachePaths
      module_function

      # Root directory for reader cache: ${XDG_CACHE_HOME:-~/.cache}/reader
      def reader_root
        cache_root = if ENV['XDG_CACHE_HOME'] && !ENV['XDG_CACHE_HOME'].empty?
                       ENV['XDG_CACHE_HOME']
                     else
                       File.join(Dir.home, '.cache')
                     end
        File.join(cache_root, 'reader')
      end
    end
  end
end
