# frozen_string_literal: true

require 'fileutils'
require 'json'

module EbookReader
  # Configuration manager
  class Config
    attr_accessor :view_mode, :theme, :show_page_numbers, :line_spacing, :highlight_quotes,
                  :page_numbering_mode

    CONFIG_DIR = File.expand_path('~/.config/reader')
    CONFIG_FILE = File.join(CONFIG_DIR, 'config.json')
    SYMBOL_KEYS = %i[view_mode line_spacing page_numbering_mode theme].freeze

    def initialize
      set_defaults
      load_config
    end

    # Save current configuration to disk.
    #
    # Creates the configuration directory if it doesn't exist and writes
    # the current settings to config.json. Fails silently if the file system
    # is read-only or other IO errors occur.
    #
    # @return [void]
    # @example
    #   config.view_mode = :single
    #   config.save  # Persists the change
    def save
      ensure_config_dir
      write_config_file
    end

    def to_h
      {
        view_mode: @view_mode,
        theme: @theme,
        show_page_numbers: @show_page_numbers,
        line_spacing: @line_spacing,
        highlight_quotes: @highlight_quotes,
        page_numbering_mode: @page_numbering_mode,
      }
    end

    private

    def set_defaults
      @view_mode = :split
      @theme = :dark
      @show_page_numbers = true
      @line_spacing = :normal
      @highlight_quotes = true
      @page_numbering_mode = :absolute
    end

    def ensure_config_dir
      FileUtils.mkdir_p(CONFIG_DIR)
    rescue StandardError
      nil
    end

    def write_config_file
      File.write(CONFIG_FILE, JSON.pretty_generate(to_h))
    rescue StandardError
      nil
    end

    def load_config
      return unless File.exist?(CONFIG_FILE)

      data = parse_config_file
      apply_config_data(data) if data
    rescue StandardError
      # Use defaults on error
    end

    def parse_config_file
      JSON.parse(File.read(CONFIG_FILE), symbolize_names: true)
    rescue StandardError
      nil
    end

    def apply_config_data(data)
      data.each do |key, value|
        setter = "#{key}="
        next unless respond_to?(setter)

        value = value.to_sym if SYMBOL_KEYS.include?(key)
        send(setter, value)
      end
    end
  end
end
