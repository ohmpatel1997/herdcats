<p align="center">
  <a href="https://herdcats.dev"><img src="web/public/assets/logo.png" width="128" height="128" alt="Herdcats logo: a pixel cat on a dark night canvas"></a>
</p>

# Herdcats

[![CI](https://github.com/zhiyao/herdcats/actions/workflows/ci.yml/badge.svg)](https://github.com/zhiyao/herdcats/actions/workflows/ci.yml)

[Website](https://herdcats.dev) · [Join the TestFlight beta](https://testflight.apple.com/join/nUr62QY1)

A native iPhone and iPad client for [Herdr](https://herdr.dev). Connect over SSH to
browse spaces and agents, read pane output, and send terminal input, composed
messages, dictation, and photos from your phone.

On iPad and on the unfolded iPhone Duo, Spaces and Agents show the list and the
selected pane side by side. Folding or narrowing the window keeps the same pane
open. iPhone stays portrait-only; iPad supports all orientations.

Herdcats uses SwiftUI and Observation on iOS 17 or later. Each SSH connection
uses **TUI** (the `herdr` CLI) or **Herdr Core** (the `hc connect` API). **Auto**,
the default for new machines, detects both and saves each one it finds. A
machine with both appears once in your lists and connects with the runtime you
used last; switch runtime from the machine menu. Existing connections remain TUI.

Herdr Core mode needs no Herdcats bridge. It shows desktop spaces and tabs when
their layout is available, plus **Other terminals** for standalone or ungrouped
terminals. Panes use the same terminal view, live keys, composer, dictation and
photos as TUI. Herdr Core has no raw text input, so live typing sends key
presses and asks you to use Compose for shifted symbols and non-ASCII text.
Desktop layout changes, native timelines and structured approval/model controls
are available through the TUI path; Herdr Core uses text snapshots rather than
a full terminal emulator.

In TUI mode, Herdcats runs the remote `herdr` CLI over SSH.
Live pane input and reads reuse persistent POSIX shell channels when available,
with separate channels so output reads do not block typing. This uses stock
Herdr and SSH without Python, additional host packages, or an installed helper.
Hosts that cannot open these channels use the existing SSH command path.
Input remains acknowledged in order; uncertain sends are never replayed.

Agent panes can also show a native **Timeline** of messages and tool activity,
with approvals, questions and model controls where the agent supports them. It
covers Claude, Codex, Agy, Pi and Cursor in TUI mode and needs the optional
**Herdcats Bridge** on the SSH computer. Install it from the Timeline screen:
Herdcats downloads the pinned release, verifies its checksum and installs it to
`~/.local/bin/herdcats-bridge`, with no sudo, background service or agent hooks.
It runs only while a Timeline is open. Pi also needs the Herdcats Pi extension;
see [Pi conversations](ios/docs/pi-conversations.md). The terminal view works
without the bridge.

**Show Compose by Default** is enabled initially, so panes open with the compose
field and keyboard ready. Turn it off in pane options or Settings → Pane to
start with the Live toolbar. Compose supports spelling correction and keyboard
suggestions; Live terminal input stays literal. Your saved preference is respected.

[Tailscale](https://tailscale.com) is the recommended way to connect your phone
and Herdr machine. Any network that can reach the SSH server also works.

Herdcats is an independent project, not affiliated with Herdr.

This is an early release. See the limitations below before using it.

## Screenshots

Current iPhone screenshots with sample data, captured from main in dark and light mode.
Click an image to view it larger. The website’s `/screenshots` gallery shows the
same images and follows its light/dark switch.

<p align="center">
  <a href="assets/screenshots/01-spaces.png"><img src="assets/screenshots/01-spaces.png" width="160" alt="Spaces tab listing three spaces: Herdcats (blocked), Checkout redesign (working), and API performance (done)."></a>
  <a href="assets/screenshots/02-agents.png"><img src="assets/screenshots/02-agents.png" width="160" alt="Agents tab listing a blocked Claude agent, a finished Cursor agent, and a working Codex agent, each with its project path."></a>
  <a href="assets/screenshots/03-pane.png"><img src="assets/screenshots/03-pane.png" width="160" alt="Live terminal pane showing a Claude Code session waiting for input, with an Esc, Tab, Ctrl, Alt and Keys toolbar."></a>
  <a href="assets/screenshots/04-keys.png"><img src="assets/screenshots/04-keys.png" width="160" alt="Terminal pane with the Keys panel open: arrow keys, Home, End, Page Up and Down, Del, Ins, Backspace, Shift, and F1 to F7."></a>
  <a href="assets/screenshots/05-agent-pane.png"><img src="assets/screenshots/05-agent-pane.png" width="160" alt="Agent pane for a blocked Claude session, with a pane card above the terminal output."></a>
</p>

<p align="center">
  <a href="assets/screenshots/06-quota.png"><img src="assets/screenshots/06-quota.png" width="160" alt="Quota tab with usage rings for ZAI, Agy, Codex, Cursor and Claude, colored by pace with time left on each window."></a>
  <a href="assets/screenshots/07-connect.png"><img src="assets/screenshots/07-connect.png" width="160" alt="Connection Settings form with host, port, username, password or private key, and a Save credentials on this iPhone toggle."></a>
  <a href="assets/screenshots/08-settings.png"><img src="assets/screenshots/08-settings.png" width="160" alt="Settings screen with auto-refresh, a toggle to keep drafts and command history on the iPhone, appearance, and pane options."></a>
  <a href="assets/screenshots/09-compose.png"><img src="assets/screenshots/09-compose.png" width="160" alt="Compose box below the native timeline with a drafted reply, an attach-photo button, a microphone button and a send button."></a>
  <a href="assets/screenshots/10-voice.png"><img src="assets/screenshots/10-voice.png" width="160" alt="Native timeline with a voice recording waveform, cancel, stop, and send controls."></a>
</p>

<details>
<summary>Light-mode screenshots</summary>

<p align="center">
  <a href="assets/screenshots/light/01-spaces.png"><img src="assets/screenshots/light/01-spaces.png" width="160" alt="Light mode: Spaces tab listing three spaces: Herdcats (blocked), Checkout redesign (working), and API performance (done)."></a>
  <a href="assets/screenshots/light/02-agents.png"><img src="assets/screenshots/light/02-agents.png" width="160" alt="Light mode: Agents tab listing a blocked Claude agent, a finished Cursor agent, and a working Codex agent, each with its project path."></a>
  <a href="assets/screenshots/light/03-pane.png"><img src="assets/screenshots/light/03-pane.png" width="160" alt="Light mode: Live terminal pane showing a Claude Code session waiting for input, with an Esc, Tab, Ctrl, Alt and Keys toolbar."></a>
  <a href="assets/screenshots/light/04-keys.png"><img src="assets/screenshots/light/04-keys.png" width="160" alt="Light mode: Terminal pane with the Keys panel open: arrow keys, Home, End, Page Up and Down, Del, Ins, Backspace, Shift, and F1 to F7."></a>
  <a href="assets/screenshots/light/05-agent-pane.png"><img src="assets/screenshots/light/05-agent-pane.png" width="160" alt="Light mode: Agent pane for a blocked Claude session, with a pane card above the terminal output."></a>
</p>
<p align="center">
  <a href="assets/screenshots/light/06-quota.png"><img src="assets/screenshots/light/06-quota.png" width="160" alt="Light mode: Quota tab with usage rings for ZAI, Agy, Codex, Cursor and Claude, colored by pace with time left on each window."></a>
  <a href="assets/screenshots/light/07-connect.png"><img src="assets/screenshots/light/07-connect.png" width="160" alt="Light mode: Connection Settings form with host, port, username, password or private key, and a Save credentials on this iPhone toggle."></a>
  <a href="assets/screenshots/light/08-settings.png"><img src="assets/screenshots/light/08-settings.png" width="160" alt="Light mode: Settings screen with auto-refresh, a toggle to keep drafts and command history on the iPhone, appearance, and pane options."></a>
  <a href="assets/screenshots/light/09-compose.png"><img src="assets/screenshots/light/09-compose.png" width="160" alt="Light mode: Compose box below the native timeline with a drafted reply, an attach-photo button, a microphone button and a send button."></a>
  <a href="assets/screenshots/light/10-voice.png"><img src="assets/screenshots/light/10-voice.png" width="160" alt="Light mode: Native timeline with a voice recording waveform, cancel, stop, and send controls."></a>
</p>
</details>

## Build the iPhone app

You need a Mac with Xcode 26 or later and an installed iOS Simulator runtime.
Launch Xcode once to finish its setup. For a new contributor, fork this
repository and clone your fork in place of the URL below.

Run `ios/bin/setup` to check Xcode, install [XcodeGen](https://github.com/yonaskolb/XcodeGen)
with Homebrew if needed, generate the project, and resolve Swift packages.
If XcodeGen is missing, install [Homebrew](https://brew.sh) first. Citadel,
the SSH dependency, is vendored at 0.12.1 with local OpenSSH fixes.
Simulator development requires no Apple account or SSH server.

```sh
git clone https://github.com/zhiyao/herdcats.git
cd herdcats
ios/bin/setup
ios/bin/launch
```

`ios/bin/launch` builds the Debug app, boots an iPhone simulator if needed,
installs the app, and opens it in Simulator. It prefers an already-booted
iPhone; select a specific simulator with `ios/bin/launch --device="iPhone 17 Pro Max"`
or `--device=<UDID>`. Build output is saved to `ios/build/Launch/build.log`.

To work in Xcode, run `open ios/Herdcats.xcodeproj`, select the **Herdcats**
scheme and an iPhone simulator, then run. To build from the repository root:

```sh
xcodebuild -project ios/Herdcats.xcodeproj -scheme Herdcats \
  -destination 'generic/platform=iOS Simulator' build
```

For a physical iPhone, select your own development team in Xcode's Signing &
Capabilities after generation. `ios/project.yml` is the source of truth;
regeneration replaces manual project settings. For command-line device builds,
pass your own team using `DEVELOPMENT_TEAM=YOUR_TEAM_ID`.

The app and website share the single pixel-cat icon from the launch screen on
the dark night canvas. Agent badges retain their standard logos. Regenerate the
launch-cat assets with `python3 ios/scripts/generate_launch_cat.py` and the icon
and logo assets with `python3 ios/scripts/generate_logo.py`.

## Connect to Herdr

1. Choose **Auto**, **TUI** or **Herdr Core** in Connection Settings. For TUI,
   install Herdr and start its default session. For Herdr Core, install
   [Herdr Core](https://github.com/herdrdev/herdr-core) (`hc`) and use its
   standalone runtime or the Herdr desktop app. Herdr Core mode never falls back
   to a TUI session.
2. Enable SSH access. On macOS, enable **System Settings → General → Sharing →
   Remote Login**. Confirm that SSH works with your account.
3. Connect the phone and machine to the same Tailscale network, or use another
   network where the phone can reach the SSH server.
4. Enter the host, port, username, and password or an **OpenSSH
   ed25519 private key** (enter its passphrase if encrypted) in Herdcats.
5. Compare the host-key fingerprint shown by the app with the server's
   fingerprint through a trusted channel, then approve it.

Add each machine as its own SSH connection, then switch from the menu under the
Herdcats logo. Give connections optional names and tap **Edit** in the connection
list to drag them into your preferred order. Auto-connect uses the last-used
machine. Herdcats no longer uses Herdr's saved machines.

Remembered credentials and approved host keys stay in the iOS Keychain. A
changed host key blocks connection, including automatic reconnects. The app shows
both fingerprints and lets you replace the approved key after explicitly confirming
that you verified the new fingerprint through a trusted channel.

Optional: install [quota-axi](https://www.npmjs.com/package/quota-axi) on the
connected machine to show provider quota. It is not required for pane access.

## Tests and GitHub Actions

[GitHub Actions](https://github.com/zhiyao/herdcats/actions) runs on pushes to
`main`, pull requests, and manual dispatch:

- **Bridge:** on macOS and Linux, test, lint and build the Herdcats Bridge
  release, test its installers, and run the Pi extension tests.
- **iOS:** generate the Xcode project, check attachment-storage behavior and
  release preparation, build the app, and run Swift unit tests on an available
  iPhone simulator.
- **Web:** install locked dependencies, run server regression tests, and build
  the static website.

These checks require no SSH server, Apple account credentials, or deployment
secrets. Simulator tests use ad-hoc signing so Keychain tests receive their
entitlements.

Changes to `main` require a pull request and passing checks.
Dependabot checks dependencies weekly and opens update pull requests for review.
For Swift dependency updates, copy the proposed version changes into
`ios/project.yml`, regenerate with `(cd ios && xcodegen generate)`, and commit
the resulting project and lockfile before merging.

Run the same checks locally from the repository root:

```sh
python3 ios/HerdcatsTests/test_attachment_storage.py
xcodebuild -project ios/Herdcats.xcodeproj -scheme Herdcats -showdestinations

# Replace SIMULATOR_UDID with an available iPhone simulator ID.
xcodebuild -project ios/Herdcats.xcodeproj -scheme Herdcats \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' \
  test -only-testing:HerdcatsTests \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

Live SSH UI tests are separate from CI. Some send input to panes: use a
**disposable SSH server and Herdr session**, with a locally generated key kept
outside Git. Configure `TEST_RUNNER_HC_USER`, `TEST_RUNNER_HC_PORT`, and
`TEST_RUNNER_HC_KEY_PATH`; live connection tests skip when the key path is absent.

## iPhone screenshots with mock data

Rendered App Store artwork is included in `assets/app-store/screenshots/dark`
and `assets/app-store/screenshots/light`, with ten slides at each of the three
configured iPhone sizes. Each folder includes a local HTML preview and manifests.

Capture all 12 native screens: onboarding replay, connection settings, spaces,
terminal, terminal keys, agents, agent pane, quotas, settings, Compose, voice,
and the native timeline. Connected screens use read-only sample workspaces, agents,
terminal output, quotas, a Compose draft, and voice recording. The recording
fixture displays the native dictation UI without opening the microphone.
No SSH server or credentials are needed:

```sh
ios/bin/screenshots-mock
ios/bin/screenshots-mock --appearance=light
npm ci --prefix ios/app-store-images
ios/bin/screenshots-app-store --iphone-input=ios/maestro/screenshots-output/mock-iPhone
ios/bin/screenshots-app-store --iphone-input=ios/maestro/screenshots-output/mock-iPhone-light --output=ios/maestro/app-store-output/light
```

The capture command builds a Debug app and defaults to an available iPhone 17
Pro Max simulator. Use `--device=<name-or-UDID>` to select another iPhone, or
`--app=<path-to-Debug-simulator-app>` to reuse a build. Raw captures go to
`ios/maestro/screenshots-output/mock-iPhone`; artwork exports go to a fresh
folder under `ios/maestro/app-store-output`, with a preview and manifests.
Light captures use `--appearance=light` and default to the separate
`ios/maestro/screenshots-output/mock-iPhone-light` folder. The native terminal
keeps its dark palette in both appearances.
Onboarding uses a read-only replay so saved machines and onboarding preferences
are preserved, even when capturing on a simulator you already use.
The screenshot fixture mode is compiled only into Debug simulator builds.
The capture manifest records the source commit, built app hash, simulator,
capture time, and PNG hashes. Each screen selects its intended terminal or
timeline surface independently of earlier captures.

Two more Maestro suites check large-screen layouts in dark mode.
`ios/bin/maestro-ipad` creates or boots an iPad Pro 13-inch (M5) simulator,
rotates it to landscape and captures Spaces and Agents. `ios/bin/maestro-duo`
runs all 12 screens on the outer and inner displays of an already booted
**iPhone Duo** simulator.

## Website

The home page, shared navigation, and footer link to `/screenshots`. Before each
production build, `web/scripts/sync-screenshots.mjs` copies the canonical images
from `assets/screenshots` into the website’s public assets. Run it manually
before local development when screenshots change.

The `web/` directory contains the Next.js landing page. Use Node.js 22 or later:

```sh
cd web
npm ci
node --test test/server.test.js
npm run build
npm run dev
```

The production build exports static files to `web/out/`. The website can be
hosted independently of the iPhone app.

## Current limitations

- SSH authentication supports passwords and OpenSSH ed25519 keys, including
  passphrase-protected keys using AES-128-CTR or AES-256-CTR and bcrypt with
  1–256 rounds. Other key formats and encryption settings are unsupported.
  Remembering the passphrase is optional; without it, unlock the key again
  after restarting the app.
- A readable Herdr default session is required; session selection is not wired up.
- Backgrounding pauses polling. This is not a general-purpose SSH shell.
- Host-key changes require manual verification and explicit replacement approval.
  Automatic reconnects remain blocked until approval.
- In TUI mode, uploaded photos remain under `~/.cache/herdrcat/attachments` on
  the connected machine until you remove them; the app does not automatically
  delete them. Herdr Core stores uploads through its own `terminal.put` API.
  The legacy `herdrcat` cache name is retained for compatibility with existing uploads.
- Each machine must be reachable over SSH from your iPhone.

## Contributing

Bug reports, documentation improvements, and focused code changes are welcome.
Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup, validation, and the PR process.
Community participation follows [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
Maintainers can follow [RELEASING.md](RELEASING.md) to prepare a source release.

## Security

Report vulnerabilities through [GitHub's private reporting form](https://github.com/zhiyao/herdcats/security/advisories/new).
See [SECURITY.md](SECURITY.md) for supported versions and reporting guidance.

## License

[GPLv3 with an additional permission for Apple App Store and Google Play
 distribution](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md) for
dependency licenses, artwork provenance, and screenshot-tooling terms.
Internal planning documents, local configuration,
credentials, and generated review artifacts are excluded from this repository.
