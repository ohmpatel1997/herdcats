#!/bin/sh
# One-command deployment of the declared runtime to an existing Fly review app.
set -eu
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 FLY_APP_NAME" >&2
    exit 2
fi
review_directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec fly deploy "$review_directory" --config "$review_directory/fly.toml.example" \
    --app "$1" --ha=false
