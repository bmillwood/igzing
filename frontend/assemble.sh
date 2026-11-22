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
files=$(find . -type f ! -name sw.js | sed 's|^\./||' | LC_ALL=C sort)
# shellcheck disable=SC2086 # file names are ours, without spaces
version=$(cat $files | sha256sum | cut -c1-16)
files_json=$(printf '%s\n' $files | jq -R . | jq -sc .)
sed -i -e "s|\"@VERSION@\"|\"igzing-$version\"|" -e "s|\"@FILES@\"|$files_json|" sw.js
