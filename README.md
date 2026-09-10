# ClipFormat

A free macOS menu-bar app that shows you the JSON or XML on your clipboard, formatted — and brings the same formatting to Finder's Quick Look.

Copy some JSON or XML, and the menu-bar icon turns green. Click it, and there's your payload, indented and syntax-coloured. Press Space on a `.json`, `.jsonc`, `.jsonl`, `.ndjson` or `.xml` file in Finder, and you get the same view.

Still free, still no paywall.

## What it does

- **Menu-bar state at a glance** — braces with a green ✓ when the clipboard holds something this app can format, a red ✕ when it holds JSON or XML that does not parse.
- **Click for the formatted view** — syntax-coloured, selectable, scrollable, with a top action cluster (Copy Pretty / Minified, font size, Preferences). Escape dismisses the popover.
- **Tear it off** — drag the six-dot grabber (or the popover) away from the menu bar and it becomes a window that keeps following the clipboard. Resizable, remembers its frame, full-screen capable, Escape to close.
- **Quick Look for `.json`, `.jsonc`, `.jsonl`, `.ndjson` and `.xml` files** — Spacebar in Finder renders through the same code the popover uses.
- **JSON Lines** — a file or clipboard holding one JSON value per line is recognised as such, each record expanded in turn. **Copy Minified** gives the file's own shape back, one record per line.
- **JSONC** — `.jsonc`, and any `.json` that tooling has written loosely (`tsconfig.json`, VS Code settings), read rather than refused: `//` and `/* … */` comments, and a comma before the closing brace or bracket.
- **XML too** — elements indented, attributes kept in source order, comments and the declaration preserved, namespaces intact.
- **Tells you what's wrong** — invalid JSON gets the parse error with a line and column, plus an excerpt of what was actually on the clipboard.
- **Stays out of the way** — no Dock icon (`LSUIElement`), no clipboard rewriting, no history stored anywhere.

Object keys keep their source order, and number literals survive verbatim: `1.50` stays `1.50`, `1e9` stays `1e9`. `JSONSerialization` gives up both, which is why there's a hand-rolled parser here.

## Build and run

Requires macOS 14+ and Xcode 15+. The project file is generated, so [XcodeGen](https://github.com/yonaskolb/XcodeGen) is the one dependency:

```sh
brew install xcodegen
xcodegen generate
open ClipFormat.xcodeproj
```

Then build and run the **ClipFormat** scheme. The Quick Look extension is embedded in the app and registers with the system when the app is launched from a stable location — move the built app to `/Applications` and open it once.

Shared-core tests run without Xcode:

```sh
cd Shared/ClipFormatShared && swift test
```

Performance microbenches for the parse → print → render path:

```sh
cd Shared/ClipFormatShared && swift test --filter PerformanceBenchmarks
```

## Layout

```
Apps/ClipFormat/            Menu-bar host: status item, popover, preferences
Extensions/ClipFormatPreview/  Quick Look preview extension (com.apple.quicklook.preview)
Shared/ClipFormatShared/    Parser, pretty printer, theme, HTML + AttributedString renderers
Fixtures/                   Sample .json files, including invalid and large ones

```

The rule the layout enforces: **the popover and Quick Look call the same functions.** Both render the same `[SyntaxToken]` stream through the same `Theme`, one to `AttributedString` and one to HTML, so they cannot drift apart.

## Preferences

Right-click the menu-bar icon → Preferences…, or press ⌘, while the app is key (popover or torn-off window).

- **Indent** — 2, 4, or 8 spaces (popover and Quick Look)
- **Font size** — 9–28 pt for the popover JSON; ⌘+ / ⌘− also change it while the popover or window is open. Quick Look uses the last saved size on the next Spacebar.
- **Show invisible characters** — spaces as `·`, tabs as `⇥`, line breaks as `↵` in the preview (formatted or plain). Copy Pretty / Minified stay clean.
- **Show ✓ / ✕ badge** — off gives you plain template braces
- **Launch at login** — via `SMAppService`

## Quick Look not updating?

Quick Look caches aggressively, and other handlers compete for `public.json`.

```sh
qlmanage -r && qlmanage -r cache     # reload generators and clear the cache
qlmanage -m plugins | grep -i clip   # confirm ClipFormat is registered
```

If it still doesn't attach: keep the app in `/Applications`, open it once, and check **System Settings → General → Login Items & Extensions → Quick Look**.

## Limits

- The menu-bar badge deliberately ignores bare literals — copying `42` or `"hello"` is technically valid JSON but flagging it would make the badge meaningless. Objects and arrays count.
- Formatted output is capped at 500,000 characters on screen; past that the view is truncated with a notice. **Copy Pretty** still gives you the whole thing.
- Sources over 32 MB aren't parsed. Quick Look reads a file whole or not at all: past that limit it says so by size, because a leading slice of a JSON document cannot parse and reporting it as malformed would be a lie. A 32 MB document can still take long enough to bump against Quick Look's time budget.
- XML attributes keep their source order, but namespace declarations are printed first regardless of where they appeared — `XMLDocument` reports them separately from the other attributes and their original position is not recoverable.
- Text inside an element is trimmed of surrounding whitespace everywhere — the formatted view, **Copy Pretty** and **Copy Minified**. That is what keeps `<title>Hi</title>` on one line, but it does rewrite a document that leans on leading or trailing spaces, including one that sets `xml:space="preserve"`.
- CDATA is shown as text. It parses and renders correctly, but the `<![CDATA[…]]>` wrapper is not reproduced.
- Comments are read, not kept. Formatting is driven by the parsed value, so **Copy Pretty** and the rendered view show the JSON without the comments that were in the source.
- Strict JSON is tried first and never re-read loosely: a document that parses as RFC 8259 JSON is reported as JSON, and the looser rules are only considered once that has failed. The consequence is that a trailing comma no longer produces a parse error in a JSON document — such a document is valid JSONC, and the menu-bar badge goes green for it. JSON Lines records stay strict, since that format is defined as one valid JSON value per line.
- JSON Lines is all or nothing: every non-empty line has to parse, and each has to be an object or an array. One bad line and the whole thing is reported as a broken JSON document instead, which keeps the parse error visible rather than burying it.
- Quick Look is a snapshot: change indent or font size, then press Space again (or `qlmanage -r`) to see it. The preview does not live-update.
- Copied `.geojson` / `.webmanifest` files are read as JSON when dropped on the pasteboard as file URLs; there is no GeoJSON-specific validation or map preview yet.

## Roadmap

Shipped recently (see `CHANGELOG.md`): Liquid Glass action chrome shared by popover and window, invisible-character toggle, Escape-to-dismiss, ⌘, → Settings, and a performance pass on parse / print / preview.

### Next up (likely order)

1. **Collapsible tree + key-path copy** — fold objects/arrays in the preview; copy a dotted / JSONPath-style path for the selection. Biggest win for large payloads once formatting alone is not enough.
2. **Secret masking** — redact values under keys like `password`, `token`, `secret`, `authorization` in the *preview* (Copy Pretty stays raw, or gets an explicit “Copy with secrets” later). Natural fit for a clipboard formatter.
3. **Find in preview** — ⌘F over the formatted text (and eventually the tree). Small surface, high daily use.
4. **YAML** — clipboard + Quick Look for `.yaml` / `.yml`, through the same token/theme pipeline so the hosts cannot drift.
5. **Thumbnail extension** — Finder icons for JSON/XML that hint at validity or kind, alongside today's Quick Look preview.
6. **GeoJSON extras** — validation and a tiny map/extent summary; file-URL paste already treats `.geojson` as JSON.
7. **Legacy Format clipboard tricks** — stack traces, Base64 and URL decoding from the 2016 app, only where they stay a one-gesture clipboard helper rather than a second product.

### Not planning

- Clipboard history, cloud sync, or rewriting what you copy
- App Store paywall
