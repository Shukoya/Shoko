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
# Our minimal ZIP reader lives at lib/zip.rb, and a top-level zip.rb wrapper ensures
# `require 'zip'` in specs loads it. Keep this require close for clarity.
require_relative 'zip'
require_relative 'ebook_reader/infrastructure/logger'
require_relative 'ebook_reader/infrastructure/validator'
require_relative 'ebook_reader/infrastructure/performance_monitor'
require_relative 'ebook_reader/infrastructure/event_bus'
require_relative 'ebook_reader/infrastructure/state_store'
require_relative 'ebook_reader/infrastructure/observer_state_store'
require_relative 'ebook_reader/infrastructure/document_service'
require_relative 'ebook_reader/infrastructure/pagination_cache'

# Error definitions
require_relative 'ebook_reader/errors'

# Constants and configuration
require_relative 'ebook_reader/constants'
require_relative 'ebook_reader/constants/ui_constants'
require_relative 'ebook_reader/models/drawing_context'
require_relative 'ebook_reader/models/scanner_context'
require_relative 'ebook_reader/models/page_rendering_context'
require_relative 'ebook_reader/models/rendering_context'
require_relative 'ebook_reader/builders/page_setup_builder'

# Core components
require_relative 'ebook_reader/version'
require_relative 'ebook_reader/terminal'
# Config/state access uses ObserverStateStore via DI (:global_state resolves to the shared state store)

# Validators
require_relative 'ebook_reader/validators/file_path_validator'
require_relative 'ebook_reader/validators/terminal_size_validator'

# Data management
require_relative 'ebook_reader/epub_finder'
require_relative 'ebook_reader/recent_files'

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
require_relative 'ebook_reader/domain/models/chapter'
require_relative 'ebook_reader/domain/models/bookmark'
require_relative 'ebook_reader/domain/models/bookmark_data'
require_relative 'ebook_reader/domain/events/base_domain_event'
require_relative 'ebook_reader/domain/events/bookmark_events'
require_relative 'ebook_reader/domain/events/annotation_events'
require_relative 'ebook_reader/domain/events/progress_events'
require_relative 'ebook_reader/domain/events/domain_event_bus'
require_relative 'ebook_reader/domain/repositories/base_repository'
require_relative 'ebook_reader/domain/repositories/bookmark_repository'
require_relative 'ebook_reader/domain/repositories/annotation_repository'
require_relative 'ebook_reader/domain/repositories/progress_repository'
require_relative 'ebook_reader/domain/repositories/config_repository'
require_relative 'ebook_reader/domain/services/base_service'
require_relative 'ebook_reader/domain/services/navigation_service'
require_relative 'ebook_reader/domain/services/bookmark_service'
require_relative 'ebook_reader/domain/services/page_calculator_service'
require_relative 'ebook_reader/domain/services/coordinate_service'
require_relative 'ebook_reader/domain/services/layout_service'
require_relative 'ebook_reader/domain/services/clipboard_service'
require_relative 'ebook_reader/domain/services/annotation_service'
require_relative 'ebook_reader/domain/services/terminal_service'
require_relative 'ebook_reader/domain/services/selection_service'
require_relative 'ebook_reader/domain/services/wrapping_service'
require_relative 'ebook_reader/domain/services/notification_service'
require_relative 'ebook_reader/domain/services/library_service'
require_relative 'ebook_reader/domain/commands/base_command'
require_relative 'ebook_reader/domain/commands/navigation_commands'
require_relative 'ebook_reader/domain/commands/application_commands'
require_relative 'ebook_reader/domain/commands/bookmark_commands'
require_relative 'ebook_reader/domain/commands/sidebar_commands'
require_relative 'ebook_reader/domain/commands/conditional_navigation_commands'
require_relative 'ebook_reader/domain/commands/menu_commands'
require_relative 'ebook_reader/domain/commands/annotation_editor_commands'
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
require_relative 'ebook_reader/domain/actions/update_ui_loading_action'
require_relative 'ebook_reader/domain/actions/update_pagination_state_action'
require_relative 'ebook_reader/domain/actions/update_reader_meta_action'
require_relative 'ebook_reader/domain/actions/update_annotations_action'
require_relative 'ebook_reader/domain/actions/update_menu_action'
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
require_relative 'ebook_reader/application/reader_view_model_builder'
require_relative 'ebook_reader/application/reader_startup_orchestrator'
require_relative 'ebook_reader/application/frame_coordinator'
require_relative 'ebook_reader/application/render_pipeline'
require_relative 'ebook_reader/application/pagination_orchestrator'
# Removed unused: reader_application, menu_application

# Controller layer - focused controllers replacing god class
require_relative 'ebook_reader/controllers/ui_controller'
require_relative 'ebook_reader/controllers/state_controller'
require_relative 'ebook_reader/controllers/input_controller'

# Core reader components updated to use new state management
# Removed: legacy global state implementation (now using Infrastructure::ObserverStateStore)
# Removed: state_accessor - no longer needed with direct state.get() and selectors
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
## recent screen removed
require_relative 'ebook_reader/components/screens/menu_screen_component'
require_relative 'ebook_reader/components/screens/annotation_detail_screen_component'
require_relative 'ebook_reader/components/screens/annotation_editor_screen_component'

# UI components
require_relative 'ebook_reader/main_menu'
require_relative 'ebook_reader/mouseable_reader'

# Application entry point
require_relative 'ebook_reader/cli'

# Annotation support
require_relative 'ebook_reader/init_annotations'

# Test-only shims and coverage warmup
if defined?(RSpec)
  require_relative 'ebook_reader/test_shims'
  EbookReader::TestShims.run!
  require_relative 'ebook_reader/test_coverage_warmup'
  EbookReader::TestCoverageWarmup.run!
end

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
  # @return [Infrastructure::ObserverStateStore] Global state instance
  def self.config
    @config ||= Domain::ContainerFactory.create_default_container.resolve(:global_state)
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
