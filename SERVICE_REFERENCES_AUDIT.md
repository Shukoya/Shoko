# SERVICE REFERENCES AUDIT

## ALL LEGACY SERVICES::* REFERENCES FOUND

### Services::CoordinateService References (6 files)
1. **mouseable_reader.rb:98** - `Services::CoordinateService.mouse_to_terminal(event[:x], event[:y])`
2. **mouseable_reader.rb:170** - `Services::CoordinateService.normalize_selection_range(range)`  
3. **mouseable_reader.rb:184** - `Services::CoordinateService.mouse_to_terminal(0, y)`
4. **mouseable_reader.rb:241** - `Services::CoordinateService.mouse_to_terminal(0, click_pos[:y])`
5. **tooltip_overlay_component.rb:61** - `Services::CoordinateService.normalize_selection_range(range)`
6. **enhanced_popup_menu.rb:15** - `Services::CoordinateService.normalize_selection_range(selection_range)`
7. **enhanced_popup_menu.rb:36** - `Services::CoordinateService.calculate_popup_position(...)`
8. **enhanced_popup_menu.rb:88** - `Services::CoordinateService.within_bounds?(...)`

### Services::ClipboardService References (4 files)
1. **mouseable_reader.rb:231** - `Services::ClipboardService.copy_with_feedback(text)`
2. **mouseable_reader.rb:234** - `Services::ClipboardService::ClipboardError` (exception handling)
3. **reader_controller.rb:943** - `Services::ClipboardService.available?`
4. **reader_controller.rb:944** - `Services::ClipboardService.copy_with_feedback(@selected_text, lambda { |msg|`
5. **enhanced_popup_menu.rb:106** - `Services::ClipboardService.available?`

### Services::LayoutService References (7 files)
1. **dynamic_page_calculator.rb:17** - `Services::LayoutService.calculate_metrics(width, height, view_mode)`
2. **dynamic_page_calculator.rb:19** - `Services::LayoutService.adjust_for_line_spacing(content_height, line_spacing)`
3. **reader_controller.rb:355** - `Services::LayoutService.calculate_metrics(width, height, view_mode)`
4. **reader_controller.rb:399** - `Services::LayoutService.calculate_metrics(width, height, :split)`
5. **reader_controller.rb:674** - `Services::LayoutService.adjust_for_line_spacing(height, @state.get(%i[config line_spacing]))`
6. **reader_controller.rb:779** - `Services::LayoutService.calculate_metrics(width, height, view_mode)`
7. **reader_controller.rb:825** - `Services::LayoutService.calculate_metrics(width, height, view_mode)`
8. **base_view_renderer.rb:45** - `Services::LayoutService.calculate_metrics(width, height, view_mode)`
9. **base_view_renderer.rb:49** - `Services::LayoutService.adjust_for_line_spacing(height, line_spacing)`
10. **base_view_renderer.rb:53** - `Services::LayoutService.calculate_center_start_row(content_height, lines_count, line_spacing)`

### Services::LibraryScanner References (2 files)
1. **main_menu.rb:189** - `@scanner = Services::LibraryScanner.new`
2. **menu_application.rb:39** - `Services::LibraryScanner.new`

### Services::MainMenuInputHandler References (1 file)
1. **main_menu.rb:190** - `@input_handler = Services::MainMenuInputHandler.new(self)`

### Services::PageManager References (1 file) 
1. **reader_controller.rb:45** - Comment: `@attr_reader page_manager [Services::PageManager]`
2. **reader_controller.rb:77** - `@page_manager = Services::PageManager.new(@doc, config)`

### Services::StateService References (1 file)
1. **reader_controller.rb:80** - `@state_service = Services::StateService.new(self)`

### Services::ChapterCache References (2 files)
1. **reader_controller.rb:85** - `@chapter_cache = Services::ChapterCache.new`
2. **reader_helpers.rb:12** - `@chapter_cache ||= Services::ChapterCache.new`

## MIGRATION PRIORITY ORDER

### CRITICAL PATH FILES (Most references)
1. **reader_controller.rb** - 8 service references (HIGHEST PRIORITY)
2. **mouseable_reader.rb** - 6 service references  
3. **enhanced_popup_menu.rb** - 4 service references
4. **base_view_renderer.rb** - 3 service references
5. **dynamic_page_calculator.rb** - 2 service references

### SUPPORTING FILES  
6. **main_menu.rb** - 2 service references
7. **tooltip_overlay_component.rb** - 1 service reference
8. **menu_application.rb** - 1 service reference
9. **reader_helpers.rb** - 1 service reference

## DEPENDENCY INJECTION REQUIREMENTS

### Classes Needing DI Constructor Updates:
1. **MouseableReader** - needs clipboard_service, coordinate_service
2. **ReaderController** - needs layout_service, page_manager equivalent, state_service equivalent, chapter_cache  
3. **EnhancedPopupMenu** - needs coordinate_service, clipboard_service
4. **BaseViewRenderer** - needs layout_service
5. **DynamicPageCalculator** - needs layout_service  
6. **MainMenu** - needs library_scanner (no more input_handler)
7. **MenuApplication** - needs library_scanner
8. **ReaderHelpers** - needs chapter_cache
9. **TooltipOverlayComponent** - needs coordinate_service

## PHASE 1.2 EXECUTION ORDER

### Step 1: Enhance Domain Services First
- Add missing methods to domain services before migration
- `domain/services/coordinate_service.rb` needs: `calculate_popup_position()`, `within_bounds?()`
- `domain/services/page_calculator_service.rb` needs: PageManager functionality

### Step 2: Update Critical Path Files  
1. Update **reader_controller.rb** (8 references)
2. Update **mouseable_reader.rb** (6 references)  
3. Update **enhanced_popup_menu.rb** (4 references)

### Step 3: Update Supporting Components
4. Update remaining rendering components
5. Update menu components
6. Update helper classes

### Step 4: Clean Up
- Delete legacy service files
- Remove require statements
- Update dependency container registrations