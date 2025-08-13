# frozen_string_literal: true

module EbookReader
  module Application
    # Clean application controller using dependency injection and pure components.
    # Replaces the tightly coupled ReaderController with proper architecture.
    class ReaderApplication
      attr_reader :dependencies, :view_model

      def initialize(epub_path, dependencies: nil)
        @epub_path = epub_path
        @dependencies = dependencies || Domain::ContainerFactory.create_default_container
        @running = true
        
        initialize_services
        setup_input_system
        setup_view_system
        setup_event_handlers
        
        load_document
      end

      def run
        Terminal.setup
        
        begin
          main_loop
        rescue Interrupt
          cleanup_and_exit("Goodbye!")
        ensure
          Terminal.cleanup
        end
      end

      def show_error_message(message)
        @dependencies.resolve(:state_store).set([:reader, :message], message)
        
        # Clear message after 3 seconds
        Thread.new do
          sleep 3
          @dependencies.resolve(:state_store).set([:reader, :message], nil)
        end
      end

      def cleanup
        @dependencies.resolve(:event_bus).unsubscribe(self)
        @input_dispatcher.cleanup if @input_dispatcher.respond_to?(:cleanup)
      end

      # Event handler for state changes
      def handle_event(event)
        case event.type
        when :state_changed
          handle_state_change(event.data)
        when :bookmark_added
          show_error_message("Bookmark added")
        when :bookmark_removed  
          show_error_message("Bookmark removed")
        when :navigated_to_bookmark
          show_error_message("Jumped to bookmark")
        end
      end

      private

      def initialize_services
        # Register application-specific services
        @dependencies.register(:application, self)
        
        # Initialize document-specific services
        @dependencies.register_factory(:document_service) do |container|
          Infrastructure::DocumentService.new(@epub_path)
        end
      end

      def setup_input_system
        @input_dispatcher = Infrastructure::InputDispatcher.new(self)
        setup_key_bindings
      end

      def setup_view_system
        @header_component = UI::Components::PureHeaderComponent.new
        @content_component = UI::Components::PureContentComponent.new
        @footer_component = UI::Components::PureFooterComponent.new
        
        @view_model = create_initial_view_model
      end

      def setup_event_handlers
        event_bus = @dependencies.resolve(:event_bus)
        event_bus.subscribe(self, :state_changed, :bookmark_added, :bookmark_removed, :navigated_to_bookmark)
      end

      def setup_key_bindings
        bindings = {
          # Navigation
          'j' => Domain::Commands::NavigationCommandFactory.next_page,
          'k' => Domain::Commands::NavigationCommandFactory.prev_page,
          'n' => Domain::Commands::NavigationCommandFactory.next_chapter,
          'p' => Domain::Commands::NavigationCommandFactory.prev_chapter,
          'g' => Domain::Commands::NavigationCommandFactory.go_to_start,
          'G' => Domain::Commands::NavigationCommandFactory.go_to_end,
          
          # Scrolling
          "\e[B" => Domain::Commands::NavigationCommandFactory.scroll_down, # Down arrow
          "\e[A" => Domain::Commands::NavigationCommandFactory.scroll_up,   # Up arrow
          
          # Application commands
          'q' => Domain::Commands::ApplicationCommandFactory.quit_to_menu,
          'Q' => Domain::Commands::ApplicationCommandFactory.quit_application,
          'v' => Domain::Commands::ApplicationCommandFactory.toggle_view_mode,
          '?' => Domain::Commands::ApplicationCommandFactory.show_help,
          't' => Domain::Commands::ApplicationCommandFactory.show_toc,
          'B' => Domain::Commands::ApplicationCommandFactory.show_bookmarks,
          
          # Mode switching
          "\e" => Domain::Commands::ApplicationCommandFactory.switch_to_mode(:read), # Escape
          
          # Bookmarks
          'b' => Domain::Commands::BookmarkCommandFactory.add_bookmark
        }
        
        @input_dispatcher.register_bindings(bindings)
      end

      def load_document
        document_service = @dependencies.resolve(:document_service)
        document = document_service.load_document
        
        state_store = @dependencies.resolve(:state_store)
        state_store.update({
          [:reader, :book_path] => @epub_path,
          [:reader, :total_chapters] => document.chapter_count,
          [:reader, :chapter_title] => document.get_chapter(0)&.title || "Chapter 1"
        })
      end

      def main_loop
        while @running
          update_view_model
          render_frame
          handle_input
          
          # Check if application should continue running
          state = @dependencies.resolve(:state_store).current_state
          @running = state.dig(:reader, :running) != false
        end
      end

      def update_view_model
        state = @dependencies.resolve(:state_store).current_state
        
        @view_model = UI::ViewModels::ReaderViewModel.new(
          current_chapter: state.dig(:reader, :current_chapter) || 0,
          total_chapters: state.dig(:reader, :total_chapters) || 0,
          current_page: state.dig(:reader, :current_page) || 0,
          total_pages: calculate_total_pages,
          chapter_title: state.dig(:reader, :chapter_title) || '',
          view_mode: state.dig(:reader, :view_mode) || :split,
          sidebar_visible: state.dig(:reader, :sidebar_visible) || false,
          mode: state.dig(:reader, :mode) || :read,
          message: state.dig(:reader, :message),
          bookmarks: state.dig(:reader, :bookmarks) || [],
          toc_entries: get_toc_entries,
          content_lines: get_content_lines,
          page_info: calculate_page_info
        )
      end

      def render_frame
        height, width = Terminal.size
        
        # Update UI dimensions in state
        @dependencies.resolve(:state_store).update({
          [:ui, :terminal_width] => width,
          [:ui, :terminal_height] => height
        })
        
        Terminal.start_frame
        
        # Calculate layout
        header_height = @view_model.has_message? ? 2 : 1
        footer_height = 1
        content_height = height - header_height - footer_height
        
        # Render components
        header_bounds = Components::Rect.new(x: 1, y: 1, width: width, height: header_height)
        content_bounds = Components::Rect.new(x: 1, y: 1 + header_height, width: width, height: content_height)
        footer_bounds = Components::Rect.new(x: 1, y: height, width: width, height: footer_height)
        
        surface = Components::Surface.new(Terminal)
        
        @header_component.render(surface, header_bounds, @view_model)
        @content_component.render(surface, content_bounds, @view_model)
        @footer_component.render(surface, footer_bounds, @view_model) if @footer_component
        
        Terminal.end_frame
      end

      def handle_input
        key = Terminal.read_key_blocking
        return unless key
        
        @input_dispatcher.handle_key(key)
      end

      def handle_state_change(event_data)
        path = event_data[:path]
        
        # Handle specific state changes that need immediate action
        case path
        when [:reader, :current_chapter]
          load_chapter_content(event_data[:new_value])
        when [:reader, :view_mode]
          clear_page_cache
        when [:ui, :terminal_width], [:ui, :terminal_height]
          clear_page_cache
        end
      end

      def load_chapter_content(chapter_index)
        document_service = @dependencies.resolve(:document_service)
        chapter = document_service.get_chapter(chapter_index)
        
        if chapter
          state_store = @dependencies.resolve(:state_store)
          state_store.set([:reader, :chapter_title], chapter.title)
        end
      end

      def clear_page_cache
        if @dependencies.registered?(:page_calculator)
          page_calculator = @dependencies.resolve(:page_calculator)
          page_calculator.clear_cache if page_calculator.respond_to?(:clear_cache)
        end
      end

      def calculate_total_pages
        return 0 unless @dependencies.registered?(:page_calculator)
        
        page_calculator = @dependencies.resolve(:page_calculator)
        state = @dependencies.resolve(:state_store).current_state
        total_chapters = state.dig(:reader, :total_chapters) || 0
        
        page_calculator.calculate_total_pages(total_chapters)
      end

      def calculate_page_info
        state = @dependencies.resolve(:state_store).current_state
        {
          current_page: state.dig(:reader, :current_page) || 0,
          total_pages: calculate_total_pages
        }
      end

      def get_toc_entries
        return [] unless @dependencies.registered?(:document_service)
        
        document_service = @dependencies.resolve(:document_service)
        document_service.get_table_of_contents
      rescue
        []
      end

      def get_content_lines
        return [] unless @dependencies.registered?(:document_service)
        
        state = @dependencies.resolve(:state_store).current_state
        current_chapter = state.dig(:reader, :current_chapter) || 0
        current_page = state.dig(:reader, :current_page) || 0
        
        document_service = @dependencies.resolve(:document_service)
        document_service.get_page_content(current_chapter, current_page)
      rescue
        ["Content loading..."]
      end

      def cleanup_and_exit(message)
        puts message
        @running = false
        cleanup
      end

      def create_initial_view_model
        UI::ViewModels::ReaderViewModel.new
      end
    end
  end
end