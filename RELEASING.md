# Preparing a release

## Guided iOS / App Store Connect deployment

Requirements: Git, Python 3.9+, the standard GitHub CLI (`gh auth login`),
Xcode 26+, XcodeGen, Ruby/Bundler, and maintainer push access. Preparation
needs no Apple credentials. Start from a clean checkout:

```sh
./ios/bin/deploy prepare 0.9.0
# Or omit the version to see a suggestion and enter one interactively.
```

Before the first app tag, you can keep the version already in `project.yml`;
the build number still increases. Once app tags exist, choose a higher version.

This fetches `origin/main` and tags, creates `release/0.9.0`, generates
TestFlight notes through HEAD, and asks you to review them. Set `EDITOR` to an
editor executable or edit the displayed file in another terminal. Notes are
committed in `ios/releases/0.9.0.txt` for PR review. The existing release helper
bumps the version/build and regenerates the project. Confirm that the proposed
build number exceeds **every** build already uploaded to App Store Connect;
the script cannot discover uploads made outside this repository. It then pushes
the branch and opens a PR. A network failure after preparation can be retried
with the same command on that release branch without another version bump.
For an interrupted preparation before the bump completes, inspect the branch
and finish or revert the incomplete preparation before retrying.

Review and merge the PR through normal repository checks. Once the merged
commit's main CI run completes successfully:

```sh
export DEVELOPMENT_TEAM=YOURTEAMID
./ios/bin/deploy publish 123  # replace with the release PR number
```

Publishing requires a merged `release/<version>` PR targeting `main`, a commit
still reachable from `origin/main`, and a successful latest **CI** push run at
that exact SHA. It uses a temporary detached worktree of that commit, copies
the reviewed notes into fastlane's ignored changelog file, and invokes `bin/beta`
with its version/changelog and final upload confirmations. Your branch stays
in place. Apple authentication/signing uses the existing environment or local
session configuration; never commit credentials.

Retry `publish` with the same PR number after a failure; it does not bump the
version. If the upload result is uncertain, check App Store Connect first:
Apple rejects duplicate build numbers, and an already accepted upload does not
need another upload. After success, check processing and tester availability
in TestFlight. This does not submit an App Store review, distribute externally,
create a GitHub release, or release the bridge.

Running `./ios/bin/deploy` without arguments retains the older interactive
branch-preparation helper. The explicit stages above provide the full flow.

## First public source preview

The first public source release uses the existing app version **0.3.1**
(build **84**) and tag **herdrcat-v0.3.1**, matching the repository's version
helpers. It is a GitHub prerelease containing source, not a signed app binary.
The existing version does not need a bump just to tag the public baseline.
Its proposed notes are in [RELEASE_NOTES.md](RELEASE_NOTES.md).

## Checklist

- Use the public repository's `main`; do not import private branches or history.
- Merge release changes through a PR with passing **iOS** and **Web** checks.
- Confirm the chosen commit on `main` has passed CI. Review open security alerts.
- Check README build commands, limitations, security-reporting links, and notices.
- Keep dependency notices consistent with committed locks. Document any unresolved
  artwork, provider-term, or redistribution questions in the release notes.
- Confirm `ios/project.yml`, the generated project, and Info.plist agree on version.
- For source previews, describe what was tested and that live SSH UI tests were
  not run by CI. Attach no credentials, captures of private sessions, or unsigned
  binaries presented as installable apps.

Create a **draft prerelease** at the exact tested commit, review it, then publish
when ready. GitHub supplies source archives when the release is published.
Do not tag a moving branch or an unmerged PR commit.

```sh
# Replace TESTED_COMMIT_SHA with the full commit SHA checked above.
gh release create herdrcat-v0.3.1 \
  --target TESTED_COMMIT_SHA --draft --prerelease \
  --title 'Herdcats 0.3.1 — first public source preview' \
  --notes-file RELEASE_NOTES.md
```

## Later versions

Create a branch, then run `./ios/bin/release MAJOR.MINOR.PATCH`. The helper
increments the current build number (or uses a higher commit-derived number),
regenerates the project, and commits the bump. It requires a clean PR branch
and does not create a tag. Push the branch, review the generated files, and
merge through the same checks. Only then prepare a draft at the tested main SHA.

Fresh public history has fewer commits than the old private repository. Preserve
build-number monotonicity rather than deriving it solely from the new history.
For App Store or TestFlight uploads, also check the highest build already uploaded
and choose a higher number. Do not assume this repository knows every uploaded build.

`ios/bin/deploy` without arguments guides branch preparation and optional
branch push. For the full PR and upload flow, use the explicit `prepare` and
`publish` stages documented above.

Signed app distribution is a separate task requiring your own Apple credentials
and signing configuration. `ios/bin/beta` uploads to TestFlight; it is not part
of preparing a GitHub source release.

## Local signing for TestFlight

Keep the shared `ios/project.yml` and generated project free of a personal
`DEVELOPMENT_TEAM` setting. XcodeGen overwrites manual project edits during
release preparation. The TestFlight lane reads the team from your environment
and passes it to the archive and IPA export without storing it in the project:

```sh
export DEVELOPMENT_TEAM=YOURTEAMID
./ios/bin/beta
```

Replace `YOURTEAMID` with the 10-character Team ID from your Apple membership.
The Team ID identifies the membership; it is not an authentication credential.
You still need authorized Apple authentication and signing credentials. Keep
API private keys and Apple sessions outside Git. Existing
`APP_STORE_CONNECT_API_KEY_*` environment variables remain supported; without
an API key, fastlane falls back to Apple session authentication.

`./ios/bin/deploy prepare` needs no Apple credentials. After merge and passing
CI, `./ios/bin/deploy publish <PR-number>` invokes the authorized TestFlight
upload. `./ios/bin/beta` remains available as a standalone helper.

## Bridge releases

Bridge versions are independent of the iOS app. Version 0.5.0 prepares Pi and
Cursor Agent support; 0.4.0 already has a tag and draft, so do not move or reuse
that tag. The 0.3.0 published release and iOS installer pin remain valid until
new published assets are verified.

1. Prepare a PR updating `bridge/Cargo.toml`, `bridge/Cargo.lock`, the default
   version in `bridge/scripts/install.sh`, agent list in setup metadata, workflow dispatch
   default, setup metadata, and `bridge/release-notes.txt`.
2. Run locked Rust tests, Clippy, a release build, the Pi extension Node suite,
   and the Python bridge installer/distribution tests. Review Pi and Cursor
   compatibility limits in their conversation docs. Automated fixtures do not
   establish compatibility with additional CLI versions.
3. Merge through passing Bridge, iOS and Web CI. From a checkout with the merged
   source, run `scripts/bridge-release-tag.sh 0.5.0`. It checks `origin/main` and
   CI, then asks before tagging and again before publishing. Never tag this
   unmerged preparation branch.
4. Review the workflow's draft: four native binaries, `install.sh`,
   `herdcats-pi-extension.tar.gz`, and `SHA256SUMS`. Check all five checksummed
   assets, the installer's rendered-template digest, and the binary's version/protocol/agent
   report. Smoke-test installation in a temporary directory on the target host.
   The Pi archive is platform-independent and comes from the arm64 Mac job;
   verify its checksum, extract it into a chosen directory, and explicitly enable
   its `herdcats/index.ts` inside Pi 1.4.0. The binary installer does not enable it.
5. After publication and verification, prepare a separate iOS pin update with the
   actual released installer SHA-256, version and supported-agent list together.
   Record platform/checksum/CI evidence under `compatibility/release/`; do not
   manufacture published-release evidence from a local build.

The release workflow builds macOS arm64/x86_64 and Linux arm64/x86_64 natively.
macOS binaries are unsigned/unnotarized; Linux requires glibc 2.35 or later.
Cursor model controls are verified only on build `2026.10.22-27dcf5f`; Pi native
controls require the opt-in extension and verified Pi `1.4.0`. Terminal fallback
and each integration's existing guards still apply.
