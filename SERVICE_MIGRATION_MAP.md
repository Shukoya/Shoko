# SERVICE MIGRATION MAPPING

## PHASE 1.2: EXACT REPLACEMENT MAP

### Direct Replacements (1:1 migration)

#### ClipboardService Migration
```ruby
# OLD (Static methods)
Services::ClipboardService.copy(text)
Services::ClipboardService.copy_with_feedback(text) { |msg| set_message(msg) }
Services::ClipboardService.available?

# NEW (Instance methods via DI)
@clipboard_service.copy(text)
@clipboard_service.copy_with_feedback(text) { |msg| set_message(msg) }
@clipboard_service.available?
```

**Files to Update**:
- `mouseable_reader.rb:231` → `copy_to_clipboard` method
- Any other files using `Services::ClipboardService`

#### CoordinateService Migration  
```ruby
# OLD (Static methods)
Services::CoordinateService.mouse_to_terminal(x, y)
Services::CoordinateService.terminal_to_mouse(x, y)
Services::CoordinateService.normalize_selection_range(range)

# NEW (Instance methods via DI)  
@coordinate_service.mouse_to_terminal(x, y)
@coordinate_service.terminal_to_mouse(x, y)
@coordinate_service.normalize_selection_range(range)
```

**Files to Update**:
- `mouseable_reader.rb:98` → `handle_popup_click` method
- `mouseable_reader.rb:169` → `extract_selected_text` method  
- `mouseable_reader.rb:241` → `determine_column_bounds` method

#### LayoutService Migration
```ruby
# OLD (Static methods)
Services::LayoutService.calculate_metrics(width, height, view_mode)
Services::LayoutService.adjust_for_line_spacing(height, line_spacing)
Services::LayoutService.calculate_center_start_row(content_height, lines_count, line_spacing)

# NEW (Instance methods via DI)
@layout_service.calculate_metrics(width, height, view_mode)  
@layout_service.adjust_for_line_spacing(height, line_spacing)
@layout_service.calculate_center_start_row(content_height, lines_count, line_spacing)
```

**Files to Update**:
- Any rendering components using layout calculations
- Search for `Services::LayoutService` across codebase

### Service Deletions (Replace with existing domain services)

#### DELETE: StateService
```ruby
# DELETE THIS FILE: services/state_service.rb
# REPLACE WITH: Direct GlobalState usage or domain services
```

#### DELETE: MainMenuInputHandler  
```ruby
# DELETE THIS FILE: services/main_menu_input_handler.rb
# REPLACE WITH: Domain commands through command factory
```

### Service Migrations (Move to domain)

#### LibraryScanner → Domain Service
```ruby
# MOVE: services/library_scanner.rb 
# TO: domain/services/library_scanner.rb
# UPDATE: Add dependency injection support
# UPDATE: Inherit from BaseService
```

#### ChapterCache → Domain Service
```ruby  
# MOVE: services/chapter_cache.rb
# TO: domain/services/chapter_cache.rb  
# UPDATE: Add dependency injection support
# UPDATE: Inherit from BaseService
```

#### PageManager → Merge into PageCalculatorService
```ruby
# MOVE FUNCTIONALITY FROM: services/page_manager.rb
# INTO: domain/services/page_calculator_service.rb
# DELETE: services/page_manager.rb after merge
```

## PHASE 1.3: DEPENDENCY INJECTION SETUP

### Constructor Updates Required

#### MouseableReader
```ruby
# OLD
class MouseableReader < ReaderController
  def initialize(epub_path, config = nil)
    super
    # ... other initialization
  end

# NEW  
class MouseableReader < ReaderController
  def initialize(epub_path, config = nil, dependencies = nil)
    super
    @dependencies = dependencies || Domain::ContainerFactory.create_default_container
    @clipboard_service = @dependencies.resolve(:clipboard_service)
    @coordinate_service = @dependencies.resolve(:coordinate_service)
    @layout_service = @dependencies.resolve(:layout_service)
    # ... other initialization
  end
```

#### MainMenu
```ruby
# OLD
class MainMenu
  def setup_services
    @scanner = Services::LibraryScanner.new
    @input_handler = Services::MainMenuInputHandler.new(self)
    # ...

# NEW
class MainMenu  
  def setup_services
    @dependencies = Domain::ContainerFactory.create_default_container
    @scanner = @dependencies.resolve(:library_scanner)
    # Remove input_handler - replace with command system
    # ...
```

### Dependency Container Updates
```ruby
# UPDATE: lib/ebook_reader/domain/dependency_container.rb
# ADD these registrations in create_default_container:

container.register_factory(:library_scanner) { |c| Domain::Services::LibraryScanner.new(c) }
container.register_factory(:chapter_cache) { |c| Domain::Services::ChapterCache.new(c) }
# Enhance page_calculator with page_manager functionality
```

## PHASE 1.4: FILE DELETION CHECKLIST

### Files to DELETE after migration:
- [ ] `lib/ebook_reader/services/clipboard_service.rb`
- [ ] `lib/ebook_reader/services/coordinate_service.rb`  
- [ ] `lib/ebook_reader/services/layout_service.rb`
- [ ] `lib/ebook_reader/services/state_service.rb`
- [ ] `lib/ebook_reader/services/page_manager.rb` (after merge)
- [ ] `lib/ebook_reader/services/main_menu_input_handler.rb`
- [ ] `lib/ebook_reader/services/library_scanner.rb` (after move)
- [ ] `lib/ebook_reader/services/chapter_cache.rb` (after move)
- [ ] `lib/ebook_reader/services/` directory (when empty)

### Require statement cleanup:
- [ ] `lib/ebook_reader.rb` lines 95-99: Remove service requires  
- [ ] `mouseable_reader.rb` lines 14-15: Remove service requires
- [ ] `main_menu.rb` line 3: Remove service requires
- [ ] Any other files with `require_relative 'services/*'`

## SUCCESS VALIDATION

After Phase 1 completion, verify:
- [ ] No `Services::*` references exist (only `Domain::Services::*`)
- [ ] `services/` directory deleted
- [ ] All functionality still works
- [ ] Tests pass
- [ ] Application runs without errors