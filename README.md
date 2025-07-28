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
- **Recent Files**: Quick access to recently opened books with smart sorting
- **Customizable Display**: Adjustable line spacing and visual preferences
- **Performance Optimized**: Lazy loading and efficient rendering for large books
- **Error Recovery**: Graceful handling of corrupted or invalid EPUB files
- **Copy Mode**: Temporarily print the current page for easy text selection

## Installation

### Via RubyGems

```bash
gem install Reader
```

### Via Bundler

Add to your Gemfile:

```ruby
gem 'Reader'
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
```

### First Time Setup

On first run, the application will:
1. Create configuration directory at `~/.config/Reader/`
2. Scan your system for EPUB files (this may take a moment)
3. Cache the results for faster subsequent launches

## Keyboard Shortcuts

### Navigation

| Key | Action | Description |
|-----|--------|-------------|
| `j` / `↓` | Scroll down | Move down one line (page in Dynamic mode) |
| `k` / `↑` | Scroll up | Move up one line (page in Dynamic mode) |
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
| `c` | Copy mode | Print current page for selection |
| `v` | Toggle view | Switch between split/single |
| `+` | Increase spacing | More line spacing |
| `-` | Decrease spacing | Less line spacing |
| `?` | Help | Show help screen |

### Application

| Key | Action | Description |
|-----|--------|-------------|
| `q` | Quit to menu | Return to main menu |
| `Q` | Quit application | Exit completely |
| `/` | Search | Search in browse mode |
| `Esc` | Back | Go back/cancel |

## Configuration

Configuration is stored in `~/.config/Reader/config.json`:

```json
{
  "view_mode": "split",
  "theme": "dark",
  "show_page_numbers": true,
  "line_spacing": "normal",
  "highlight_quotes": true,
  "page_numbering_mode": "absolute"
}
```

### Configuration Options

- **view_mode**: `"split"` or `"single"` - Default reading view
- **theme**: `"dark"` or `"light"` - Color theme (currently dark only)
- **show_page_numbers**: `true` or `false` - Display page numbers
- **line_spacing**: `"compact"`, `"normal"`, or `"relaxed"` - Line spacing
- **highlight_quotes**: `true` or `false` - Highlight quoted text
- **page_numbering_mode**: `"absolute"` or `"dynamic"` - Page numbering strategy. In `dynamic` mode, navigation keys jump by full pages.

## Architecture

The application follows a modular, layered architecture:

### Core Components

- **Terminal**: Low-level terminal manipulation using ANSI escape codes
- **Config**: User preferences and settings management
- **EPUBDocument**: EPUB parsing and content extraction

### UI Layer

- **MainMenu**: Application entry point and file selection
- **Reader**: Main reading interface with mode management
- **ReaderModes**: Specialized handlers for different view modes
- **Renderers**: Component-based rendering system

### Services Layer

- **ReaderNavigation**: Navigation logic and state management
- **BookmarkManager**: Bookmark persistence and retrieval
- **ProgressManager**: Reading position tracking
- **RecentFiles**: Recent file history management

### Infrastructure

- **Logger**: Structured logging system
- **Validator**: Input validation framework
- **PerformanceMonitor**: Performance tracking and profiling

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
- EPUB parsing uses [rubyzip](https://github.com/rubyzip/rubyzip)
- Special thanks to all contributors

## Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/reader/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/reader/discussions)
- **Wiki**: [Project Wiki](https://github.com/yourusername/reader/wiki)
