# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative '../constants'

module EbookReader
  module State
    class ConfigState
      CONFIG_FILE = File.join(Constants::CONFIG_DIR, 'config.json')

      DEFAULTS = {
        view_mode: :split,
        theme: :dark,
        show_page_numbers: true,
        line_spacing: :normal,
        page_numbering_mode: :absolute,
        highlight_quotes: true,
      }.freeze

      def initialize
        @observers_by_field = Hash.new { |h, k| h[k] = [] }
        @observers_all = []
        load_config
      end

      def add_observer(observer, *fields)
        if fields.nil? || fields.empty?
          @observers_all << observer unless @observers_all.include?(observer)
        else
          fields.each do |f|
            list = @observers_by_field[f]
            list << observer unless list.include?(observer)
          end
        end
      end

      def remove_observer(observer)
        @observers_all.delete(observer)
        @observers_by_field.each_value { |list| list.delete(observer) }
      end

      def update(field, value)
        iv = :"@#{field}"
        old_value = instance_variable_get(iv)
        return value if old_value == value

        instance_variable_set(iv, value)
        persist_config
        notify_observers(field, old_value, value)
        value
      end

      def notify_observers(field, old_value, new_value)
        @observers_by_field[field].each do |obs|
          safe_notify(obs, field, old_value, new_value)
        end
        @observers_all.each do |obs|
          safe_notify(obs, field, old_value, new_value)
        end
      end

      def safe_notify(observer, field, old_value, new_value)
        return unless observer.respond_to?(:config_changed)

        observer.config_changed(field, old_value, new_value)
      rescue StandardError
        nil
      end

      # Dynamic accessors for all config fields
      DEFAULTS.each_key do |field|
        define_method(field) do
          instance_variable_get(:"@#{field}")
        end

        define_method(:"#{field}=") do |value|
          update(field, value)
        end
      end

      def to_hash
        DEFAULTS.keys.each_with_object({}) do |key, hash|
          hash[key] = instance_variable_get(:"@#{key}")
        end
      end

      private

      def load_config
        config_data = load_from_file
        DEFAULTS.each do |key, default_value|
          instance_variable_set(:"@#{key}", config_data.fetch(key, default_value))
        end
      end

      def load_from_file
        return {} unless File.exist?(CONFIG_FILE)

        JSON.parse(File.read(CONFIG_FILE), symbolize_names: true)
      rescue StandardError
        {}
      end

      def persist_config
        FileUtils.mkdir_p(Constants::CONFIG_DIR)
        File.write(CONFIG_FILE, JSON.pretty_generate(to_hash))
      rescue StandardError
        nil
      end
    end
  end
end
