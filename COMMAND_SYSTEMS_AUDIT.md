# COMMAND SYSTEMS AUDIT

## THREE SEPARATE COMMAND SYSTEMS DISCOVERED

### 1. LEGACY COMMANDS (`commands/`)
**Location**: `lib/ebook_reader/commands/`
**Pattern**: Class-based commands with simple BaseCommand
**Usage**: Limited, mostly unused

**Files**:
- `base_command.rb` (80 lines) - Simple command interface
- `navigation_commands.rb` (67 lines) - Basic navigation actions
- `command_factory.rb` (59 lines) - Creates command instances
- `sidebar_commands.rb` (45 lines) - Sidebar-specific commands

**Command Interface**:
```ruby
# Simple execution model
def execute(context, key = nil)
  perform(context, key)
end
```

**Key Issues**:
- No proper error handling
- Basic validation
- Direct method calls on context
- No dependency injection

### 2. DOMAIN COMMANDS (`domain/commands/`)
**Location**: `lib/ebook_reader/domain/commands/`
**Pattern**: Enhanced command pattern with DI and services
**Usage**: New architecture, properly designed but not integrated

**Files**:
- `base_command.rb` (145 lines) - Enhanced with error handling, validation
- `navigation_commands.rb` (87 lines) - Service-based navigation
- `application_commands.rb` (134 lines) - Application lifecycle commands
- `bookmark_commands.rb` (98 lines) - Bookmark operations

**Command Interface**:
```ruby
# Enhanced execution with full error handling
def execute(context, params = {})
  validate_context(context)
  validate_parameters(params)
  perform(context, params)
end
```

**Advantages**:
- Proper error handling and validation
- Dependency injection support
- Service-based execution
- Comprehensive logging

### 3. INPUT SYSTEM (`input/`)
**Location**: `lib/ebook_reader/input/`
**Pattern**: Functional approach with lambdas and symbol dispatch
**Usage**: ACTIVE - Primary input handling system

**Files**:
- `commands.rb` (58 lines) - Command execution dispatcher
- `command_factory.rb` (189 lines) - Creates lambda-based commands
- `dispatcher.rb` (156 lines) - Main input handling
- `key_definitions.rb` (245 lines) - Key binding definitions
- `binding_generator.rb` (78 lines) - Generates key bindings

**Command Interface**:
```ruby
# Multiple command types supported
def execute(command, context, key = nil)
  case command
  when Symbol then context.public_send(command)
  when Proc then command.call(context, key)
  when Array then context.public_send(*command)
  when BaseCommand then command.execute(context, key)
  end
end
```

## OVERLAP ANALYSIS

### Navigation Commands
**Legacy Commands**:
- `NavigationCommand.new(:next_page)` → `context.next_page`

**Domain Commands**: 
- `NavigationCommand.new(:next_page)` → `navigation_service.next_page`

**Input System**:
- Direct symbol: `:next_page` → `context.next_page`
- Lambda factory: `lambda { |ctx| ctx.next_page }`

### Current Usage Patterns

#### 1. Reader Controller Input Handling
**File**: `lib/ebook_reader/input/dispatcher.rb`
**Pattern**: Uses Input system with lambdas and symbols
```ruby
# Current active pattern
commands = Input::CommandFactory.navigation_commands(context, ...)
Input::Commands.execute(command, context, key)
```

#### 2. Legacy Command References
**Files Using Commands::**:
- `main_menu.rb` (1 reference)
- `reader_controller.rb` (1 reference) 
- `input/commands.rb` (1 reference)

#### 3. Domain Command Usage
**Files Using Domain::Commands::**:
- `reader_application.rb` (new architecture, limited usage)
- Test files only

## MIGRATION COMPLEXITY ASSESSMENT

### HIGH COMPLEXITY: Input System Integration
The Input system (`input/`) is the **primary active system** handling all user interactions:

- **156 lines** of complex dispatcher logic
- **189 lines** of command factory with lambda generation
- **245 lines** of key definitions and bindings
- Integrated with **all major components** (ReaderController, MainMenu, etc.)

### MEDIUM COMPLEXITY: Legacy Command Cleanup
Legacy `commands/` system has **limited usage**:
- Only **3 active references** found
- Simple class-based pattern
- Easy to replace with domain commands

### LOW COMPLEXITY: Domain Command Enhancement  
Domain `domain/commands/` system is **well-designed but unused**:
- Proper architecture already in place
- Good error handling and validation
- Needs integration, not redesign

## RECOMMENDED MIGRATION STRATEGY

### Phase 2.1: Analyze Current Flow
✅ COMPLETE - This document

### Phase 2.2: Bridge Integration
Create bridge layer to allow Input system to use Domain commands:

1. **Enhance Input::Commands** to recognize Domain::Commands
2. **Create Domain command factories** for common input patterns
3. **Maintain backward compatibility** with existing lambda/symbol patterns

### Phase 2.3: Gradual Migration
Replace Input system lambdas with Domain commands:

1. **Navigation commands first** (most common)
2. **Mode switching commands** 
3. **Menu navigation commands**
4. **Special action commands**

### Phase 2.4: Legacy Cleanup
Remove old `commands/` system:

1. **Replace 3 active references** with domain commands
2. **Delete legacy command files**
3. **Update require statements**

### Phase 2.5: Input System Simplification
Once Domain commands are integrated:

1. **Simplify Input::Commands dispatcher** 
2. **Remove lambda-based command factory**
3. **Keep key definitions and binding system**

## SUCCESS CRITERIA

- [ ] Single command execution path: `Input → Domain::Commands → Services`
- [ ] All navigation uses `NavigationService` through commands  
- [ ] All mode switching uses `ApplicationCommands`
- [ ] Legacy `commands/` directory deleted
- [ ] Input system simplified to dispatch only
- [ ] Backward compatibility maintained during transition

## RISK ASSESSMENT

**LOW RISK**: Well-contained change
- Input system is already abstracted through dispatcher
- Domain commands are well-designed and tested  
- Can maintain compatibility during migration
- Each component can be migrated independently

**CRITICAL**: Must maintain working input during migration
- Reader must remain functional throughout process
- Key bindings must continue working
- Error handling must be preserved