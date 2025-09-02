# frozen_string_literal: true

module EbookReader
  module Domain
    module Commands
      # Commands for driving the Annotation Editor screen via a clean, public API.
      class AnnotationEditorCommand < BaseCommand
        def initialize(action, name: nil, description: nil)
          @action = action
          super(
            name: name || "annotation_editor_#{action}",
            description: description || "Annotation editor #{action.to_s.tr('_', ' ')}"
          )
        end

        protected

        def perform(context, params = {})
          ui = context.dependencies.resolve(:ui_controller)
          mode = ui.current_mode

          case @action
          when :save
            mode&.save_annotation
          when :cancel
            ui.cleanup_popup_state
            ui.switch_mode(:read)
          when :backspace
            mode&.handle_backspace
          when :enter
            mode&.handle_enter
          when :insert_char
            ch = (params[:key] || '').to_s
            return :pass if ch.empty?
            mode&.handle_character(ch)
          else
            return :pass
          end

          :handled
        end
      end

      module AnnotationEditorCommandFactory
        def self.save
          AnnotationEditorCommand.new(:save)
        end

        def self.cancel
          AnnotationEditorCommand.new(:cancel)
        end

        def self.backspace
          AnnotationEditorCommand.new(:backspace)
        end

        def self.enter
          AnnotationEditorCommand.new(:enter)
        end

        def self.insert_char
          AnnotationEditorCommand.new(:insert_char)
        end
      end
    end
  end
end

