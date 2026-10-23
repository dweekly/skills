---
name: ios-simulator-qa
description: Builds, runs, drives and visually verifies iPhone apps on the Simulator, including iPhone Duo, and turn a verified walkthrough into an unattended XCTest or Maestro flow. Covers picking a device by runtime and UDID, a beta Xcode without xcode-select, simulators as shared state, the missing tab bar on iPad and iPhone Duo under XCUITest, reading a test log for crashes versus failures, multi-display capture and poses on the Duo, system UI that sits outside the app's tree, and honest scoping of evidence. Use for any simulator test run, QA pass or test-automation task; not for ordinary iOS implementation with no testing in scope.
license: MIT
---


# iPhone simulator QA

Two kinds of content. The **run mechanics** (first six sections) were each
earned on real runs in September 2026 (Xcode 27.0 and the 27.1 beta,
macOS 27) and are checks or commands, not advice. The **method** sections
after them come from a Duo QA pass on another app and are the
working practice for driving and verifying a flow. For Duo displays and
poses read [references/duo.md](references/duo.md); for turning a
walkthrough into a durable flow read
[references/automated-flows.md](references/automated-flows.md).

A build, a launch PID, a visible accessibility element or a tap command
that returned success does not prove the user flow works. Produce an
observable result, and a rerunnable flow when regression coverage is in
scope.

## Pick the device by runtime, then pin its UDID

A test target with an iOS deployment target newer than the simulator's runtime
fails at **build** time with "doesn't match ... deployment target", before a
single test runs. Device names do not identify a runtime: a machine can easily have several
devices called "iPhone 17 Pro" under different runtimes. Select from the JSON and
pass the UDID.

```sh
xcrun simctl list devices available -j | python3 -c '
import json,sys
want_name, min_runtime = "iPhone 17 Pro", (26, 2)   # deployment target of the test bundle
for rt, devs in json.load(sys.stdin)["devices"].items():
    ver = tuple(int(x) for x in rt.rsplit(".", 1)[-1].split("-")[1:])
    if "iOS" in rt and ver >= min_runtime:
        for d in devs:
            if d["name"] == want_name: print(rt.rsplit(".",1)[-1], d["udid"], d["state"])'
xcodebuild test ... -destination "platform=iOS Simulator,id=<UDID>"
```

Pin the UDID in the script, overridable by an environment variable
(e.g. `APP_SIMULATOR_UDID`), so two sessions can hold
different devices.

## A beta Xcode needs no xcode-select

`xcode-select` needs sudo, which never works from a session. `DEVELOPER_DIR`
per command does the same job for that command only, and `xcrun simctl` under
it sees the beta's runtimes and device types (the 27.1 beta's `iPhone Duo`
was reached this way):

```sh
export DEVELOPER_DIR=/path/to/Xcode-beta.app/Contents/Developer
xcrun simctl list runtimes            # shows the beta's runtimes
xcrun simctl list devicetypes | grep -i duo
xcodebuild test ...                   # builds with the beta's SDK
```

Unset it, or run in a subshell, so later commands go back to the installed
Xcode.

## Simulators are shared state between sessions

Two devices of the same type under the same runtime look identical in a
listing; one of them may be booted by another project. Before booting:

```sh
xcrun simctl list devices booted      # anything listed belongs to someone until proven otherwise
```

Boot your own by UDID, shut down that UDID when done, and never
`simctl shutdown all`. A script that records real-time footage should also
wait until no other simulator it did not boot is running a test, because a
concurrent UI run competes for the same CPU. (That timing skew is a
precaution taken, not a measurement made.)

## iPad and iPhone Duo have no `TabBar` under XCUITest

`app.tabBars.buttons["Name"]` finds nothing on iPad since iOS 18 (the floating
tab bar) and on iPhone Duo under iOS 27.1: most UI failures in one Duo run
were this one selector. Any tab helper should try the tab bar and fall back to
a label predicate on every device:

```swift
let tab = app.tabBars.buttons[name]
if tab.waitForExistence(timeout: 2) { tab.tap(); return }
let fallback = app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
XCTAssertTrue(fallback.waitForExistence(timeout: 3), "Could not find tab: \(name)")
fallback.tap()
```

Related: a view with `.navigationBarTitleDisplayMode(.inline)` and no
`.navigationTitle` has no navigation bar to match by name; assert on content
the screen shows instead.

## Read the log for crashes separately from failures

"33 failures" and "the app crashed" are different findings and the log tells
them apart. After a run:

```sh
grep -E "Test run with [0-9]+ tests|Executed [0-9]+ tests" test.log | tail -3   # totals per bundle
grep -E "error: -\[" test.log | sed -E 's/.*\] : //; s/"[^"]*"/"…"/g' | sort | uniq -c | sort -rn   # failures by cause
grep -ciE "crashed|EXC_BAD|SIGABRT|Fatal error" test.log                        # 0 means no crash
```

Two lines on the iOS 27.1 runtime are noise, not defects: `CHHapticPattern ...
hapticpatternlibrary.plist couldn't be opened` and `Class
UIAccessibilityLoaderWebShared is implemented in both ... WebCore ... WebKit`.

## Never let a pipe hide the exit code

`xcodebuild test ... | grep ... | tail` reports the exit status of `tail`. The
first Duo attempt "succeeded" on a build that never ran. Capture the log and
print the pipeline's own status:

```sh
set -o pipefail
xcodebuild test ... 2>&1 | tee test.log | grep -E "✘|TEST (SUCCEEDED|FAILED)|error:" | tail -20
echo "pipeline exit: $?"
```

## Swift Testing filters

`-only-testing:Target/Suite` runs a Swift Testing suite; a filter that matches
nothing still exits 0, so assert on the totals line, not the exit code.

## Establish the target and test state

- Inspect the project's existing test runner, scheme, configuration and
  launch hooks before inventing another harness. Debug does not mean
  staging; confirm the backend and use that project's documented fixtures,
  never another app's credentials or reset flags.
- Record Xcode version and build, simulator runtime, UDID, app build and
  configuration, and (on the Duo) the current pose, and pin every device
  command and test destination to the same UDID.
- Distinguish a fresh-user launch from a returning-user launch. Read what a
  launch flag does: an innocently named UI-test flag may erase defaults and
  sign out on every launch. Omit resets when checking persistence.

## Observe before diagnosing

Use the accessibility hierarchy for semantic selection and screenshots for
visual results, and check both at layout-sensitive checkpoints.

- Select by stable accessibility identifier and element type. A SwiftUI
  `Button` and its child text can expose the same identifier; restrict the
  query rather than picking an ambiguous match.
- Wait for existence, enabled state and hittability. Hidden drawers may
  remain in the tree; lazy lists omit off-screen children, so scroll the
  container before insisting the target must exist.
- Target the actual scroll view. A whole-app swipe that scrolls a menu on a
  compact phone can hit a different pane in a wide layout; prefer a stable
  container identifier over `firstMatch` when several scroll views exist.
- Verify postconditions after actions (prompt gone, expected screen open,
  persisted item present, playback time advanced) with bounded predicate
  waits, not fixed sleeps.
- Accessibility exposes full strings even when the rendered text ends in an
  ellipsis. A height check catches truncation for one font and layout; it
  is not universal proof of legibility. Inspect the screenshot.

Capture display evidence with the bundled helper, which screenshots every
integrated display of a booted simulator plus toolchain and device metadata
without changing app state or pose, and refuses to overwrite an existing
output directory:

```sh
python3 <skill-dir>/scripts/capture_simulator.py --udid "$SIM_UDID" --output "$SCRATCH/qa-checkpoint-1"
```

On a toolchain whose `simctl io enumerate` output the helper cannot parse,
pass `--display` explicitly (`simctl io help` lists the accepted selectors:
screen ID, screen name, "internal" or "external"). The helper does not
decide which display is active; look at the images.

## System UI and unreliable automation

Permission prompts, contact pickers and share sheets can live outside the
app's tree; the app stays fully enumerable while a system sheet intercepts
every interaction.

- Inspect both a screenshot of the active display and the relevant system
  hierarchy, for example `XCUIApplication(bundleIdentifier:
  "com.apple.springboard")`. Some pickers belong to other system processes.
- Pre-grant supported simulator permissions (`simctl privacy`) when the
  prompt is irrelevant to the scenario; for first-run permission testing,
  keep the prompt and test it deliberately. `simctl privacy` does not cover
  every permission type.
- Follow the requested permission choice. Selecting no contacts is the right
  way to exit a contacts picker the scenario only needs to dismiss.
- If a driver reports a successful tap and the prompt remains, save its
  bounds and a screenshot, retry only to test a concrete hypothesis, and use
  native XCTest where it can express the interaction. No prolonged
  coordinate guessing, and never two drivers on one device.
- Separate reproduced symptoms from suspected causes. Search upstream by the
  actual symptom, tool version, sheet type and orientation. A similar issue
  supports a known failure class; it does not establish a diagnosis.

Use the repository's existing Maestro flows when they are reliable. Native
XCTest is the tool for system UI and multi-screen attachments. `simctl`
supplies lifecycle and capture operations, not a semantic tap API.

## Scope evidence honestly

A static wide-layout pass does not establish fold continuity. Simulator
playback does not establish real-device audio interruptions, Bluetooth
routing or background suspension. State exactly which flows and poses
passed, what evidence was saved and what remains untested. Treat beta
observations as versioned evidence and recheck `simctl io help` and the
current docs before carrying them into a new SDK.

## Related

- The Xcode 27 plugin's `device-interaction` skill drives a booted simulator by
  screenshot and taps; it is iOS-only and complements this skill.
- [references/duo.md](references/duo.md): multiple displays, poses, layout and
  lifecycle checks, a practical Duo matrix, and a Maestro symptom with its
  upstream reports.
- [references/automated-flows.md](references/automated-flows.md): the runner,
  fixture and cleanup contract, assertions and evidence, and app test hooks.
- `agents/openai.yaml`: the same skill's display metadata for the codex CLI.
