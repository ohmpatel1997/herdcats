# Fly review machine

The desired runtime lives in [`runtime.env`](runtime.env): Herdr **0.9.3**, Pi
**1.4.0**, and Herdcats bridge plus Pi extension **0.5.0**, with pinned publisher
SHA-256 digests for Linux amd64 and arm64. Pi 1.4.0 is an exact compatibility
requirement of the current extension, not a minimum version.

## Update the existing review machine

From the repository root, after signing in with `fly auth login`:

```sh
sh ios/review-fly/deploy.sh herdrcat-review-d4f11a11
```

This builds the image and deploys to the named app using `fly.toml.example`.
The app must already have its `review_data` volume and `REVIEW_SSH_PASSWORD`
secret. For a new app, first provision these using the example Fly configuration.
The deploy script disables spare-machine creation for this single-machine setup.

**Deployment restarts the machine and interrupts its active terminals.** Finish
important work first. The volume preserves files, credentials, settings, and Pi
history; it does not preserve running processes. After deployment, open a fresh
Pi pane in Herdcats, select Conversation, and tap **Check again**. Plain `pi`
now launches the declared version. Do not resume an existing session concurrently
in a second process.

## What is managed

- Image build downloads and verifies all runtime artifacts against `runtime.env`,
  then checks the real Pi, Herdr and bridge versions and bridge Pi capability.
- The image keeps its bundle at `/opt/review`, outside the mounted `/data` volume.
- Before starting SSH or Herdr, startup runs as `review` to reconcile only
  `~/.local/bin/herdcats-bridge` and the three packaged files in
  `~/.pi/agent/extensions/herdcats/`. These files are image-managed and replaced
  on every boot. Keep custom extensions beside that directory.
- Pi settings are seeded from `pi-settings.json` only when settings do not exist.
  Existing credentials, settings, history, project files and other extensions
  remain untouched. No recursive ownership changes are made.
- Startup verifies that the home copies match the image. A mismatch or missing
  runtime stops startup with a clear error. It does not download at boot.

Check a deployed machine without opening transcripts:

```sh
fly ssh console --app herdrcat-review-d4f11a11 --user review \
  -C 'review-verify /data/home/review'
```

That command checks installed files and versions. A successful Conversation in a
fresh pane additionally verifies the live Herdr-to-Pi session connection.

## Development checks

```sh
python3 -m unittest discover -s ios/review-fly/tests -v
docker build --platform linux/amd64 -t herdcats-review:test ios/review-fly
python3 ios/review-fly/tests/smoke_runtime.py herdcats-review:test
```

The smoke check uses a disposable local container and volume. It exercises
startup, reconciliation on restart with preserved synthetic user files, and a
real Pi TUI loading the shipped extension and responding over its Unix socket.
It makes no provider requests and uses no real credentials.

When upgrading, change the manifest's versions and corresponding release digests
together, run the checks, then deploy. Rebuilding and redeploying the previous
revision rolls back the managed runtime. Back up important user data before
testing session-history compatibility across Pi upgrades; runtime rollback does
not undo any data migration performed by an agent.
