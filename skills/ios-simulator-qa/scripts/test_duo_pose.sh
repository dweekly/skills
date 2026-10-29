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

posterboard() { xcrun simctl spawn "$udid" launchctl list 2>/dev/null | awk '$3 == "com.apple.PosterBoard" { print $1, $2 }'; }

# Given PosterBoard's `launchctl list` reading ("PID LASTEXIT", PID "-" when not running) before and
# after the poses, and how many times launchd_sim spawned it in between, print what looks like a
# crash, or nothing. A crash need not have been followed by a respawn yet.
posterboard_problem() {
  local before=$1 after=$2 spawns=$3
  local b_pid=${before%% *} b_exit=${before#* } a_pid=${after%% *} a_exit=${after#* }
  if [ -z "$after" ]; then
    [ -n "$before" ] && echo "PosterBoard is no longer listed by launchctl"
    return 0
  fi
  if [ -n "$before" ] && [ "$b_pid" != "-" ] && [ "$a_pid" != "$b_pid" ]; then
    echo "the PosterBoard that was running (PID $b_pid) is gone (now PID $a_pid, last exit $a_exit)"
  elif [ "$a_exit" != "$b_exit" ] && [ "$a_exit" != "0" ]; then
    echo "its last exit status changed to $a_exit"
  elif [ "$spawns" -gt 1 ] && [ "$a_exit" != "0" ]; then
    echo "it was spawned $spawns times, last exit status $a_exit"
  fi
  return 0
}

# The verdict above is the only thing between a PosterBoard crash and a PASS, so check it on fixed
# readings first (no device needed). Format: before|after|spawns|expect (crash or ok).
for case in "101 0|- -5|0|crash" "101 0|101 0|0|ok" "50448 -5|50448 -5|0|ok" "101 0|202 -5|1|crash" \
            "101 0|202 0|1|crash" "- -5|303 -5|1|ok" "- 0|- -5|0|crash" "101 0||0|crash" "||0|ok"; do
  IFS='|' read -r b a n want <<<"$case"
  got=ok; [ -n "$(posterboard_problem "$b" "$a" "$n")" ] && got=crash
  if [ "$got" != "$want" ]; then
    echo "FAIL self-check: PosterBoard verdict for before='$b' after='$a' spawns=$n is $got, expected $want" >&2
    exit 3
  fi
done

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
problem=$(posterboard_problem "$before" "$after" "${spawns:-0}")
if [ -n "$problem" ]; then
  failures=$((failures + 1))
  echo "FAIL PosterBoard: $problem (PID/last exit before: ${before:-none}, after: ${after:-none}; spawns: ${spawns:-0}). Crash reports: ~/Library/Logs/DiagnosticReports/PosterBoard-*.ips naming $udid (written up to a minute late)."
else
  echo "PASS PosterBoard stable (PID/last exit before: ${before:-none}, after: ${after:-none}; spawns: ${spawns:-0})"
fi

if [ $failures -eq 0 ]; then echo "duo-pose self-test passed"; else echo "duo-pose self-test FAILED ($failures)"; fi
[ $failures -eq 0 ]
