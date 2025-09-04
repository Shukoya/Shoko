# EBook Reader Refactoring Roadmap

**Current Status: Phase 4.6 - Documentation + Input Alignment**  
**Overall Progress: ~90% Complete (audited 2025-09-04)**  
**Estimated Completion: Phase 4.6**  
**Status Note:** Overlay and reader input are unified; annotations flow in the reader is unified via a component. Menu annotation editor input is already routed through Domain commands. Documentation has been aligned (Project Structure + DI examples). Minor menu state API consistency remains. Reader loading flicker has been fixed by keeping the app in the alternate screen. Progress is shown inline during menu-driven open; direct CLI open performs a silent, frame-safe pre-build without flicker. Canonical book identity (`EPUBDocument#source_path`) ensures progress/bookmarks restore whether opening the original file or a cache dir, and first frame now lands on the saved page in dynamic mode.

## Phase 1: Infrastructure Foundation ✅ COMPLETE

### 1.1 Core Infrastructure ✅ DONE
- [x] Event Bus system (`infrastructure/event_bus.rb`)
- [x] StateStore with immutable state (`infrastructure/state_store.rb`)  
- [x] Dependency Container with DI (`domain/dependency_container.rb`)
- [x] Base service classes with DI support

### 1.2 Domain Layer Structure ✅ DONE
- [x] Domain services in `domain/services/`
- [x] Domain actions in `domain/actions/`
- [x] Domain commands in `domain/commands/`
- [x] Domain selectors in `domain/selectors/`

### 1.3 Input System Modernization ✅ DONE
- [x] CommandFactory for consistent input patterns
- [x] DomainCommandBridge for command routing
- [x] KeyDefinitions centralization

## Phase 2: Legacy Elimination ❌ INCOMPLETE

### 2.1 Service Layer Consolidation ✅ COMPLETE (re-verified)
**Verified Status**: Legacy wrappers for `coordinate_service`, `clipboard_service`, and `layout_service` do NOT exist under `lib/ebook_reader/services/` anymore. All active implementations live under `lib/ebook_reader/domain/services/`.
- [x] Legacy wrappers removed (`coordinate_service.rb`, `clipboard_service.rb`, `layout_service.rb`) — verified absent
- [x] All references use `domain/services/` versions only — verified
- [x] `chapter_cache.rb` retained only as an internal helper to `Domain::Services::WrappingService` (no public DI registration)
- [x] No stray container registrations for deleted legacy services

### 2.2 State System Unification ✅ COMPLETE  
**Issue Resolved**: ObserverStateStore fully implemented, GlobalState class eliminated
- [x] Replace ALL GlobalState usage with ObserverStateStore
- [x] Migrate state structure from GlobalState to StateStore format
- [x] Update all `@state.update()` calls to use StateStore events  
- [x] Maintain GlobalState compatibility through ObserverStateStore
- [x] Update DependencyContainer to resolve ObserverStateStore as primary state
- [x] Verified :global_state dependency key correctly resolves to ObserverStateStore (GlobalState class completely removed)

### 2.3 Component Interface Standardization ✅ COMPLETE (updated)
**Correction**: `do_render` is now the prevailing pattern for active components, including the sidebar tab header component.
- [x] ComponentInterface defined
- [x] Reading components extend BaseComponent and implement do_render
- [x] TooltipOverlayComponent implements do_render (verified)
- [x] EnhancedPopupMenu is a proper component (do_render) and not a data object
- [x] ReaderModes::AnnotationEditorMode removed (legacy file deleted)
- [x] Surface abstraction adopted
- [x] Legacy direct Terminal writes removed (components render via Surface)

## Phase 3: Architecture Cleanup 📋 PLANNED

### 3.1 ReaderController Decomposition ✅ COMPLETE (re-verified)
**Issue Resolved**: God class decomposed into focused controllers
- [x] Extract NavigationController (page/chapter navigation)
- [x] Extract UIController (mode switching, overlays)  
- [x] Extract InputController (key handling consolidation)
- [x] Extract StateController (state updates and persistence)
- [x] Keep ReaderController as coordinator only (currently ~843 LOC; further slimming planned by pushing wrapping/window orchestration fully into services).

### 3.2 Input System Unification ✅ COMPLETE
**Issue Resolved**: All core navigation uses Domain Commands, specialized modes retain existing patterns
- [x] Route ALL reader navigation bindings to Domain::Commands (NavigationCommand) via DomainCommandBridge
- [x] Remove lambda-based input handlers for main navigation
- [x] Standardize on CommandFactory + DomainCommandBridge pattern for all core actions
- [x] Remove direct method call fallbacks for navigation commands in Input::Commands
- [x] Navigation commands (:next_page, :prev_page, :next_chapter, :prev_chapter, :scroll_up, :scroll_down) now use NavigationService through Domain layer

### 3.3 Terminal Access Elimination ✅ COMPLETE (re‑verified)
**Verified Status**: All rendering constructs surfaces via `TerminalService`. No direct `Terminal` construction remains in UI paths. `TerminalService` is now a singleton. `UI::LoadingOverlay` updated to use `terminal_service.create_surface`.
- [x] Remove direct Terminal writes from MouseableReader
- [x] Most component rendering goes through Surface/Component system
- [x] `TerminalService` abstraction exists and is used in Reader loop
- [x] ReaderController now uses `terminal_service.create_surface` (verified)
- [x] Legacy `DynamicPageCalculator` removed (replaced by `Domain::Services::PageCalculatorService`)
- [x] Remove fallbacks to `Components::Surface.new(Terminal)` in UI and modes; require injected `terminal_service`.
  - Keep `Terminal::ANSI` usage for color constants; all I/O is via `Surface`/`TerminalService`.

## Phase 4: Clean Architecture Enforcement 🚧 IN PROGRESS

### 4.1 Layer Boundary Enforcement 🚧 IN PROGRESS
```
Presentation Layer (Components)
    ↓ (Events only)
Application Layer (Unified Application)
    ↓ (Commands only)
Domain Layer (Services, Actions, Models)
    ↓ (Repository pattern)
Infrastructure Layer (StateStore, EventBus, Terminal)
```
- [ ] Enforce strict layer dependencies (components → controllers/application → domain → infrastructure)
- [ ] Remove circular/side-channel dependencies (e.g., components updating navigation state directly)
- [ ] Create clear interfaces between layers (no component-level navigation logic)
- [x] Legacy `Components::Reading::NavigationHandler` removed
- [ ] Remove cross-layer requires from components (e.g., domain/services required within components)
- [ ] Unify overlay rendering via TooltipOverlayComponent; drop legacy popup render fallbacks

### 4.2 Dependency Injection Completion ✅ MOSTLY COMPLETE
- [x] Remove direct instantiation of `EPUBDocument` in `ReaderController` (now uses `Infrastructure::DocumentService`)
- [x] All core services injected through DependencyContainer
- [x] Controllers use proper dependency injection pattern
- [ ] Create child container per EPUB load for per-book services (future enhancement)
- [ ] Add constructor parameter validation for controllers/services (future enhancement)

### 4.3 Event-Driven Architecture ❌ TODO  
- [ ] Convert ALL state mutations to events
- [ ] Make components purely reactive to state events
- [ ] Remove imperative component updates
- [ ] Add event sourcing for complex state changes

## Phase 5: EPUB Caching ✅ MOSTLY COMPLETE

Goal: Instant subsequent opens by avoiding ZIP inflation and OPF parsing; cache-backed Library view for instant startup.

### 5.1 Disk Cache Infrastructure ✅ COMPLETE
- [x] `Infrastructure::EpubCache` with SHA‑256 subdir under `${XDG_CACHE_HOME:-~/.cache}/reader/`
- [x] Copies `META-INF/container.xml`, OPF, and spine XHTML
- [x] Manifest write is atomic; MessagePack preferred, JSON fallback

### 5.2 EPUBDocument Integration ✅ COMPLETE
- [x] Cache-first load (cache dir path or hashed path)
- [x] Background population of cache on first open
- [x] Skip heavy precompute on cache hits; build page-map in background

### 5.3 Library Screen ✅ COMPLETE
- [x] Enumerates cache dirs and opens directly from cache for instant open
- [x] Uses centralized cache root path helper

### 5.4 Tests ✅ COMPLETE
- [x] Instant open from Library
- [x] Wipe cache removes disk cache, scan cache, and recent files

### 5.5 Follow-ups 🔶 OPEN
- [ ] Manifest schema version for future upgrades; bump to invalidate old schemas
- [ ] Cache validation helper (`EpubCache.validate!(dir)`) to detect missing/corrupt files and fall back safely
- [ ] Test coverage for MessagePack manifest path (write+read) and corrupt JSON/MessagePack fallbacks
- [ ] Documentation note in ARCHITECTURE.md referencing `CachePaths`

### 5.6 Instant-Open Runtime Optimizations ✅ COMPLETE
- [x] Windowed wrapping for first paint (`WrappingService#wrap_window`) to avoid full chapter wrapping
- [x] Background prefetch of ±20 pages around visible window to make immediate navigation snappy
- [x] Library→Reader open uses cache dir directly (bypasses ZIP and OPF parsing entirely)
- [x] Bookmarks and annotations load on a background thread (no delay before first frame)
- [x] Direct CLI open sets up the terminal before document load to avoid pre-frame shell delay (uses `TerminalService` session depth)
- [x] `TerminalService` and `WrappingService` are singletons to stabilize lifecycle and share caches

### 5.7 Remaining Latency Risk (to address) 🔶 OPEN
- [ ] Prefetch size configurability: expose `config.prefetch_pages` (default 20) and honor it in `ReaderController#wrapped_window_for`.
- [ ] Window cache memory: add a small LRU or cap per chapter/width to bound growth during long sessions.

## Critical Path Issues ✅ RESOLVED

### 1. Dual State Systems ✅ RESOLVED
**Location**: `core/global_state.rb` vs `infrastructure/state_store.rb`
**Solution**: Unified state system using ObserverStateStore with backward compatibility

### 2. Service Layer Confusion ✅ RESOLVED  
**Location**: `services/` vs `domain/services/` directories
**Solution**: Legacy service wrappers deleted, all references use domain services

### 3. ReaderController Complexity ✅ RESOLVED
**Location**: `reader_controller.rb` (1314→491 lines, 62% reduction)
**Solution**: God class decomposed into NavigationController, UIController, StateController, InputController

## Phase 5: Component System Standardization ✅ COMPLETE

### 5.1 Component Interface Unification ✅ COMPLETE
- [x] Convert ALL reading components to standard ComponentInterface pattern
- [x] Replace view_render(surface, bounds, controller) with do_render(surface, bounds) and render_with_context() in 6 components
- [x] Move controller access through dependency injection instead of parameter passing
- [x] Ensure all true components extend BaseComponent and implement mount/unmount lifecycle

### 5.2 Component Directory Cleanup ✅ COMPLETE  
- [x] Remove non-component classes from components/ directory:
  - NavigationHandler (deleted - unused legacy code)
  - ProgressTracker (deleted - unused legacy code)
  - ContentRenderer (deleted - unused legacy code)
  - ViewRendererFactory (kept - is actually a proper factory, updated to support new interface)

## Next Immediate Steps (Updated Priority)

**COMPLETED:** (re-verified)
1. ✅ **Component Interface Standardization** - All reading components now use standard ComponentInterface pattern
2. ✅ **State System Unification** - GlobalState class eliminated, ObserverStateStore fully implemented  
3. ✅ **Component Directory Cleanup** - Non-component classes removed from components directory
4. ✅ **Input System Unification** - All navigation commands now use Domain::Commands through NavigationService
5. ✅ **Dependency Injection Core** - EPUBDocument instantiation moved to Infrastructure::DocumentService
6. ✅ **create_view_model Error Fix** - Method visibility issue resolved, book opening now works
7. ✅ **Layer Hygiene (minor)** - Removed unused `require_relative 'annotations/annotation_store'` from MouseableReader
8. ✅ **No cross-layer requires in components** - UI components do not require domain/services directly; services resolved via DI
9. ✅ **Overlay Rendering Path** - Dropped legacy `render_with_surface` fallback; components render via `render(surface, bounds)`
10. ✅ **Annotations Mutations Centralization** - All UI/controllers use `AnnotationService`; removed store fallbacks
11. ✅ **Legacy Mode Removal** - Deleted `reader_modes/annotation_editor_mode.rb` (superseded by screen component)
12. ✅ **Debug IO Cleanup** - Removed `/tmp/nav_debug.log` writes from `PageCalculatorService`

**REMAINING PRIORITIES (Updated Priority Order):**
13. ✅ **Loading Overlay Hygiene** - `UI::LoadingOverlay` now uses `terminal_service.create_surface` (no direct `Terminal`).
14. ✅ **Persistence via Repositories Only** - Removed controller fallbacks to `ProgressManager`/`BookmarkManager`; controllers use DI repositories exclusively.
15. ✅ **Legacy Model Aliases Removed** - Deleted `lib/ebook_reader/models/bookmark*` aliases; domain models are the single source of truth.
16. ✅ **LibraryScanner Layering** - Moved `LibraryScanner` to `infrastructure/` and updated DI registration.
17. ✅ **Renderer Windowing via Service** - Reading renderers now use `WrappingService#wrap_window` directly (no controller calls) for dynamic/absolute fallbacks.

**Remaining:**
- ✅ Renderer/controller decoupling complete: renderers build context from DI + state + document, no controller calls.
1. ✅ HIGH: DI consistency in renderers (single source of services)
   - Implemented: `ViewRendererFactory` passes `controller.dependencies`; `BaseViewRenderer` now requires dependencies (no ad-hoc containers). Also switched rendered_lines to one-shot dispatch per frame from `BaseViewRenderer`.
2. ✅ HIGH: Remove unused legacy UI scaffolding
   - Implemented: deleted `lib/ebook_reader/ui/base_screen.rb` (no references remained).
3. ✅ MEDIUM: Styling consistency
   - Implemented: replaced raw `Terminal::ANSI` color codes in components with `Constants::UIConstants` (kept italics and reset codes).
4. 🔶 LOW: State API consistency (menu)
   - Verified: menu updates use `UpdateMenuAction`; keep this consistent.
5. ✅ LOW: Message timeout hygiene
   - Implemented debounced timers in `UIController#set_message` and `StateController#set_message` to avoid thread buildup.
6. ✅ HIGH: Unify menu annotation editor input
   - Verified: menu `:annotation_editor` bindings use `Domain::Commands::AnnotationEditorCommandFactory` (save/cancel/backspace/enter/insert). No inline lambdas remain for the editor.
7. ✅ LOW: Message handling centralization
   - Implemented: `Domain::Services::NotificationService` centralizes set/clear with timers; both UI and State controllers delegate.
8. ✅ LOW: Rendered lines update consistency
   - Implemented: `BaseViewRenderer` buffers rendered lines and dispatches `UpdateRenderedLinesAction` once per frame.
9. 🔶 LOW: Center-row logic unification
   - Implemented: Both dynamic and absolute renderers use `LayoutService#calculate_center_start_row`.

## Verification Notes (Claims Re‑checked)

- Phase 2.1 Service Layer Consolidation: Verified no legacy wrappers under `lib/ebook_reader/services/` for coordinate/clipboard/layout; `chapter_cache.rb` remains as an internal helper for `WrappingService`; `LibraryScanner` moved to `infrastructure/` and registered via DI.
- Phase 2.2 State System Unification: No `GlobalState` class in codebase; `:global_state` DI key resolves to `ObserverStateStore`. Some comments still mention “GlobalState”; update docs/comments only.
- Phase 3.1 ReaderController Decomposition: Done; controllers exist (`navigation/ui/state/input`), and `ReaderController` now orchestrates.
- Phase 3.2 Input System Unification: Reader navigation keys route through `DomainCommandBridge` and domain commands (verified in `Input::CommandFactory`, `Input::Commands`).
- Phase 3.3 Terminal Access Elimination: COMPLETE — all surfaces created via `TerminalService`; `UI::LoadingOverlay` uses `terminal_service.create_surface`; frame lifecycle centralized in `ReaderController` (spec verified).
- Annotation UX Fixes: ESC cancel clears selection (`UIController#cleanup_popup_state` in editor bindings). Selected text extraction uses `SelectionService` in both `UIController` and `MouseableReader` — VERIFIED.
- Annotations layering: `Components::Screens::AnnotationsScreenComponent` reads from state only (OK). `Components::Sidebar::AnnotationsTabRenderer` does not require `annotation_store` — VERIFIED. No `ReaderModes::AnnotationsMode` found — claim outdated.
- Component contract: `TooltipOverlayComponent` and `EnhancedPopupMenu` implement `do_render` (OK).
 - Popup input: `EnhancedPopupMenu` now exposes `handle_input` for consistency with component interface (delegates to existing logic).
- Singleton `PageCalculatorService`: Registered as singleton in container; used by nav/render paths.
- Terminal dimension sync: `StateStore#update_terminal_size` updates both `[:reader, :last_width/height]` and `[:ui, :terminal_width/height]`.
- Dispatcher duplication: Not present — only `Input::Dispatcher` exists (no `Infrastructure::InputDispatcher`).
- DI hygiene: `Components::TooltipOverlayComponent` injects `coordinate_service` via constructor — VERIFIED.
 - UI boundary: No component requires domain/services directly — services are accessed via DI — VERIFIED.
 - MouseableReader: No lingering direct requires of `AnnotationStore` — VERIFIED.
 - Selection/overlay duplication: Eliminated — column-bounds logic now lives in `CoordinateService`; overlay and selection extraction use it — VERIFIED.
- Annotation editor input: Reader-context editor is routed via `Domain::Commands::AnnotationEditorCommandFactory` (InputController) — VERIFIED.  
  Menu-context editor is also routed via `Domain::Commands::AnnotationEditorCommandFactory` in `MainMenu#register_annotation_editor_bindings` — VERIFIED.
- Loading UX: Previously, `MainMenu#run_reader` called `@terminal_service.cleanup` before constructing the reader, causing a flicker to the shell while large books loaded. Fixed by removing the pre-reader cleanup and making `TerminalService#setup/cleanup` idempotent (reference-counted). Menu-driven open shows inline progress during precomputation; direct CLI open runs a silent pre-build without flicker.
 - Progress identity: Previously, progress keyed by the open path failed when opening via cache dir (landing on "Cover"). Fixed by introducing `EPUBDocument#source_path` and switching persistence to use the canonical path.
 - First-frame accuracy: In dynamic mode, exact page restoration now runs immediately after the initial page-map build, not only when a background build completes.

## Phase 4: Annotations Unification 🚧 IN PROGRESS

Goal: One coherent annotations flow with strict layering (Domain Service + Actions + Selectors; UI via components only; no direct store access from UI), and a single presentation path (no duplicate modes/screens doing the same job).

### 4.1 Establish Domain AnnotationService ✅ COMPLETE (updated)
- [x] `Domain::Services::AnnotationService` implemented with `list_for_book`, `list_all`, `add`, `update`, `delete`.
- [x] Delegates to `Annotations::AnnotationStore`, dispatches `UpdateAnnotationsAction` after mutations.
- [x] Registered as `:annotation_service` in `Domain::ContainerFactory`.

### 4.2 Remove UI-store coupling; enforce component contract ✅ COMPLETE
- [x] `Components::Screens::AnnotationsScreenComponent` reads from state only (OK).
- [x] `Components::Sidebar::AnnotationsTabRenderer` uses state only — no direct store coupling.
- [x] Remove legacy `ReaderModes::AnnotationEditorMode` file to avoid confusion (superseded by screen component).
- [x] `TooltipOverlayComponent` implements `do_render` (OK).
- [x] Drop legacy popup render fallbacks; rely on component `render` (no `render_with_surface`).

### 4.3 Centralize annotation mutations through Controller+Service ✅ COMPLETE
- [x] Remove direct `AnnotationStore` fallbacks in `StateController#refresh_annotations` and MainMenu annotation actions; use `AnnotationService` exclusively.
- [x] `UIController#refresh_annotations` delegates to `state_controller.refresh_annotations` (present).
- [x] `MouseableReader#refresh_annotations` uses `AnnotationService`.

### 4.4 Selection/Overlay cohesion and cleanup ✅ COMPLETE (updated)
- [x] Selection text extraction consolidated via `SelectionService`.
- [x] `TooltipOverlayComponent` uses `do_render`; keep redraw-based invalidation and remove legacy popup fallbacks.
- [x] Lightweight tests exist for selection normalization (`SelectionService`) and popup placement (`CoordinateService`).

### 4.5 Documentation Alignment 📖 COMPLETE (updated)
- [x] Update `ARCHITECTURE.md` and README Architecture section to reflect Clean Architecture layering (Infrastructure → Domain (services, actions, selectors, commands) → Application (controllers, UnifiedApplication) → Presentation (components)).
- [x] Remove or reframe references to `ReaderModes` in docs; the editor is now a screen component and overlays are components.  
  - Verified: `DEVELOPMENT.md` already uses “Dispatcher + Screen Components”.
- [x] Ensure configuration path casing in README is `~/.config/reader` (matches `Infrastructure::StateStore::CONFIG_DIR`).
- [x] Update `DEVELOPMENT.md` Project Structure to match actual layout (`domain`, `application`, `controllers`, `components`, `infrastructure`, `input`, etc.). Current tree references `core/concerns/renderers/services` which no longer exists.
- [x] Fix DI examples in docs: avoid creating an unused container in the sample (UnifiedApplication builds its own); add concrete examples for resolving services inside components via provided dependencies.

Outcome: A single, predictable flow — UI reads from state; controllers invoke Domain services; services persist and dispatch actions; the overlay is a proper component; there is no mode/screen duplication for annotations.

## Verified Findings: Dynamic Navigation (status)

- Navigation now branches correctly on `config.page_numbering_mode` in `Domain::Services::NavigationService` and updates `[:reader, :current_page_index]` in dynamic mode.
- `:page_calculator` is a container singleton; totals are consistent between navigation and rendering.
- Terminal dimensions feed both `reader.last_*` and `ui.terminal_*`.

Conclusion: the previously listed dynamic navigation bug is resolved in code; keep an eye on edge cases but consider this item complete.

## Success Metrics

- **Code Maintainability**: Single responsibility per class
- **State Consistency**: One source of truth (StateStore only)
- **Testability**: All dependencies injectable  
- **Component Isolation**: No direct terminal access outside infrastructure
- **Input Consistency**: All user input through Domain commands

**Target Architecture**: Clean Architecture with strict layer boundaries and dependency injection throughout.
### 2.4 Legacy Controller/Module Removal ✅ COMPLETE
**Verified Status**: Legacy ReaderController and dynamic pagination module removed.
- [x] Remove `reader_controller_old.rb` — verified removed
- [x] Remove `dynamic_page_calculator.rb` — verified removed

---

## Newly Identified Follow-ups (from deep scan)

1) Reader annotations mode vestiges — RESOLVED  
   - `UIController#open_annotations` now toggles the sidebar tab; no reader `:annotations` mode or draw_screen special case remains.

2) Input controller lambdas using `instance_variable_get` — RESOLVED  
   - No remaining `instance_variable_get(:@dependencies)` patterns found in input/controller code.

3) Consistent menu state updates — PARTIAL  
   - Remaining: some lambdas still use `state.set` (e.g., menu/browse nav). Convert to dispatching `UpdateMenuAction` for consistency.

4) Architecture docs — OPEN  
   - Update `DEVELOPMENT.md` Project Structure + DI examples as noted above.

5) MainMenu/component DI hygiene — RESOLVED  
   - No direct `instance_variable_get(:@dependencies)` use found. Continue to pass dependencies explicitly where needed.

6) Component duplication — RESOLVED  
   - `Components::Screens::AnnotationsScreenComponent` has a single `normalize_list` implementation.

7) Main menu file-open duplication — COMPLETE  
  - `open_book`/`run_reader`/`handle_file_path` and `sanitize_input_path` live in `Actions::FileActions`. `MainMenu` delegates — no duplication.

8) Unused render cache — N/A  
  - No `RenderCache` exists; nothing to remove.

9) Absolute page map duplication — COMPLETE  
  - Both reader and menu use `Domain::Services::PageCalculatorService#build_absolute_page_map`.

10) Naming consistency — COMPLETE  
   - Standardized on `page_calculator` across rendering context and renderers.

11) Dead helpers in MainMenu — COMPLETE  
   - Removed `MainMenu#create_menu_navigation_commands` and `#create_browse_navigation_commands`; dispatcher registrations are explicit per mode.

12) Centralize cache paths — COMPLETE  
   - Introduced `Infrastructure::CachePaths.reader_root` and adopted it in EpubCache, Library screen, and cache wipe.
 
13) Canonicalize book identity — COMPLETE
   - Introduced `EPUBDocument#source_path` (canonical path) sourced from cache manifest `epub_path` or original `.epub` file path.
   - `StateController` now uses the canonical path for `ProgressManager` and `BookmarkManager`, ensuring restore consistency across open modes (original file vs cache dir).
   - After initial dynamic page-map build, pending progress is applied precisely for a correct first frame.
