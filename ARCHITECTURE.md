# Reader - Architecture

## Overview

Reader follows a Clean Architecture with strict layer boundaries, dependency injection, and component-driven rendering. Presentation never talks directly to persistence; all state mutations flow through domain services and actions.

## Layers

```
┌─────────────────────────────────────────────────────────────┐
│                        Presentation                          │
├─────────────────────────────────────────────────────────────┤
│  UI Components (do_render)  │  Overlay/Popup Components      │
│  Screens (e.g. Annotation Editor, Annotations, Browse)       │
├─────────────────────────────────────────────────────────────┤
│                        Application                           │
├─────────────────────────────────────────────────────────────┤
│  Controllers (Reader/UI/State/Input) │ UnifiedApplication    │
├─────────────────────────────────────────────────────────────┤
│                           Domain                              │
├─────────────────────────────────────────────────────────────┤
│  Services  │  Actions  │  Commands  │  Selectors              │
├─────────────────────────────────────────────────────────────┤
│                        Infrastructure                         │
├─────────────────────────────────────────────────────────────┤
│  StateStore/ObserverStateStore │ EventBus │ Terminal/Surface  │
│  DocumentService  │ Logger  │ Persistence (JSON)             │
└─────────────────────────────────────────────────────────────┘
```

## Core Design Patterns

- Command Pattern (Input): Key bindings route to `Domain::Commands` via `Input::Dispatcher` and `DomainCommandBridge`.
- Observer Pattern (State): `ObserverStateStore` notifies components/controllers on path changes.
- Dependency Injection: `Domain::ContainerFactory` resolves services and infrastructure; components receive dependencies via constructor.
- Component Rendering: Components implement `do_render(surface, bounds)`; all terminal I/O goes through `TerminalService` + `Components::Surface`.

Note: Legacy ReaderModes are replaced by screen components. The former `ReaderModes::AnnotationEditorMode` was superseded by `Components::Screens::AnnotationEditorScreenComponent`.

## Key Components

- Presentation
  - UI Components: Header, Content, Footer, Sidebar, Overlay (tooltip, popup, annotations overlay), Screens (Browse, Library, Settings, Annotations, Annotation Editor). Annotation overlays reuse the same viewport math as full-screen editors—snippet preview + note viewport anchored top-left—so cursoring and rendering stay consistent across contexts.
  - Rendering Surface: `Components::Surface` abstracts writing to Terminal.
- Application
- Controllers: `ReaderController` orchestrates rendering and loop; `UIController` manages modes, sidebar, and overlays; `StateController` handles persistence; `InputController` configures the dispatcher. Navigation flows through the `NavigationService` plus targeted state actions for persisted jumps so rendering stays decoupled from storage. Modal input (annotation popup) is coordinated via `Application::AnnotationEditorOverlaySession`; `ReaderController` owns the session and exposes it for the input dispatcher's modal stack, while `UIController` simply resolves the input controller and silently ignores resolution failures.
  - Input: Popup handling is centralized via `with_popup_menu` and `process_popup_result` helpers to avoid repeated conditional branches for navigation/action/cancel.
  - UnifiedApplication: decides between menu and reader modes.
- Domain
  - Services: Navigation, PageCalculator, Selection, Coordinate, Layout, Clipboard, Annotation, Library.
  - NavigationService: uses `dynamic_route_exec` to route dynamic vs absolute strategies and small updater helpers to apply split/alignment updates without repeated conditionals.
  - DocumentService: uses `cached_fetch` and `with_chapter` helpers to consolidate caching and chapter access.
  - Actions/Selectors: explicit state transitions and read-only projections.
  - Commands: Navigation/Application/Sidebar command objects for input.
- Infrastructure
  - StateStore/ObserverStateStore, EventBus, Terminal (buffered output/input/mouse), Logger, DocumentService, Managers (recent files).
  - Repositories persist via domain file stores: `Storage::BookmarkFileStore`, `Storage::ProgressFileStore`, `Storage::AnnotationFileStore`.
  - LibraryService wraps cached-library enumeration and is resolved via DI for components (no direct Infra access in components).
  - Debug helpers: `EPUBFinder` and `DirectoryScanner` provide `debug?`/`warn_debug` helpers to keep debug logging free of repeated conditionals.

## Data Flow

1. Startup: CLI → `Application::UnifiedApplication` → either MainMenu or Reader
2. Input: Terminal → `Input::Dispatcher` → Domain Commands → Domain Services → Actions → StateStore
3. Rendering: Controllers request `TerminalService.create_surface`; Components render via `do_render` into Surface; `TerminalService` manages frames
4. Persistence: Domain services/Managers persist to JSON via Infrastructure; UI reads via selectors/state

## Extension Points

- New Screen/Component: extend `Components::BaseComponent` and implement `do_render`.
- New Input behavior: add `Domain::Commands` and map via `DomainCommandBridge`.
- New Domain logic: implement a service; expose actions/selectors as needed.
- New File format: implement a document parser and plug into `DocumentService`.
  - DocumentService is created via the DI `:document_service_factory` per book (no container creation inside the service).

### Internal Service Helpers

- For complex domain services that need small, focused helpers, place them under
  `lib/ebook_reader/domain/services/internal/` and do not register them in DI.
  These helpers are implementation details of a facade service (e.g.,
  `PageCalculatorService`) and must not be resolved by components or controllers.
  Example helpers:
  - `Internal::DynamicPageMapBuilder` — builds dynamic pagination page data.
  - `Internal::AbsolutePageMapBuilder` — computes absolute page counts per chapter.
  - `Internal::ChapterCache` — local wrapped-lines caching used by `WrappingService`.

## Performance Considerations

- Buffered output: Terminal double-buffering via `TerminalBuffer`.
- Lazy loading: Chapters loaded on demand.
- Caching: Library scan and chapter wrapping caches via services.
 - Cached Library: `Domain::Services::LibraryService` lists cached books by reading Marshal payloads in `.cache` files via `Infrastructure::Repositories::CachedLibraryRepository`.

## EPUB Cache

- Goal: instant subsequent opens by avoiding ZIP inflation and XML parsing.
- Key: cache file `${XDG_CACHE_HOME:-~/.cache}/reader/<sha256>.cache`, where `<sha256>` is the SHA‑256 of the `.epub` file.
- Implementation: `Infrastructure::BookCachePipeline` coordinates `EpubImporter` (ZIP/OPF/HTML processing) and `EpubCache` (Marshal serialization with integrity metadata + pagination layouts).
- First open (miss): pipeline imports the EPUB, builds `BookData` (chapters, resources, metadata) and writes a single `.cache` file via `AtomicFileWriter`.
- Subsequent opens (hit): pipeline loads the Marshal payload, validates version/digest/mtime, and hands `BookData` directly to `EPUBDocument`; no filesystem extraction is required. Pagination layouts are retrieved from the same payload when available.
- Dependencies: Standard library only; ZIP reads handled in-house via a minimal reader using `Zlib`.

## Content Formatting Pipeline

- XHTML Parsing: `Infrastructure::Parsers::XHTMLContentParser` walks chapter markup and emits
  `Domain::Models::ContentBlock` + `TextSegment` objects capturing headings, paragraphs, lists,
  block quotes, and code blocks without leaking raw HTML to the presentation layer.
- Formatting Service: `Domain::Services::FormattingService` orchestrates parsing, caches
  `DisplayLine` collections per document/width, and exposes `wrap_window`/`wrap_all` for
  block-aware text retrieval. Plain-text fallbacks remain available for legacy consumers.
- Wrapping Integration: `Domain::Services::WrappingService` now defers to the formatting
  service when present so pagination and prefetching align with the styled output rendered to
  the terminal.
- Rendering: `Components::Reading::BaseViewRenderer` prefers formatted display lines,
  applies ANSI styling per block type, and records visible bounds via
  `Helpers::TextMetrics` to keep selection/highlighting accurate.
- Backwards Compatibility: When formatting data is unavailable (e.g., tests or truncated
  chapters) the system gracefully falls back to the legacy plain-text wrapping path.
