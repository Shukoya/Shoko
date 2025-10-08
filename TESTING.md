# Testing Guide

## Quick Start
- Run `bundle exec rspec`. `spec/spec_helper.rb` enables `EBOOK_READER_TEST_MODE=1` so the suite never touches the real TTY.
- Coverage is collected automatically; reports land in `coverage/`.

## Spec Taxonomy
- **Unit specs** live alongside the code they verify (`spec/domain`, `spec/application`, `spec/infrastructure`, `spec/components`, etc.). They target pure logic and DOM-free render helpers.
- **Integration specs** (`spec/integration/`) cover multi-component flows: menu navigation, cache wipes, pagination rebuilds, repositories.
- **System smoke specs** (`spec/system/`) run CLI entrypoints with the safe terminal adapter to guard regressions without opening the UI.

## Terminal & Input Safety
- `EbookReader::TestSupport::TerminalDouble` replaces the production terminal in test mode. No raw/cbreak, alternate screen, or cursor hiding occurs.
- Access the injectable terminal service via `container.resolve(:terminal_service)`. In test mode it is an instance of `EbookReader::TestSupport::TestMode::TestTerminalService` and exposes:
  - `queue_input(*keys)` – push scripted key sequences (or escape strings) for deterministic input.
  - `configure_size(height:, width:)` – control terminal geometry seen by the code under test.
  - `drain_input` – clear pending keys between expectations.
- Legacy helper `mock_terminal(width:, height:)` now delegates to the terminal double and remains safe to use.

## Writing New Specs
- Prefer building a fresh dependency container: `container = EbookReader::Domain::ContainerFactory.create_default_container`. In test mode it already uses the safe terminal service.
- Avoid calling long-running loops (`ReaderController#run`, `MenuController#run`). Instead, exercise controllers via injected services and dispatchers while queuing deterministic input.
- For CLI behavior, wrap calls with `StringIO` (`spec/system/cli_smoke_spec.rb` shows the pattern) and assert on captured output.
- Use `FakeFS` (tag `:fakefs`) for filesystem-heavy flows. Keep EPUB fixtures minimal; `spec/support/zip_builder.rb` helps build archives when needed.
- When stubbing repositories or background services, register them on the container (`container.register(:settings_service, double(...))`) instead of altering production singletons.

## Cleanup & Determinism
- `spec/spec_helper.rb` resets the terminal double and logger before every example, preventing leakage between tests.
- `Infrastructure::Logger` is silenced (`level = :fatal`, writes to `/dev/null`) in test mode. If a spec needs to observe logging, temporarily override `Logger.output` and restore it in an `ensure` block.

## Performance Targets
- Full suite finishes in under ~15s on a mid-tier laptop (Ruby 3.4). Integration specs avoid sleeps and blocking IO; any new long-running test should document its runtime and gating conditions.

## Adding Fixtures
- EPUB fixtures should stay tiny (<5 KB) and live in `spec/fixtures/epub/` if persisted. Prefer on-the-fly generation with `ZipTestBuilder` or `FakeFS` to keep checkout size small.
- Cache directories and user-config paths must be pointed at temporary locations (use `stub_const` + `FakeFS`). Never write to the real `$HOME` or XDG directories during tests.

Following these rules keeps the suite terminal-safe, deterministic, and CI-friendly.
