# frozen_string_literal: true

module EbookReader
  # Central location for all application constants.
  # This module contains configuration values, limits, and
  # magic numbers used throughout the application.
  module Constants
    # Version of the configuration file format
    CONFIG_VERSION = 1

    # Application metadata
    APP_NAME = 'Reader'
    APP_AUTHOR = 'Your Name'
    APP_HOMEPAGE = 'https://github.com/yourusername/reader'

    # File system constants
    xdg_config_home = ENV.fetch('XDG_CONFIG_HOME', nil)
    config_root = if xdg_config_home && !xdg_config_home.empty?
                    xdg_config_home
                  else
                    File.join(Dir.home, '.config')
                  end
    CONFIG_DIR = File.join(config_root, 'reader')
    CACHE_DIR = File.join(CONFIG_DIR, 'cache')
    LOG_DIR = File.join(CONFIG_DIR, 'logs')

    # File names
    CONFIG_FILE = 'config.json'
    BOOKMARKS_FILE = 'bookmarks.json'
    PROGRESS_FILE = 'progress.json'
    RECENT_FILE = 'recent.json'
    CACHE_FILE = 'epub_cache.json'

    # Scanning limits
    SCAN_TIMEOUT = 20 # Maximum time for system scan in seconds
    MAX_DEPTH = 3            # Maximum directory depth for scanning
    MAX_FILES = 500          # Maximum number of EPUB files to index
    CACHE_DURATION = 86_400  # Cache validity in seconds (24 hours)
    MIN_FILE_SIZE = 100      # Minimum EPUB file size in bytes

    # Performance limits
    MAX_LINE_LENGTH = 120 # Maximum line length before wrapping
    MAX_CHAPTER_SIZE = 1_000_000  # Maximum chapter size in bytes
    RENDER_BUFFER_SIZE = 100      # Number of lines to buffer for rendering
    SCROLL_INDICATOR_WIDTH = 2    # Width of scroll indicator

    # Reader settings
    DEFAULT_LINE_SPACING = :compact
    LINE_SPACING_VALUES = %i[compact normal relaxed].freeze
    LINE_SPACING_MULTIPLIERS = {
      compact: 1.0,
      normal: 0.75,
      relaxed: 0.5,
    }.freeze
    VIEW_MODES = %i[split single].freeze
    READER_MODES = %i[read help toc bookmarks].freeze

    # Display settings
    CHAPTER_INFO_MAX_WIDTH = 100
    HIGHLIGHT_WORDS = [
      'Chinese poets', 'philosophers', 'Taoyuen-ming', 'celebrated', 'fragrance',
      'plum-blossoms', 'Linwosing', 'Chowmushih'
    ].freeze
    HIGHLIGHT_PATTERNS = Regexp.union(HIGHLIGHT_WORDS)
    # Matches basic quoted spans for optional highlighting. Supports:
    # - ASCII quotes: "..." and '...'
    # - Curly quotes: “...” and ‘...’
    # - Guillemets: «...» and ‹...›
    QUOTE_PATTERNS = /(["“„«‹][^"“”„«»‹›]*["”»›])|(['‘‚][^'‘’‚]*['’])/

    # Recent files
    MAX_RECENT_FILES = 10

    # Menu settings
    MENU_ITEMS_COUNT = 5
    BROWSE_LIST_PADDING = 8
    SETTINGS_ITEM_SPACING = 3

    # Navigation
    PAGE_BOUNDARY_PERCENT = 0.7  # For word wrap decisions
    VISIBLE_LIST_PADDING = 2     # Items to show above/below selection

    # Skip directories for scanning
    SKIP_DIRS = %w[
      node_modules vendor cache tmp temp .git .svn
      __pycache__ build dist bin obj debug release
      .idea .vscode .atom .sublime library frameworks
      applications system windows programdata appdata
      .Trash .npm .gem .bundle .cargo .rustup .cache
      .local .config backup backups old archive
    ].freeze

    # File patterns
    EPUB_PATTERN = '*.epub'
    BACKUP_PATTERN = '*~'
    TEMP_PATTERN = '.*.tmp'

    # Time formatting
    MINUTE = 60
    HOUR = 3600
    DAY = 86_400
    WEEK = 604_800

    # Key repeat delay in milliseconds
    KEY_REPEAT_DELAY = 20

    # Debug settings
    DEBUG_MODE = ENV['DEBUG'] || ARGV.include?('--debug')

    # Logging levels
    LOG_LEVELS = %i[debug info warn error fatal].freeze
    DEFAULT_LOG_LEVEL = DEBUG_MODE ? :debug : :info

    # Performance thresholds
    SLOW_OPERATION_THRESHOLD = 1.0 # seconds
    MEMORY_WARNING_THRESHOLD = 100_000_000 # bytes (100MB)

    # UI Layout
    MIN_MENU_COLUMN_WIDTH = 20
    MENU_POINTER_WIDTH = 2
    RECENT_ITEM_HEIGHT = 2
    BOOKMARK_ITEM_HEIGHT = 2
    TOC_SCROLL_PADDING = 2

    # ASCII Art dimensions
    LOGO_LINE_COUNT = 6
    LOGO_SPACING = 5
    MENU_START_OFFSET = 15

    # Browse screen
    SEARCH_BAR_ROW = 3
    SEARCH_PROMPT_WIDTH = 8
    STATUS_ROW = 4
    LIST_START_ROW = 6

    # Reader layout calculations
    CHAPTER_HEADER_ROW = 2
    DIVIDER_START_ROW = 3
    SINGLE_VIEW_WIDTH_PERCENT = 0.9
    PAGE_NUMBER_PADDING = 2

    # Error handling
    MAX_ERROR_MESSAGE_LENGTH = 200
    ERROR_CHAPTER_LINE_COUNT = 11
  end
end
