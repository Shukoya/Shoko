# EBook Reader Refactoring Roadmap

**Current Status: Phase 2.2 - State System Unification**  
**Overall Progress: 35% Complete**  
**Estimated Completion: Phase 4.1**

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

## Phase 2: Legacy Elimination ⚠️ IN PROGRESS (35%)

### 2.1 Service Layer Consolidation ❌ TODO
**Current Issue**: Dual service implementations causing confusion
- [ ] Delete `lib/ebook_reader/services/coordinate_service.rb` (legacy wrapper)
- [ ] Delete `lib/ebook_reader/services/clipboard_service.rb` (legacy wrapper)  
- [ ] Delete `lib/ebook_reader/services/layout_service.rb` (legacy wrapper)
- [ ] Update all references to use `domain/services/` versions only
- [ ] Remove service resolution from DependencyContainer for deleted services

### 2.2 State System Unification ❌ CRITICAL - TODO
**Current Issue**: Two competing state systems
- [ ] Replace ALL GlobalState usage with StateStore
- [ ] Migrate state structure from GlobalState to StateStore format
- [ ] Update all `@state.update()` calls to use StateStore events  
- [ ] Delete `core/global_state.rb` entirely
- [ ] Update DependencyContainer to resolve StateStore as primary state

### 2.3 Component Interface Standardization ⚠️ PARTIAL
**Current Issue**: Inconsistent component interfaces
- [x] ComponentInterface defined
- [ ] Enforce ComponentInterface on ALL components
- [ ] Remove direct Terminal access from components
- [ ] Standardize render method signatures
- [ ] Create Surface abstraction for all rendering

## Phase 3: Architecture Cleanup 📋 PLANNED

### 3.1 ReaderController Decomposition ❌ TODO  
**Current Issue**: 1300+ line God class
- [ ] Extract NavigationController (page/chapter navigation)
- [ ] Extract UIController (mode switching, overlays)
- [ ] Extract InputController (key handling consolidation)
- [ ] Extract StateController (state updates and persistence)
- [ ] Keep ReaderController as coordinator only

### 3.2 Input System Unification ❌ TODO
**Current Issue**: Multiple input handling patterns
- [ ] Use ONLY Domain::Commands through single dispatcher
- [ ] Remove direct method calls from input handlers
- [ ] Remove lambda-based input handlers
- [ ] Standardize on CommandFactory + DomainCommandBridge pattern

### 3.3 Terminal Access Elimination ❌ TODO
**Current Issue**: Components bypass rendering system
- [ ] Remove direct Terminal writes from MouseableReader
- [ ] Remove direct Terminal writes from TooltipOverlayComponent  
- [ ] Channel ALL terminal access through Surface/Component system
- [ ] Create TerminalService abstraction for infrastructure layer

## Phase 4: Clean Architecture Enforcement 📋 PLANNED

### 4.1 Layer Boundary Enforcement ❌ TODO
```
Presentation Layer (Components) 
    ↓ (Events only)
Application Layer (Unified Application)
    ↓ (Commands only) 
Domain Layer (Services, Actions, Models)
    ↓ (Repository pattern)
Infrastructure Layer (StateStore, EventBus, Terminal)
```
- [ ] Enforce strict layer dependencies
- [ ] Remove circular dependencies between layers
- [ ] Create clear interfaces between layers

### 4.2 Dependency Injection Completion ❌ TODO
- [ ] Inject ALL dependencies through container
- [ ] Remove direct instantiation (`new`) from business logic
- [ ] Create factory methods for complex object creation
- [ ] Add constructor parameter validation

### 4.3 Event-Driven Architecture ❌ TODO  
- [ ] Convert ALL state mutations to events
- [ ] Make components purely reactive to state events
- [ ] Remove imperative component updates
- [ ] Add event sourcing for complex state changes

## Critical Path Issues ⚠️

### 1. Dual State Systems (Blocking Progress)
**Location**: `core/global_state.rb` vs `infrastructure/state_store.rb`
**Impact**: Every feature must handle two different state APIs
**Solution**: Complete migration to StateStore in Phase 2.2

### 2. Service Layer Confusion (Daily Development Impact)
**Location**: `services/` vs `domain/services/` directories
**Impact**: Developers don't know which services to use
**Solution**: Delete legacy services immediately in Phase 2.1

### 3. ReaderController Complexity (Maintenance Nightmare)
**Location**: `reader_controller.rb` (1300+ lines)
**Impact**: Changes in one area break unrelated functionality
**Solution**: Controller decomposition in Phase 3.1

## Next Immediate Steps

1. **Phase 2.1**: Delete legacy service wrappers
2. **Phase 2.2**: Migrate GlobalState to StateStore  
3. **Phase 2.3**: Enforce ComponentInterface across all UI components
4. **Phase 3.1**: Break down ReaderController into focused controllers

## Success Metrics

- **Code Maintainability**: Single responsibility per class
- **State Consistency**: One source of truth (StateStore only)
- **Testability**: All dependencies injectable  
- **Component Isolation**: No direct terminal access outside infrastructure
- **Input Consistency**: All user input through Domain commands

**Target Architecture**: Clean Architecture with strict layer boundaries and dependency injection throughout.