# Changelog

All notable changes to ClipFormat are recorded here. The version in
`project.yml` (`MARKETING_VERSION`) is the source of truth; the release
workflow refuses to build a tag that disagrees with it.

## 0.1.0

First public build of the revived ClipFormat.

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
