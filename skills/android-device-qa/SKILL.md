---
name: android-device-qa
description: Builds, installs, drives and visually verifies Android apps on emulators and physical phones, and turns a verified walkthrough into an unattended Maestro flow and a screen matrix across devices, font sizes and orientations. Covers running a fleet of headless emulators in parallel on one Mac, the emulator that records the room through the host microphone, emulators shared with other agents, wireless adb pairing on macOS (the daemon that loses Local Network access), what a uiautomator dump can and cannot show, a target-size and label checker with its rounding trap, TalkBack's limits under adb, font-scale and rotation that reset behind your back, clean status bars and screenshots without alpha, measuring time to content rather than time to splash, version-code downgrades, run-as quoting, and shell traps with adb. Use for any Android test run, QA pass, accessibility audit, screenshot capture or test-automation task; not for ordinary Android implementation with no testing in scope.
license: MIT
---

# Android device QA

Everything here was earned on real runs in October 2026 (emulator 37.2, platform-tools 37.0,
Maestro 2.10, macOS on Apple silicon, physical phones on Android 16 and 17) and is a check or a
command, not advice. Dates are given where a behavior may change with a release.

A build, an install, a launch that returned 0 or a tap that "succeeded" does not prove the
user flow works. Produce an observable result (a screenshot you looked at, a log line you
counted, a file you measured) and a rerunnable flow when regression coverage is in scope.

## Emulators: a headless fleet, never the host microphone

**Start QA emulators with `-no-audio`.** An emulator started with `-allow-host-audio` (or with
the window's "Virtual microphone uses host audio input" toggle on) hears the room through the
Mac's microphone. If the app under test records and uploads, an unattended run uploads real
conversations from the room. That happened overnight once. The toggle in the window cannot be
detected from outside, so leave it off, and make the test scripts refuse an emulator whose
command line carries `-allow-host-audio`:

```sh
ps -axo command | grep -E "qemu-system.*-avd $AVD( |$)" | grep -q -- -allow-host-audio && {
  echo "refusing: $AVD hears the host microphone" >&2; exit 1; }
```

**A fleet in parallel.** Each emulator needs about 2 to 4 GB of RAM. On a large Mac, four to six
run side by side without trouble:

```sh
E=$ANDROID_HOME/emulator/emulator
$E -avd QA_Phone -port 5570 -no-window -no-audio -no-boot-anim -no-snapshot-save -read-only &
$E -avd QA_Phone -port 5572 -no-window -no-audio -no-boot-anim -no-snapshot-save -read-only &
adb -s emulator-5570 wait-for-device shell 'while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 1; done'
```

- The port is the even console port (5554 to 5682); adb is that port plus one, and the
  serial is `emulator-<port>`. Pick ports explicitly so two sessions never collide.
- `-read-only` is what lets two instances of the same AVD run at once. Neither keeps its
  changes, so sign-in and seed data are redone per boot, or baked into a snapshot beforehand.
- `-no-window` runs the `qemu-system-aarch64-headless` binary. Seen on emulator 37.2
  (2026-10-29): the windowed binary failed to start ("Library not loaded:
  @rpath/libandroid-emu-tracing.dylib") while the headless one ran. Reinstall the emulator
  package if you need a window.
- An emulator can die on its own: a `qemu-system-aarch64` crash report whose stack ends in
  `std::bad_function_call` inside the emulator's gRPC code is the emulator, not the app. The
  app's own crash shows in `adb logcat -b crash`.

**Emulators are shared state.** Other agents on the same Mac run their own. Before you start,
`adb devices` and `ps -axo pid,lstart,command | grep qemu-system` show what is running and for
whom (the AVD name usually says). Use your own AVD names with a prefix, address only your
serials (`ANDROID_SERIAL` or `adb -s`), kill only the PIDs you started, and never
`adb emu kill` or `pkill qemu` broadly.

## Physical phones over wireless adb on macOS

Pair once per phone (Developer options, Wireless debugging, "Pair device with pairing code"),
then connect. Three things go wrong, in this order:

1. **The daemonized adb server cannot reach the phone.** `adb pair` fails with
   "protocol fault (couldn't read status message)", and the server log says
   "No route to host", while `nc` from the same shell reaches the phone. The detached daemon
   is no longer covered by the terminal's Local Network permission. Run the server attached:

   ```sh
   adb kill-server
   adb nodaemon server &          # keep it running for the session
   ```

2. **adb's mDNS sees nothing.** Find the phones with macOS's own resolver instead:

   ```sh
   dns-sd -B _adb-tls-connect._tcp           # phones offering a connection
   dns-sd -B _adb-tls-pairing._tcp           # a phone showing its pairing dialog
   dns-sd -L <instance-name> _adb-tls-pairing._tcp   # its pairing port
   adb pair <ip>:<pairing-port> <six-digit-code>
   adb connect <ip>:<connect-port>           # the connect port differs from the pairing port
   ```

   The phone and the Mac must be on the same network. A phone on a guest or second SSID is
   invisible, not broken.

3. **`CERTIFICATE_UNKNOWN` in the handshake** means the phone forgot the pairing. Pair again.

Phones on wireless debugging vanish when they sleep: `adb devices` is empty while mDNS still
advertises them, and `adb connect` brings them back. Turn on "Stay awake" in Developer options
for the session and keep the phone unlocked: a locked phone screenshots its lock screen and no
flow can tap through it. The connect port changes when wireless debugging restarts.

A budget phone is the better test device. A 720-pixel phone at 260 dpi is about 443 dp wide,
narrower than most emulator profiles, and it is where truncation, wrapping and cramped rows
show up first.

## What a hierarchy dump can show

`adb shell uiautomator dump` (and Maestro's view, `maestro hierarchy`) give each node `text`,
`content-desc`, `resource-id`, `class`, `clickable`, `checkable`, `checked`, `selected`,
`enabled`, `focused`, `scrollable` and `bounds`. They do **not** carry a Compose
`stateDescription`, a heading flag or a role. So:

- A test can assert a control's name and on/off state, not what TalkBack will say about it.
  Assert on visible text, or on the name, which is the content description when there is one.
- Compose test tags are invisible to both unless the root sets
  `Modifier.semantics { testTagsAsResourceId = true }`, which exposes them as `resource-id`.
  That turns coordinate taps into named taps, and the same names make screenshots scriptable.
- Coordinates from one device, scale or orientation are wrong on the next. If a flow must fall
  back to coordinates, read them from a dump on the same run, and remove the fallback once the
  control has a name.

## Accessibility checks you can automate, and the one you cannot

**A label and target-size checker over the dumps.** Flag a clickable node in the app's package
with no `text` or `content-desc` anywhere inside it (TalkBack cannot name it), and a clickable
node under 48 dp in either dimension (a finger cannot reliably hit it). Two refinements stop it
crying wolf:

- **Clipping per axis.** A row cut off by the top or bottom of the screen or its scrolling list
  is short because it is clipped, not because it is small. Judge height only for nodes not
  clipped vertically and width only for nodes not clipped horizontally.
- **Rounding.** dp converts to pixels with rounding, so a 48 dp button at 260 dpi measures
  77 px against a computed 78. Allow one pixel: `min_px = 48 * dpi / 160 - 1`. Without that,
  every 48 dp control on such a phone is a false finding.

Record counts per cell (device, configuration, screen) and fail a run when any cell's count
rises or a cell the baseline had is missing (a screen whose flow failed is not an improvement).
Refuse to compare runs that cover different devices or configurations.

**TalkBack cannot be driven from adb.** Injected taps and swipes (`input`, Maestro) do not reach
TalkBack's gesture handling, so focus does not move, and TalkBack does not log what it speaks.
A TalkBack pass is done by a person with the phone. Hand them a short checklist per screen:
what each control should say, the reading order, and which state changes must be announced.

## The screen matrix: devices x font scale x orientation

People who use large text meet a different app. Walk every main screen at several font scales,
in both orientations, on at least one small phone, one large phone and one tablet, and look at
every screenshot.

```sh
adb shell settings put system font_scale 2.0      # 1.0, 1.3, 2.0 (2.0 is the Android 14+ maximum)
adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation 1     # 0 portrait, 1 landscape on a phone
adb shell wm density 320                          # emulate another density; `wm density reset`
adb shell wm size 1080x2400                       # emulate another size; `wm size reset`
```

- **Rotation resets behind you.** Force-stopping the app brings the launcher forward, and the
  phone emulators then went back to rotation 0. Set the orientation inside the flow after each
  launch (Maestro `setOrientation`), and check every screenshot's shape: a "landscape" capture
  that is taller than wide is a failed cell, not a result.
- "Portrait" and "landscape" are shapes, not rotation numbers: a tablet held upright may be
  rotation 1.
- A landscape phone at 2x text shows a line or two per swipe. Scrolling to a far item needs long
  timeouts, and an item the layout makes unreachable (a pinned footer leaving the list less
  than a row tall) is an app finding, not a flaky test.
- Restore `font_scale 1.0`, rotation and density when you finish, or the next agent's run on
  that device inherits them. Check them before any flow that types: a sign-in flow on a phone
  left in landscape failed because the keyboard covered the Continue button.

## Maestro

- `maestro --device <serial> test flow.yaml`. Run one Maestro per device, in parallel.
- **In 2.10, a flow's `env:` block beats `-e` on the command line.** Declare no defaults in the
  flow for values the script passes.
- **Something floating takes the tap.** A mini player, snackbar or bottom bar over the target
  receives a tap aimed at the target's centre. Scroll the target clear first, or tap by a
  point inside the visible part.
- **First-run state** (carousels, tooltips, permission dialogs) appears once per install. A
  tooltip is often a separate window: the dump then shows only the tooltip. Handle each with
  `runFlow: when: visible:` blocks, so the flow works on both a fresh and a used install.
- **Optional steps** (`optional: true`) for things that may or may not be there. Use them
  sparingly: an optional step that silently never runs hides a broken screen.
- **A relaunch is not a reopen.** Launching the app with a force-stop resets every in-process
  singleton (a media player, a cache). A bug in "leave the screen and come back" only shows
  when the flow goes back and reopens the screen inside the same process. Write the test that
  way, or it passes against a state no user is in.
- Data a flow relies on changes under it. Another person or run posting to the shared test
  account moved a list and broke a flow's assumption about what is on screen. Seed the state
  the flow needs, find items by name rather than position, and screenshot before trusting a
  reproduction.

## Measuring instead of looking

- **The app's own log lines are counters.** Clear the log, run the flow, then count a line the
  app writes on every bind, parse or request: `adb logcat -d --pid=$(adb shell pidof <pkg>)`.
  Filter by pid or another process's lines pollute the count.
- **`am start -W` times the first frame, which is usually the splash.** For time to content,
  record the launch and find the frame where the content appears:

  ```sh
  adb shell screenrecord --time-limit 10 /sdcard/launch.mp4 &
  sleep 1; adb shell am start -n <pkg>/<activity>; wait
  adb pull /sdcard/launch.mp4
  ffmpeg -i launch.mp4 -vf "select='gt(scene,0.05)',showinfo" -f null - 2>&1 | grep pts_time
  ```

  Take the median of several cold starts on the same device rather than one run.
- **`screenrecord` encodes a frame only when the display changes.** A static screen yields a
  one-frame file, so a tiny recording is itself proof of a quiet screen; counting frames that
  differ from their predecessor quantifies flicker when it is not quiet.
- **Microphone and audio state are visible in `dumpsys audio`.** Its RecordActivityMonitor
  section logs each recording client's start and stop with timestamps, which proves a pause
  released the microphone. Compare the recorded file's duration (`ffprobe`) with the
  microphone-on time to prove a pause left no gap or extra audio.
- **Footprint from a release build.** Debug APKs carry no shrinking and are not comparable.
  Build both sides of a comparison clean, from the same toolchain.

## Screenshots for people and stores

- **Clean status bar:** System UI demo mode.

  ```sh
  adb shell settings put global sysui_demo_allowed 1
  adb shell am broadcast -a com.android.systemui.demo -e command enter
  adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941
  adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false
  adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4
  adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false
  adb shell am broadcast -a com.android.systemui.demo -e command exit    # when done
  ```

- **`adb exec-out screencap -p` writes a PNG with an alpha channel.** Google Play accepts JPEG
  or 24-bit PNG without alpha; flatten before upload (`magick in.png -alpha off out.png`).
- Use `exec-out` for binary output; it passes bytes through with no terminal in between.

## Installing and reaching app data

- **Version-code downgrades.** A local build usually has a lower versionCode than a CI build
  already on the device. `adb install -r -d` allows the downgrade for debuggable builds only;
  otherwise the install fails with `INSTALL_FAILED_VERSION_DOWNGRADE` and the choice is
  uninstalling, which loses sign-in and data. Bump the local versionCode instead when the
  state matters.
- `adb install -r` keeps data, so a signed-in test account survives reinstalls.
- **`run-as <pkg>`** (debuggable builds only) reads and writes the app's private files and
  preferences. It does not start in the app's directory: use `/data/user/0/<pkg>/...`.
- **`adb shell` re-parses its argument.** `adb shell run-as pkg sh -c "cat x > y"` arrives as
  `run-as pkg sh -c cat x > y`: the redirect runs as the shell user, which cannot write the
  app's directory, and the error is "Permission denied" on a path the app owns. Quote the whole
  remote command once: `adb shell "run-as pkg sh -c 'cat x > y'"`.

## Shell traps

- **adb eats stdin.** Inside `while read line; do adb ...; done < list`, the first adb call
  consumes the rest of the list and the loop runs once. Give every adb call `</dev/null`
  (or use `adb shell -n`).
- **zsh does not word-split unquoted variables.** `set -- $bounds` or `for x in $list` gets one
  word in zsh. Run such scripts with `bash`, or split explicitly (`${=var}`).
- **`./gradlew ... | tail; echo $?` reports tail's exit, not Gradle's.** A build whose output
  was filtered through a pipe "passed" while the APK on disk was half an hour old, and the next
  device check ran the old code. Check the APK's timestamp, or capture Gradle's status directly
  (`./gradlew ... > log 2>&1; echo $?`, or `set -o pipefail`) before installing.
- **A waiter built on `pgrep -f <pattern>` waits forever** when the pattern appears in the
  waiter's own command line (`until ! pgrep -f "matrix/run1"; do sleep 10; done` matches
  itself). Record the PID when you start the job and wait on it: `while kill -0 $pid; do ...`.
- `uiautomator dump` writes to the device; read it back in the same command
  (`adb shell 'uiautomator dump /sdcard/u.xml >/dev/null && cat /sdcard/u.xml'`) so two
  parallel runs on one device do not read each other's file, and use a path per run.

## Honest scope

Say which devices, Android versions, font scales and orientations a result covers, and which
it does not. An emulator says nothing about a real microphone, real thermal throttling or a
real budget phone's speed. A checker that reports zero findings has checked names and sizes,
not what a screen reader says. "Verified" means you looked at the output of a check that would
have failed if the thing were broken.
