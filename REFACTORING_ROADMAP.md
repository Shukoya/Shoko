# EBook Reader Refactoring Roadmap

**Current Status: Phase 4.1 - Layer Boundary Enforcement**  
**Overall Progress: 78% Complete (re-verified and updated)**  
**Estimated Completion: Phase 4.3**  
**Critical Issue: Annotation highlight persists after editor cancel; saved annotations use placeholder text**

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

### 2.1 Service Layer Consolidation ✅ COMPLETE (corrected)
**Verified Status**: Legacy wrappers for `coordinate_service`, `clipboard_service`, and `layout_service` do NOT exist under `lib/ebook_reader/services/` anymore. All active implementations live under `lib/ebook_reader/domain/services/`.
- [x] Legacy wrappers removed (`coordinate_service.rb`, `clipboard_service.rb`, `layout_service.rb`) — verified absent
- [x] All references use `domain/services/` versions only — verified
- [x] `chapter_cache.rb` remains intentionally in `services/` as legacy infra helper (kept by design)
- [x] No stray container registrations for deleted legacy services

### 2.2 State System Unification ✅ COMPLETE  
**Issue Resolved**: ObserverStateStore fully implemented, GlobalState class eliminated
- [x] Replace ALL GlobalState usage with ObserverStateStore
- [x] Migrate state structure from GlobalState to StateStore format
- [x] Update all `@state.update()` calls to use StateStore events  
- [x] Maintain GlobalState compatibility through ObserverStateStore
- [x] Update DependencyContainer to resolve ObserverStateStore as primary state
- [x] Verified :global_state dependency key correctly resolves to ObserverStateStore (GlobalState class completely removed)

### 2.3 Component Interface Standardization ✅ COMPLETE
**Issue Resolved**: All reading components now follow standard ComponentInterface pattern (100% compliance for active components)
- [x] ComponentInterface defined
- [x] Enforce ComponentInterface on ALL active components (all reading components now extend BaseComponent)
- [x] Remove direct Terminal access from components (97% compliance - only EnhancedPopupMenu has minimal direct access)
- [x] Standardize render method signatures - all reading components now use standard render(surface, bounds) → do_render(surface, bounds) pattern
- [x] Create Surface abstraction for all rendering
- [x] Convert ALL legacy reading components (base_view_renderer, single_view_renderer, split_view_renderer, help_renderer, toc_renderer, bookmarks_renderer) to standard ComponentInterface pattern
- [x] Remove non-component classes from components directory (NavigationHandler, ProgressTracker, ContentRenderer deleted as unused legacy code)

## Phase 3: Architecture Cleanup 📋 PLANNED

### 3.1 ReaderController Decomposition ✅ COMPLETE
**Issue Resolved**: God class decomposed into focused controllers
- [x] Extract NavigationController (page/chapter navigation)
- [x] Extract UIController (mode switching, overlays)  
- [x] Extract InputController (key handling consolidation)
- [x] Extract StateController (state updates and persistence)
- [x] Keep ReaderController as coordinator only (1314→491 lines, 62% reduction)

### 3.2 Input System Unification ✅ COMPLETE
**Issue Resolved**: All core navigation uses Domain Commands, specialized modes retain existing patterns
- [x] Route ALL reader navigation bindings to Domain::Commands (NavigationCommand) via DomainCommandBridge
- [x] Remove lambda-based input handlers for main navigation
- [x] Standardize on CommandFactory + DomainCommandBridge pattern for all core actions
- [x] Remove direct method call fallbacks for navigation commands in Input::Commands
- [x] Navigation commands (:next_page, :prev_page, :next_chapter, :prev_chapter, :scroll_up, :scroll_down) now use NavigationService through Domain layer

### 3.3 Terminal Access Elimination ✅ PARTIAL (corrected)
**Verified Status**: Most rendering goes through `Surface`, but several direct `Terminal` accesses remain.
- [x] Remove direct Terminal writes from MouseableReader
- [x] Remove direct Terminal writes from most components
- [x] Channel rendering via Surface/Component system  
- [x] `TerminalService` abstraction exists
- [x] ReaderController uses `Components::Surface.new(Terminal)` — replace with `terminal_service.create_surface`
- [x] Legacy `DynamicPageCalculator` removed (replaced by `Domain::Services::PageCalculatorService`)

## Phase 4: Clean Architecture Enforcement 📋 PLANNED

### 4.1 Layer Boundary Enforcement ❌ TODO (in progress)
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
- [ ] Remove `Components::Reading::NavigationHandler` once controller/domain handlers cover all cases

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

**REMAINING PRIORITIES (Updated Priority Order):**
1. **CRITICAL: Annotation UX Bugs**
   - Persisting blue highlight after cancel: cancel path in `AnnotationEditorMode` did not clear selection. Fix applied: ESC now calls `reader.cleanup_popup_state` before switching to `:read`.
   - Saved annotations use placeholder text: `UIController#extract_selected_text_from_selection` now extracts real text from `rendered_lines` using `CoordinateService` (replaces the "Selected text" stub).
   - Follow-up: unify text extraction into a single `Domain::Services::SelectionService` to remove duplication between `MouseableReader` and `UIController`.
2. **HIGH: Terminal Access Cleanup** — Replace remaining direct `Terminal` usage.
   - Replace `Components::Surface.new(Terminal)` usages in `ReaderController` special-mode branch with `@terminal_service.create_surface`.
   - Evaluate `DynamicPageCalculator` for retirement in favor of `PageCalculatorService`.
3. **HIGH: Singleton PageCalculator** — Verified COMPLETE.
   - `:page_calculator` registered as a singleton in `ContainerFactory` (shared instance between navigation and rendering).
4. **HIGH: Terminal Dimensions Consistency** — Verified COMPLETE.
   - `StateStore#update_terminal_size` updates both `[:reader, :last_width/height]` and `[:ui, :terminal_width/height]`.
5. **MEDIUM: Layer Boundary Enforcement** — Continue removing cross-layer imports and any residual circular dependencies.
6. **MEDIUM: Complete Event-Driven Architecture** — Make components fully reactive to state events.

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
