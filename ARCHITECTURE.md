# Reader - Architecture

## Overview

Reader follows a modular, object-oriented architecture designed for maintainability and extensibility.

## Core Design Patterns

### 1. **Command Pattern** (Input Handling)
- Encapsulates user actions as command objects
- Enables undo/redo functionality (future feature)
- Decouples input handling from business logic

### 2. **Strategy Pattern** (Reader Modes)
- Different strategies for rendering content (reading, help, TOC, bookmarks)
- Easy to add new viewing modes
- Consistent interface for all modes

### 3. **Template Method Pattern** (Rendering)
- Base renderer defines structure
- Subclasses implement specific rendering logic
- Promotes code reuse

### 4. **Observer Pattern** (State Management)
- Configuration changes notify dependent components
- Progress tracking updates automatically

## Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Application Layer                     │
├─────────────────────────────────────────────────────────────┤
│  CLI  │  MainMenu  │  Reader  │  ReaderModes  │  Commands  │
├─────────────────────────────────────────────────────────────┤
│                         UI Layer                             │
├─────────────────────────────────────────────────────────────┤
│  Terminal  │  Renderers  │  UI Components  │  InputHandler  │
├─────────────────────────────────────────────────────────────┤
│                      Business Layer                          │
├─────────────────────────────────────────────────────────────┤
│  EPUBDocument  │  Config  │  Managers  │  EPUBFinder        │
├─────────────────────────────────────────────────────────────┤
│                       Data Layer                             │
├─────────────────────────────────────────────────────────────┤
│  File System  │  JSON Storage  │  EPUB Files                │
└─────────────────────────────────────────────────────────────┘
```

## Key Components

### Terminal Layer
- **Terminal**: Low-level terminal manipulation using ANSI escape codes
- **ANSI Module**: Constants for colors and control sequences

### Application Components
- **CLI**: Entry point and command-line interface
- **MainMenu**: File selection and application menu
- **Reader**: Main reading interface and mode coordination

### UI Components
- **Renderers**: Specialized rendering for different content types
- **ReaderModes**: Mode-specific behavior and rendering
- **InputHandler**: Keyboard input processing
- **Copy-friendly Rendering**: Header, content, footer, and messages are printed directly so standard terminal text selection always works; no separate copy mode exists.

### Business Logic
- **EPUBDocument**: EPUB parsing and content extraction
- **Config**: User preferences and settings
- **Managers**: Bookmarks, progress, and recent files

### Data Storage
- **JSON Files**: Configuration, bookmarks, progress
- **File System**: EPUB file scanning and access

## Data Flow

1. **Startup**: CLI → MainMenu → EPUBFinder
2. **File Selection**: MainMenu → Reader → EPUBDocument
3. **Reading**: Reader → ReaderMode → Renderer → Terminal
4. **Input**: Terminal → Reader → Command → State Change
5. **Persistence**: Managers → JSON Files

## Extension Points

- **New Reader Modes**: Implement `ReaderModes::BaseMode`
- **New Commands**: Implement command methods directly on Reader
- **New Renderers**: Use UI components or create new ones under `UI`
- **New File Formats**: Implement document parser interface

## Performance Considerations

- **Lazy Loading**: Chapters loaded on demand
- **Caching**: EPUB file list cached for 24 hours
- **Double Buffering**: Terminal updates use buffering
- **Efficient Parsing**: Minimal DOM parsing for performance
