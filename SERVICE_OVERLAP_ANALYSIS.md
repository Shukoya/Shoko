# SERVICE OVERLAP ANALYSIS

## EXACT DUPLICATES (Same functionality in both locations)

### 1. ClipboardService
**Legacy**: `lib/ebook_reader/services/clipboard_service.rb` (123 lines)
**Domain**: `lib/ebook_reader/domain/services/clipboard_service.rb` (105 lines)

**Overlapping Methods**:
- `copy(text)` - Both do same clipboard operations
- `copy_with_feedback(text)` - Identical functionality, different signatures
- `available?()` - Both check if clipboard commands exist
- `detect_clipboard_command()` - Identical platform detection logic

**Key Differences**:
- Legacy: Static methods (class methods)
- Domain: Instance methods with dependency injection
- Legacy: Direct Infrastructure::Logger calls
- Domain: Uses dependency injection for logging

### 2. CoordinateService  
**Legacy**: `lib/ebook_reader/services/coordinate_service.rb` (116 lines)
**Domain**: `lib/ebook_reader/domain/services/coordinate_service.rb` (62 lines)

**Overlapping Methods**:
- `mouse_to_terminal(x, y)` - Identical conversion logic
- `terminal_to_mouse(x, y)` - Identical reverse conversion  
- `normalize_selection_range(range)` - Same normalization, different implementation

**Key Differences**:
- Legacy: More comprehensive (popup positioning, bounds checking)
- Legacy: Static methods
- Domain: Instance methods, simpler API
- Domain: Missing popup positioning and bounds validation

### 3. LayoutService
**Legacy**: `lib/ebook_reader/services/layout_service.rb` (32 lines)  
**Domain**: `lib/ebook_reader/domain/services/layout_service.rb` (57 lines)

**Overlapping Methods**:
- `calculate_metrics(width, height, view_mode)` - Identical logic
- `adjust_for_line_spacing(height, line_spacing)` - Same implementation
- `calculate_center_start_row(content_height, lines_count, line_spacing)` - Identical

**Key Differences**:
- Legacy: Static methods, minimal API
- Domain: Instance methods, extended with additional methods
- Domain: Added `calculate_optimal_column_width()` and `calculate_centered_padding()`

## LEGACY-ONLY SERVICES (No domain equivalent)

### 4. StateService
**File**: `lib/ebook_reader/services/state_service.rb`
**Purpose**: State management wrapper (legacy)
**Migration**: DELETE - replaced by GlobalState directly

### 5. PageManager  
**File**: `lib/ebook_reader/services/page_manager.rb`
**Purpose**: Page calculation and navigation
**Migration**: MERGE into `domain/services/page_calculator_service.rb`

### 6. LibraryScanner
**File**: `lib/ebook_reader/services/library_scanner.rb` 
**Purpose**: EPUB file scanning and caching
**Migration**: KEEP as domain service (move to domain/services/)

### 7. MainMenuInputHandler
**File**: `lib/ebook_reader/services/main_menu_input_handler.rb`
**Purpose**: Menu input processing  
**Migration**: DELETE - replace with domain commands

### 8. ChapterCache
**File**: `lib/ebook_reader/services/chapter_cache.rb`
**Purpose**: Chapter content caching
**Migration**: KEEP as domain service (move to domain/services/)

## DOMAIN-ONLY SERVICES (No legacy equivalent)

### 9. BaseService
**File**: `lib/ebook_reader/domain/services/base_service.rb`
**Purpose**: Service base class with dependency injection
**Action**: KEEP - foundation for all domain services

### 10. NavigationService  
**File**: `lib/ebook_reader/domain/services/navigation_service.rb`
**Purpose**: Navigation logic with state management
**Action**: KEEP - new domain architecture

### 11. BookmarkService
**File**: `lib/ebook_reader/domain/services/bookmark_service.rb`
**Purpose**: Bookmark operations
**Action**: KEEP - new domain architecture

### 12. PageCalculatorService
**File**: `lib/ebook_reader/domain/services/page_calculator_service.rb`  
**Purpose**: Page calculation with dependency injection
**Action**: KEEP and enhance with PageManager functionality

## MIGRATION STRATEGY SUMMARY

### DELETE ENTIRELY:
- services/state_service.rb (replaced by GlobalState)
- services/main_menu_input_handler.rb (replaced by domain commands)

### MIGRATE TO DOMAIN:
- services/library_scanner.rb → domain/services/library_scanner.rb
- services/chapter_cache.rb → domain/services/chapter_cache.rb  
- services/page_manager.rb → merge into domain/services/page_calculator_service.rb

### REPLACE LEGACY WITH DOMAIN:
- services/clipboard_service.rb → USE domain/services/clipboard_service.rb
- services/coordinate_service.rb → USE domain/services/coordinate_service.rb  
- services/layout_service.rb → USE domain/services/layout_service.rb

### ENHANCE DOMAIN SERVICES:
- domain/services/coordinate_service.rb needs popup positioning methods from legacy
- domain/services/page_calculator_service.rb needs PageManager functionality