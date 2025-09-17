# Foliate EPUB Formatting – Reference Notes

## Source Layout
- `foliate/src/reader/reader.js` – main runtime for the embedded WebView. Generates CSS, wires settings (line height, hyphenation, justification, fonts, themes) and manages renderer helpers.
- `foliate/src/reader/markup.js` – converts HTML fragments to Pango markup for tooltips/annotations; handles tag sanitising.
- `foliate/src/themes.js` – theme palette definitions (light/dark pairs) and loader for external JSON themes.
- `foliate/src/reader` assets (`reader.html`, `reader.js`) – UI host for the renderer, hooking footnotes/TTS/printing.
- `foliate/src/selection-tools/…` – context actions and overlay styling for selections.
- `foliate/src/book-viewer.js` – glue between GTK UI and WebView settings (not yet analysed in depth).
- `foliate/src/foliate-js/view.js` – main renderer (submodule, not present locally; follow up when available).

## Key Behaviours to Mirror
1. **CSS Injection Pipeline** (`reader.js:getCSS`)
   - Dynamically builds CSS using runtime style object: `lineHeight`, `justify`, `hyphenate`, `invert`, theme colors, user style sheet, optional font override, and active-media class.
   - Uses `color-scheme`, `color-mix`, `prefers-color-scheme` media queries to keep light/dark/invert in sync.
   - Applies `hanging-punctuation`, `orphans/widows`, balanced headings, and `pre` adjustments (pre-wrap, tab-size).
   - When theme backgrounds differ from pure white/black, forces body descendants to inherit theme colours and applies blend modes to images.

2. **Theme Architecture** (`themes.js`)
   - Themes are defined as { name, label, light, dark } with `fg`, `bg`, and `link` colours.
   - Additional JSON themes can be loaded at runtime.
   - GTK CSS provider maps theme IDs to UI preview accents.
   - `invertTheme` derives inverted palette for cases like high-contrast invert.

3. **Markup Sanitisation** (`markup.js`)
   - Converts arbitrary HTML fragments to a restricted tag set usable in Pango (anchors, basic emphasis, lists, code).
   - Inserts newlines for block elements and bullet markers for list items.
   - Removes unsupported attributes and tags by hoisting their children (the `usurp` helper).
   - Escapes HTML entities carefully (`&amp;` handling for double escaping).

4. **Renderer Hooks** (`reader.js`)
   - `makeBook` (foliate-js) instantiates a reader view and passes it to `Reader` class (GTK WebKit). The view exposes `renderer` with methods `scrollBy`, `snap`, `tts`, `print` wrappers.
   - Selection handling uses `FootnoteHandler`, `Overlayer` for footnote pop-ups and selection overlays.
   - `embedImages` converts images inside selection ranges to data URIs before copy/export.
   - Uses `Intl` locales to format numbers, dates, durations; matches locales via Gio/GLib.

5. **User Settings Influence**
   - `lineHeight`, `justify`, `hyphenate`, `overrideFont`, `userStylesheet` are toggled at runtime and re-injected.
   - `mediaActiveClass` is added to highlight active audio/video elements.
   - Justification and hyphenation applied at paragraph level, but headings/hgroup override to `text-align: unset` / `hyphens: unset`.

6. **Accessibility**
   - `color-scheme` set to honour user system theme.
   - Uses `text-wrap: balance` for headings to improve readability.
   - `selection-tools` (not fully reviewed) likely add overlays with proper contrast.

## Gaps / Follow-up
- `foliate-js` submodule missing locally; need to inspect `view.js`, renderer implementation, and pagination strategy when available.
- Not yet captured: how Foliate handles intersections with MathML, RTL scripts, vertical writing – investigate `foliate-js` once retrieved.
- Evaluate how footnote overlays gather content (likely via `foliate-js/footnotes.js`).

## Migration Ideas for Ruby CLI Reader
1. **CSS Generator Equivalent**
   - Build a CSS template (string builder) in Ruby that mirrors Foliate’s `getCSS` toggles. Use configuration struct with line height, justification, hyphenation, theme palette, font override.
   - Support light/dark/ invert by computing ANSI palettes for CLI (see `lib/ebook_reader/constants/themes.rb` and `Components::RenderStyle.configure`). Map to attributes for primary/secondary/quote/code output.

2. **Theme Registry**
   - Port `themes.js` list to Ruby YAML/JSON, allowing user-provided themes. Provide colour pairs for CLI (foreground/background) and highlight colours.

3. **Markup Sanitiser**
   - Recreate `toPangoMarkup` logic to convert EPUB fragments to ANSI-friendly markup: restrict tags, convert lists/headings to bullet/spacing, strip unsupported attributes.
   - Build extractor using Nokogiri (or Oga) in Ruby.

4. **Renderer Strategy**
   - Investigate Foliate renderer (when available) to understand pagination, column layout, and hyphenation logic. Adapt principles to Ruby `FormattingService` (line spacing, Pango-like emphasis).

5. **Selection and Footnotes**
   - Study `selection-tools` and `footnotes.js` to see how inline footnotes/annotations are rendered. Plan CLI overlay equivalent (maybe using popups in alternate screen).

6. **Internationalisation**
   - Foliate relies on `Intl.*`. In Ruby, map to `I18n` / `strftime` / `NumberToHuman` to format language names, numbers, durations when presenting metadata.

7. **Testing References**
   - Capture sample CSS output from `getCSS` for different settings to use as fixtures while porting.

Keeping this document updated as we dig deeper (especially once the `foliate-js` renderer sources are available) will help translate Foliate’s mature formatting pipeline into the CLI reader.
