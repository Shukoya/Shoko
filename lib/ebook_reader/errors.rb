# frozen_string_literal: true

module EbookReader
  # Base error class for EbookReader
  class Error < StandardError; end

  # Raised when EPUB file cannot be parsed
  class EPUBParseError < Error
    attr_reader :file_path

    def initialize(message, file_path)
      super("Failed to parse EPUB at #{file_path}: #{message}")
      @file_path = file_path
    end
  end

  # Raised when required file is not found
  class FileNotFoundError < Error
    attr_reader :file_path

    def initialize(file_path)
      super("File not found: #{file_path}")
      @file_path = file_path
    end
  end

  # Raised when configuration is invalid
  class ConfigurationError < Error; end

  # Raised when terminal is too small
  class TerminalSizeError < Error
    def initialize(width, height)
      min_width = Constants::UIConstants::MIN_WIDTH
      min_height = Constants::UIConstants::MIN_HEIGHT
      super("Terminal too small: #{width}x#{height}. Minimum required: #{min_width}x#{min_height}")
    end
  end

  # Raised when no interactive terminal is available
  class TerminalUnavailableError < Error
    def initialize
      super('Interactive terminal not available')
    end
  end

  # Raised when reader state is invalid
  class InvalidStateError < Error
    attr_reader :state

    def initialize(message, state)
      super("Invalid reader state: #{message}")
      @state = state
    end
  end

  # Raised when navigation is not possible
  class NavigationError < Error
    attr_reader :direction, :reason

    def initialize(direction, reason)
      super("Cannot navigate #{direction}: #{reason}")
      @direction = direction
      @reason = reason
    end
  end

  # Raised when bookmark operation fails
  class BookmarkError < Error
    attr_reader :operation

    def initialize(operation, message)
      super("Bookmark #{operation} failed: #{message}")
      @operation = operation
    end
  end

  # Raised when rendering fails
  class RenderError < Error
    attr_reader :component

    def initialize(component, message)
      super("Rendering failed in #{component}: #{message}")
      @component = component
    end
  end

  # Raised when content normalization produces no semantic blocks
  class FormattingError < Error
    attr_reader :source

    def initialize(source, message)
      super("Formatting failed for #{source}: #{message}")
      @source = source
    end
  end

  class CacheLoadError < Error
    attr_reader :path

    def initialize(path, message = 'Cache is corrupt or incompatible')
      super("Cache load failed for #{path}: #{message}")
      @path = path
    end
  end
end
