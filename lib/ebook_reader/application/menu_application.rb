# frozen_string_literal: true

module EbookReader
  module Application
    # StateStore-based menu system replacing legacy MainMenu
    class MenuApplication
      def initialize(dependencies = nil)
        @dependencies = dependencies || Domain::ContainerFactory.create_default_container
        @running = true
        setup_initial_state
        setup_services
      end

      def run
        Terminal.setup

        begin
          main_loop
        rescue Interrupt
          cleanup_and_exit('Goodbye!')
        ensure
          Terminal.cleanup
        end
      end

      private

      def setup_initial_state
        @dependencies.resolve(:state_store).update({
                                                     %i[menu mode] => :main,
                                                     %i[menu selected] => 0,
                                                     %i[menu running] => true,
                                                   })
      end

      def setup_services
        # Initialize menu-specific services through DI
        @dependencies.register_factory(:library_scanner) do |_container|
          Services::LibraryScanner.new
        end
      end

      def main_loop
        while @running
          render_menu
          handle_input

          # Check if application should continue
          state = @dependencies.resolve(:state_store).current_state
          @running = state.dig(:menu, :running) != false
        end
      end

      def render_menu
        Terminal.size
        Terminal.start_frame

        # Simple menu rendering for now - will be enhanced
        Terminal.write(1, 1, 'EBook Reader Menu')
        Terminal.write(3, 1, '1. Browse Library')
        Terminal.write(4, 1, '2. Recent Files')
        Terminal.write(5, 1, '3. Open File')
        Terminal.write(6, 1, '4. Exit')

        Terminal.end_frame
      end

      def handle_input
        key = Terminal.read_key_blocking
        return unless key

        case key
        when 'q', "\e"
          @running = false
        when '1'
          handle_browse_library
        when '3'
          handle_open_file
        end
      end

      def handle_browse_library
        # For now, use legacy MainMenu - will be replaced in later steps
        @running = false
        MainMenu.new.run
      end

      def handle_open_file
        print 'Enter file path: '
        path = gets.chomp.strip
        return unless File.exist?(path) && path.downcase.end_with?('.epub')

        @running = false
        Application::ReaderApplication.new(path, dependencies: @dependencies).run
      end

      def cleanup_and_exit(message)
        puts message
        @running = false
      end
    end
  end
end
