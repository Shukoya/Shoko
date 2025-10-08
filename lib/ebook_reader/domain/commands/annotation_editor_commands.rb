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
          ui = context.dependencies.resolve(:ui_controller) if context.respond_to?(:dependencies)
          # Prefer a context-provided editor component (menu or reader), else fall back to UI current_mode
          mode = if context.respond_to?(:current_editor_component)
                   context.current_editor_component
                 else
                   ui&.current_mode
                 end

          case @action
          when :save
            return :handled if dispatch_to_mode(mode, :save_annotation)
          when :cancel
            # Reader: cleanup + back to read; Menu: back to annotations
            if dispatch_to_mode(mode, :cancel_annotation)
              # Mode handled the cancel path completely
            elsif ui
              begin
                ui.cleanup_popup_state
              rescue StandardError
                # no-op (menu has no popup state)
              end
              begin
                ui.switch_mode(:read)
              rescue StandardError
                # fall through to menu path
              end
            else
              # Menu context: switch to annotations screen
              begin
                context.state.dispatch(EbookReader::Domain::Actions::UpdateMenuAction.new(mode: :annotations))
              rescue StandardError
                # best-effort
              end
            end
          when :backspace
            return :handled if dispatch_to_mode(mode, :handle_backspace)
          when :enter
            return :handled if dispatch_to_mode(mode, :handle_enter)
          when :insert_char
            ch = (params[:key] || '').to_s
            return :pass if ch.empty?

            return :handled if dispatch_to_mode(mode, :handle_character, ch)
          else
            return :pass
          end

          :handled
        end

        private

        def dispatch_to_mode(mode, method, *)
          return false unless mode.respond_to?(method)

          mode.public_send(method, *)
          true
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
