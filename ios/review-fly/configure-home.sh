#!/bin/sh
# Reconcile only image-managed files; preserve the rest of the mounted home.
# Run as the review user, never as root.
set -eu
review_bundle=${1:?Expected image bundle directory}
review_home=${2:?Expected persistent home directory}

for review_source in bin/herdcats-bridge extensions/herdcats/index.ts \
    extensions/herdcats/runtime.mjs extensions/herdcats/README.md pi-settings.json; do
    if [ ! -f "$review_bundle/$review_source" ]; then
        echo "Review runtime bundle is incomplete: $review_source" >&2
        exit 1
    fi
done

for review_dir in "$review_home" "$review_home/.local" "$review_home/.local/bin" \
    "$review_home/.pi" "$review_home/.pi/agent" "$review_home/.pi/agent/extensions" \
    "$review_home/.pi/agent/extensions/herdcats"; do
    if [ -L "$review_dir" ]; then
        echo "Refusing symlink in managed runtime path: $review_dir" >&2
        exit 1
    fi
    mkdir -p "$review_dir"
done

review_stage=
trap 'if [ -n "$review_stage" ]; then rm -f "$review_stage"; fi' EXIT
install_managed() {
    if [ -L "$3" ] || { [ -e "$3" ] && [ ! -f "$3" ]; }; then
        echo "Managed runtime destination must be a regular file: $3" >&2
        exit 1
    fi
    review_stage=$(mktemp "${3%/*}/.review-install.XXXXXX")
    install -m "$1" "$2" "$review_stage"
    mv -f "$review_stage" "$3"
    review_stage=
}

install_managed 755 "$review_bundle/bin/herdcats-bridge" "$review_home/.local/bin/herdcats-bridge"
for review_file in index.ts runtime.mjs README.md; do
    install_managed 644 "$review_bundle/extensions/herdcats/$review_file" \
        "$review_home/.pi/agent/extensions/herdcats/$review_file"
done

# Defaults apply only to a new home. Existing preferences and credentials belong to the user.
if [ ! -e "$review_home/.pi/agent/settings.json" ] && [ ! -L "$review_home/.pi/agent/settings.json" ]; then
    install_managed 600 "$review_bundle/pi-settings.json" "$review_home/.pi/agent/settings.json"
fi
