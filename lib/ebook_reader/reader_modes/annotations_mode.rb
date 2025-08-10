# frozen_string_literal: true

require_relative 'base_mode'
require_relative '../annotations/annotation_store'

module EbookReader
  module ReaderModes
    # Mode for displaying annotations for the current book
    class AnnotationsMode < BaseMode
      def initialize(reader)
        super
        @annotations = Annotations::AnnotationStore.get(reader.path)
        @selected_annotation = 0
      end

      def draw(height, width)
        surface = Components::Surface.new(Terminal)
        bounds = Components::Rect.new(x: 1, y: 1, width: width, height: height)
        surface.write(bounds, 1, 2, "Annotations for #{File.basename(reader.path)}")

        return if @annotations.empty?

        @annotations.each_with_index do |annotation, i|
          text = annotation['text'].tr("\n", ' ').strip
          note = annotation['note'].tr("\n", ' ').strip

          display_text = "#{i == @selected_annotation ? '> ' : '  '} \"#{text[0, 30]}...\""
          display_note = "    Note: #{note[0, 40]}..."

          surface.write(bounds, (i * 2) + 3, 4, display_text)
          surface.write(bounds, (i * 2) + 4, 4, display_note)
        end
      end

      def handle_input(key)
        return unless key

        handlers = input_handlers
        (handlers[key] || handlers[:__default__])&.call(key)
      end

      def input_handlers
        @input_handlers ||= begin
          h = {}
          # Exit keys
          ['q', "\e", "\u0001"].each { |k| h[k] = ->(_) { reader.switch_mode(:read) } }

          # Navigation
          if @annotations.any?
            # Support vim-style j/k and arrow keys
            down = ['j', "\e[B", "\eOB"]
            up = ['k', "\e[A", "\eOA"]
            down.each do |k|
              h[k] = lambda { |_|
                @selected_annotation = [@selected_annotation + 1, @annotations.length - 1].min
              }
            end
            up.each do |k|
              h[k] = ->(_) { @selected_annotation = [@selected_annotation - 1, 0].max }
            end
            ["\r", "\n"].each { |k| h[k] = ->(_) { jump_to_annotation } }
          end

          h[:__default__] = ->(_) {}
          h
        end
      end

      private

      def jump_to_annotation
        annotation = @annotations[@selected_annotation]
        return unless annotation

        reader.current_chapter = annotation['chapter_index']
        # For now, we just go to the chapter. Line-specific jumping is more complex.
        reader.send(:reset_pages)
        reader.switch_mode(:read)
      end
    end
  end
end
