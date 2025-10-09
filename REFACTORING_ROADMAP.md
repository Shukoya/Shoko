# EBook Reader Refactoring Roadmap

**Current Status: Phase 4.6 - Documentation + Input Alignment**  
**Overall Progress: ~88% Complete (audited 2025-09-11, updated)**  
**Estimated Completion: Phase 4.6**  
**Status Note:** Overlay and reader input are unified; annotations flow in the reader is unified via a component. Menu annotation editor input is already routed through Domain commands. Documentation alignment is still pending—`DEVELOPMENT.md` carries stale guidance that needs updating. Terminal exit regression remains reproducible when returning from the reader via `q`; reopen the cleanup work so the shell state is restored consistently. Progress is shown inline during menu-driven open, and direct CLI open renders the same loading overlay via `Application::PaginationOrchestrator.initial_build`. Canonical book identity (`EPUBDocument#canonical_path`) ensures progress/bookmarks restore whether opening the original file or a cache dir, and the first frame lands on the saved page in dynamic mode once pagination completes. Annotation popup input is still managed via `ReaderController#activate_annotation_editor_overlay_session`; add DI validation as part of upcoming cleanup.
- 2025-10-09 Library cached reopen regression traced to `lib/ebook_reader/controllers/menu/state_controller.rb:41` retaining the prior `:document` singleton for cached paths.
- Fix primes cached launches via `ensure_reader_document_for` so each `run_reader` registers the freshly selected book before `MouseableReader` boots.
- Regression guard: `spec/integration/library_reopens_selected_book_spec.rb` asserts Library A ➝ quit ➝ B opens the new selection.

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
**Issue Resolved**: God class decomposed into focused controllers; navigation is delegated to Domain services
- [x] Navigation delegated to `Domain::Services::NavigationService` (no dedicated NavigationController)
- [x] Extract UIController (mode switching, overlays)  
- [x] Extract InputController (key handling consolidation)
- [x] Extract StateController (state updates and persistence)
- [x] Keep ReaderController primarily as a coordinator (currently ~762 LOC in the class body as of this audit); further slimming is required by moving startup/pagination orchestration fully into Application/Domain services.

### 3.2 Input System Unification ✅ COMPLETE
**Issue Resolved**: All core navigation uses Domain Commands, specialized modes retain existing patterns
- [x] Route ALL reader navigation bindings to Domain::Commands (NavigationCommand) via DomainCommandBridge
- [x] Remove lambda-based input handlers for main navigation
- [x] Standardize on CommandFactory + DomainCommandBridge pattern for all core actions
- [x] Remove direct method call fallbacks for navigation commands in Input::Commands
- [x] Navigation commands (:next_page, :prev_page, :next_chapter, :prev_chapter, :scroll_up, :scroll_down) now use NavigationService through Domain layer

### 3.3 Terminal Access Elimination 🔶 PARTIAL
**Reality Check (2025-04-XX)**: Terminal session depth is now guarded by `TerminalService.force_cleanup` and covered by `spec/integration/menu_terminal_spec.rb` (menu → reader → exit); keep an eye on field reports but the regression fix is back under test.
- [x] Balance menu ⇄ reader terminal lifecycle and add regression coverage.
- [x] Replace direct STDOUT writes in menu controllers with logger/notification based handling.
- [x] Remove direct Terminal writes from MouseableReader.
- [x] Most component rendering goes through Surface/Component system.
- [x] `TerminalService` abstraction exists and is used in Reader loop.
- [x] ReaderController now uses `terminal_service.create_surface` (verified).
- [x] Legacy `DynamicPageCalculator` removed (replaced by `Domain::Services::PageCalculatorService`).
- [x] Remove fallbacks to `Components::Surface.new(Terminal)` in UI and modes; require injected `terminal_service`.
  - Keep `Terminal::ANSI` usage for color constants; all I/O is via `Surface`/`TerminalService`.

### 3.4 Menu & Domain Consistency 🔶 OPEN
- [ ] Replace the `MainMenu` shim with an explicit façade (no `method_missing` / `instance_variable_get`); expose only the controller surface that presentation needs.
- [ ] Move menu settings + cache wiping behaviors into dedicated services so presentation components stop invoking infrastructure (`FileUtils`, repositories) directly.
- [ ] Ensure all menu interactions dispatch domain actions—eliminate remaining `state.update` calls inside menu commands/controllers in favour of explicit actions/selectors.

### 3.5 Domain Command Hygiene 🔶 OPEN
- [ ] Fix `Domain::Actions::ActionCreators#toggle_page_numbers` to read from state via selectors and add regression coverage.
- [ ] Refactor `Domain::Commands::ApplicationCommand` so helper methods live inside the class and shutdown flows are coordinated by the application layer (no direct `exit(0)` in domain code).
- [ ] Split `Input::DomainCommandBridge` mappings by context to avoid duplicate keys (`:toggle_view_mode`, etc.) and make reader vs menu bindings explicit.
- [ ] Require declared dependencies in services (e.g., `CoordinateService` → `:terminal_service`) so DI validation catches missing wiring.

### 3.6 Document Formatting Alignment 🔶 OPEN
- [ ] Trim `Infrastructure::DocumentService` back to pure document loading; delegate wrapping/formatting to `Domain::Services::FormattingService` / `WrappingService` instead of maintaining parallel caches.
- [ ] Add integration coverage for the styled formatting pipeline (LineAssembler + `wrap_window`) to lock in EPUB-driven formatting guarantees.
- [ ] Reformat and harden `FormattingService` (indentation, targeted error handling) to keep the line assembly pipeline maintainable.

### 3.7 Reader Loop Simplification 🔶 OPEN
- [ ] Replace the remaining `toc_*` / `bookmark_*` controller helpers with domain commands so navigation logic lives in one place.
- [ ] Centralise pagination/background work onto a monitored job helper (no ad-hoc `Thread.new` without lifecycle tracking).
- [ ] Audit popup/selection cleanup so UI surface relies on state + services instead of bespoke controller callbacks.

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
- [x] Removed synchronous pagination prepopulation on cached pagination load; cached books open instantly with lazy page-line population.

### 5.7 Latency Risk Follow-ups ✅ VERIFIED
- [x] Prefetch size configurability: `WrappingService#fetch_window_and_prefetch` uses `config.prefetch_pages` (default 20) from `StateStore` (`lib/ebook_reader/infrastructure/state_store.rb:205-214`).
- [x] Window cache memory: `WrappingService::WINDOW_CACHE_LIMIT` (200) bounds cached windows per chapter/width (`lib/ebook_reader/domain/services/wrapping_service.rb:18-21,162-191`).

## Code Duplication Elimination (moved)

Tracking for code duplication has moved to `RUBOCOP_OFFENSES_REFACTOR_ROADMAP.md` and is handled under the renderer unification and monolith breakdown sections. This keeps architectural and style enforcement work consolidated in a single place.

## Critical Path Issues ✅ RESOLVED

### 1. Dual State Systems ✅ RESOLVED
**Location**: `core/global_state.rb` vs `infrastructure/state_store.rb`
**Solution**: Unified state system using ObserverStateStore with backward compatibility

### 2. Service Layer Confusion ✅ RESOLVED  
**Location**: `services/` vs `domain/services/` directories
**Solution**: Legacy service wrappers deleted, all references use domain services

### 3. ReaderController Complexity ✅ RESOLVED
**Location**: `reader_controller.rb` (1314→664 lines, ~53% reduction from peak; additional slimming tracked below)
**Solution**: God class decomposed into UIController, StateController, InputController; navigation now goes through `Domain::NavigationService`

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
6. ✅ **Reader Startup Bug Fix** - `ReaderStartupOrchestrator#safe_resolve_state_controller` scoping fixed; book opening works
7. ✅ **Layer Hygiene (minor)** - Removed unused `require_relative 'annotations/annotation_store'` from MouseableReader
8. ✅ **No cross-layer requires in components** - UI components do not require domain/services directly; services resolved via DI
9. ✅ **Overlay Rendering Path** - Dropped legacy `render_with_surface` fallback; components render via `render(surface, bounds)`
10. ✅ **Annotations Mutations Centralization** - All UI/controllers use `AnnotationService`; removed store fallbacks
11. ✅ **Legacy Mode Removal** - Deleted `reader_modes/annotation_editor_mode.rb` (superseded by screen component)
12. ✅ **Debug IO Cleanup** - Removed `/tmp/nav_debug.log` writes from `PageCalculatorService`

**REMAINING PRIORITIES (Updated Priority Order):**
13. ✅ **Loading Overlay Hygiene** - Legacy `UI::LoadingOverlay` removed; replaced by `Components::Screens::LoadingOverlayComponent` (no direct `Terminal`).
14. ✅ **Persistence via Repositories Only** - Controllers use DI repositories exclusively; fallbacks removed. Repositories persist via domain file stores (no direct manager usage).
15. ✅ **Legacy Model Aliases Removed** - Deleted `lib/ebook_reader/models/bookmark*` aliases; domain models are the single source of truth.
16. ✅ **LibraryScanner Layering** - Moved `LibraryScanner` to `infrastructure/` and updated DI registration.
17. ✅ **Renderer Windowing via Service** - Reading renderers now use `WrappingService#wrap_window` directly (no controller calls) for dynamic/absolute fallbacks.
18. ✅ **Repositories Backed by Domain Stores** - Bookmark/Progress/Annotation repositories persist via domain file stores (no direct managers/stores in components/controllers).

**Remaining:**
- ✅ Renderer/controller decoupling complete: sidebar renderers resolve state/doc via injected dependencies (e.g., `Sidebar::TocTabRenderer`, `Sidebar::BookmarksTabRenderer`).
- ✅ **Annotations Overlay Integration** - Popup editor now runs in-modal: dispatcher pushes `:annotation_editor`, `Application::AnnotationEditorOverlaySession` adapts the overlay to domain commands, and reader mode remains active without leaking quit bindings.
  - 2024-10: Hardened `UIController#activate_annotation_editor_overlay_session` to fail fast when DI wiring is missing and added an integration spec asserting that the dispatcher stack keeps `:annotation_editor` on top while the modal is active.
  - 2024-11: Overlay viewport mirrors the full-screen editor (cursor-relative scrolling, top-left anchoring, snippet preview) so rendering stays consistent and the popup no longer bottom-aligns content or floods the frame background.
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
- Test harness: `spec/domain/services/terminal_service_session_spec.rb` now stubs `Terminal.setup/cleanup` via `mock_terminal` so running the suite no longer leaves the shell in the alternate screen.
- Phase 2.2 State System Unification: No `GlobalState` class in codebase; `:global_state` DI key resolves to `ObserverStateStore`. Some comments still mention “GlobalState”; update docs/comments only.
- Phase 3.1 ReaderController Decomposition: Done; controllers exist (`ui/state/input`). No dedicated `NavigationController` — input routes to `Domain::NavigationService`.
- Phase 3.2 Input System Unification: Reader navigation keys route through `DomainCommandBridge` and domain commands (verified in `Input::CommandFactory`, `Input::Commands`).
- Phase 3.3 Terminal Access Elimination: COMPLETE — all surfaces created via `TerminalService`; loading overlay is a component; frame lifecycle centralized and only accessed via `TerminalService` (components may reference `Terminal::ANSI` constants via `Constants::UIConstants`).
- Annotation UX Fixes: ESC cancel clears selection (`UIController#cleanup_popup_state` in editor bindings). Selected text extraction uses `SelectionService` in both `UIController` and `MouseableReader` — VERIFIED.
- Annotations layering: `Components::Screens::AnnotationsScreenComponent` reads from state only (OK). `Components::Sidebar::AnnotationsTabRenderer` does not require `annotation_store` — VERIFIED. No `ReaderModes::AnnotationsMode` found — claim outdated.
- Component contract: `TooltipOverlayComponent` and `EnhancedPopupMenu` implement `do_render` (OK).
- Controllers use DI repositories exclusively — VERIFIED (2025-09 recent audit). `MainMenu` file flows resolve `:recent_library_repository`, and `LibraryService#index_recent_by_path` now reads via that repository facade; no direct `RecentFiles` references remain in controllers/services.
- Popup input: `EnhancedPopupMenu` now exposes `handle_input` for consistency with component interface (delegates to existing logic).
- Singleton `PageCalculatorService`: Registered as singleton in container; used by nav/render paths.
- Terminal dimension sync: `StateStore#update_terminal_size` updates both `[:reader, :last_width/height]` and `[:ui, :terminal_width/height]`.
- Dispatcher duplication: Not present — only `Input::Dispatcher` exists (no `Infrastructure::InputDispatcher`).
- DI hygiene: `Components::TooltipOverlayComponent` injects `coordinate_service` via constructor — VERIFIED.
- UI boundary: ✅ `BrowseScreenComponent` now consumes `Domain::Services::CatalogService`; infrastructure scanner/metadata helpers are hidden behind the domain facade.
- MouseableReader: No lingering direct requires of `AnnotationStore` — VERIFIED.
 - Selection/overlay duplication: Eliminated — column-bounds logic now lives in `CoordinateService`; overlay and selection extraction use it — VERIFIED.
- Annotation editor input: Reader-context editor is routed via `Domain::Commands::AnnotationEditorCommandFactory` (InputController) — VERIFIED.  
  Menu-context editor is also routed via `Domain::Commands::AnnotationEditorCommandFactory` in `MainMenu#register_annotation_editor_bindings` — VERIFIED.
- Loading UX: Previously, `MainMenu#run_reader` called `@terminal_service.cleanup` before constructing the reader, causing a flicker to the shell while large books loaded. Fixed by removing the pre-reader cleanup and making `TerminalService#setup/cleanup` idempotent (reference-counted). Menu-driven open shows inline progress during precomputation; direct CLI open runs a silent pre-build without flicker.
 - Progress identity: Previously, progress keyed by the open path failed when opening via cache dir (landing on "Cover"). Fixed by introducing `EPUBDocument#source_path` and switching persistence to use the canonical path.
 - First-frame accuracy: In dynamic mode, exact page restoration now runs immediately after the initial page-map build, not only when a background build completes.

## Phase 2.4: Legacy Manager Cleanup ✅ COMPLETE (verified)

- Verified the following files are not present in the codebase:
  - `lib/ebook_reader/bookmark_manager.rb`
  - `lib/ebook_reader/progress_manager.rb`
  - `lib/ebook_reader/annotations/annotation_store.rb`
  - Repositories under `domain/repositories` are the single source of persistence.

## Consistency Follow-ups 🔶 OPEN

- Replace remaining direct `state.update` calls that set nested reader fields with domain actions where applicable — audited and consistent in app code; action classes use `state.update` by design (OK).
- Unify selection text extraction — COMPLETE. `SelectionService.extract_from_state` is used by both `UIController` and `MouseableReader`.
- `ReaderController#wrapped_window_for` — keep temporarily (used in specs). Plan: move to `WrappingService` or spec helper, update specs, then remove from `ReaderController`.
- ZIP import path — keep top-level `zip.rb` by design to satisfy `require 'zip'` in specs. Library code uses `require_relative 'zip'`.

## Phase 4: Annotations Unification 🚧 IN PROGRESS

Goal: One coherent annotations flow with strict layering (Domain Service + Actions + Selectors; UI via components only; no direct store access from UI), and a single presentation path (no duplicate modes/screens doing the same job).

### 4.1 Establish Domain AnnotationService ✅ COMPLETE (updated)
- [x] `Domain::Services::AnnotationService` implemented with `list_for_book`, `list_all`, `add`, `update`, `delete`.
- [x] Delegates to Domain repository (`Domain::Repositories::AnnotationRepository`) and dispatches `UpdateAnnotationsAction` after mutations.
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

### 4.5 Documentation Alignment 📖 IN PROGRESS
- [x] Update `ARCHITECTURE.md` and README Architecture section to reflect Clean Architecture layering (Infrastructure → Domain (services, actions, selectors, commands) → Application (controllers, UnifiedApplication) → Presentation (components)).
- [x] Remove or reframe references to `ReaderModes` in docs; the editor is now a screen component and overlays are components.  
  - Verified: `DEVELOPMENT.md` already uses “Dispatcher + Screen Components”.
- [x] Ensure configuration path casing in README is `~/.config/reader` (matches `Infrastructure::StateStore::CONFIG_DIR`).
- [ ] Update `DEVELOPMENT.md` Project Structure to match actual layout (`domain`, `application`, `controllers`, `components`, `infrastructure`, `input`, etc.). Current tree references removed directories.
- [x] Fix DI examples in docs: avoid creating an unused container in the sample (UnifiedApplication builds its own); add concrete examples for resolving services inside components via provided dependencies.

Outcome: A single, predictable flow — UI reads from state; controllers invoke Domain services; services persist and dispatch actions; the overlay is a proper component; there is no mode/screen duplication for annotations.

### 4.6 Loading Overlay Component ✅ COMPLETE (new)
- Converted progress overlay to a `Components::Screens::LoadingOverlayComponent` implementing `do_render(surface, bounds)`.
- `ReaderController` now renders the overlay component within its frame; removed direct calls to the module’s frame-managed renderer.

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
- **Input Consistency**: Navigation/selection keys route through Domain command objects; text input remains on dispatcher lambdas that dispatch domain actions directly

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

3) Consistent menu state updates — RESOLVED  
   - Menu/browse interactions already dispatch `UpdateMenuAction`; no remaining `state.set` in menu.

4) Architecture docs — OPEN  
   - Update `DEVELOPMENT.md` Project Structure + DI examples as noted above.

5) MainMenu/component DI hygiene — RESOLVED  
   - No direct `instance_variable_get(:@dependencies)` use found. Continue to pass dependencies explicitly where needed.

6) Component duplication — RESOLVED  
   - `Components::Screens::AnnotationsScreenComponent` has a single `normalize_list` implementation.

7) Main menu file-open duplication — ✅ COMPLETE  
  - `open_book`/`run_reader`/`handle_file_path` and `sanitize_input_path` live in `Actions::FileActions` and `handle_file_path` delegates to `run_reader(path)`. Reader-launch path is unified.

8) Unused render cache — N/A  
  - No `RenderCache` exists; nothing to remove.

9) Absolute page map duplication — COMPLETE  
  - Both reader and menu use `Domain::Services::PageCalculatorService#build_absolute_page_map`.

10) Naming consistency — COMPLETE  
   - Standardized on `page_calculator` across rendering context and renderers.

11) Dead helpers in MainMenu — ✅ COMPLETE  
   - Removed `MainMenu#create_menu_navigation_commands`, `#create_browse_navigation_commands`, and the unused `register_recent_bindings` method.

12) Centralize cache paths — COMPLETE  
   - Introduced `Infrastructure::CachePaths.reader_root` and adopted it in EpubCache, Library screen, and cache wipe.
 
13) Canonicalize book identity — COMPLETE
   - Introduced `EPUBDocument#source_path` (canonical path) sourced from cache manifest `epub_path` or original `.epub` file path.
  - `StateController` now uses the canonical path via repositories, ensuring restore consistency across open modes (original file vs cache dir).
   - After initial dynamic page-map build, pending progress is applied precisely for a correct first frame.

14) DocumentService DI boundary — ✅ COMPLETE  
   - `Infrastructure::DocumentService` now accepts an injected `wrapping_service`.  
   - Added `:document_service_factory` to the container; all callers use the factory to create per-book instances.

15) Remove unused presenter — ✅ COMPLETE  
   - Deleted `presenters/reader_presenter.rb` and removed its usage from `ReaderController`.

16) Single navigation path — ✅ COMPLETE  
   - Removed `Controllers::NavigationController` and all delegations. Input routes to `Domain::NavigationService` exclusively.

17) Renderer helper factoring — ✅ COMPLETE  
   - Introduced `BaseViewRenderer#draw_lines` and updated Single/Split renderers to use it, reducing duplication.

18) Pagination orchestration helpers — ✅ COMPLETE
  - Added `PageCalculatorService#build_dynamic_map!`, `#build_absolute_map!`, and `#apply_pending_precise_restore!`.
  - `ReaderController` uses these consistently for initial build, rebuild, background build, and updates.

19) Legacy search actions — ✅ COMPLETE (2025-02-18)
  - Removed `MainMenu::Actions::SearchActions`, which still referenced the deprecated `@input_handler` and caused `NoMethodError` when `delete_selected_item` delegations fired.

20) Recent-files persistence boundary — ✅ COMPLETE (2025-02-18)
  - Added `Domain::Repositories::RecentLibraryRepository` and wired MainMenu + LibraryService through DI, removing direct `RecentFiles` references from presentation/services.

21) List rendering helpers — ✅ COMPLETE (2025-02-18)
  - Introduced `Components::UI::ListHelpers` and adopted it in browse/library/sidebar/annotations screens to share pagination logic and reduce duplication.

---

## Refactor Addendum (2025-09-11)

- ✅ Reader startup orchestration no longer uses reflection. Added explicit public APIs on `ReaderController` (`pending_initial_calculation?`, `perform_initial_calculations_if_needed`, `defer_page_map?`, `schedule_background_page_map_build`, `clear_defer_page_map!`). `ReaderStartupOrchestrator` now calls these directly.
- ✅ Frame lifecycle unified for menu and reader. `MainMenu#draw_screen` now renders via `Application::FrameCoordinator#with_frame`. Terminal size updates are centralized in `FrameCoordinator` during rendering.
- ✅ Component dependency naming unified. `BaseComponent` now exposes `@dependencies` (not `@services`); updated `LibraryScreenComponent` accordingly.
- ✅ Duplicate rendered-lines clearing removed from `MouseableReader#draw_screen`. Clearing now occurs centrally in the render pipeline.
- ✅ Extracted `Internal::LayoutMetricsCalculator` from `PageCalculatorService` to encapsulate column/line calculations and reduce method complexity.

### Code Duplication Elimination — Status and Plan (audited 2025-09-11)

Current measurement (reek DuplicateMethodCall): 144 warnings across 52 files (as of latest run).

Completed (true, confirmed):
- ✅ Shared UI helpers extracted to remove duplication in screens
  - `Components::UI::BoxDrawer#draw_box` used by annotation screens and detail view.
  - `Components::UI::TextUtils#wrap_text`, `#truncate_text` used by annotation and browse screens.
- ✅ Storage/util helpers
  - `Domain::Repositories::Storage::FileStoreUtils.load_json_or_empty` dedupes JSON loads in file stores.
  - `Infrastructure::SerializerSupport.msgpack_available?` used by EpubCache and PaginationCache.
- ✅ Domain event deduplication
  - Introduced `BookmarkEventBase` and made `BookmarkAdded/Removed/Navigated` inherit to eliminate triplicated initializers.
- ✅ Action deduplication
  - Added `Domain::Actions::UpdateFieldHelpers.apply_allowed` and used in pagination/meta actions.
- ✅ MainMenu duplication reductions
  - Added binding helpers: `add_back_bindings`, `add_confirm_bindings`, `add_nav_up_down` and applied across register_* methods.
  - Localized repeated state and scanner access in `handle_backspace_input`, `process_scan_results_if_available`.
  - Normalized annotation id/note handling in open/edit/delete flows.
- ✅ Services/controllers local caching to reduce repeated method calls
  - `NavigationService`, `PageCalculatorService#get_page`, `WrappingService#wrap_window/fetch_window_and_prefetch`.
  - `ReaderController` page calculations and pending jump; `StateController` bookmark flows.

Pending (single best path):
1) Input::CommandFactory (16 warnings)
   - Extract small internal helpers for repeated dispatch patterns:
     - `dispatch_menu(field, value)`, `dispatch_selection(field, value)`, `dispatch_sidebar(field, value)`.
   - Cache `current` and `cursor` locals inside `text_input_commands` branches; factor common `KeyDefinitions` lookups into locals.
   - Acceptance: warnings for file drop to ≤ 5.

2) MainMenu::Actions::FileActions (7 warnings)
   - Centralize progress fraction computation `progress = done.to_f / [total, 1].max`.
   - Extract builder for large `UpdateMenuAction` payloads used during progress updates.
   - Restructure flow to avoid repeated `run_reader(path)` by single exit point.

3) Selection/Overlay path (TooltipOverlayComponent, CoordinateService, SelectionService)
   - Cache `start_pos`/`end_pos` members and highlight `bounds[:start]/[:end]` in locals within loops.
   - Replace repeated equality checks with booleans stored once per iteration.

4) Sidebar and reading components (medium clusters)
   - Consistently cache `bounds.x/y/width/height` and per-item ctx fields inside list renderers (toc, bookmarks, annotations tab), reducing repeated calls.
   - Where heavily repeated in a single method, use a local `write_primary(surface, bounds, row, col, text)` helper to factor string composition once (kept file-local, no cross-module dependency).

5) State stores (low risk)
   - `StateStore`/`ObserverStateStore`: cache `arr = Array(path)` and similar within methods where reek flags repeated `Array(path)` or `get_nested_value` inputs.

6) Acceptable residuals (no change planned)
   - Tiny, readability-friendly duplicates such as `render_with_context` branching in renderers, arithmetic (+2/−2) in split navigation, and the in-repo `lib/zip.rb` shim.

7) Input key read-loop duplication
   - Unify `read_input_keys`/drain-extra-keys logic used in `ReaderController` and `MainMenu` into a single helper (e.g., `TerminalService#read_keys_blocking`), keeping mouse-aware paths in `MouseableReader`.

Milestones
- M1: Finish Input::CommandFactory refactor; drop ≈ 10–12 warnings. (In progress; −3 achieved)
- M2: MainMenu::FileActions refactor; drop ≈ 5–7 warnings. (In progress; −3 achieved)
- M3: Selection/Overlay locals; drop ≈ 10–15 warnings. (In progress; initial reductions applied)
- M4: Sidebar/reading components locals; drop ≈ 20–30 warnings. (In progress; initial reductions applied)
- Target: reduce DuplicateMethodCall warnings to ≤ 200 without sacrificing readability or introducing risk.
- 2025-10-09: Resolved browse-library reopen bug by always registering the active document when skipping the progress overlay (`lib/ebook_reader/controllers/menu/state_controller.rb`:46-92). Added `spec/integration/browse_skip_overlay_spec.rb` to guard the regression. Risk: future refactors must keep per-open document registration intact when toggling `READER_SKIP_PROGRESS_OVERLAY`.

---

## Phase 5: EPUB Formatting Modernization 🚧 PLANNED

### 5.1 Structured XHTML parsing ✅ COMPLETE
- [x] Add `Domain::Models::ContentBlock` and `TextSegment` (or similar) to capture semantic structure (headings, paragraphs, lists, quotes, pre/code) without exposing raw HTML to renderers.
- [x] Implement `Infrastructure::Parsers::XHTMLContentParser` (REXML-backed) to walk XHTML spine entries and emit normalized content blocks, preserving ordering, list hierarchy, and inline emphasis metadata.

### 5.2 Formatting service integration ✅ COMPLETE
- [x] Introduce `Domain::Services::FormattingService` that coordinates XHTML parsing, block normalization, and caching. Service becomes the single entry point for text shaping and is registered in the container.
- [x] Update `EPUBDocument`/`DocumentService` to prefer the formatting service over legacy `Helpers::HTMLProcessor.html_to_text`, while retaining the HTML scrubber as a fallback to populate plain `lines` when formatting fails.

### 5.3 Renderer alignment ✅ COMPLETE
- [x] Extend `Components::Reading::BaseViewRenderer` with helpers to render content blocks (headings, paragraphs, lists, block quotes, code) using terminal-friendly styling while respecting Clean Architecture boundaries.
- [x] Create lightweight segment renderer that applies ANSI styling at render time so wrapping logic operates on plain text metrics.
- [x] Update single/split view renderers and sidebar preview components to consume formatted blocks consistently.

### 5.4 Wrapping + measurement upgrades ✅ COMPLETE
- [x] Enhance wrapping pipeline to operate on formatted content blocks using display-length calculations that ignore ANSI escape sequences and respect indentation/bullet prefixes.
- [x] Provide shared utility (`Helpers::TextMetrics.visible_length`/`truncate_to`) to keep string-width calculations consistent across services and renderers.

### 5.5 Quality gates ✅ COMPLETE
- [x] Add unit tests covering XHTML samples (headings, nested lists, block quotes, code blocks, inline emphasis) to lock in parser output.
- [x] Add integration specs for reader rendering to verify spacing, bullet alignment, and code-block monospace styling across terminal widths.
- [x] Document the new formatting pipeline in `ARCHITECTURE.md` and `DEVELOPMENT.md`, including extension guidance for new block types.
