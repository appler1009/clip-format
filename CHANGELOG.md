# Changelog

All notable changes to ClipFormat are recorded here. The version in
`project.yml` (`MARKETING_VERSION`) is the source of truth; the release
workflow refuses to build a tag that disagrees with it.

## 0.5.0

- Settings → Formatting can show invisible characters: spaces as `·`, tabs as
  `⇥`, and line breaks as `↵`. Works for formatted JSON/XML and for plain
  unrecognized clipboard text. Copy Pretty / Minified stay clean.
- The status-item popover and the torn-off window share the same top-trailing
  Liquid Glass action cluster (Copy menu, font size, Preferences). The window
  no longer uses a separate toolbar for those controls.

## 0.4.4

- Preferences no longer includes the Quick Look troubleshooting blurb with
  `qlmanage` — that belongs in the README, not in Settings.

## 0.4.3

- The popover no longer restates what the menu-bar ✓/✕ already says: status
  titles, coloured dots and error labels are gone. Unrecognised clipboard text
  is not labelled as broken JSON.
- A quiet grabber at the top of the popover cues drag-to-tear-off. The torn-off
  window keeps its title bar and omits the handle.
- About, window title and the status-item menu name the product rather than
  assuming JSON is the only format.

## 0.4.2

- About ClipFormat reads `Revived.` on its own line, then `JSON in the menu bar
  and in Quick Look.` — no more "Formats".
- The installer DMG has a styled Finder window: white background matching the
  light theme, minified → pretty as the drag direction, and the app's syntax
  colours for the arrow between ClipFormat and Applications.

## 0.4.1

- The formatted text sits at the top left of the pane again. A scroll view
  centres content smaller than itself, which never showed in the popover's
  fixed frame but left a short document floating in the middle of a torn-off
  window that had been made large.

## 0.4.0

- JSONC. `.jsonc` files, and any `.json` that tooling has written loosely —
  `tsconfig.json`, VS Code settings — are read instead of refused: `//` and
  `/* … */` comments, and a comma before the closing brace or bracket.
- XML. Elements are indented, attributes keep their source order, and comments,
  the declaration and namespace declarations all survive. `.xml` files preview
  in Finder, and XML on the clipboard is recognised the same way JSON is.
- The torn-off window can go full screen; the green button offered only zoom
  before. Its remembered frame is unaffected by the transition.

Strict JSON is still tried first and is never re-read loosely, so a document
that parses as RFC 8259 JSON is reported as JSON. Two consequences worth
knowing: a trailing comma is no longer an error in a JSON document, since such
a document is valid JSONC (JSON Lines records stay strict, that format being
defined as one valid JSON value per line); and neither comments nor trailing
commas survive the formatting, because the output is rebuilt from the parsed
value — `{"a":1,}` comes back as `{"a":1}`.

## 0.3.0

- JSON Lines. A file or clipboard holding one JSON value per line — the format
  also called NDJSON — is recognised as such rather than reported as a broken
  document. Each record is expanded in turn, the header counts them, and
  **Copy Minified** gives the file's own shape back, one record per line.
- Quick Look now previews `.jsonl` and `.ndjson` alongside `.json`.

Detection is deliberately strict: every non-empty line has to parse and each
has to be an object or an array. One bad line and the source is reported as a
broken JSON document, so the parse error stays visible instead of being
swallowed by a guess about the format.

## 0.2.0

- The popover tears off into a window. Drag it away from the status item and it
  becomes a standalone "Clipboard JSON" window — AppKit's own gesture, no button
  to learn. The window keeps mirroring the clipboard rather than freezing what
  was on screen when it was torn off, so it can sit beside your work and follow
  along. It is resizable, remembers where and how big you left it, and Escape
  closes it. While one is open, clicking the status item brings it forward
  instead of opening a second copy.

## 0.1.2

- App icon: the menu-bar braces holding three syntax-coloured lines, drawn in
  the same palette as the popover and the Quick Look preview. Small sizes get
  their own treatment — two heavier lines at 32px, braces alone at 16px, since
  three thin lines smear at that scale.

## 0.1.1

First published build. 0.1.0 was tagged but never released — its release
workflow failed on signing, and the fixes below landed before it shipped.

- Quick Look reads a `.json` file whole or not at all. It previously parsed only
  the first 8 MB, so any larger file — however valid — was reported as "Not
  JSON" rather than previewed. Files past the 32 MB limit now say so by size.
- The App Group identifier is prefixed with the team id, which is what macOS
  requires outside the App Store. Without it the shared defaults suite never
  existed and Quick Look silently ignored the indent and font size set in the
  app.
- Releases sign with the Developer ID certificate alone; the provisioning
  profiles the workflow used to require are gone, and the build no longer emits
  a binary carrying `get-task-allow`.

Everything from 0.1.0 below is part of this build.

## 0.1.0

Tagged but never published; superseded by 0.1.1.

- Menu-bar status item showing whether the clipboard holds valid JSON, with a
  green ✓ / red ✕ badge on template braces.
- Popover with pretty-printed, syntax-coloured JSON, byte count, Copy Pretty and
  Copy Minified, and ⌘+ / ⌘− to change the text size.
- Quick Look preview extension for `.json` files, rendering through the same
  formatter as the popover so the two cannot drift apart.
- Hand-written JSON parser that preserves object key order and number literals,
  and reports parse errors with a line and column.
- Preferences: indent width, popover font size, badge visibility, launch at
  login.
- Large payloads are parsed off the main thread and formatted output is capped
  on screen; Copy Pretty still returns the whole document.
