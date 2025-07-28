# Changelog

All notable changes to Reader will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive infrastructure layer with logging and performance monitoring
- Validation framework for input sanitization
- Dedicated service objects for complex operations
- Core state management extracted from Reader class
- Component-based rendering system
- Extensive YARD documentation for all public APIs
- Development guide with best practices
- Integration tests for new components
- Terminal size validation with recommendations
- Performance monitoring with automatic slow operation detection

### Changed
- Refactored Reader class to use smaller, focused components
- Consolidated constants into a single module
- Improved error handling with specific error types
- Enhanced documentation with examples and usage patterns
- Extracted navigation logic into dedicated service
- Standardized logging throughout the application
- Improved code organization with clear separation of concerns

### Fixed
- Terminal size validation edge cases
- Memory efficiency in large documents
- Input handling race conditions
- Error recovery in corrupted EPUB files
- Consistent error handling patterns
- Dynamic page numbering now advances pages without manual scrolling

### Security
- Added input validation for all file paths
- Sanitized user input in search functionality

## [0.9.212-beta] - 2024-01-15

### Added
- Initial implementation
- Basic EPUB reading functionality
- Bookmark support
- Progress tracking
- Recent files history
- Split and single view modes
- Vim-style navigation
- Customizable line spacing
- Search functionality in browse mode

### Known Issues
- Some EPUB files with complex formatting may not display correctly
- Large files (>10MB) may experience slower initial loading
