# frozen_string_literal: true

module Shoko
  module Adapters::Output::Ui::Components
    # Small helper for composing styled strings and common UI elements.
    module RenderStyle
      DEFAULT_PALETTE = Shoko::Adapters::Output::Ui::Constants::Themes::DEFAULT_PALETTE

      @palette = DEFAULT_PALETTE.dup

      class << self
        def configure(palette)
          @palette = DEFAULT_PALETTE.merge(palette || {})
        end

        def palette
          @palette || DEFAULT_PALETTE
        end

        def color(key)
          palette[key] || DEFAULT_PALETTE[key]
        end

        def primary(text)
          color(:primary) + text.to_s + Terminal::ANSI::RESET
        end

        def accent(text)
          color(:accent) + text.to_s + Terminal::ANSI::RESET
        end

        def dim(text)
          color(:dim) + text.to_s + Terminal::ANSI::RESET
        end

        def selection_pointer
          Shoko::Adapters::Output::Ui::Constants::UI::SELECTION_POINTER
        end

        def selection_pointer_colored
          color(:accent) + selection_pointer + Terminal::ANSI::RESET
        end

        def styled_segment(text, styles = {}, metadata: {})
          content = text.to_s
          return content if content.empty?

          codes = []
          block_type = metadata && metadata[:block_type]
          highlight_allowed = metadata.key?(:highlight_enabled) ? metadata[:highlight_enabled] : true

          color_code = color_for(styles, block_type, highlight_allowed)
          codes << color_code if color_code

          codes << Terminal::ANSI::BOLD if styles[:bold] || block_type == :heading
          codes << Terminal::ANSI::ITALIC if styles[:italic] || styles[:quote] || block_type == :quote
          codes << Terminal::ANSI::DIM if styles[:prefix] || styles[:dim]

          codes.join + content + Terminal::ANSI::RESET
        end

        private

        def color_for(styles, block_type, highlight_allowed)
          if styles[:code] || block_type == :code
            color(:code)
          elsif styles[:accent] || styles[:highlight] || styles[:keyword]
            color(:accent)
          elsif block_type == :heading
            highlight_allowed ? color(:heading) : color(:primary)
          elsif block_type == :quote || styles[:quote]
            highlight_allowed ? color(:quote) : color(:primary)
          elsif block_type == :separator
            color(:separator)
          elsif styles[:prefix]
            color(:prefix)
          else
            color(:primary)
          end
        end
      end
    end
  end
end
