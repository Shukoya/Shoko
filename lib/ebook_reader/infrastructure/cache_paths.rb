# frozen_string_literal: true

module EbookReader
  module Infrastructure
    module CachePaths
      module_function

      # Root directory for reader cache: ${XDG_CACHE_HOME:-~/.cache}/reader
      def reader_root
        env_home = ENV.fetch('XDG_CACHE_HOME', nil)
        cache_root = if env_home && !env_home.empty?
                       env_home
                     else
                       File.join(Dir.home, '.cache')
                     end
        File.join(cache_root, 'reader')
      end
    end
  end
end
