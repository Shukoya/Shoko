# Reader Data & Pipeline Reference

## Data Artifacts
- **EPUB cache file** (`~/.cache/reader/<sha256>.cache`)
  - Produced by `EbookReader::Infrastructure::BookCachePipeline` on first import.
  - Serialized via `Marshal` and encapsulates an `EpubCache::CachePayload` containing:
    - Source metadata (`source_sha256`, `source_path`, `source_mtime`, `generated_at`).
    - `BookData` (title, language, authors, chapters, TOC entries, OPF path, spine, resolved chapter hrefs, raw resources, extracted metadata).
    - Embedded pagination layouts keyed by layout string (`layouts[key] = { 'version' => 1, 'pages' => [...] }`).
- **Pagination cache entries**
  - Stored inside the `.cache` payload and managed via `Infrastructure::PaginationCache`.
  - Schema version `1`; entries mirror the compact format used by `PageCalculatorService`.
- **Library scan cache** (`~/.config/reader/epub_cache.json`)
- **Library scan cache** (`~/.config/reader/epub_cache.json`)
  - Produced by `EPUBFinder`; keeps `version`, `timestamp`, and `files[]` entries (`path`, `name`, `size`, `modified`, `dir`).
  - Expiry governed by `Constants::CACHE_DURATION`.
- **Recent files** (`~/.config/reader/recent.json`)
  - Managed by `EbookReader::RecentFiles`; list of `{path, name, accessed}` objects.
- **Reading progress** (`~/.config/reader/progress.json`)
  - Written by `ProgressFileStore`; map keyed by canonical book path containing `chapter`, `line_offset`, `timestamp`.
- **Bookmarks** (`~/.config/reader/bookmarks.json`)
  - Stored via `BookmarkFileStore`; per-book lists of `{chapter, line_offset, text, timestamp}`.
- **Annotations** (`~/.config/reader/annotations.json`)
  - Tracked by `AnnotationFileStore`; per-book arrays containing `{id, text, note, range, chapter_index, created_at, updated_at?, page_*}` metadata.

## Cache Keys & Invalidation
- **Book cache**: filename uses the SHA-256 digest of the source EPUB. `EpubCache#load_for_source` treats files as stale when the payload version differs or when the stored digest/mtime mismatch the current EPUB.
- **Pagination cache**: key = `width x height + view_mode + line_spacing` (`PaginationCache.layout_key`). Entries are embedded within the Marshal payload; missing keys trigger a rebuild.
- **Library scan cache**: invalidated when `Constants::CACHE_DURATION` elapses or `--force` scan is requested.
- **Per-book metadata (progress/bookmarks/annotations)**: keyed by canonical EPUB path (`StateController#canonical_path_for_doc`); no automatic pruning when files move.

## Pipelines
```
Cold open
-----------
cli.rb -> UnifiedApplication#reader_mode
  -> PerfTracer.start_open
  -> DocumentService#load_document
      -> BookCachePipeline.load (miss)
          -> EpubImporter.import (Zip::File, container/OPF parse, chapter/resource extraction)
          -> EpubCache.write_book! (Marshal payload)
  -> ReaderController#run
      -> ReaderStartupOrchestrator#start (load progress, pagination build)
      -> PaginationOrchestrator.initial_build (dynamic map)
      -> ReaderController#perform_first_paint (TTFP metric, PerfTracer.complete)
```
```
Warm open
----------
cli.rb -> UnifiedApplication#reader_mode
  -> PerfTracer.start_open
  -> DocumentService#load_document
      -> BookCachePipeline.load (cache hit, payload integrity check)
  -> ReaderController#run
      -> ReaderStartupOrchestrator#start (load progress, pagination cache check)
      -> PageCalculatorService#get_page (hydrate cached page map entries)
      -> ReaderController#perform_first_paint (TTFP metric, PerfTracer.complete)
```

## Performance Metrics (DEBUG_PERF=1)
- `open.invoke` — total time from CLI invocation until first paint completes.
- `cache.lookup` — combined time spent loading Marshal payloads and pagination layouts (`BookCachePipeline.load`, `PaginationCache.load_for_document`).
- `zip.read` — time spent opening the EPUB archive and reading container/OPF/chapter resources.
- `opf.parse` — OPF XML parsing and spine/manifest extraction.
- `xhtml.normalize` — XHTML to plain text conversion for chapters presented before first paint.
- `page_map.hydrate` — hydration of cached pagination entries into line slices for rendering.
- `render.first_paint.ttfp` — recorded TTFP (monotonic clock delta at `ReaderController#perform_first_paint`).

Log output when instrumentation is enabled (one line per open):
```
perf open=warm open.invoke=142ms cache.lookup=10ms zip.read=6ms opf.parse=18ms xhtml.normalize=0ms page_map.hydrate=22ms render.first_paint.ttfp=142ms
```

## Known Limitations
- Cache payloads trust embedded resources; manual edits that keep Marshal loadable may surface only when rendered.
- Pagination layouts remain layout-keyed and rewrite the full `.cache` file when updated.
- Cache files accumulate under `~/.cache/reader/`—there is no automatic eviction for obsolete hashes.

## Performance (current baseline)
Measured with `tmp/books/book_short.epub` (single-chapter) and `tmp/books/book_long.epub` (three chapters) using `EBOOK_READER_TEST_MODE=1` to exit immediately after first paint.

### Cold Open (ms)
| Stage | Short Story P50 | Short Story P95 | Collected Letters P50 | Collected Letters P95 |
| --- | --- | --- | --- | --- |
| open.invoke | 15 | 16 | 27 | 28 |
| cache.lookup | 1 | 1 | 1 | 1 |
| zip.read | 1 | 1 | 1 | 1 |
| opf.parse | 1 | 1 | 1 | 1 |
| xhtml.normalize | 0 | 0 | 0 | 0 |
| page_map.hydrate | 0 | 0 | 0 | 0 |
| render.first_paint.ttfp | 15 | 16 | 27 | 28 |

### Warm Open (ms)
| Stage | Short Story P50 | Short Story P95 | Collected Letters P50 | Collected Letters P95 |
| --- | --- | --- | --- | --- |
| open.invoke | 5 | 5 | 18 | 19 |
| cache.lookup | 3 | 3 | 3 | 3 |
| zip.read | 0 | 0 | 0 | 0 |
| opf.parse | 1 | 1 | 1 | 1 |
| xhtml.normalize | 0 | 0 | 0 | 0 |
| page_map.hydrate | 0 | 0 | 0 | 0 |
| render.first_paint.ttfp | 5 | 5 | 18 | 19 |
