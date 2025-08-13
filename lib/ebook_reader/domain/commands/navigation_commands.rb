# frozen_string_literal: true

module EbookReader
  module Domain
    module Commands
      # Navigation commands using proper domain services.
      # Eliminates direct controller coupling and state manipulation.
      class NavigationCommand < BaseCommand
        def initialize(action, name: nil, description: nil)
          @action = action
          super(
            name: name || "navigate_#{action}",
            description: description || "Navigate #{humanize_action(action)}"
          )
        end

        def validate_context(context)
          super
          unless context.respond_to?(:dependencies)
            raise ValidationError.new("Context must provide dependencies", command_name: name)
          end
        end

        def can_execute?(context, params = {})
          context.dependencies.registered?(:navigation_service) &&
            context.dependencies.registered?(:state_store)
        end

        protected

        def perform(context, params = {})
          navigation_service = context.dependencies.resolve(:navigation_service)
          
          case @action
          when :next_page
            navigation_service.next_page
          when :prev_page
            navigation_service.prev_page
          when :next_chapter
            current_state = context.dependencies.resolve(:state_store).current_state
            current_chapter = current_state.dig(:reader, :current_chapter) || 0
            navigation_service.jump_to_chapter(current_chapter + 1)
          when :prev_chapter
            current_state = context.dependencies.resolve(:state_store).current_state
            current_chapter = current_state.dig(:reader, :current_chapter) || 0
            navigation_service.jump_to_chapter([current_chapter - 1, 0].max)
          when :go_to_start
            navigation_service.go_to_start
          when :go_to_end
            navigation_service.go_to_end
          else
            raise ExecutionError.new("Unknown navigation action: #{@action}", command_name: name)
          end
          
          @action
        end

        private

        def humanize_action(action)
          action.to_s.gsub('_', ' ')
        end
      end

      class ScrollCommand < BaseCommand
        def initialize(direction, lines: 1, name: nil, description: nil)
          @direction = direction
          @lines = lines
          super(
            name: name || "scroll_#{direction}",
            description: description || "Scroll #{direction} #{lines} line(s)"
          )
        end

        def validate_parameters(params)
          super
          
          valid_directions = [:up, :down]
          unless valid_directions.include?(@direction)
            raise ValidationError.new("Direction must be one of #{valid_directions}", command_name: name)
          end
          
          unless @lines.is_a?(Integer) && @lines > 0
            raise ValidationError.new("Lines must be a positive integer", command_name: name)
          end
        end

        protected

        def perform(context, params = {})
          navigation_service = context.dependencies.resolve(:navigation_service)
          navigation_service.scroll(@direction, @lines)
          
          { direction: @direction, lines: @lines }
        end
      end

      class JumpToChapterCommand < BaseCommand
        def initialize(chapter_index = nil, name: nil, description: nil)
          @chapter_index = chapter_index
          super(
            name: name || 'jump_to_chapter',
            description: description || 'Jump to specific chapter'
          )
        end

        def validate_parameters(params)
          super
          
          # Chapter index can come from params or constructor
          index = params[:chapter_index] || @chapter_index
          
          unless index.is_a?(Integer) && index >= 0
            raise ValidationError.new("Chapter index must be a non-negative integer", command_name: name)
          end
        end

        protected

        def perform(context, params = {})
          navigation_service = context.dependencies.resolve(:navigation_service)
          index = params[:chapter_index] || @chapter_index
          
          navigation_service.jump_to_chapter(index)
          
          { chapter_index: index }
        end
      end

      # Factory methods for common navigation commands
      module NavigationCommandFactory
        def self.next_page
          NavigationCommand.new(:next_page)
        end

        def self.prev_page
          NavigationCommand.new(:prev_page)
        end

        def self.next_chapter
          NavigationCommand.new(:next_chapter)
        end

        def self.prev_chapter
          NavigationCommand.new(:prev_chapter)
        end

        def self.go_to_start
          NavigationCommand.new(:go_to_start)
        end

        def self.go_to_end
          NavigationCommand.new(:go_to_end)
        end

        def self.scroll_up(lines = 1)
          ScrollCommand.new(:up, lines: lines)
        end

        def self.scroll_down(lines = 1)
          ScrollCommand.new(:down, lines: lines)
        end

        def self.jump_to_chapter(index)
          JumpToChapterCommand.new(index)
        end
      end
    end
  end
end