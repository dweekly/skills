#!/bin/bash
# Self-test for duo-pose on an iPhone Duo simulator: closed, open, closed, partial, open, each set
# and then read back, so every pose is reached from a different one at least once. Fails if the private hinge event stops working (as it may on a new Xcode or runtime)
# or if PosterBoard crashes while the poses change.
#
#   test_duo_pose.sh            create a temporary iPhone Duo on the newest iOS runtime that has
#                               one, boot it, test, then shut it down and delete it
#   test_duo_pose.sh <UDID>     use that booted iPhone Duo instead (its pose is changed and left open)
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tool="$here/duo-pose"
created=""
failures=0

cleanup() {
  if [ -n "$created" ]; then
    xcrun simctl shutdown "$created" >/dev/null 2>&1
    xcrun simctl delete "$created" && echo "deleted temporary simulator $created"
  fi
}
trap cleanup EXIT

if [ $# -ge 1 ]; then
  udid=$1
else
  runtime=$(xcrun simctl list runtimes -j | python3 -c '
import json, sys
rts = [r for r in json.load(sys.stdin)["runtimes"]
       if r.get("platform") == "iOS" and r.get("isAvailable")
       and any(t.get("identifier", "").endswith(".iPhone-Duo") for t in r.get("supportedDeviceTypes", []))]
rts.sort(key=lambda r: [int(x) for x in r["version"].split(".")])
print(rts[-1]["identifier"] if rts else "")')
  if [ -z "$runtime" ]; then echo "FAIL: no installed iOS runtime supports iPhone Duo" >&2; exit 3; fi
  created=$(xcrun simctl create "duo-pose self-test $$" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo "$runtime") || exit 3
  udid=$created
  echo "created temporary simulator $udid ($runtime); booting"
  xcrun simctl boot "$udid" || exit 3
  xcrun simctl bootstatus "$udid" -b >/dev/null || exit 3
fi

posterboard() { xcrun simctl spawn "$udid" launchctl list 2>/dev/null | awk '$3 == "com.apple.PosterBoard" { print $1, $2 }'; }
start=$(date "+%Y-%m-%d %H:%M:%S")
before=$(posterboard)

for pose in closed open closed partial open; do
  set_out=$("$tool" "$udid" "$pose" 2>&1); set_rc=$?
  get_out=$("$tool" "$udid" get 2>&1); get_rc=$?
  if [ $set_rc -eq 0 ] && [ "$set_out" = "$pose" ] && [ $get_rc -eq 0 ] && [ "$get_out" = "$pose" ]; then
    echo "PASS $pose"
  else
    failures=$((failures + 1))
    echo "FAIL $pose: set exit $set_rc: $set_out"
    echo "     get exit $get_rc: $get_out"
    case $set_rc in
      1) echo "     The event was sent but the pose did not follow. Likely cause: a new Xcode or runtime changed the private hinge event (payload, service name or how locationd reads it). Compare with Device Hub's own event: log stream on the simulator while moving its hinge control." ;;
      3) echo "     Likely cause: a private interface the tool needs is gone (CoreSimulator's lookup:error:, libxpc's *_4sim functions, or the vendordefined HID service), or the device is wrong." ;;
    esac
  fi
done

# PosterBoard has crashed once on an iPhone Duo just after a Device Hub pose change; a pose change
# must not crash it, and a crash loop would break home-screen and lock-screen captures.
after=$(posterboard)
spawns=$(xcrun simctl spawn "$udid" log show --start "$start" --style compact \
  --predicate 'process == "launchd_sim" AND eventMessage CONTAINS "Successfully spawned PosterBoard"' 2>/dev/null \
  | grep -c "Successfully spawned PosterBoard")
last_exit=${after#* }
if [ "${spawns:-0}" -gt 0 ] && [ "$last_exit" != "0" ]; then
  failures=$((failures + 1))
  echo "FAIL PosterBoard respawned $spawns time(s) during the test, last exit status $last_exit (PID/status before: ${before:-none}, after: ${after:-none}). Crash reports: ~/Library/Logs/DiagnosticReports/PosterBoard-*.ips naming $udid (written up to a minute late)."
else
  echo "PASS PosterBoard stable (PID/last exit before: ${before:-none}, after: ${after:-none}; respawns: ${spawns:-0})"
fi

if [ $failures -eq 0 ]; then echo "duo-pose self-test passed"; else echo "duo-pose self-test FAILED ($failures)"; fi
[ $failures -eq 0 ]
