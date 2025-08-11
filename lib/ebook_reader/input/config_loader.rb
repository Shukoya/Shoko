# frozen_string_literal: true

require 'yaml'
require_relative 'key_definitions'

module EbookReader
  module Input
    # Loads and parses declarative input configuration from YAML files
    class ConfigLoader
      class << self
        def load_bindings(config_path = default_config_path)
          return @cached_bindings if @cached_bindings

          config = YAML.load_file(config_path)
          @cached_bindings = parse_config(config)
        rescue StandardError => e
          Infrastructure::Logger.error('Failed to load input configuration', error: e.message)
          @cached_bindings = fallback_bindings
        end

        def clear_cache
          @cached_bindings = nil
        end

        private

        def default_config_path
          File.join(File.dirname(__FILE__), '../../..', 'config', 'input_bindings.yml')
        end

        def parse_config(config)
          parsed = {}

          config.each do |mode, categories|
            parsed[mode.to_sym] = {}

            categories.each_value do |bindings|
              bindings.each do |action, keys|
                action_sym = action.to_sym
                parsed[mode.to_sym][action_sym] = normalize_keys(keys)
              end
            end
          end

          parsed
        end

        def normalize_keys(keys)
          return [keys] if keys.is_a?(String)
          return keys if keys.is_a?(Array)

          [keys.to_s]
        end

        def fallback_bindings
          {
            reader: {
              next_page: KeyDefinitions::READER[:next_page],
              prev_page: KeyDefinitions::READER[:prev_page],
              scroll_down: KeyDefinitions::READER[:scroll_down],
              scroll_up: KeyDefinitions::READER[:scroll_up],
              next_chapter: KeyDefinitions::READER[:next_chapter],
              prev_chapter: KeyDefinitions::READER[:prev_chapter],
              go_to_start: KeyDefinitions::READER[:go_to_start],
              go_to_end: KeyDefinitions::READER[:go_to_end],
              toggle_view: KeyDefinitions::READER[:toggle_view],
              toggle_page_mode: KeyDefinitions::READER[:toggle_page_mode],
              increase_spacing: KeyDefinitions::READER[:increase_spacing],
              decrease_spacing: KeyDefinitions::READER[:decrease_spacing],
              show_toc: KeyDefinitions::READER[:show_toc],
              add_bookmark: KeyDefinitions::READER[:add_bookmark],
              show_bookmarks: KeyDefinitions::READER[:show_bookmarks],
              show_help: KeyDefinitions::READER[:show_help],
              quit_to_menu: KeyDefinitions::ACTIONS[:quit],
              quit_application: KeyDefinitions::ACTIONS[:force_quit],
            },
            menu: {
              up: KeyDefinitions::NAVIGATION[:up],
              down: KeyDefinitions::NAVIGATION[:down],
              confirm: KeyDefinitions::ACTIONS[:confirm],
              cancel: KeyDefinitions::ACTIONS[:cancel],
              browse: ['f'],
              recent: ['r'],
              open_file: ['o'],
              settings: ['s'],
              quit: ['q'],
            },
          }
        end
      end
    end
  end
end
