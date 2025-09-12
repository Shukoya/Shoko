# frozen_string_literal: true

module EbookReader
  module Components
    module UI
      module TextUtils
        module_function

        def wrap_text(text, width)
          t = (text || '').to_s
          return [''] if t.empty?

          t.split("\n", -1).flat_map { |line| line.empty? ? [''] : line.scan(/.{1,#{width}}/) }
        end

        def truncate_text(text, max_length)
          str = (text || '').to_s
          return str if str.length <= max_length

          "#{str[0...(max_length - 3)]}..."
        end
      end
    end
  end
end

