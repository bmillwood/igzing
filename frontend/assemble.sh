#!/usr/bin/env bash
# Put the site together from its parts, and stamp the service worker with the
# list of files to cache and a version derived from their contents.
#
# Usage: assemble.sh ELM_JS DATA_DIR OUT_DIR
set -euo pipefail

static=$(dirname "$0")/static
elm_js=$1
data=$2
out=$3

mkdir -p "$out/data"
cp "$static"/* "$out/"
cp "$elm_js" "$out/elm.js"
cp "$data"/*.json "$out/data/"
chmod -R u+w "$out"

cd "$out"
list() { find . -type f ! -name sw.js "$@" | sed 's|^\./||' | LC_ALL=C sort; }
# shellcheck disable=SC2046 # file names are ours, without spaces
version=$(cat $(list) | sha256sum | cut -c1-16)
# Each accent's dictionary is a few megabytes, so the service worker only
# keeps the ones that get used, rather than installing them all up front.
files_json=$(list ! \( -path './data/*' ! -name accents.json \) | jq -R . | jq -sc .)
sed -i -e "s|\"@VERSION@\"|\"igzing-$version\"|" -e "s|\"@FILES@\"|$files_json|" sw.js
