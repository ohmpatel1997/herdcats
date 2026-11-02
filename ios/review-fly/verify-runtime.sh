#!/bin/sh
# Run at build and boot, or manually with: review-verify /data/home/review
set -eu
review_bundle=/opt/review
. "$review_bundle/runtime.env"
fail() { echo "Review runtime check failed: $*" >&2; exit 1; }

[ "$(/usr/local/bin/pi --version)" = "$PI_VERSION" ] || fail "expected Pi $PI_VERSION"
[ "$(/usr/local/bin/herdr --version)" = "herdr $HERDR_VERSION" ] || fail "expected Herdr $HERDR_VERSION"
review_bridge_info=$("$review_bundle/bin/herdcats-bridge" --version-json) || fail "bridge cannot run"
printf '%s\n' "$review_bridge_info" | jq -e \
    --arg version "$HERDCATS_BRIDGE_VERSION" \
    '.name == "herdcats-bridge" and .version == $version and .protocol == 1
     and .herdr_protocol == 22 and (.agents | index("pi") != null)' >/dev/null \
    || fail "bridge version or Pi capability mismatch"

if [ "$#" -gt 0 ]; then
    review_home=$1
    [ -x "$review_home/.local/bin/herdcats-bridge" ] || fail "home bridge is not executable"
    cmp -s "$review_bundle/bin/herdcats-bridge" "$review_home/.local/bin/herdcats-bridge" \
        || fail "home bridge differs from image"
    for review_file in index.ts runtime.mjs README.md; do
        cmp -s "$review_bundle/extensions/herdcats/$review_file" \
            "$review_home/.pi/agent/extensions/herdcats/$review_file" \
            || fail "home Pi extension differs from image: $review_file"
    done
fi
printf 'Review runtime verified: Herdr %s, Pi %s, Herdcats bridge/extension %s\n' \
    "$HERDR_VERSION" "$PI_VERSION" "$HERDCATS_BRIDGE_VERSION"
