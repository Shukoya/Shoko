# Zipper Implementation Roadmap (Make rubyzip Obsolete)

Goal: Remove the third‑party `rubyzip` dependency and replace all ZIP/EPUB archive reads with a small, internal implementation that uses only the Ruby standard library. Users should be able to download and run Reader with just Ruby installed — no `bundle install` required.

## Current State and Usage

- Dependency: `rubyzip` declared in `Gemfile` and `Reader.gemspec`.
- Call sites (read‑only):
  - `lib/ebook_reader/epub_document.rb` — opens `.epub` (ZIP), reads entries with `zip.read`, checks existence with `find_entry`, closes `zip`.
  - `lib/ebook_reader/helpers/metadata_extractor.rb` — opens `.epub`, finds OPF via `META-INF/container.xml`, reads OPF.
  - `lib/ebook_reader/helpers/opf_processor.rb` — optionally receives an open `zip` object; uses `read` and `find_entry`.
  - `lib/ebook_reader/infrastructure/epub_cache.rb` — copies a handful of entries into a cache directory using `zip.read`.
- Required API surface (minimal):
  - `Zip::File.open(path) { |zip| ... }`
  - `zip.read(entry_path) -> String`
  - `zip.find_entry(entry_path) -> truthy/nil`
  - `zip.close` and `zip.closed?`
  - Exception class: `Zip::Error` (raised on malformed archives/unsupported compression/missing entries where appropriate).

No write/update/append semantics are used anywhere. EPUBs are treated as read‑only containers.

## Single Best Approach

Implement a tiny, read‑only ZIP reader that mimics the subset of `rubyzip` we use, exposed under `Zip::File`. Place it at `lib/zip.rb` so `require 'zip'` resolves to our code. Keep call sites unchanged. Internally, parse the ZIP End‑of‑Central‑Directory and Central Directory records to index entries, and read file data by seeking to the Local File Header and inflating DEFLATE (method 8) via `Zlib` or returning stored (method 0) bytes. No external tools. Standard library only: `File`, `StringIO`, `Zlib`.

Rationale:
- Zero call‑site churn: API compatible with existing usage.
- Small and auditable: implement only what we need (read file by name, existence check), aligned with the project’s lightweight philosophy.
- Robust enough for EPUBs: Most EPUBs use DEFLATE or STORE, no encryption, modest file sizes.

## Detailed Implementation Plan

1) Implement internal ZIP reader (read‑only)
   - File: `lib/zip.rb`
   - Public API:
     - `module Zip; class Error < StandardError; end; class File ... end; end`
     - `.open(path) { |zip| ... }` with block semantics and `.close` fallback if no block.
     - `#read(path)` returns decompressed bytes as binary string.
     - `#find_entry(path)` returns an entry object or `nil` (truthiness only used).
     - `#closed?` mirrors underlying file state.
   - Internal model: `Entry = Struct` with: `name`, `compressed_size`, `uncompressed_size`, `compression_method`, `gp_flags`, `local_header_offset`.
   - Parsing:
     - Locate EOCD (signature `0x06054b50`) by scanning last ≤ 66 KiB of the file.
     - Read Central Directory size/offset and entry count.
     - Iterate Central Directory headers (signature `0x02014b50`), collect entry metadata and names. Normalize names to forward slashes, strip leading `./`.
   - Reading an entry:
     - Seek to Local File Header at `local_header_offset` (signature `0x04034b50`).
     - Parse local header to compute start of file data (`name_len + extra_len` after header).
     - Read `compressed_size` bytes (from Central Directory entry), then:
       - If method `0` (store): return as‑is.
       - If method `8` (deflate): inflate using `Zlib::Inflate.new(-Zlib::MAX_WBITS)` and return.
       - Else: raise `Zip::Error, 'unsupported compression method'`.
     - Do not implement encryption, spanned archives, ZIP64, or other methods.
   - Error handling:
     - On malformed headers/signatures/short reads: raise `Zip::Error`.
     - On missing entry in `#read`: raise `Zip::Error` (current code rescues it). `#find_entry` returns `nil`.
   - Performance: keep one open `::File` handle per `Zip::File`; index entries once on open; no temporary extraction.

2) Integrate with existing code
   - Keep `require 'zip'` in:
     - `lib/ebook_reader/epub_document.rb`
     - `lib/ebook_reader/helpers/metadata_extractor.rb`
   - No changes to call sites. Our `lib/zip.rb` will be loaded via `$LOAD_PATH`.
   - Optional: update comments where they mention rubyzip.

3) Remove `rubyzip` dependency
   - `Gemfile`: delete `gem 'rubyzip'`.
   - `Reader.gemspec`: remove `spec.add_dependency 'rubyzip', '~> 2.3'`.
   - `README.md`: remove “EPUB parsing uses rubyzip” note.

4) Tests and validation
   - Unit tests for `Zip::File` (new):
     - Fixture: add a tiny `.zip` (or `.epub`) containing a few small files with DEFLATE and STORE entries. Verify `#find_entry` and `#read` byte‑exact outputs and `Zip::Error` on unknown names.
     - EOCD search robustness: exercise with and without a ZIP comment.
   - Integration smoke:
     - Existing integration tests already open cached directories; add one that opens a real `.epub` fixture via `EPUBDocument` to validate the end‑to‑end flow with our reader.
   - Performance check: open a medium `.epub` and read OPF + 3 spine files; ensure timings comparable to or better than rubyzip for these operations.

5) Documentation
   - This file tracks goal, scope, and progress.
   - `ARCHITECTURE.md`: add a short note under “EPUB Cache” that ZIP reads are handled in‑house (stdlib only).
   - `README.md`: reflect zero runtime deps beyond Ruby; remove `rubyzip` mention.

## Scope and Constraints

- Supported:
  - Read‑only ZIP archives with methods: STORE (0) and DEFLATE (8).
  - UTF‑8 file names (common in EPUBs). Directory entries are ignored for reads.
  - Archives where sizes are reliable in the Central Directory (standard case, even when local header uses data descriptor — we trust CD values).
- Not supported (will raise `Zip::Error`):
  - Encrypted archives.
  - Spanned/multi‑disk archives.
  - ZIP64 (very large files) — not expected in EPUBs.
  - Non‑UTF‑8 names or exotic compression methods.

These constraints match typical EPUBs and our current usage, keeping the implementation minimal and robust.

## Risks and Mitigations

- Non‑DEFLATE EPUBs: Rare; raise clear `Zip::Error` with instructions. Mitigation: document support and add a fallback message in `EPUBDocument` error chapter.
- Name encoding quirks (CP437): Most EPUBs use UTF‑8. Mitigation: normalize and treat names as UTF‑8; consider CP437 fallback only if encountered in the wild.
- ZIP64 archives: out‑of‑scope; validate on open and raise early.
- Spec coverage: add focused unit tests for the ZIP reader and one end‑to‑end `EPUBDocument` open test with a small fixture.

## Acceptance Criteria

- Code compiles and runs without `rubyzip` in Gemfile or gemspec.
- All existing specs pass; additional ZIP unit tests pass.
- Opening a normal `.epub` renders chapters, metadata, and builds cache correctly.
- `EPUBDocument` and `MetadataExtractor` work unchanged and rescue `Zip::Error` on invalid archives.
- `README.md` no longer references `rubyzip` and states “Ruby only” runtime.

## Implementation Checklist (to update as we go)

- [x] Add `lib/zip.rb` with `Zip::File` read‑only implementation and `Zip::Error`.
- [x] Wire into repo (no call‑site changes required).
- [x] Remove `rubyzip` from Gemfile and gemspec.
- [x] Update README/ARCHITECTURE notes.
- [ ] Add ZIP unit tests + end‑to‑end EPUB open test.
- [ ] Verify performance and memory on medium EPUB.
- [ ] Cut a release tag or note in CHANGELOG.

## Developer Notes (format details for implementers)

- Little‑endian helpers:
  - `u16 = bytes.unpack1('v')`, `u32 = bytes.unpack1('V')`.
- Headers:
  - EOCD: `PK\x05\x06` at unknown offset near EOF; fields: disk numbers, entry counts, CD size, CD offset, comment length.
  - Central Directory header: `PK\x01\x02`; fields include method, flags, sizes, name/extra/comment lengths, local header offset.
  - Local File header: `PK\x03\x04`; fields include method, flags, (sizes may be 0 if data descriptor used), name/extra lengths; data follows.
- DEFLATE inflation: `Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(data) + finish` (ensure `ensure { inflater.close }`).
- Normalize entry names: replace backslashes with `/`, strip leading `./`.

---

Owner: Infra/Core  
Last updated: YYYY‑MM‑DD  
Contact: Maintainers
