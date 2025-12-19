# frozen_string_literal: true

require 'fileutils'
require_relative 'base_service'

module EbookReader
  module Domain
    module Services
      # Centralises filesystem path lookups for configuration and cache roots
      # so domain repositories do not reach into infrastructure helpers.
      class PathService < BaseService
        def initialize(dependencies)
          super
          @cache_paths = resolve_optional(:cache_paths)
        end

        def reader_config_root
          xdg = ENV.fetch('XDG_CONFIG_HOME', nil)
          base = if xdg && !xdg.empty?
                   xdg
                 else
                   File.join(Dir.home, '.config')
                 end
          File.join(base, 'reader')
        end

        def reader_config_path(*segments)
          File.join(reader_config_root, *segments)
        end

        def cache_root
          if @cache_paths.respond_to?(:reader_root)
            @cache_paths.reader_root
          else
            xdg = ENV.fetch('XDG_CACHE_HOME', nil)
            base = if xdg && !xdg.empty?
                     xdg
                   else
                     File.join(Dir.home, '.cache')
                   end
            File.join(base, 'reader')
          end
        end

        private

        def resolve_optional(name)
          resolve(name)
        rescue StandardError
          nil
        end
      end
    end
  end
end
