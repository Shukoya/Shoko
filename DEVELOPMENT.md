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
├── bin/                         # Executables (rspec, rubocop, ebook_reader, etc.)
├── lib/
│   └── ebook_reader/
│       ├── annotations/         # Reader mouse helpers for selection/coordinates
│       ├── application/         # Orchestrators (UnifiedApplication, frame/pagination coordination)
│       ├── builders/            # Page/setup builders shared across layers
│       ├── components/          # Presentation components (screens, reading, sidebar, overlays)
│       ├── controllers/         # Application controllers (UI/input/state for reader + menu)
│       ├── domain/              # Actions, commands, selectors, services, repositories, domain models
│       ├── helpers/             # EPUB/HTML/text helpers and processors
│       ├── infrastructure/      # Event bus, logger, state stores, document service, caches
│       ├── input/               # Dispatcher, key definitions, command builders, bindings
│       ├── main_menu/           # Menu actions and presenters (screens live under components/)
│       ├── models/              # Shared data/value objects (contexts, view models)
│       ├── ui/                  # View models and UI metadata
│       ├── validators/          # File and terminal validation
│       └── terminal*            # Terminal facade plus buffer/output/input primitives
├── spec/                        # Tests
├── ARCHITECTURE.md              # Architecture notes
├── DEVELOPMENT.md               # This guide
└── REFACTORING_ROADMAP.md       # Refactor status and plan
```

### Layer Responsibilities (updated)

- Presentation (components): Rendering flows through `Surface#do_render(surface, bounds)`; components read state via selectors and may resolve presentation-scoped services supplied via dependency injection (layout, formatting, coordinate). Direct terminal I/O remains encapsulated inside the Surface/Terminal abstractions.
- Application (controllers): Orchestrates flows, resolves services via DI, dispatches actions.
- Domain (services/actions/selectors/commands): Business logic, explicit state mutations, input commands.
- Infrastructure: State store, event bus, logger, terminal IO, persistence helpers.

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

- **Dispatcher + Screen Components**: Presentation uses a dispatcher with domain commands to route input into the application layer. “Modes” are implemented as screen components (e.g., Annotations, Annotation Editor, Browse) that implement `do_render(surface, bounds)`.
- **Observer Pattern**: State changes notify components/controllers via `ObserverStateStore`.
- **Service Objects (Domain Services)**: Core logic behind stable APIs, invoked by commands/controllers, mutating state via explicit domain actions.

### Dependency Injection (DI)

- A single `Domain::DependencyContainer` is created once and threaded through the app.
- Controllers resolve services via `@dependencies.resolve(:service_name)`.
- Components do not create containers; they are given dependencies (or a controller that holds them) via constructor when needed.
 - DocumentService is constructed via `@dependencies.resolve(:document_service_factory).call(path)` (no container creation inside services).
 - Navigation is handled only via the domain `navigation_service` (no NavigationController).

Examples:

```ruby
# CLI entry → Unified application owns the container
EbookReader::CLI.run

# application/unified_application.rb
def run
  if @epub_path
    MouseableReader.new(@epub_path, nil, @dependencies).run
  else
    MainMenu.new(@dependencies).run
  end
end

# In a controller (UIController)
def open_toc
  nav = @dependencies.resolve(:navigation_service)
  nav.jump_to_chapter(index)
end

# In a component that needs a service: pass dependencies explicitly
overlay = Components::TooltipOverlayComponent.new(reader_controller,
                                                 coordinate_service: @dependencies.resolve(:coordinate_service))
```

## Formatting Pipeline Guidelines

- **Parser First**: Update `Infrastructure::Parsers::XHTMLContentParser` when adding block-level semantics so chapters emit structured `ContentBlock`/`TextSegment` objects.
- **Formatting Service**: Prefer `Domain::Services::FormattingService.wrap_window`/`wrap_all` for retrieving display-ready lines. It caches parsed blocks per document and width.
- **Rendering Hooks**: Reading components should call `BaseViewRenderer#fetch_wrapped_lines` (already formatting-aware) rather than rolling custom HTML scrubbing. When building new styled strings, use `Helpers::TextMetrics.visible_length` to keep selection/highlighting accurate.
- **Fallbacks**: Tests or tooling that only provide `Chapter#lines` still work—the formatting service automatically falls back to the legacy plaintext wrappers.
- **Extending**: New block types require parser updates, formatting-service handling, renderer assertions, and documentation updates to keep the pipeline coherent.


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
# In a controller (creating a document service)
factory = @dependencies.resolve(:document_service_factory)
doc = factory.call(path).load_document
