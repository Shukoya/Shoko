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
  - UI Components: Header, Content, Footer, Sidebar, Overlay (tooltip/popup), Screens (Browse, Recent, Settings, Annotations, Annotation Editor).
  - Rendering Surface: `Components::Surface` abstracts writing to Terminal.
- Application
  - Controllers: `ReaderController` orchestrates rendering and loop; `UIController` manages modes/overlays; `NavigationController` and `StateController` handle navigation/persistence; `InputController` configures the dispatcher.
  - UnifiedApplication: decides between menu and reader modes.
- Domain
  - Services: Navigation, PageCalculator, Selection, Coordinate, Layout, Clipboard, Annotation.
  - Actions/Selectors: explicit state transitions and read-only projections.
  - Commands: Navigation/Application/Sidebar command objects for input.
- Infrastructure
  - StateStore/ObserverStateStore, EventBus, Terminal (buffered output/input/mouse), Logger, DocumentService, Managers (bookmarks, progress, recent files).

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

## Performance Considerations

- Buffered output: Terminal double-buffering via `TerminalBuffer`.
- Lazy loading: Chapters loaded on demand.
- Caching: Library scan and chapter wrapping caches via services.
