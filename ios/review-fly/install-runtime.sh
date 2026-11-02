#!/bin/sh
# Image-build step only. Startup reconciles local files without downloading.
set -eu
review_arch=${1:?Expected Docker TARGETARCH}
review_bundle=/opt/review
. "$review_bundle/runtime.env"

case "$review_arch" in
    amd64)
        herdr_asset=herdr-linux-x86_64
        pi_asset=pi-linux-x64.tar.gz
        bridge_asset=herdcats-bridge-linux-x86_64
        herdr_sha=$HERDR_SHA256_AMD64
        pi_sha=$PI_SHA256_AMD64
        bridge_sha=$BRIDGE_SHA256_AMD64
        ;;
    arm64)
        herdr_asset=herdr-linux-aarch64
        pi_asset=pi-linux-arm64.tar.gz
        bridge_asset=herdcats-bridge-linux-arm64
        herdr_sha=$HERDR_SHA256_ARM64
        pi_sha=$PI_SHA256_ARM64
        bridge_sha=$BRIDGE_SHA256_ARM64
        ;;
    *) echo "Unsupported architecture: $review_arch" >&2; exit 1 ;;
esac

review_downloads=$(mktemp -d)
trap 'rm -rf "$review_downloads"' EXIT
cd "$review_downloads"

fetch_verified() {
    curl --fail --location --silent --show-error --retry 3 \
        --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 180 \
        "$1" -o "$2"
    printf '%s  %s\n' "$3" "$2" | sha256sum -c -
}

fetch_verified "https://github.com/herdrdev/herdr/releases/download/v${HERDR_VERSION}/${herdr_asset}" \
    "$herdr_asset" "$herdr_sha"
fetch_verified "https://github.com/earendil-works/pi/releases/download/v${PI_VERSION}/${pi_asset}" \
    "$pi_asset" "$pi_sha"
review_release="https://github.com/zhiyao/herdcats/releases/download/herdcats-bridge-v${HERDCATS_BRIDGE_VERSION}"
fetch_verified "$review_release/$bridge_asset" "$bridge_asset" "$bridge_sha"
fetch_verified "$review_release/herdcats-pi-extension.tar.gz" \
    herdcats-pi-extension.tar.gz "$PI_EXTENSION_SHA256"

install -m 755 "$herdr_asset" /usr/local/bin/herdr
tar -xzf "$pi_asset" -C /opt
ln -s /opt/pi/pi /usr/local/bin/pi
install -d "$review_bundle/bin" "$review_bundle/extensions"
install -m 755 "$bridge_asset" "$review_bundle/bin/herdcats-bridge"
ln -s "$review_bundle/bin/herdcats-bridge" /usr/local/bin/herdcats-bridge
tar -xzf herdcats-pi-extension.tar.gz -C "$review_bundle/extensions"
sh "$review_bundle/scripts/verify-runtime.sh"
