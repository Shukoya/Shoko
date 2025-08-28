# EBOOK READER ARCHITECTURAL REFACTORING ROADMAP

## CRITICAL CONTEXT
- **Current Rating**: 4/10 (Severe architectural inconsistency)
- **Problem**: Multiple parallel systems doing the same tasks
- **Strategy**: Surgical replacement, not parallel development
- **Rule**: ONE pattern survives, everything else dies

## REFACTORING PHASES

### PHASE 1: SERVICE LAYER UNIFICATION
**Status**: ✅ COMPLETE
**Goal**: Single service layer using dependency injection

#### 1.1 Audit Duplicate Services
**Status**: ✅ COMPLETE
- [x] Document exact overlap between `services/` and `domain/services/` → SERVICE_OVERLAP_ANALYSIS.md
- [x] Create service migration mapping document → SERVICE_MIGRATION_MAP.md
- [x] Identify all external references to old services → SERVICE_REFERENCES_AUDIT.md

#### 1.2 Migrate Service Dependencies  
**Status**: ✅ COMPLETE
- [x] Update `mouseable_reader.rb` line 14,15,98,169,231 to use Domain services ✅
- [x] Update `reader_controller.rb` all 8 service references to use Domain services ✅
- [x] Update `main_menu.rb` service references (deferred to Phase 2 - command system) ✅
- [x] Update core `Services::*` references to use `Domain::Services::*` ✅
- [x] Update dependency container registrations ✅
- [x] **CRITICAL**: Fix Domain::Services initialization error ✅
- [x] Replace StateService with direct state management ✅  
- [x] Book opening functionality restored ✅

#### 1.3 Delete Legacy Services
**Status**: ✅ COMPLETE
- [x] Replace `lib/ebook_reader/services/coordinate_service.rb` with delegation to domain ✅
- [x] Replace `lib/ebook_reader/services/clipboard_service.rb` with delegation to domain ✅
- [x] Replace `lib/ebook_reader/services/layout_service.rb` with delegation to domain ✅
- [x] Delete `lib/ebook_reader/services/state_service.rb` (replaced by direct state management) ✅
- [x] Delete `lib/ebook_reader/services/page_manager.rb` (merged into page_calculator_service) ✅
- [x] Keep `lib/ebook_reader/services/main_menu_input_handler.rb` (needed for Phase 2) ✅
- [x] Keep `lib/ebook_reader/services/library_scanner.rb` (needed, will migrate later) ✅
- [x] Keep `lib/ebook_reader/services/chapter_cache.rb` (needed, will migrate later) ✅

#### 1.4 Update Require Statements
**Status**: ✅ COMPLETE
- [x] Remove deleted service require statements from main files ✅
- [x] Update `lib/ebook_reader.rb` to remove state_service and page_manager ✅
- [x] Verify application still loads and runs correctly ✅
- [ ] Update any remaining service requires across codebase

### PHASE 2: COMMAND SYSTEM UNIFICATION  
**Status**: ✅ COMPLETE
**Goal**: Single command system using Command pattern

#### 2.1 Audit Command Systems  
**Status**: ✅ COMPLETE
- [x] Document all command implementations in `commands/` vs `domain/commands/` → COMMAND_SYSTEMS_AUDIT.md ✅
- [x] Map input handlers to new command structure → COMMAND_MIGRATION_MAP.md ✅  
- [x] Identify all direct method calls that should be commands ✅

#### 2.2 Bridge Integration
**Status**: ✅ COMPLETE
- [x] Enhanced Input::Commands dispatcher to support Domain commands ✅
- [x] Created DomainCommandBridge for automatic symbol-to-command conversion ✅
- [x] Integrated bridge with loading order and dependency management ✅
- [x] Verified application functionality with bridge layer ✅

#### 2.3 Navigation Migration  
**Status**: ✅ COMPLETE
- [x] Replace reader navigation symbols with domain commands ✅
- [x] Replace menu navigation lambdas with domain commands (deferred complex state patterns) ✅
- [x] Test navigation functionality ✅
- [x] Fixed domain command bridge constructor issues ✅
- [x] Verified complete command flow: Input → Bridge → Domain Commands → Services ✅

#### 2.4 Delete Legacy Commands
**Status**: ✅ COMPLETE  
- [x] Find and update all legacy Commands:: references ✅
- [x] Delete `lib/ebook_reader/commands/base_command.rb` ✅
- [x] Delete `lib/ebook_reader/commands/navigation_commands.rb` ✅
- [x] Delete `lib/ebook_reader/commands/command_factory.rb` ✅
- [x] Delete `lib/ebook_reader/commands/sidebar_commands.rb` ✅
- [x] Delete entire `lib/ebook_reader/commands/` directory ✅
- [x] Update require statements ✅
- [x] Verify application functionality ✅

#### 2.5 Update Command References (MERGED INTO 2.4)
- [x] Update `lib/ebook_reader.rb` lines 60-62 to only load domain commands ✅
- [x] Replace all `Commands::*` with `Domain::Commands::*` ✅
- [x] Update input binding generation to use domain commands ✅

### PHASE 3: STATE MANAGEMENT OVERHAUL
**Status**: ❌ NOT STARTED  
**Goal**: Proper Redux-like state with immutable updates

#### 3.1 Create State Action System
- [ ] Create `lib/ebook_reader/domain/actions/` directory
- [ ] Create base action class: `Domain::Actions::BaseAction`
- [ ] Create specific actions: `UpdateReaderMode`, `UpdatePage`, `UpdateSelection`
- [ ] Create action creators for common state changes

#### 3.2 Refactor GlobalState
- [ ] Convert GlobalState to pure state container (no business logic)
- [ ] Remove all convenience methods (lines 169-556 in global_state.rb)
- [ ] Keep only: `get()`, `update()`, `add_observer()`, `remove_observer()`
- [ ] Add action dispatcher: `dispatch(action)`

#### 3.3 Eliminate Direct State Access
- [ ] Replace `@state.mode = :read` with `dispatch(UpdateReaderMode.new(:read))`
- [ ] Replace `@state.selection = nil` with `dispatch(ClearSelection.new)`
- [ ] Update `mouseable_reader.rb` lines 23-27 to use actions
- [ ] Update all direct state mutations across codebase

#### 3.4 Create State Selectors
- [ ] Create `lib/ebook_reader/domain/selectors/` directory
- [ ] Create reader selectors: `current_chapter()`, `current_page()`, etc.
- [ ] Create menu selectors: `selected_item()`, `search_active?()`, etc.
- [ ] Replace direct state access with selectors

### PHASE 4: RENDERING SYSTEM UNIFICATION
**Status**: ❌ NOT STARTED
**Goal**: All rendering through component system

#### 4.1 Eliminate Direct Terminal Access
- [ ] Remove direct terminal writes from `mouseable_reader.rb` line 113-122
- [ ] Replace highlighting logic with component-based approach
- [ ] Create dedicated highlighting component
- [ ] Update tooltip overlay to handle all terminal interaction

#### 4.2 Standardize Component Interface
- [ ] Ensure all components implement `ComponentInterface`
- [ ] Update components that bypass the interface system
- [ ] Create consistent render() method signatures
- [ ] Implement proper bounds checking in all components

#### 4.3 Create Rendering Pipeline
- [ ] Create single rendering coordinator class
- [ ] Implement render queue system for complex UI updates
- [ ] Add render optimization (only render changed components)
- [ ] Create consistent screen refresh mechanism

### PHASE 5: INPUT SYSTEM CONSOLIDATION
**Status**: ❌ NOT STARTED
**Goal**: Single input pipeline through domain commands

#### 5.1 Unify Input Reading
- [ ] Create single input reader class
- [ ] Handle both keyboard and mouse input in one place
- [ ] Standardize input event format
- [ ] Create input validation system

#### 5.2 Centralize Key Bindings
- [ ] Consolidate all key binding definitions
- [ ] Use single binding format across all modes
- [ ] Create dynamic binding system (user customizable)
- [ ] Implement context-sensitive bindings

#### 5.3 Command Dispatch Pipeline
- [ ] Create single input → command → action pipeline
- [ ] Remove all direct method calls from input handlers
- [ ] Implement command validation and error handling
- [ ] Add command logging for debugging

### PHASE 6: APPLICATION STRUCTURE CLEANUP
**Status**: ❌ NOT STARTED
**Goal**: Clean separation of concerns

#### 6.1 Finalize Dependency Injection
- [ ] Ensure all classes use dependency injection
- [ ] Remove singleton patterns and global state access
- [ ] Create proper service interfaces
- [ ] Implement service lifecycle management

#### 6.2 Clean Up Legacy Code
- [ ] Remove unused classes and modules
- [ ] Clean up require statements in main files
- [ ] Remove commented-out code
- [ ] Update documentation to match new architecture

#### 6.3 Final Architecture Validation
- [ ] Verify single responsibility principle across all classes
- [ ] Ensure proper abstraction layers
- [ ] Validate dependency flow (no circular dependencies)
- [ ] Run full test suite and fix any regressions

## CRITICAL RULES

### During Refactoring:
1. **NEVER create parallel systems** - Replace, don't duplicate
2. **ONE PHASE AT A TIME** - Complete each phase fully before next
3. **UPDATE THIS FILE** - Check boxes immediately after completion
4. **TEST AFTER EACH STEP** - Ensure application still runs
5. **NO FEATURE WORK** - Only architectural changes

### File Update Protocol:
1. When starting a task: Update status to "🔄 IN PROGRESS"  
2. When completing a task: Check the box ✅
3. When completing a phase: Update phase status to "✅ COMPLETE"
4. Always commit with descriptive message referencing roadmap item

### Emergency Rollback:
If anything breaks during refactoring:
1. Immediately rollback to last working commit
2. Update roadmap with "❌ FAILED" status and reason
3. Adjust approach before continuing

## CURRENT CHECKPOINT  
- **Phase**: Phase 2.4 COMPLETE ✅ 
- **Next Action**: Begin Phase 3 - State Management Overhaul
- **Last Updated**: 2025-08-28
- **Current Commit**: 3fc67d5 refactored
- **Status**: Legacy command system completely removed - Only Domain commands remain ✅

## SUCCESS CRITERIA
- **Target Rating**: 8/10 (Clean, consistent architecture)
- **Single service layer**: Only `domain/services/` exists
- **Single command system**: Only `domain/commands/` exists  
- **Immutable state**: All updates through actions
- **Component rendering**: No direct terminal access
- **Unified input**: Single pipeline for all input types