#!/usr/bin/env bash
#
# Runs one Apple build/test command on the MacBook Air against the tree tool/mac_sync.sh put
# there (03-01 task 1, requirement BULD-02). This script does NOT sync: sync once with
# tool/mac_sync.sh, then run as many of these as you need against the same tree.
#
# Every command runs on the Mac with the SECOND Flutter SDK (~/development/flutter-stable,
# stable channel, the same one CI tracks) first on PATH -- never Dan's own ~/flutter, which is
# below this package's pubspec floor and must not be touched (D-18) -- and with Homebrew's bin
# on PATH so `pod` resolves for the example's committed Podfiles. Every command is bounded by
# an alarm (MAC_RUN_TIMEOUT seconds, default 540): the whole remote process group is killed
# when it fires, so a hung simulator launch or a stuck xcodebuild can never wedge the caller.
# CI's `perl -e 'alarm shift; exec @ARGV'` idiom kills only the exec'd shell, and the shell's
# children then keep the ssh channel open until they finish on their own; the wrapper below
# puts the command in its own process group and kills the group, so the bound has teeth even
# for `sleep 30` -- the acceptance test for this script.
#
# Usage: tool/mac_run.sh <command> [args...]
#   build-ios                         flutter build ios --simulator --no-codesign (example app)
#   build-macos                       flutter build macos --debug (example app)
#   ios <suite-path> [flutter test args]
#                                     boot an available iOS simulator, then
#                                     flutter test <suite-path> -d <udid> ... in example/
#                                     (e.g. ios integration_test/compress_audio_test.dart)
#   macos [flutter test args]         flutter test integration_test -d macos in example/
#   xctest-ios                        xcodebuild test, Runner scheme, on an available simulator
#   xctest-macos                      xcodebuild test, Runner scheme, platform=macOS
#   shell <raw command...>            run a raw command in the synced tree
#
#   MAC_HOST          ssh host (default: dans-macbook-air, from ~/.ssh/config)
#   MAC_DIR           remote directory (default: ~/CodeProjects/compress-video)
#   MAC_RUN_TIMEOUT   seconds before the remote process group is killed (default: 540)
#
# Exit status is the remote command's; 142 means the alarm fired.

set -euo pipefail

MAC_HOST="${MAC_HOST:-dans-macbook-air}"
MAC_DIR="${MAC_DIR:-CodeProjects/compress-video}"
MAC_RUN_TIMEOUT="${MAC_RUN_TIMEOUT:-540}"

usage() {
  sed -n '/^# Usage:/,/^# Exit status/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

[ "$#" -ge 1 ] || usage
COMMAND="$1"
shift

# Resolves the first available iOS simulator's UDID (the same selection CI makes), boots it
# and waits for it to be ready. Emitted as remote shell text; runs on the Mac.
SIM_PRELUDE=$(cat <<'REMOTE'
if command -v jq >/dev/null 2>&1; then
  UDID=$(xcrun simctl list devices available --json \
    | jq -r '.devices | to_entries | map(select(.key | contains("iOS"))) | map(.value) | flatten | map(select(.isAvailable)) | .[0].udid // empty')
else
  UDID=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
print(next((d["udid"] for runtime, ds in devices.items() if "iOS" in runtime for d in ds if d.get("isAvailable")), ""))')
fi
if [ -z "$UDID" ]; then
  echo "mac_run: no available iOS simulator on this Mac" >&2
  xcrun simctl list devices available >&2
  exit 1
fi
echo "mac_run: using simulator $UDID"
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b
REMOTE
)

quote_args() {
  local out=""
  for a in "$@"; do out+=" $(printf '%q' "$a")"; done
  printf '%s' "$out"
}

case "$COMMAND" in
  build-ios)
    BODY='cd example && flutter build ios --simulator --no-codesign'
    ;;
  build-macos)
    BODY='cd example && flutter build macos --debug'
    ;;
  ios)
    [ "$#" -ge 1 ] || { echo "mac_run: ios needs a suite path, e.g. integration_test/compress_audio_test.dart" >&2; exit 2; }
    SUITE="$1"; shift
    BODY="$SIM_PRELUDE
cd example && flutter test $(quote_args "$SUITE") -d \"\$UDID\" -r expanded --timeout 120s$(quote_args "$@")"
    ;;
  macos)
    BODY="cd example && flutter test integration_test -d macos -r expanded --timeout 120s$(quote_args "$@")"
    ;;
  xctest-ios)
    BODY="$SIM_PRELUDE
cd example/ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination \"platform=iOS Simulator,id=\$UDID\""
    ;;
  xctest-macos)
    BODY="cd example/macos && xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=macOS'"
    ;;
  shell)
    [ "$#" -ge 1 ] || { echo "mac_run: shell needs a command" >&2; exit 2; }
    BODY="$*"
    ;;
  *)
    echo "mac_run: unknown command '$COMMAND'" >&2
    usage
    ;;
esac

# The remote side: the login shell slurps the whole script off stdin (`$(cat)`) and hands it
# to `bash -c` as one argument -- so nothing here needs shell quoting across the ssh boundary,
# and no command the script runs can swallow script text (with `bash -s`, a child reading
# stdin would eat the rest of the script; and a `exec </dev/null` at the top of a `bash -s`
# script ends the script itself, which is exactly the bug the first version of this file had).
# perl forks the command into a fresh process group of its own and on alarm kills that whole
# group, then exits 142 itself so the caller sees the alarm rather than a dropped connection.
WRAPPER='
my $t = shift;
my $pid = fork;
if (!$pid) { setpgrp(0, 0); exec @ARGV; exit 127; }
$SIG{ALRM} = sub {
  print STDERR "mac_run: alarm after ${t}s -- killing the remote process group\n";
  kill "TERM", -$pid; sleep 2; kill "KILL", -$pid; exit 142;
};
alarm $t;
waitpid $pid, 0;
my $st = $?;
exit(($st & 127) ? 128 + ($st & 127) : $st >> 8);
'

ssh -o BatchMode=yes -o ConnectTimeout=10 "$MAC_HOST" \
  "perl -e $(printf '%q' "$WRAPPER") $MAC_RUN_TIMEOUT bash -c \"\$(cat)\"" <<EOF
exec </dev/null
set -eo pipefail
export PATH="\$HOME/development/flutter-stable/bin:/opt/homebrew/bin:\$PATH"
cd ~/$MAC_DIR
$BODY
EOF
