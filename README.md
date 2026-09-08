# ClipFormat

A free macOS menu-bar app that shows you the JSON on your clipboard, formatted — and brings the same formatting to Finder's Quick Look.

Copy some JSON, and the menu-bar icon turns green. Click it, and there's your payload, indented and syntax-coloured. Press Space on a `.json` file in Finder, and you get the same view.

Still free, still no paywall.

## What it does

- **Menu-bar state at a glance** — braces with a green ✓ when the clipboard holds valid JSON, a red ✕ when it doesn't.
- **Click for the formatted view** — syntax-coloured, selectable, scrollable, with **Copy Pretty** and **Copy Minified**.
- **Quick Look for `.json` files** — Spacebar in Finder renders through the same code the popover uses.
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

### App Group (Quick Look prefs)

Both binaries request `TN2RQ5P647.group.com.appler1009.ClipFormat`. Outside the
App Store macOS authorises a group by the **team ID prefix on the identifier**,
so the id must start with the team id — a bare `group.…` is rejected, and
`containermanagerd` says so in the log:

```
REJECTED. Group containers identifiers should be prefixed by requestor's
team ID to allow access on this platform.
```

On a paid team, register the group once so both App IDs can claim it:

1. [developer.apple.com/account](https://developer.apple.com/account) → **Identifiers** → **App Groups** → register `TN2RQ5P647.group.com.appler1009.ClipFormat`.
2. Edit App IDs `com.appler1009.ClipFormat` and `com.appler1009.ClipFormat.Preview` → enable **App Groups** → tick that group.
3. Or in Xcode: each target → **Signing & Capabilities** → **+ Capability** → **App Groups** → check the same id.

Without that portal step, each process gets its own defaults file and Quick Look
stays on the built-in 2-space / 12 pt defaults. No provisioning profile is
involved: a Developer ID certificate signs the group entitlement on its own.

The id changed after the first builds, and preferences do not migrate — indent,
font size and badge visibility live in the old container. The first launch after
this change looks like a preferences reset; set them again, or copy the old
values across.

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

## Releasing

`MARKETING_VERSION` in `project.yml` is the single source of truth for the
version — currently **0.1.0**. Everything else derives from it, and the release
workflow fails the build if a pushed tag disagrees, so the two can't drift.

To cut a release: bump `MARKETING_VERSION`, add a matching `## <version>`
section to [CHANGELOG.md](CHANGELOG.md) (its body becomes the release notes),
commit, then push a tag.

```sh
git tag v0.1.0 && git push origin v0.1.0
```

GitHub Actions builds, signs, notarizes, staples, and publishes a `.dmg`, a
`.zip` and `SHA256SUMS.txt` to the release. The same script runs locally:

```sh
Scripts/package.sh          # unsigned build into dist/
```

Signing and notarization are optional — without credentials the script still
produces artifacts, they just trip Gatekeeper on someone else's Mac. To get a
clean install, set these repository secrets:

| Secret | What it is |
| --- | --- |
| `CERTIFICATE_P12` | base64 of a **Developer ID Application** certificate export (`base64 -i cert.p12`) |
| `CERTIFICATE_PASSWORD` | password used for that export |
| `SIGNING_IDENTITY` | e.g. `Developer ID Application: Your Name (TEAMID)` |
| `TEAM_ID` | Apple Developer team identifier |
| `NOTARY_APPLE_ID` | Apple ID for notarization |
| `NOTARY_PASSWORD` | app-specific password for that Apple ID |

No provisioning profiles. An App Group is authorised outside the App Store by the
team ID prefix on its identifier, so the certificate signs both binaries on their
own. Profiles would only return for a `com.apple.developer.*` capability (iCloud,
push) or a Mac App Store build.

Because nothing validates entitlements against a profile, Xcode would otherwise
inject `com.apple.security.get-task-allow` into the Release build and the notary
service rejects any binary carrying it. The build sets
`CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` and `Scripts/package.sh` checks both
binaries afterwards, so that failure is caught locally rather than one
notarisation round trip later.

Note that a *Developer ID Application* certificate is required — an *Apple
Development* certificate signs builds that run on your own machine but cannot
be notarized for distribution.

## Limits

- The menu-bar badge deliberately ignores bare literals — copying `42` or `"hello"` is technically valid JSON but flagging it would make the badge meaningless. Objects and arrays count.
- Formatted output is capped at 500,000 characters on screen; past that the view is truncated with a notice. **Copy Pretty** still gives you the whole thing.
- Sources over 32 MB aren't parsed. Quick Look reads a file whole or not at all: past that limit it says so by size, because a leading slice of a JSON document cannot parse and reporting it as malformed would be a lie. A 32 MB document can still take long enough to bump against Quick Look's time budget.
- Quick Look is a snapshot: change indent or font size, then press Space again (or `qlmanage -r`) to see it. The preview does not live-update.

## Roadmap

Thumbnail extension, JSONC / NDJSON / GeoJSON, collapsible tree view and key-path copy, secret masking for `password` / `token` keys, and the 2016 app's other formats — XML, stack traces, Base64 and URL decoding.
