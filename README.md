# ClipFormat

A free macOS menu-bar app that shows you the JSON on your clipboard, formatted — and brings the same formatting to Finder's Quick Look.

Copy some JSON, and the menu-bar icon turns green. Click it, and there's your payload, indented and syntax-coloured. Press Space on a `.json`, `.jsonc`, `.jsonl` or `.ndjson` file in Finder, and you get the same view.

Still free, still no paywall.

## What it does

- **Menu-bar state at a glance** — braces with a green ✓ when the clipboard holds valid JSON, a red ✕ when it doesn't.
- **Click for the formatted view** — syntax-coloured, selectable, scrollable, with **Copy Pretty** and **Copy Minified**.
- **Tear it off** — drag the popover away from the menu bar and it becomes a window that keeps following the clipboard. Resizable, remembers its frame, Escape to close.
- **Quick Look for `.json`, `.jsonc`, `.jsonl` and `.ndjson` files** — Spacebar in Finder renders through the same code the popover uses.
- **JSON Lines** — a file or clipboard holding one JSON value per line is recognised as such, each record expanded in turn with a count in the header. **Copy Minified** gives the file's own shape back, one record per line.
- **JSONC** — `.jsonc`, and any `.json` that tooling has written loosely (`tsconfig.json`, VS Code settings), read rather than refused: `//` and `/* … */` comments, and a comma before the closing brace or bracket.
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

## Layout

```
Apps/ClipFormat/            Menu-bar host: status item, popover, preferences
Extensions/ClipFormatPreview/  Quick Look preview extension (com.apple.quicklook.preview)
Shared/ClipFormatShared/    Parser, pretty printer, theme, HTML + AttributedString renderers
Fixtures/                   Sample .json files, including invalid and large ones

```

The rule the layout enforces: **the popover and Quick Look call the same functions.** Both render the same `[JSONToken]` stream through the same `Theme`, one to `AttributedString` and one to HTML, so they cannot drift apart.

## Preferences

Right-click the menu-bar icon → Preferences.

- **Indent** — 2, 4, or 8 spaces (popover and Quick Look)
- **Font size** — 9–28 pt for the popover JSON; ⌘+ / ⌘− also change it while the popover is open. Quick Look uses the last saved size on the next Spacebar.
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
- Comments are read, not kept. Formatting is driven by the parsed value, so **Copy Pretty** and the rendered view show the JSON without the comments that were in the source.
- Strict JSON is tried first and never re-read loosely: a document that parses as RFC 8259 JSON is reported as JSON, and the looser rules are only considered once that has failed. The consequence is that a trailing comma no longer produces a parse error anywhere — such a document is valid JSONC, and the menu-bar badge goes green for it.
- JSON Lines is all or nothing: every non-empty line has to parse, and each has to be an object or an array. One bad line and the whole thing is reported as a broken JSON document instead, which keeps the parse error visible rather than burying it.
- Quick Look is a snapshot: change indent or font size, then press Space again (or `qlmanage -r`) to see it. The preview does not live-update.

## Roadmap

Thumbnail extension, XML, YAML, GeoJSON, collapsible tree view and key-path copy, secret masking for `password` / `token` keys, and the 2016 app's other formats — XML, stack traces, Base64 and URL decoding.
