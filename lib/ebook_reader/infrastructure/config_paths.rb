# frozen_string_literal: true

module EbookReader
  module Infrastructure
    # Resolves XDG-aware configuration paths for Reader.
    module ConfigPaths
      module_function

      # Root directory for reader config: ${XDG_CONFIG_HOME:-~/.config}/reader
      def reader_root
        env_home = ENV.fetch('XDG_CONFIG_HOME', nil)
        config_root = if env_home && !env_home.empty?
                        env_home
                      else
                        File.join(Dir.home, '.config')
                      end
        File.join(config_root, 'reader')
      end

      # Legacy root kept for migration/backwards compatibility.
      # Historically some parts of the code hardcoded `~/.config/reader`.
      def legacy_reader_root
        File.join(Dir.home, '.config', 'reader')
      end
    end
  end
end
