# Reader

A fast, keyboard-driven terminal EPUB reader written in Ruby.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Configuration](#configuration)
- [Architecture](#architecture)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## Features

- **Multiple View Modes**: Split (two-column) and single (centered) view modes
- **Vim-style Navigation**: Familiar keyboard shortcuts for efficient reading
- **Smart Bookmarks**: Save and organize bookmarks with contextual information
- **Progress Tracking**: Automatic saving and restoration of reading position
- **Library Cache**: Browse cached books with recorded last-accessed timestamps from prior sessions
- **Customizable Display**: Adjustable line spacing and visual preferences
- **Performance Optimized**: Lazy loading and efficient rendering for large books
- **Error Recovery**: Graceful handling of corrupted or invalid EPUB files
- **Native Text Selection**: Pages are rendered directly to the terminal, allowing highlight and copy without a special mode

## Installation

### Via RubyGems

```bash
gem install reader
```

### Via Bundler

Add to your Gemfile:

```ruby
gem 'reader'
```

Then run:

```bash
bundle install
```

### From Source

```bash
git clone https://github.com/Shayancx/Reader.git
cd Reader
bundle install
rake install
```

## Usage

### Basic Usage

```bash
ebook_reader
```

### Command Line Options

```bash
ebook_reader --help              # Show help
ebook_reader --debug             # Enable debug mode
ebook_reader /path/to/book.epub  # Open specific book
ebook_reader --log /tmp/reader.log        # Persist logs to the given file
ebook_reader --log-level info             # Adjust log verbosity
```

### First Time Setup

On first run, the application will:
1. Create configuration directory at `~/.config/reader/`
2. Scan your system for EPUB files (this may take a moment)
3. Cache the results for faster subsequent launches

## Keyboard Shortcuts

### Navigation

| Key | Action | Description |
|-----|--------|-------------|
| `j` / `↓` | Scroll down | Move down one line |
| `k` / `↑` | Scroll up | Move up one line |
| `l` / `→` / `Space` | Next page | Go to next page |
| `h` / `←` | Previous page | Go to previous page |
| `n` | Next chapter | Jump to next chapter |
| `p` | Previous chapter | Jump to previous chapter |
| `g` | Go to start | Beginning of chapter |
| `G` | Go to end | End of chapter |

### Features

| Key | Action | Description |
|-----|--------|-------------|
| `t` | Table of Contents | Show chapter list |
| `b` | Add bookmark | Bookmark current position |
| `B` | View bookmarks | Show all bookmarks |
| `v` | Toggle view | Switch between split/single |
| `+` | Increase spacing | More line spacing |
| `-` | Decrease spacing | Less line spacing |
| `?` | Help | Show help screen |

Text selection is always available—simply highlight any text in your terminal to copy it.

### Application

| Key | Action | Description |
|-----|--------|-------------|
| `q` | Quit to menu | Return to main menu |
| `Q` | Quit application | Exit completely |
| `/` | Search | Search in browse mode |
| `Esc` | Back | Go back/cancel |

## Configuration

Configuration is stored in `~/.config/reader/config.json`:

```json
{
  "view_mode": "split",
  "theme": "dark",
  "show_page_numbers": true,
  "line_spacing": "compact",
  "highlight_quotes": true,
  "page_numbering_mode": "absolute"
}
```

### Configuration Options

- **view_mode**: `"split"` or `"single"` - Default reading view
- **theme**: `"dark"` (default) or one of `default`, `gray`, `sepia`, `grass`, `cherry`, `sky`,
  `solarized`, `gruvbox`, `nord` – selects the active color palette
- **show_page_numbers**: `true` or `false` - Display page numbers
- **line_spacing**: `"compact"` (tight), `"normal"` (moderate spacing), or `"relaxed"` (double spacing); default `compact`
- **highlight_quotes**: `true` or `false` - Highlight quoted text
- **page_numbering_mode**: `"absolute"` or `"dynamic"` - Page numbering strategy

## Architecture

Reader uses Clean Architecture with DI and component-driven rendering.

### Layers

- **Presentation**: UI components/screens implement `do_render(surface, bounds)` and render via `Components::Surface`. An overlay component unifies highlights and popup menus. The annotation editor is implemented as a screen component (no legacy modes).
- **Application**: Controllers coordinate state and rendering (`ReaderController`, `UIController`, `StateController`, `InputController`, `Controllers::MenuController`). `Application::UnifiedApplication` selects menu vs reader mode and threads the shared dependency container through both flows.
- **Domain**: Services (Navigation, PageCalculator, Layout, Selection, Coordinate, Clipboard, Annotation), Actions, Commands, Selectors. All mutations go through services which dispatch actions to the state store.
- **Infrastructure**: `ObserverStateStore`, `EventBus`, `Terminal` (buffered I/O + mouse), `DocumentService`, Logger, and JSON-backed managers (bookmarks, progress, recent files).

### Input

Key bindings are centralized and routed through `Input::Dispatcher` using `DomainCommandBridge` to create domain command objects. This keeps input consistent and decoupled from UI/app code.

For detailed architecture documentation, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Development

### Prerequisites

- Ruby 3.3 or higher
- Bundler

### Setup Development Environment

```bash
git clone https://github.com/yourusername/reader.git
cd reader
bundle install
```

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run with coverage report
bundle exec rspec --format documentation

# Run specific test file
bundle exec rspec spec/reader_spec.rb
```

### Code Quality

```bash
# Run RuboCop for style checking
bundle exec rubocop

# Run all quality checks
bundle exec rake quality
```

### Debugging

Enable debug mode to see detailed logs:

```bash
ebook_reader --debug
```

Or set the environment variable:

```bash
DEBUG=1 ebook_reader
```

Additional logging controls:

- `--log PATH` (or `READER_LOG_PATH`) writes JSON log lines to the specified file.
- `--log-level LEVEL` (or `READER_LOG_LEVEL`) sets verbosity (`debug`, `info`, `warn`, `error`, `fatal`).

Additional logging controls:

- `READER_LOG_PATH=/path/to/log` will persist structured logs to the given file (directories are created automatically).
- `READER_LOG_LEVEL=info` adjusts verbosity when not using `--debug` (supported values: `debug`, `info`, `warn`, `error`, `fatal`).

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`bundle exec rspec`)
5. Check code quality (`bundle exec rake quality`)
6. Commit your changes (`git commit -m 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

### Contribution Guidelines

- Follow Ruby style guide (enforced by RuboCop)
- Write comprehensive tests for new features
- Update documentation as needed
- Keep commits atomic and well-described
- Ensure backward compatibility

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Terminal manipulation inspired by [curses](https://github.com/ruby/curses)
- Special thanks to all contributors

## Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/reader/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/reader/discussions)
- **Wiki**: [Project Wiki](https://github.com/yourusername/reader/wiki)
