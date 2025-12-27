# RuboCop + Reek Refactoring Roadmap

This repo currently has a large set of style and smell findings in `rubocop_report.txt` and `reek_report.txt`.
The goal of this roadmap is to reduce both steadily without disabling, loosening, or bypassing rules.

## Current Baseline (from existing reports)

- RuboCop: `239 files inspected, 810 offenses detected`
- Reek: `2809 total warnings`

Top RuboCop offense categories (by count):
- `Metrics/MethodLength` (177)
- `Metrics/AbcSize` (153)
- `Metrics/CyclomaticComplexity` (106)
- `Metrics/PerceivedComplexity` (91)
- `Naming/MethodParameterName` (56)
- `Metrics/ParameterLists` (53)
- `Style/Documentation` (40)
- `Metrics/ClassLength` (20)

Top Reek smell categories (by count):
- `TooManyStatements` (577)
- `DuplicateMethodCall` (393)
- `UtilityFunction` (330)
- `UncommunicativeVariableName` (250)
- `FeatureEnvy` (184)
- `ManualDispatch` (171)
- `LongParameterList` (144)
- `ControlParameter` (126)
- `NilCheck` (100)
- `DataClump` (94)
- `IrresponsibleModule` (89)

## Current Snapshot (after initial refactor batches)

- RuboCop: `408 files inspected, 680 offenses detected` (from `bundle exec rubocop`)
- Reek: `2711 total warnings` (from `bundle exec reek lib bin`)

Note: the numbers differ from the checked-in report files because current runs include more paths (e.g. `bin/`, `spec/`).

## Operating Rules (non-negotiable)

- No disabling cops/smells, no exclusions added as a “fix”, no rule loosening.
- Refactors must be incremental, behavior-preserving, and verified after each batch.
- `lib/` and `bin/` are the only code “source of truth”; other files are supporting material.
- No “cleanup leftovers”: if we introduce helpers/objects, they must be used and justified.

## Workflow (to avoid regressions and new offenses)

For each batch:
1. Pick a small, coherent slice (1–3 files or 1 subsystem).
2. Fix RuboCop + Reek issues together for that slice (don’t fix one by worsening the other).
3. Run:
   - `bundle exec rubocop`
   - `bundle exec reek`
   - `bundle exec rspec`
4. Only then move to the next slice.

## Prioritization Strategy

### Phase 1 — “Cheap wins” with real value (high impact / low risk)

These changes reduce noise and improve clarity without changing architecture:

- [x] Add missing top-level documentation comments (`Style/Documentation` + `IrresponsibleModule`)
- [x] Fix bad predicate naming (`Naming/PredicateMethod`, `Naming/PredicatePrefix`)
- [x] Fix short parameter names (`Naming/MethodParameterName`) by using domain terms (`row`, `col`, `width`, `height`, `codepoint`, …)
- [ ] Replace manual clamp patterns with `Comparable#clamp` (`Style/ComparableClamp`)
- [ ] Fix correctness lint warnings (`Lint/*`) such as duplicate methods, unused args, missing `super`
- [ ] Remove suppressed exceptions in test helpers by logging/handling intentionally (`Lint/SuppressedException`)
- [x] Fix large hard-coded collection literals by moving data to a dedicated data file (`Metrics/CollectionLiteralLength`)

### Phase 2 — Kill “TooManyStatements” + RuboCop metrics together

This is the biggest payoff area because it tackles the largest RuboCop/Reek categories simultaneously.

Primary technique:
- Extract small private methods until:
  - `Metrics/MethodLength <= 15`
  - `Metrics/AbcSize <= 20`
  - `Metrics/CyclomaticComplexity <= 8`
  - `Metrics/PerceivedComplexity <= 9`
  - Reek `TooManyStatements` is naturally reduced.

Guardrails while extracting:
- Don’t introduce long parameter lists. Prefer existing parameter objects (e.g. `Models::RenderParams`) or introduce narrowly-scoped value objects.
- Prefer pure helpers as `module_function`/class helpers when they don’t depend on state (helps Reek `UtilityFunction`).

### Phase 3 — Reduce “god classes” (`Metrics/ClassLength`, `TooManyMethods`)

Tactics:
- Extract nested classes to their own files when they represent independent responsibilities.
- Split renderer responsibilities: geometry tracking, styling/highlighting, kitty image placement.

### Phase 4 — Reek-specific deep smells (after RuboCop is under control)

Targeted improvements:
- `DuplicateMethodCall`: cache values locally in the method scope.
- `ManualDispatch`: replace `send`/`public_send` and `respond_to?` ladders with explicit interfaces (or safe optional dependencies with clear boundaries).
- `FeatureEnvy`: move logic closer to the data it manipulates.
- `DataClump`: introduce small domain value objects (`Size`, `Point`, `Rect`, etc.) to replace repeated `(width, height)`/`(x, y)` pairs.
- `ControlParameter`/`BooleanParameter`: replace flags with objects/strategies where meaningful.

## “Hot Spots” (where the biggest reductions live)

Highest Reek-warning files:
- `lib/ebook_reader/domain/services/formatting_service.rb` (106)
- `lib/ebook_reader/components/reading/base_view_renderer.rb` (84)
- `lib/ebook_reader/infrastructure/epub_cache.rb` (83)
- `lib/ebook_reader/domain/services/page_calculator_service.rb` (83)
- `lib/ebook_reader/components/sidebar/toc_tab_renderer.rb` (71)
- `lib/ebook_reader/helpers/opf_processor.rb` (69)
- `lib/ebook_reader/infrastructure/parsers/xhtml_content_parser.rb` (67)
- `lib/ebook_reader/infrastructure/json_cache_store.rb` (62)
- `lib/ebook_reader/domain/services/navigation_service.rb` (57)

Highest RuboCop-offense files:
- `lib/ebook_reader/components/reading/base_view_renderer.rb` (33)
- `lib/ebook_reader/domain/services/formatting_service.rb` (31)
- `lib/ebook_reader/infrastructure/epub_cache.rb` (24)
- `lib/ebook_reader/helpers/opf_processor.rb` (24)
- `lib/ebook_reader/domain/services/navigation_service.rb` (23)
- `lib/ebook_reader/reader_controller.rb` (20)
- `lib/ebook_reader/components/sidebar/toc_tab_renderer.rb` (19)
- `lib/ebook_reader/infrastructure/json_cache_store.rb` (18)

## Concrete Next Steps (the first milestones)

Milestone A (noise removal, unlocks faster iteration):
- [x] Fix all `Style/Documentation` offenses (and matching Reek `IrresponsibleModule`)
- [x] Fix all `Naming/Predicate*` offenses
- [x] Fix all `Naming/MethodParameterName` offenses
- [x] Fix all `Lint/*` offenses in the report
- [x] Fix `Metrics/CollectionLiteralLength` in `KittyUnicodePlaceholders`

Milestone B (first meaningful metrics reduction without large architecture change):
- [x] Refactor `lib/zip.rb` to satisfy method/class metrics while preserving security limits
- [x] Refactor `EbookReader::CLI` logger setup to satisfy metrics and keep behavior

Milestone C (large, high-value refactors; do one at a time):
- [x] Split `BaseViewRenderer` into small collaborators (geometry, highlighting, kitty images)
- [x] Refactor `SingleViewRenderer` + `SplitViewRenderer` (reduce metrics + remove split-layout crash path)
- [x] Split `FormattingService::LineAssembler` into focused components
- [x] Simplify `PageCalculatorService#get_page` by delegating hydration to `Internal::PageHydrator`
- [x] Reduce `EpubCache` surface area (extract persistence, layouts, IO helpers)

Notes (recent changes):
- `FormattingService::LineAssembler` extracted to `lib/ebook_reader/domain/services/formatting_service/line_assembler.rb` and split into `ImageBuilder`, `Tokenizer`, and `TextWrapper`.
- `FormattingService#wrap_window` now takes `offset:` and `length:` as keyword args to satisfy `Metrics/ParameterLists`; call sites updated.
- `PageHydrator` now prefers `FormattingService` when available and uses the injected `DefaultTextWrapper` for plain fallback.
- Fixed report-listed `Lint/*` offenses (`Lint/UselessConstantScoping`, `Lint/DuplicateBranch`, `Lint/HashCompareByIdentity`, `Lint/ShadowedException`, `Lint/EmptyBlock`) and refactored `TocRenderer`/`TabHeaderComponent` to satisfy metrics without changing behavior.
- Refactored `EbookReader::CLI` logger setup to reduce method metrics and remove duplicated `/dev/null` handling (now uses `IO::NULL`); `bundle exec rspec` passes.
- Split `EpubCache` into focused helpers under `lib/ebook_reader/infrastructure/epub_cache/` (source resolution, persistence, memory cache, serializer) and normalized layout cache updates; validated with `bundle exec rubocop`, `bundle exec reek lib bin`, and `bundle exec rspec`.
- Split `JsonCacheStore` into focused helpers under `lib/ebook_reader/infrastructure/json_cache_store/` and refactored `write_payload`/chapter/resource helpers to satisfy RuboCop metrics; kept Reek total steady and verified with `bundle exec rspec`.
- Extracted overlay layout sizing/helpers and split annotation overlay rendering into focused helpers (note/footer/list renderers) to cut parameter lists and method metrics while preserving overlay behavior.
- Refactored `PaginationCachePreloader` to use layout/size value objects and smaller helpers (reduced method length, parameter lists, and fallback complexity) while preserving cache hydration behavior.
- Reworked `PaginationOrchestrator` with a context object and slimmed orchestration methods (reduced data clumps, repeated conditionals, and utility-method smells) while keeping pagination build flows unchanged.
- Refactored `PageInfoCalculator` to use a dependencies bundle and smaller calculation helpers, reducing method metrics and repeated state lookups without changing page-number behavior.
- Split `AnnotationDetailScreenComponent` and `AnnotationEditScreenComponent` renders into context-driven helpers to eliminate `do_render` god methods and reduce parameter clumps while preserving layout/output.
- Refined annotation detail/edit screens to use `AnnotationTextBox` helpers (`next_box`, `render_lines`) and removed redundant padding helpers, reducing data clumps and duplicate wrapping.
- Added `AnnotationEditState` to centralize menu edit state reads/writes and reduce render-component class length.
- Reworked `AnnotationTextBox` to use row-based naming, internal render helpers, and a render-context interface to remove parameter clumps and duplicate box rendering.
- Refactored `AnnotationEditorScreenComponent` into context-driven header/body/footer rendering with shared `AnnotationTextBox` helpers and extracted save flow steps to reduce method complexity.
- Refactored `TerminalInput::Decoder` with `EscSequenceParser` and `Utf8Validator`, inlined UTF-8 sequence length checks, and reduced action dispatch complexity; `lib/ebook_reader/terminal_input/decoder.rb` now clears RuboCop/Reek for the file.
