# Reader Data & Pipeline Reference

## Data Artifacts
- **EPUB cache directory** (`~/.cache/reader/<sha256>/`)
  - Created per book in `EbookReader::Infrastructure::EpubCache`.
  - Contains copied spine assets (`META-INF/container.xml`, OPF, XHTML) plus generated metadata.
  - Cache key is the SHA-256 digest of the source `.epub`; directory name doubles as cache key.
- **Manifest** (`manifest.msgpack` or `manifest.json` inside the cache directory)
  - Written via `EpubCache#write_manifest!` as version `1`.
  - Fields: `title`, `author`, `authors[]`, `opf_path`, `spine[]`, `epub_path`, optional `version`.
  - `msgpack` preferred when the gem is available; falls back to JSON.
- **Pagination cache** (`<cache>/pagination/<width>x<height>_<view>_<line>.msgpack|json`)
  - Saved through `Infrastructure::PaginationCache.save_for_document` with schema version `1`.
  - Payload: `pages[]` entries each holding `chapter_index`, `page_in_chapter`, `total_pages_in_chapter`, `start_line`, `end_line`.
  - Used for dynamic page numbering and hydrated lazily on warm open.
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
- **Book cache**: key = `SHA256(source_epub)` (see `EpubCache#initialize`). Miss occurs if required files are absent or manifest version exceeds 1.
- **Pagination cache**: key = `width x height + view_mode + line_spacing` (`PaginationCache.layout_key`). Layout changes or missing files trigger a rebuild.
- **Manifest**: `version` gate allows backward compatibility; higher version is ignored.
- **Library scan cache**: invalidated when `Constants::CACHE_DURATION` elapses or `--force` scan is requested.
- **Per-book metadata (progress/bookmarks/annotations)**: keyed by canonical EPUB path (`StateController#canonical_path_for_doc`); no automatic pruning when files move.

## Pipelines
```
Cold open
-----------
cli.rb -> UnifiedApplication#reader_mode
  -> PerfTracer.start_open
  -> DocumentService#load_document
      -> EPUBDocument#load_from_cache_dir? (miss) / #load_from_cache? (miss)
      -> Zip::File.open + parse_epub (find OPF, process spine, HTML normalize)
      -> schedule_cache_population (background)
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
      -> EPUBDocument#load_from_cache_dir? / #load_from_cache (manifest/msgpack)
  -> ReaderController#run
      -> ReaderStartupOrchestrator#start (load progress, pagination cache check)
      -> PageCalculatorService#get_page (hydrate cached page map entries)
      -> ReaderController#perform_first_paint (TTFP metric, PerfTracer.complete)
```

## Performance Metrics (DEBUG_PERF=1)
- `open.invoke` — total time from CLI invocation until first paint completes.
- `cache.lookup` — combined time spent loading manifest/pagination caches (`load_from_cache*`, `PaginationCache.load_for_document`).
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
- Cached spine assets are trusted after existence checks; stale or hand-edited cache directories are not revalidated against the source EPUB hash.
- Pagination caches are layout-keyed only; clearing occurs manually when dimensions change or users request cache deletion.
- Cache directories accumulate under `~/.cache/reader/`—there is no automatic eviction for obsolete hashes.

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
