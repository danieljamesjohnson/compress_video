#!/usr/bin/env bash
#
# Pushes this repository's working tree to the MacBook Air so tool/mac_run.sh can build and
# test the Apple side there (03-01 task 1, requirement BULD-02).
#
# The Mac cannot reach danserver's git remote (only GitHub over https), so the sync is an
# rsync of the working tree, not a git pull -- which also means whatever is checked out and
# edited HERE, committed or not, is what the Mac builds. `--delete` keeps the remote tree an
# exact mirror; the excludes keep out everything the Mac must generate for itself (build/,
# .dart_tool/, Pods, .symlinks, ephemeral) and everything it has no business seeing (.git,
# .planning/). Sync once, then run as many tool/mac_run.sh commands as you like against it.
#
# Usage: tool/mac_sync.sh [--dry-run]
#   MAC_HOST   ssh host to sync to (default: dans-macbook-air, from ~/.ssh/config)
#   MAC_DIR    remote directory (default: ~/CodeProjects/compress-video)
#
# Let every failure propagate: an unreachable Mac, a failed mkdir or a failed rsync all exit
# non-zero. Probe the Mac first with `timeout 15 ssh -o ConnectTimeout=8 -o BatchMode=yes
# dans-macbook-air true` if you are not sure it is awake -- it sleeps on battery.

set -euo pipefail

MAC_HOST="${MAC_HOST:-dans-macbook-air}"
MAC_DIR="${MAC_DIR:-CodeProjects/compress-video}"

DRY_RUN=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=(--dry-run) ;;
    *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ssh -o BatchMode=yes -o ConnectTimeout=10 "$MAC_HOST" "mkdir -p ~/$MAC_DIR"

STATS=$(rsync --archive --delete --stats "${DRY_RUN[@]}" \
  --exclude '.git' \
  --exclude 'build/' \
  --exclude '.dart_tool/' \
  --exclude '.planning/' \
  --exclude 'Pods' \
  --exclude '.symlinks' \
  --exclude 'ephemeral' \
  --exclude '*.iml' \
  "$REPO_ROOT/" "$MAC_HOST:$MAC_DIR/")

TRANSFERRED=$(printf '%s\n' "$STATS" | sed -n 's/^Number of regular files transferred: *//p' | tr -d ',')
echo "mac_sync: ${TRANSFERRED:-?} file(s) transferred to $MAC_HOST:~/$MAC_DIR${DRY_RUN:+ (dry run)}"
