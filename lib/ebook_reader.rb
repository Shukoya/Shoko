# frozen_string_literal: true

# Reader - A fast, keyboard-driven terminal EPUB reader
#
# This is the main entry point for the EbookReader gem. It loads all
# necessary components in the correct order to ensure dependencies are
# satisfied.
#
# @example Basic usage
#   require 'ebook_reader'
#   EbookReader::CLI.run
#
# @example Programmatic usage
#   reader = EbookReader::MouseableReader.new('/path/to/book.epub')
#   reader.run

# Core infrastructure - must be loaded first
require_relative 'ebook_reader/infrastructure/logger'
require_relative 'ebook_reader/infrastructure/validator'
require_relative 'ebook_reader/infrastructure/performance_monitor'
require_relative 'ebook_reader/infrastructure/event_bus'
require_relative 'ebook_reader/infrastructure/state_store'
require_relative 'ebook_reader/infrastructure/document_service'
require_relative 'ebook_reader/infrastructure/input_dispatcher'

# Error definitions
require_relative 'ebook_reader/errors'

# Constants and configuration
require_relative 'ebook_reader/constants'
require_relative 'ebook_reader/constants/ui_constants'
require_relative 'ebook_reader/models/chapter'
require_relative 'ebook_reader/models/bookmark'
require_relative 'ebook_reader/models/bookmark_data'
require_relative 'ebook_reader/models/drawing_context'
require_relative 'ebook_reader/models/scanner_context'
require_relative 'ebook_reader/models/page_rendering_context'
require_relative 'ebook_reader/builders/page_setup_builder'

# Core components
require_relative 'ebook_reader/version'
require_relative 'ebook_reader/terminal'
# Config functionality now in GlobalState

# Validators
require_relative 'ebook_reader/validators/file_path_validator'
require_relative 'ebook_reader/validators/terminal_size_validator'

# Data management
require_relative 'ebook_reader/epub_finder'
require_relative 'ebook_reader/recent_files'
require_relative 'ebook_reader/progress_manager'
require_relative 'ebook_reader/bookmark_manager'

# Document handling
require_relative 'ebook_reader/epub_document'

# Command system - load before input system
require_relative 'ebook_reader/commands/base_command'
require_relative 'ebook_reader/commands/navigation_commands'
require_relative 'ebook_reader/commands/command_factory'

# Input system - load early for dependency resolution
require_relative 'ebook_reader/input/key_definitions'
require_relative 'ebook_reader/input/command_factory'
require_relative 'ebook_reader/input/config_loader'
require_relative 'ebook_reader/input/binding_generator'

# Domain layer - new architecture
require_relative 'ebook_reader/domain/dependency_container'
require_relative 'ebook_reader/domain/services/navigation_service'
require_relative 'ebook_reader/domain/services/bookmark_service'
require_relative 'ebook_reader/domain/services/page_calculator_service'
require_relative 'ebook_reader/domain/commands/base_command'
require_relative 'ebook_reader/domain/commands/navigation_commands'
require_relative 'ebook_reader/domain/commands/application_commands'
require_relative 'ebook_reader/domain/commands/bookmark_commands'

# UI layer - new architecture  
require_relative 'ebook_reader/ui/view_models/reader_view_model'
require_relative 'ebook_reader/ui/components/pure_header_component'
require_relative 'ebook_reader/ui/components/pure_content_component'

# Application layer - new architecture
require_relative 'ebook_reader/application/reader_application'

# Core reader components (legacy - will be phased out)
require_relative 'ebook_reader/core/global_state'
require_relative 'ebook_reader/services/navigation_service'
require_relative 'ebook_reader/services/bookmark_service'
require_relative 'ebook_reader/services/state_service'
require_relative 'ebook_reader/services/page_manager'
require_relative 'ebook_reader/services/main_menu_input_handler'
require_relative 'ebook_reader/services/coordinate_service'
require_relative 'ebook_reader/services/clipboard_service'
require_relative 'ebook_reader/services/service_registry'

# Reading components
require_relative 'ebook_reader/components/reading/base_view_renderer'
require_relative 'ebook_reader/components/reading/split_view_renderer'
require_relative 'ebook_reader/components/reading/single_view_renderer'
require_relative 'ebook_reader/components/reading/help_renderer'
require_relative 'ebook_reader/components/reading/toc_renderer'
require_relative 'ebook_reader/components/reading/bookmarks_renderer'
require_relative 'ebook_reader/components/reading/view_renderer_factory'

# Screen components
require_relative 'ebook_reader/components/screens/base_screen_component'
require_relative 'ebook_reader/components/screens/recent_screen_component'
require_relative 'ebook_reader/components/screens/menu_screen_component'

# UI components
require_relative 'ebook_reader/main_menu'
require_relative 'ebook_reader/mouseable_reader'

# Application entry point
require_relative 'ebook_reader/cli'

# Annotation support
require_relative 'ebook_reader/init_annotations'

# Main module for the EbookReader application
#
# This module serves as the namespace for all EbookReader components
# and provides version information and error classes.
#
# @example Check version
#   puts EbookReader::VERSION
#
# @example Handle errors
#   begin
#     EbookReader::CLI.run
#   rescue EbookReader::Error => e
#     puts "Error: #{e.message}"
#   end
module EbookReader
  # Custom error class for the EbookReader application.
  # All application-specific errors should inherit from this class.
  class Error < StandardError; end

  # Module-level configuration
  #
  # @return [Core::GlobalState] Global state instance
  def self.config
    @config ||= Core::GlobalState.new
  end

  # Module-level logger
  #
  # @return [Infrastructure::Logger] Global logger instance
  def self.logger
    Infrastructure::Logger
  end

  # Reset module state (mainly for testing)
  def self.reset!
    @config = nil
    Infrastructure::Logger.clear
    Infrastructure::PerformanceMonitor.clear
  end
end
