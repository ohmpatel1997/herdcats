# Website app screenshots

## Latest website images

The Features page and Support's Compose and Voice examples use
`assets/screenshots/` from the 28 October 2026 refresh (source revision
`5caa3009bbb578113973715ed61c50f9bee62c6e`). Both gallery appearances are copied
by `npm run prebuild`; content hashes in `versions.json` version the image URLs
so refreshed captures bypass older browser caches. The homepage retains the original cat scene without a screenshot showcase.

The Timeline, Bridge setup, and approval examples in Support retain the
27 October captures documented below; the latest supplied gallery set does
not include these examples.

## Supplemental Support captures

Captured on 27 October 2026 from Herdcats **0.5.0 (108)**, built from commit
`fdd9433844ae` (see the asset manifest for the full revision), in the
`website-compose-bridge` Herdr worktree.

These are unaltered app UI captures using the app's built-in simulator
fixtures, not mockups or private conversations. Fixtures demonstrate the
current views; they do not certify a live SSH connection or a published
Bridge release. At capture time, the pinned installer supplied Bridge 0.3.0 for Claude
and Codex. The current app pins Bridge 0.5.0 with Claude, Codex, Agy, Pi, and
Cursor support; Pi requires its separately enabled extension.

Device: iPhone 17 Pro simulator, iOS 27.0. Original PNGs are 1206 × 2622.
Website copies are 600 × 1304 WebP images, resized with Lanczos and encoded
at quality 90. Their contents are unchanged. A 9:41 status-bar override is
cleared after capture. The light and dark conversation views use a seeded
Compose draft with automatic keyboard focus disabled for framing.

| Asset | What it shows |
| --- | --- |
| `timeline-light` | Light Timeline, tool activity, and a Compose draft |
| `timeline-dark` | The same conversation in dark mode |
| `terminal-compose` | The original terminal output with a reviewed draft |
| `voice` | The real recording bar in its screenshot fixture state |
| `bridge-setup` | Timeline benefits and explicit install/defer actions |
| `approval` | A native Claude approval card, without selecting a response |

Full-resolution originals are in [app-screenshots/2026-10-27](app-screenshots/2026-10-27/).
Web assets and launch arguments are in [the asset manifest](../public/assets/app/manifest.json).
Visually inspect every screen before publishing; first-launch initialization
or a concurrent simulator workflow can interrupt a capture.

## Refresh

Use a dedicated simulator so other apps and sessions are not disturbed.
The script requires Python 3 with Pillow and a booted simulator. List devices
with `xcrun simctl list devices available`; use the selected device's actual
UDID in the commands below. Do not use the ambiguous `booted` shorthand.

From the repository root:

```sh
(cd ios && xcodegen generate)
xcodebuild -project ios/Herdcats.xcodeproj -scheme Herdcats \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/herdcats-website-derived CODE_SIGNING_ALLOWED=NO build

xcrun simctl bootstatus <device-udid> -b
python3 web/scripts/capture-app-screenshots.py \
  --device <device-udid> \
  --app /tmp/herdcats-website-derived/Build/Products/Debug-iphonesimulator/Herdcats.app \
  --raw-dir web/docs/app-screenshots/2026-10-27
```

Use `--only timeline-light` to recapture one screen. The script replaces only
selected asset files and preserves other manifest entries. After inspection,
shut down the dedicated device with `xcrun simctl shutdown <device-udid>`.

## Website validation

Build with `npm ci && npm run build` from `web/`. Serve `web/out/` with any
static file server, then check the landing page and Support on mobile and
desktop in both themes. Verify the screenshot links and these app destinations:

- `/support/#connect`
- `/support/#using-app-codex-shared-background-server`

Support uses an imported stylesheet so its styling survives a direct load of
the production static export. The Features page uses the project's Moonlit colors and typography.

## Large-device creative refresh (3 November 2026)

The dark App Store header, search creative, and `web/public/og.png` consume
`ios/maestro/screenshots-output/ipad/13_split_spaces.png` and
`ios/maestro/screenshots-output/iphone-duo/inner/13_split_spaces.png` through
`ios/app-store-images/render-creative.mjs`. Their source and output hashes are
recorded in `assets/app-store/manifest.json`. Both large-device hero sources
show two active panes: Claude reviewing onboarding and Codex building checkout. The companion `14_split_agents.png` scene opens
terminal output beside a native conversation from Agents. These use
simulator-only sample conversations.
The existing iPhone source and the light iPhone-only creatives are preserved.
The raw iPad manifest records the source commit, app and fixture hashes, and
all 14 landscape captures. See the repository README for dedicated simulator
capture commands and the Device Hub fallback for Duo inner.
