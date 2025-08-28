# COMMAND MIGRATION MAPPING

## PHASE 2.2: BRIDGE INTEGRATION - EXACT MIGRATION PLAN

### Strategy Overview
**Approach**: Enhance the active Input system to use Domain commands while maintaining full backward compatibility.

**Why This Approach**:
- Input system is the **primary active system** (156 + 189 + 245 lines of integration)
- Domain commands are **well-designed and tested**
- Legacy commands have only **3 references** (easy cleanup)
- Maintains functionality throughout migration

### Step 1: Enhance Input::Commands Dispatcher

**File**: `lib/ebook_reader/input/commands.rb`
**Current Code** (line 18-21):
```ruby
def execute(command, context, key = nil)
  case command
  when EbookReader::Commands::BaseCommand
    command.execute(context, key)
```

**Enhanced Code**:
```ruby
def execute(command, context, key = nil)
  case command
  when EbookReader::Domain::Commands::BaseCommand
    # New: Support domain commands with parameter conversion
    params = { key: key, triggered_by: :input }
    command.execute(context, params)
  when EbookReader::Commands::BaseCommand
    # Legacy: Keep existing support during transition
    command.execute(context, key)
```

### Step 2: Create Domain Command Bridge Factory

**New File**: `lib/ebook_reader/input/domain_command_bridge.rb`
```ruby
module EbookReader
  module Input
    # Bridge to create Domain commands for Input system usage
    class DomainCommandBridge
      def self.navigation_command(action)
        Domain::Commands::NavigationCommand.new(action)
      end

      def self.application_command(action)
        Domain::Commands::ApplicationCommand.new(action)
      end

      def self.bookmark_command(action, params = {})
        Domain::Commands::BookmarkCommand.new(action, params)
      end
    end
  end
end
```

### Step 3: Migration Mapping - Navigation Commands

#### Current Input System Navigation (Primary Usage)
**File**: `lib/ebook_reader/input/command_factory.rb`
**Lines**: 14-45 (navigation_commands method)

**Current Pattern**:
```ruby
# Up navigation - creates lambdas
KeyDefinitions::NAVIGATION[:up].each do |key|
  commands[key] = lambda do |ctx, _|
    current = ctx.state.send(selection_field)
    ctx.state.send("#{selection_field}=", [current - 1, 0].max)
    :handled
  end
end
```

**Migration Pattern**:
```ruby
# Enhanced to use domain commands
KeyDefinitions::NAVIGATION[:up].each do |key|
  commands[key] = DomainCommandBridge.navigation_command(:prev_item)
end
```

#### Reader Navigation Commands
**Current Active Usage** in ReaderController:

| Current Input Symbol | Domain Command | Service Action |
|---------------------|----------------|----------------|
| `:next_page` | `NavigationCommand.new(:next_page)` | `navigation_service.next_page` |
| `:prev_page` | `NavigationCommand.new(:prev_page)` | `navigation_service.prev_page` |
| `:next_chapter` | `NavigationCommand.new(:next_chapter)` | `navigation_service.next_chapter` |
| `:prev_chapter` | `NavigationCommand.new(:prev_chapter)` | `navigation_service.prev_chapter` |
| `:scroll_up` | `NavigationCommand.new(:scroll_up)` | `navigation_service.scroll_up` |
| `:scroll_down` | `NavigationCommand.new(:scroll_down)` | `navigation_service.scroll_down` |

### Step 4: Migration Mapping - Application Commands

#### Mode Switching
**Current Pattern** (Input system):
```ruby
# Current direct symbol calls
:show_help    → context.switch_mode(:help)
:open_toc     → context.switch_mode(:toc) 
:open_bookmarks → context.switch_mode(:bookmarks)
```

**Domain Command Pattern**:
```ruby
# New domain command approach
:show_help    → ApplicationCommand.new(:switch_mode, mode: :help)
:open_toc     → ApplicationCommand.new(:switch_mode, mode: :toc)
:open_bookmarks → ApplicationCommand.new(:switch_mode, mode: :bookmarks)
```

#### Application Lifecycle
| Current Symbol | Domain Command | Action |
|---------------|----------------|--------|
| `:quit` | `ApplicationCommand.new(:quit)` | Proper cleanup and exit |
| `:quit_to_menu` | `ApplicationCommand.new(:quit_to_menu)` | Return to main menu |

### Step 5: Migration Mapping - Menu Navigation

#### TOC Navigation (High Usage)
**File**: `lib/ebook_reader/reader_modes/toc_mode.rb`
**Current**: Lambda-based navigation with state manipulation
**Target**: `NavigationCommand.new(:menu_up)`, `NavigationCommand.new(:menu_down)`

#### Bookmark Navigation 
**File**: `lib/ebook_reader/reader_modes/bookmarks_mode.rb`  
**Current**: Direct state access
**Target**: `BookmarkCommand.new(:navigate)`, `BookmarkCommand.new(:select)`

### Step 6: Legacy Command System Cleanup

#### Files to Replace (3 references total):

1. **main_menu.rb** (1 reference)
   - **Line**: Search for `Commands::`
   - **Replace**: Use Domain::Commands equivalent

2. **reader_controller.rb** (1 reference)  
   - **Line**: Search for `Commands::`
   - **Replace**: Use Domain::Commands equivalent

3. **input/commands.rb** (1 reference)
   - **Line**: 20 - BaseCommand handling
   - **Action**: Already handled in Step 1

### Step 7: Delete Legacy Command Files

**Files to Delete** (after migration):
```bash
rm lib/ebook_reader/commands/base_command.rb
rm lib/ebook_reader/commands/navigation_commands.rb  
rm lib/ebook_reader/commands/command_factory.rb
rm lib/ebook_reader/commands/sidebar_commands.rb
rmdir lib/ebook_reader/commands/
```

### Step 8: Input System Simplification

#### Command Factory Simplification
**File**: `lib/ebook_reader/input/command_factory.rb`
**Current**: 189 lines of lambda generation
**Target**: 50-80 lines using domain command bridge

#### Dispatcher Simplification
**File**: `lib/ebook_reader/input/dispatcher.rb`
**Current**: 156 lines with complex routing
**Target**: 100-120 lines with domain command routing

## IMPLEMENTATION ORDER

### Phase 2.2: Bridge Integration (This Phase)
1. ✅ Enhance Input::Commands dispatcher (Step 1)
2. ✅ Create DomainCommandBridge (Step 2)
3. ✅ Test basic integration

### Phase 2.3: Navigation Migration
1. Replace reader navigation symbols with domain commands
2. Replace menu navigation lambdas with domain commands  
3. Test navigation functionality

### Phase 2.4: Application Command Migration
1. Replace mode switching with domain commands
2. Replace application lifecycle commands
3. Test mode transitions

### Phase 2.5: Legacy Cleanup
1. Update 3 legacy command references
2. Delete legacy command files
3. Simplify input system

## VALIDATION CRITERIA

### After Each Step:
- [ ] Application loads without errors
- [ ] Book opening functionality works
- [ ] Key navigation responds correctly  
- [ ] Mode switching functions properly
- [ ] Error handling maintains user experience

### Final Success:
- [ ] All commands flow through Domain::Commands
- [ ] Input system simplified but functional
- [ ] Legacy commands directory deleted
- [ ] No functionality regression
- [ ] Clean command execution path

## ROLLBACK PLAN

**If Step Fails**: 
1. Revert specific file changes
2. Verify application functionality
3. Update mapping plan with issue details
4. Continue with alternative approach

**Files to Monitor**:
- Reader navigation (most critical)
- Mode switching (user-visible)
- Input responsiveness (user experience)
- Error handling (stability)