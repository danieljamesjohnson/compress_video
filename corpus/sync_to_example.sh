#!/usr/bin/env bash
# Mirror the corpus clips AND their sidecars into example/assets/corpus/, so
# the example app's integration tests can read both through `rootBundle`.
#
# Fails loudly (non-zero exit, message naming the missing directory) if
# `example/` does not exist yet, rather than silently doing nothing. It does
# NOT create `example/` itself - that is the plugin scaffold's job, in a
# later plan.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXAMPLE_DIR="$REPO_ROOT/example"
DEST_DIR="$EXAMPLE_DIR/assets/corpus"

if [ ! -d "$EXAMPLE_DIR" ]; then
  echo "example/ not found — run this after the plugin scaffold exists" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"

CLIPS=(portrait_rot90.mp4 small_480p.mp4 noaudio_720p.mp4 portrait_hibitrate_1080p60.mp4 trim_source_10s.mp4)
# Deliberately damaged, has no sidecar by design (see verify_corpus.sh) — do
# not fail just because its ".expected.json" doesn't exist.
DAMAGED_CLIPS=(truncated_mdat.mp4)

sync_one() {
  local f="$1"
  local src="$SCRIPT_DIR/$f"
  local dest="$DEST_DIR/$f"
  if [ ! -f "$src" ]; then
    echo "ERROR: $src not found — run generate_corpus.sh / verify_corpus.sh --write first" >&2
    exit 1
  fi
  cp "$src" "$dest"
  local src_sha dest_sha
  src_sha=$(sha256sum "$src" | awk '{print $1}')
  dest_sha=$(sha256sum "$dest" | awk '{print $1}')
  if [ "$src_sha" != "$dest_sha" ]; then
    echo "ERROR: checksum mismatch after copying $f ($src_sha != $dest_sha)" >&2
    exit 1
  fi
  echo "synced $f (sha256 verified)"
}

for clip in "${CLIPS[@]}"; do
  sidecar="${clip%.mp4}.expected.json"
  sync_one "$clip"
  sync_one "$sidecar"
done

for clip in "${DAMAGED_CLIPS[@]}"; do
  sync_one "$clip"
done

echo "All corpus clips and sidecars synced to $DEST_DIR"
