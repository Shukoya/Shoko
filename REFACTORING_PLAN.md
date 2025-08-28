# READER REFACTORING EXECUTION PLAN
# Version: 1.0
# Status: IN_PROGRESS
# Current Phase: SETUP

## CRITICAL RULES
1. **NEVER skip steps** - each must be completed in exact order
2. **NEVER leave broken code** - each step must compile and run
3. **ALWAYS commit** after each completed step
4. **ALWAYS run tests** after each step (if they exist)
5. **NEVER modify multiple files simultaneously** unless explicitly stated

## OVERVIEW
- **Total Steps**: 47
- **Estimated Time**: 3 weeks
- **Current Step**: 0 (Setup)
- **Status**: Starting refactoring execution

---

# PHASE 1: FOUNDATION CLEANUP (Steps 1-15)
**Goal**: Remove architectural dualities, establish single source of truth

## Step 1: Create Backup Branch ❌
**Status**: NOT_STARTED
**Files**: None (Git operation)
**Action**: 
```bash
git checkout -b refactor-backup
git checkout main
git checkout -b architecture-refactor
```
**Test**: `git branch --list` shows both branches exist
**Commit**: "Create refactoring branches"

## Step 2: Remove CLI Dual Architecture ❌
**Status**: NOT_STARTED  
**File**: `lib/ebook_reader/cli.rb`
**Current Lines**: 14-18
**Action**: Replace conditional logic with single architecture
**Before**:
```ruby
if args.first
  Application::ReaderApplication.new(args.first).run
else  
  MainMenu.new.run
end
```
**After**:
```ruby
UnifiedApplication.new(args.first).run
```
**Test**: `bin/ebook_reader` and `bin/ebook_reader file.epub` both work
**Commit**: "Remove CLI dual architecture"

## Step 3: Create UnifiedApplication Class ❌
**Status**: NOT_STARTED
**File**: `lib/ebook_reader/application/unified_application.rb` (NEW FILE)
**Dependencies**: 
- `lib/ebook_reader/domain/dependency_container.rb`
- `lib/ebook_reader/application/reader_application.rb`
- `lib/ebook_reader/main_menu.rb`
**Action**: Create class that handles both scenarios
```ruby
module EbookReader
  module Application  
    class UnifiedApplication
      def initialize(epub_path = nil)
        @epub_path = epub_path
        @dependencies = Domain::ContainerFactory.create_default_container
      end
      
      def run
        if @epub_path
          reader_mode
        else
          menu_mode  
        end
      end
      
      private
      
      def reader_mode
        ReaderApplication.new(@epub_path, dependencies: @dependencies).run
      end
      
      def menu_mode
        # Will be replaced with new menu architecture in Step 8
        MainMenu.new.run
      end
    end
  end
end
```
**Test**: Both scenarios work through new class
**Commit**: "Add UnifiedApplication"

## Step 4: Update CLI to Use UnifiedApplication ❌  
**Status**: NOT_STARTED
**File**: `lib/ebook_reader/cli.rb`
**Action**: Update require and method call
**Before**: Lines 14-18 (conditional logic)
**After**: `Application::UnifiedApplication.new(args.first).run`
**Add Require**: `require_relative 'application/unified_application'` at line 14
**Test**: CLI works for both scenarios
**Commit**: "Update CLI to use UnifiedApplication"

## Step 5: Update Main Loader ❌
**Status**: NOT_STARTED  
**File**: `lib/ebook_reader.rb`
**Action**: Add require for unified_application
**Line**: Add after line 85: `require_relative 'ebook_reader/application/unified_application'`
**Test**: No load errors
**Commit**: "Add unified_application to main loader"

## Step 6: Remove StateStore/GlobalState Duality - Analysis ❌
**Status**: NOT_STARTED
**Files**: 
- `lib/ebook_reader/core/global_state.rb` (697 lines - TO DELETE)
- `lib/ebook_reader/infrastructure/state_store.rb` (KEEP)
**Action**: Identify all GlobalState usage
**Command**: 
```bash
grep -r "GlobalState" lib/ --include="*.rb"
grep -r "Core::GlobalState" lib/ --include="*.rb"  
```
**Document**: List all files using GlobalState in this step's notes
**Test**: Commands complete successfully
**Commit**: "Document GlobalState usage for removal"

## Step 7: Replace GlobalState in ReaderApplication ❌
**Status**: NOT_STARTED
**File**: `lib/ebook_reader/application/reader_application.rb`
**Action**: Already uses StateStore - verify no GlobalState references
**Check**: Grep for `GlobalState` in this file - should be empty
**Test**: File loads without GlobalState dependencies
**Commit**: "Verify ReaderApplication uses StateStore only"

## Step 8: Create New Menu Architecture ❌
**Status**: NOT_STARTED
**File**: `lib/ebook_reader/application/menu_application.rb` (NEW FILE)
**Dependencies**: StateStore, not GlobalState
**Action**: Create StateStore-based menu system
```ruby
module EbookReader
  module Application
    class MenuApplication
      def initialize(dependencies = nil)
        @dependencies = dependencies || Domain::ContainerFactory.create_default_container
        setup_initial_state
      end
      
      def run
        # StateStore-based menu implementation
      end
      
      private
      
      def setup_initial_state
        @dependencies.resolve(:state_store).update({
          [:menu, :mode] => :main,
          [:menu, :selected] => 0
        })
      end
    end
  end
end
```
**Test**: Class loads and instantiates
**Commit**: "Add StateStore-based MenuApplication"

## Step 9: Update UnifiedApplication to Use New Menu ❌
**Status**: NOT_STARTED
**File**: `lib/ebook_reader/application/unified_application.rb`
**Action**: Replace MainMenu.new.run with MenuApplication
**Before**: `MainMenu.new.run`
**After**: `MenuApplication.new(@dependencies).run`
**Add Require**: `require_relative 'menu_application'`
**Test**: Menu mode works through new architecture
**Commit**: "Switch UnifiedApplication to new menu architecture"

## Step 10: Remove MainMenu Class Usage ❌
**Status**: NOT_STARTED
**Files**: Find all MainMenu references
**Command**: `grep -r "MainMenu" lib/ --include="*.rb"`
**Action**: Document all usages - prepare for removal
**Test**: Grep command completes
**Commit**: "Document MainMenu usage for removal"

## Step 11: Remove ReaderController - Analysis ❌
**Status**: NOT_STARTED  
**File**: `lib/ebook_reader/reader_controller.rb` (1,011 lines - TO DELETE)
**Command**: `grep -r "ReaderController" lib/ --include="*.rb"`
**Action**: Document all ReaderController references
**Test**: Grep completes successfully
**Commit**: "Document ReaderController usage for removal"

## Step 12: Remove MouseableReader Inheritance ❌
**Status**: NOT_STARTED
**File**: `lib/ebook_reader/mouseable_reader.rb`
**Current**: `class MouseableReader < ReaderController`
**Problem**: Cannot delete ReaderController while this exists
**Action**: Refactor MouseableReader to use composition instead of inheritance
**After**: `class MouseableReader` (standalone)
**Test**: MouseableReader can instantiate independently  
**Commit**: "Remove MouseableReader inheritance from ReaderController"

## Step 13: Extract Mouse Functionality to Service ❌
**Status**: NOT_STARTED
**File**: `lib/ebook_reader/domain/services/mouse_service.rb` (NEW FILE)
**Source**: Extract mouse handling logic from MouseableReader
**Action**: Create service for mouse interactions using DI pattern
```ruby
module EbookReader
  module Domain
    module Services
      class MouseService
        def initialize(dependencies)
          @dependencies = dependencies
        end
        
        def handle_mouse_event(event)
          # Extract logic from MouseableReader
        end
      end
    end
  end
end
```
**Test**: Service instantiates and has basic structure
**Commit**: "Add MouseService with DI pattern"

## Step 14: Remove Legacy Command System ❌
**Status**: NOT_STARTED
**Files**: 
- `lib/ebook_reader/commands/base_command.rb` (TO DELETE)
- `lib/ebook_reader/commands/navigation_commands.rb` (TO DELETE)  
- `lib/ebook_reader/commands/command_factory.rb` (TO DELETE)
**Action**: First ensure domain commands handle all functionality
**Check**: `lib/ebook_reader/domain/commands/` has equivalent functionality
**Test**: Domain command system is complete
**Commit**: "Verify domain commands replace legacy commands"

## Step 15: Phase 1 Validation ❌
**Status**: NOT_STARTED
**Action**: Comprehensive test of Phase 1 changes
**Tests**:
1. `bin/ebook_reader` opens menu successfully
2. `bin/ebook_reader file.epub` opens reader successfully  
3. No GlobalState references remain in active code
4. No ReaderController inheritance exists
5. All requires resolve successfully
**Command**: `ruby -c lib/ebook_reader.rb` (syntax check)
**Commit**: "Phase 1 complete - foundation cleanup validated"

---

# PHASE 2: SERVICE CONSOLIDATION (Steps 16-31)
**Goal**: Standardize all services to use DI pattern, remove service duplication

## Step 16: Standardize Service Base Class ❌
**Status**: NOT_STARTED
**File**: `lib/ebook_reader/domain/services/base_service.rb` (NEW FILE)
**Action**: Create standard base class for all services
**Dependencies**: DependencyContainer
**Test**: Base class loads and can be inherited from
**Commit**: "Add BaseService with DI pattern"

## Step 17: Migrate NavigationService ❌  
**Status**: NOT_STARTED
**File**: `lib/ebook_reader/domain/services/navigation_service.rb`
**Action**: Ensure inherits from BaseService, follows DI pattern
**Current**: Already well-structured
**Verify**: Uses injected dependencies, not direct instantiation
**Test**: Service works with new base class
**Commit**: "Validate NavigationService follows DI pattern"

## Step 18: Migrate BookmarkService ❌
**Status**: NOT_STARTED  
**File**: `lib/ebook_reader/domain/services/bookmark_service.rb`
**Action**: Ensure inherits from BaseService
**Test**: Bookmark operations work through DI
**Commit**: "Validate BookmarkService follows DI pattern"

## Step 19: Remove Legacy Services Directory ❌
**Status**: NOT_STARTED
**Files**: `lib/ebook_reader/services/` (ENTIRE DIRECTORY TO DELETE)
**Action**: First migrate needed services to domain/services
**Services to Migrate**:
- `clipboard_service.rb` → `domain/services/clipboard_service.rb`
- `coordinate_service.rb` → `domain/services/coordinate_service.rb`
- `layout_service.rb` → `domain/services/layout_service.rb`
**Test**: All needed services migrated to domain layer
**Commit**: "Prepare legacy services for removal"

## Step 20-24: Individual Service Migrations ❌
**Status**: NOT_STARTED
**Pattern**: Each service gets individual migration step
**Files**: One service per step, following DI pattern
**Test**: Each service works independently with DI
**Commits**: "Migrate [ServiceName] to domain layer with DI"

## Step 25: Update Service Registry ❌  
**Status**: NOT_STARTED
**File**: `lib/ebook_reader/domain/dependency_container.rb`
**Action**: Register all migrated services
**Test**: All services resolve through container
**Commit**: "Register all services in dependency container"

## Step 26-30: Remove Legacy Service Files ❌
**Status**: NOT_STARTED  
**Action**: Delete old service files after migration
**Test**: No broken requires, all services resolve
**Commits**: "Remove legacy [ServiceName]"

## Step 31: Phase 2 Validation ❌
**Status**: NOT_STARTED
**Action**: All services use DI, no legacy services remain
**Test**: Complete application functionality through new services
**Commit**: "Phase 2 complete - service consolidation validated"

---

# PHASE 3: COMPONENT STANDARDIZATION (Steps 32-47)
**Goal**: Standardize component architecture, eliminate direct terminal writes

## Step 32: Create Component Interface ❌
**Status**: NOT_STARTED
**File**: `lib/ebook_reader/components/component_interface.rb` (NEW FILE)
**Action**: Define standard component contract
**Test**: Interface can be included by components
**Commit**: "Add ComponentInterface standard"

## Step 33-40: Component Migrations ❌
**Status**: NOT_STARTED
**Pattern**: Each major component system gets standardized
**Test**: Each component follows interface contract  
**Commits**: "Standardize [ComponentName] interface"

## Step 41: Remove Direct Terminal Writes ❌
**Status**: NOT_STARTED
**Action**: Find and eliminate all direct Terminal calls outside components
**Command**: `grep -r "Terminal\." lib/ --include="*.rb"`
**Test**: All terminal interaction through components
**Commit**: "Remove direct terminal writes"

## Step 42-46: Component Tree Implementation ❌
**Status**: NOT_STARTED
**Action**: Implement hierarchical component system
**Test**: Components render in tree structure
**Commits**: Individual component tree steps

## Step 47: Final Validation ❌
**Status**: NOT_STARTED
**Action**: Complete architectural validation
**Tests**: 
1. No legacy architecture remains
2. All interactions through DI
3. All rendering through components
4. Clean separation of concerns
**Commit**: "Complete architecture refactor"

---

# ROLLBACK PROCEDURES
## If Any Step Fails:
1. `git checkout main`  
2. `git branch -D architecture-refactor`
3. Review step requirements
4. `git checkout -b architecture-refactor-v2`

## Emergency Rollback:
1. `git checkout refactor-backup`
2. `git checkout -b main-restore`
3. Continue from there

---

# NEXT SESSION INSTRUCTIONS
1. **Read this file first** - check current status
2. **Find first ❌ step** - start from there
3. **Complete EXACTLY as specified** - no shortcuts
4. **Update status to ✅** when step complete
5. **Commit with exact commit message**
6. **Run tests before moving to next step**

---

# CURRENT STATUS SUMMARY
- **Phase**: 1 (Foundation Cleanup)  
- **Next Step**: Step 1 (Create Backup Branch)
- **Files Modified**: 0
- **Commits Made**: 0
- **Estimated Time Remaining**: 3 weeks