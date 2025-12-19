# frozen_string_literal: true

require_relative '../../helpers/text_metrics'

module EbookReader
  module Components
    module UI
      # Shared text layout utilities for terminal UI rendering.
      module TextUtils
        module_function

        def wrap_text(text, width)
          t = (text || '').to_s
          w = width.to_i
          return [''] if t.empty?
          return [''] if w <= 0

          EbookReader::Helpers::TextMetrics.wrap_cells(t, w)
        end

        def truncate_text(text, max_length)
          str = (text || '').to_s
          w = max_length.to_i
          return '' if w <= 0

          return str if EbookReader::Helpers::TextMetrics.visible_length(str) <= w

          ellipsis = '...'
          ellipsis_w = EbookReader::Helpers::TextMetrics.visible_length(ellipsis)
          return EbookReader::Helpers::TextMetrics.truncate_to(str, w) if ellipsis_w >= w

          base = EbookReader::Helpers::TextMetrics.truncate_to(str, w - ellipsis_w)
          base + ellipsis
        end

        def pad_right(text, width, pad: ' ')
          EbookReader::Helpers::TextMetrics.pad_right(text.to_s, width.to_i, pad: pad)
        end

        def pad_left(text, width, pad: ' ')
          EbookReader::Helpers::TextMetrics.pad_left(text.to_s, width.to_i, pad: pad)
        end
      end
    end
  end
end
