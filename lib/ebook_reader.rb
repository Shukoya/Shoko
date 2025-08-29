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
require_relative 'ebook_reader/models/rendering_context'
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

# Legacy command system removed - now using Domain commands only

# Input system - load early for dependency resolution
require_relative 'ebook_reader/input/key_definitions'
require_relative 'ebook_reader/input/command_factory'
require_relative 'ebook_reader/input/config_loader'
require_relative 'ebook_reader/input/binding_generator'

# Domain layer - new architecture (must load before bridge)
require_relative 'ebook_reader/domain/dependency_container'
require_relative 'ebook_reader/domain/services/base_service'
require_relative 'ebook_reader/domain/services/navigation_service'
require_relative 'ebook_reader/domain/services/bookmark_service'
require_relative 'ebook_reader/domain/services/page_calculator_service'
require_relative 'ebook_reader/domain/services/coordinate_service'
require_relative 'ebook_reader/domain/services/layout_service'
require_relative 'ebook_reader/domain/services/clipboard_service'
require_relative 'ebook_reader/domain/services/terminal_service'
require_relative 'ebook_reader/domain/commands/base_command'
require_relative 'ebook_reader/domain/commands/navigation_commands'
require_relative 'ebook_reader/domain/commands/application_commands'
require_relative 'ebook_reader/domain/commands/bookmark_commands'
require_relative 'ebook_reader/domain/actions/base_action'
require_relative 'ebook_reader/domain/actions/toggle_view_mode_action'
require_relative 'ebook_reader/domain/actions/switch_reader_mode_action'
require_relative 'ebook_reader/domain/actions/quit_to_menu_action'
require_relative 'ebook_reader/domain/actions/update_reader_mode_action'
require_relative 'ebook_reader/domain/actions/update_page_action'
require_relative 'ebook_reader/domain/actions/update_selection_action'
require_relative 'ebook_reader/domain/actions/update_message_action'
require_relative 'ebook_reader/domain/actions/update_chapter_action'
require_relative 'ebook_reader/domain/actions/update_config_action'
require_relative 'ebook_reader/domain/actions/update_bookmarks_action'
require_relative 'ebook_reader/domain/actions/update_mode_action'
require_relative 'ebook_reader/domain/actions/update_sidebar_action'
require_relative 'ebook_reader/domain/actions/update_selections_action'
require_relative 'ebook_reader/domain/actions/update_popup_menu_action'
require_relative 'ebook_reader/domain/actions/update_rendered_lines_action'
require_relative 'ebook_reader/domain/actions/update_annotations_action'
require_relative 'ebook_reader/domain/actions/action_creators'

# Domain selectors for state access
require_relative 'ebook_reader/domain/selectors/reader_selectors'
require_relative 'ebook_reader/domain/selectors/menu_selectors'
require_relative 'ebook_reader/domain/selectors/config_selectors'

# Input system bridge (load after domain commands)
require_relative 'ebook_reader/input/domain_command_bridge'

# UI layer - new architecture
require_relative 'ebook_reader/ui/view_models/reader_view_model'
# Removed unused: pure_content_component, pure_footer_component

# Application layer - new architecture  
require_relative 'ebook_reader/application/unified_application'
# Removed unused: reader_application, menu_application

# Core reader components (legacy - will be phased out)
require_relative 'ebook_reader/core/global_state'
# Removed state_accessor - no longer needed with direct state.get() and selectors
# Removed: state_service (replaced with direct state management)
# Removed: page_manager (merged into PageCalculatorService)
# Removed: services/main_menu_input_handler (replaced by dispatcher bindings)

# Legacy service wrappers removed - now using domain services directly

# Reading components
require_relative 'ebook_reader/components/reading/base_view_renderer'
require_relative 'ebook_reader/components/reading/split_view_renderer'
require_relative 'ebook_reader/components/reading/single_view_renderer'
require_relative 'ebook_reader/components/reading/help_renderer'
require_relative 'ebook_reader/components/reading/toc_renderer'
require_relative 'ebook_reader/components/reading/bookmarks_renderer'
require_relative 'ebook_reader/components/reading/view_renderer_factory'

# Component system
require_relative 'ebook_reader/components/component_interface'
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
