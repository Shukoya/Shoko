# RuboCop Offenses Refactor Roadmap

Status audited: 2025-09-14 (updated)

Scope and counts
- Scope: `lib/` only (matches how we enforce style in code, excludes `bin/` and `spec/`).
- Offenses: 557 total across 112 files (`bundle exec rubocop lib --format offenses`, sampled during this review; cache directory creation warnings were benign).
- Top offense categories (count):
  - Metrics/MethodLength (115)
  - Metrics/AbcSize (99)
  - Metrics/CyclomaticComplexity (59)
  - Metrics/PerceivedComplexity (53)
  - Metrics/ParameterLists (46)
  - Naming/MethodParameterName (41)
  - Style/Documentation (40)
  - Layout/LineLength (17) [Safe Correctable]
  - Metrics/ClassLength (13)
  - Naming/AccessorMethodName (12)
  - Lint/SuppressedException (10)
  - Naming/PredicateMethod (9)
  - Naming/PredicatePrefix (9)
  - Style/ComparableClamp (9) [Safe Correctable]
  - Lint/UselessConstantScoping (7)
  - Remaining cop counts are single digits; see latest `rubocop` output for the full tail.

Hotspots (highest impact)
- `lib/ebook_reader/reader_controller.rb` (class length + several long methods)
- `lib/ebook_reader/domain/services/page_calculator_service.rb` (very large class; multiple long/complex methods)
- `lib/ebook_reader/domain/services/navigation_service.rb` (long/branchy methods, several trailing-comma fixups)
- `lib/ebook_reader/input/command_factory.rb` (monolithic factory with large methods)
- `lib/ebook_reader/infrastructure/state_store.rb` (long methods)
- Rendering components under `lib/ebook_reader/components/screens/*` (long do_render, parameter lists)

Guardrails
- Do not change `.rubocop.yml` and do not disable cops with inline comments.
- No monkey patches; prefer extraction and composition, keep behavior identical.
- Respect the architecture boundaries (Infrastructure, Domain, Application, Controllers, Components).
- After each batch, run specs and a focused manual sanity pass on reading and menu flows.

Execution plan (single, best path)
1) Low-risk auto-correctables and naming hygiene (batchable, no behavior change)
   - Apply safe corrections: trailing commas, long lines, Comparable#clamp, minor predicate renames inside private APIs.
   - Fix `Naming/PredicatePrefix` and `Naming/PredicateMethod` in non-public methods (`has_*? -> *?`). For any public readers, add delegator shims to avoid breaking callers and deprecate in docs.
   - Ensure `TerminalService` uses a class instance var (already done) and keep session-depth semantics unchanged.

2) Parameter-list reductions with value objects (targeted, mechanical)
   - Rendering: enforce `Models::RenderParams` everywhere renderers call shared draw helpers.
   - Sidebar/tab item renderers: introduce `ItemRenderContext` to replace 6–7 arg lists.
   - Repositories: introduce small range/data structs for annotation/bookmark operations to satisfy `Metrics/ParameterLists`.

3) Renderer consolidation (functional duplication -> base helpers)
   - Move shared column/windowing helpers from `SingleViewRenderer` and `SplitViewRenderer` into `BaseViewRenderer` (divider, centering, wrapped-line fetch, draw_lines already present; extend rather than re-implement).
   - Keep all writing via `Surface`; eliminate any overlooked direct `Terminal.*` calls (currently clean).

4) Slim monoliths with internal extractions (largest wins first)
   - PageCalculatorService: extract `PageMapBuilder`, `AbsolutePageMapBuilder`, and `ChapterLineProvider`. Keep public API stable; wire via DI container as a single facade.
   - NavigationService: extract strategies per mode (`DynamicNavigation`, `AbsoluteNavigation`) to reduce branching; retain one orchestrating facade.
   - ReaderController: keep only coordination + render loop; delegate startup fully to `Application::ReaderStartupOrchestrator` (already present) and move remaining pagination rebuild helpers into `PageCalculatorService`.
   - Input::CommandFactory: split into modules (Navigation, Control, Menu, TextInput) and require them from the factory to satisfy class/method length.

5) State and repositories trimming
   - `Infrastructure::StateStore`: split deep methods (e.g., `dispatch`, `deep_dup`) into smaller private helpers.
   - `Domain::Repositories::*`: split long methods (e.g., `exists_in_range?`) into smaller predicates.

6) Documentation cops
   - Add missing top-level class/module comments for public classes.
   - Keep docs short and factual; avoid noise.

7) Final pass: complexity smoothing
   - Re-check `Metrics/*` thresholds; break up any remaining 20+ line methods in view components (prefer extracting small, pure helpers).

Milestones and acceptance criteria
- M1: Safe correctables + naming hygiene. Offense delta: −60 to −90. No behavior change.
- M2: Param-list reductions applied in renderers/sidebar/repositories. Offense delta: −40 to −60.
- M3: Renderer consolidation complete; no duplication between single/split except rendering specifics. Offense delta: −30 to −40.
- M4: PageCalculatorService split behind a facade; identical behavior; specs pass. Offense delta: −60 to −90.
- M5: NavigationService strategies extracted; specs pass. Offense delta: −30 to −40.
- M6: Input::CommandFactory split; DomainCommandBridge simplified. Offense delta: −25 to −35.
- M7: State/Repo trims + docs. Offense delta: −20 to −30.

Tracking (current)
- Current snapshot (review run): 557 offenses in lib (112 files). Metrics cops still dominate; clearing safe-correctable layout items would remove roughly 120 violations.
- Target (phase end): ≤ 100 offenses in lib (mainly long, inherently complex algorithms where extraction would add risk without benefit).

Notes
- Full-repo counts were not re-sampled in this audit; prior (2025-04-XX) snapshot was ~637 offenses including `spec/` and binstubs. This roadmap continues to focus strictly on `lib/` as per project policy.
- Any public API renames must ship with deprecation shims for at least one release.
