# Development Guide

This guide covers the development setup, architecture, and best practices for contributing to Reader.

## Table of Contents

- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Architecture Overview](#architecture-overview)
- [Coding Standards](#coding-standards)
- [Text Selection and Copying](#text-selection-and-copying)
- [Testing Guidelines](#testing-guidelines)
- [Performance Considerations](#performance-considerations)
- [Debugging Tips](#debugging-tips)
- [Release Process](#release-process)

## Development Setup

### Prerequisites

- Ruby 3.3 or higher
- Bundler 2.0 or higher
- Git

### Initial Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/reader.git
   cd reader
   ```

2. **Install dependencies**
   ```bash
   bundle install
   ```

3. **Run tests to verify setup**
   ```bash
   bundle exec rspec
   ```

4. **Set up git hooks (optional)**
   ```bash
   cp hooks/pre-commit .git/hooks/
   chmod +x .git/hooks/pre-commit
   ```

## Project Structure

```
reader/
├── bin/                    # Executable files
│   └── ebook_reader       # Main executable
├── lib/                   # Library code
│   └── ebook_reader/      # Main module
│       ├── core/          # Core components
│       ├── concerns/      # Shared concerns
│       ├── helpers/       # Helper modules
│       ├── infrastructure/# Infrastructure (logging, etc.)
│       ├── renderers/     # Rendering components
│       ├── services/      # Service objects
│       ├── ui/            # UI components
│       └── validators/    # Input validators
├── spec/                  # Test files
├── docs/                  # Additional documentation
└── examples/              # Example usage
```

### Key Directories

- **core/**: Essential domain objects and state management
- **infrastructure/**: Cross-cutting concerns like logging and monitoring
- **services/**: Business logic extracted into service objects
- **validators/**: Input validation and sanitization
- **renderers/**: Display and formatting logic

## Architecture Overview

The application follows a layered architecture with clear separation of concerns:

### Layer Responsibilities

1. **Presentation Layer** (UI, Renderers)
   - Terminal manipulation
   - User input handling
   - Visual rendering

2. **Application Layer** (Reader, MainMenu)
   - Orchestrates user flows
   - Manages application state
   - Coordinates between layers

3. **Domain Layer** (Core, Models)
   - Business logic
   - Domain objects
   - State management

4. **Infrastructure Layer** (Logger, Config)
   - Technical concerns
   - External dependencies
   - System integration

### Design Patterns

- **Strategy Pattern**: Reader modes (`ReaderModes::*`)
- **Observer Pattern**: Configuration changes
- **Service Objects**: Complex operations

## Coding Standards

### Ruby Style Guide

We follow the [Ruby Style Guide](https://rubystyle.guide/) with some modifications:

- **Line Length**: 100 characters (relaxed from 80)
- **Method Length**: 20 lines maximum
- **Class Length**: 200 lines maximum
- **ABC Complexity**: 20 maximum

### Documentation

All public methods must have YARD documentation:

```ruby
# Calculate the reading time for a chapter
#
# @param chapter [Hash] Chapter data with :lines array
# @param words_per_minute [Integer] Reading speed (default: 250)
# @return [Integer] Estimated reading time in minutes
# @example
#   time = calculate_reading_time(chapter, 300)
#   puts "#{time} minutes to read"
def calculate_reading_time(chapter, words_per_minute = 250)
  # Implementation
end
```

### Naming Conventions

- **Classes**: `PascalCase` (e.g., `NavigationService`)
- **Methods**: `snake_case` (e.g., `calculate_width`)
- **Constants**: `SCREAMING_SNAKE_CASE` (e.g., `MAX_WIDTH`)
- **Predicates**: End with `?` (e.g., `valid?`)
- **Dangerous methods**: End with `!` (e.g., `save!`)

## Text Selection and Copying

Reader intentionally renders content directly to the terminal without any special "copy mode".
This ensures standard terminal text selection works in all contexts.

- Avoid introducing alternate rendering paths that bypass direct printing of page content.
- Maintain the header → content → footer → message drawing order so text stays selectable.
- New features should preserve copy-friendly output and not require additional key bindings.

## Testing Guidelines

### Test Structure

```ruby
RSpec.describe EbookReader::SomeClass do
  # Use contexts to group related tests
  context 'when initialized with valid data' do
    # Use descriptive test names
    it 'creates an instance with correct attributes' do
      # Arrange
      data = { title: 'Test' }
      
      # Act
      instance = described_class.new(data)
      
      # Assert
      expect(instance.title).to eq('Test')
    end
  end
end
```

### Test Coverage

- Aim for 100% coverage of public methods
- Test edge cases and error conditions
- Use mocks sparingly, prefer real objects
- Integration tests for critical paths

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific file
bundle exec rspec spec/reader_spec.rb

# Run with coverage
COVERAGE=true bundle exec rspec

# Run with documentation format
bundle exec rspec --format documentation
```

## Performance Considerations

### Memory Management

- Use lazy loading for large content
- Clear caches when switching books
- Monitor memory usage in development

### Rendering Performance

- Buffer terminal updates
- Minimize ANSI escape sequences
- Cache calculated layouts
- Use efficient string operations

### Profiling

```ruby
# Enable performance monitoring
EbookReader::Infrastructure::PerformanceMonitor.time("operation") do
  # Code to profile
end

# View statistics
stats = EbookReader::Infrastructure::PerformanceMonitor.stats("operation")
```

## Debugging Tips

### Debug Mode

Enable debug mode for verbose logging:

```bash
DEBUG=1 ebook_reader
# or
ebook_reader --debug
```

### Logging

Use the built-in logger:

```ruby
EbookReader.logger.debug("Processing chapter", index: 0)
EbookReader.logger.error("Failed to parse", error: e)
```

### Interactive Debugging

Add `binding.pry` or `debugger` statements:

```ruby
require 'pry' # Add to Gemfile first

def complex_method
  binding.pry  # Execution stops here
  # Rest of method
end
```

### Terminal Issues

For terminal-related issues:

```ruby
# Log terminal state
puts Terminal.size.inspect
puts ENV['TERM']

# Test without terminal manipulation
HEADLESS=1 ebook_reader
```

## Release Process

### Version Numbering

We follow [Semantic Versioning](https://semver.org/):

- **MAJOR**: Incompatible API changes
- **MINOR**: New functionality, backward compatible
- **PATCH**: Bug fixes, backward compatible

### Release Checklist

1. **Update version number**
   ```ruby
   # lib/ebook_reader/version.rb
   VERSION = 'x.y.z'
   ```

2. **Update CHANGELOG.md**
   - Add release date
   - List all changes
   - Credit contributors

3. **Run full test suite**
   ```bash
   bundle exec rake quality
   ```

4. **Build gem**
   ```bash
   gem build reader.gemspec
   ```

5. **Test gem locally**
   ```bash
   gem install ./reader-x.y.z.gem
   ```

6. **Tag release**
   ```bash
   git tag -a vx.y.z -m "Release version x.y.z"
   git push origin vx.y.z
   ```

7. **Push to RubyGems**
   ```bash
   gem push reader-x.y.z.gem
   ```

### Post-Release

1. Create GitHub release with changelog
2. Update documentation if needed
3. Announce in relevant channels

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed contribution guidelines.

## Questions?

- Open an issue for bugs or features
- Start a discussion for questions
- Check the wiki for additional documentation
