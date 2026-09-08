# Changelog

All notable changes to ClipFormat are recorded here. The version in
`project.yml` (`MARKETING_VERSION`) is the source of truth; the release
workflow refuses to build a tag that disagrees with it.

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
