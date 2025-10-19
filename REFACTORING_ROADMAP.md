# Refactoring Roadmap

## Status Snapshot – Q4 2024

- Clean architecture boundaries are now enforced in code and tests. Controllers and components resolve infrastructure collaborators through the container, and an architecture spec guards against future cross-layer leaks.
- Legacy EPUB cache migrations (Marshal-based `.cache` files and pointer rebuilders) have been removed. The cache layer now assumes the SQLite-backed store and fails fast when pointers are invalid.
- Dependency container exposes explicit registrations for instrumentation, pagination cache access, background worker factories, and the new `Domain::Services::CacheService` so presentation code never instantiates infrastructure types.
- Test-only monkey patches (`TestShims`) were deleted; specs no longer intercept global classes and must declare their own collaborators explicitly.

## Recent Improvements

- **Dependency Injection**: Reader/Menu controllers, pagination orchestrators, and formatting services now rely on container-provided collaborators (`instrumentation_service`, `pagination_cache`, `xhtml_parser_factory`, etc.).
- **Caching Pipeline**: Added `CacheService` to centralise cache validation and canonical path lookups, removing direct `Infrastructure::EpubCache` usage from controllers.
- **Presentation Discipline**: Controllers/components stopped requiring infrastructure files; a new architecture spec asserts this boundary.
- **Legacy Removal**: Stripped Marshal migration paths from `EpubCache`, removed pointer regeneration helpers, and eliminated test shims.

## Upcoming Initiatives

### Boundary & Layer Enforcement
1. Extend architectural specs to cover domain/services (e.g., forbid direct `Infrastructure::` references outside adapter services such as `CacheService`).
2. Catalogue helper modules under `lib/ebook_reader/helpers/` and decide which belong in domain vs infrastructure; document the outcome in `ARCHITECTURE.md`.
3. Audit `EpubDocument` responsibilities—split formatting and telemetry concerns into injected collaborators so the document remains a pure domain model.

### Dependency Composition & Container Hygiene
1. Replace remaining module singletons (`Infrastructure::Logger`, `Infrastructure::PerformanceMonitor`) with lightweight adapters that can be swapped for tests without mutating globals (Instrumentation bridge is first step).
2. Introduce container validation on boot that highlights unresolvable registrations (e.g., missing `:pagination_cache` in custom containers).
3. Provide factory shims for specs that currently stub the full container; move repeated stubbing logic into `spec/support/` helpers.

### Legacy & Dead Code Cleanup
1. Remove unused helpers and constants left under `lib/ebook_reader/helpers/` and `lib/ebook_reader/constants/` (audit with coverage + `rg 'TODO remove'`).
2. Collapse redundant application orchestrators once reader/menu loops share the same rendering pipeline hooks.
3. Delete outdated documentation (`RUBOCOP_OFFENSES_REFACTOR_ROADMAP.md`, stale TODO comments) after migrating relevant tasks into this roadmap or issue tracker.

### Observability & Telemetry Alignment
1. Wrap `PerfTracer`/`PerformanceMonitor` behind an injected instrumentation service; expose structured events so both UI modes publish uniform metrics.
2. Ship a log sanitiser that redacts book paths before emitting to the shared logger.
3. Add an opt-in instrumentation toggle to the container for offline CLI runs.

## Supporting Work

- **Testing**: Keep `bundle exec rspec` and architecture specs in CI. Add mutation or contract tests around `CacheService` to guarantee pointer invalidation behaviour.
- **Documentation**: Update `ARCHITECTURE.md` whenever new services or boundaries are introduced. Include diagrams showing DI flow from container → controllers → domain.
- **Tooling**: Consider a custom RuboCop cop (or Danger rule) that mirrors the new architecture spec so editors receive feedback before CI.

## Decision Log

- 2024-11-XX — Removed Marshal cache migrations and pointer rebuilders; cache regeneration now requires the SQLite pipeline.
- 2024-11-XX — Introduced `Domain::Services::CacheService` and architecture spec; controllers/components must resolve infrastructure dependencies through DI.
- 2024-11-XX — Added `Domain::Services::InstrumentationService` bridge and normalized controller specs to use shared document stubs, eliminating cross-spec constant leaks.
- 2024-11-XX — Deleted `TestShims` monkey patches; specs must stub collaborators directly.
