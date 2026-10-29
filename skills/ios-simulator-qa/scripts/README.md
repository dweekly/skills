# ios-simulator-qa scripts

- `capture_simulator.py`: screenshots every integrated display of a booted simulator plus toolchain and device metadata; usage in SKILL.md.
- `duo-pose`: sets or reads an iPhone Duo simulator's fold pose from the command line (below).
- `test_duo_pose.sh`: self-test for `duo-pose`.

## duo-pose

```sh
duo-pose <UDID> get                 # prints closed, partial or open ("unknown" and exit 1 if unclear)
duo-pose <UDID> closed|partial|open # sets it, prints the confirmed pose
```

Exit 0 only when the pose is confirmed three ways: SpringBoard's log shows the matching hinge state (`Closed`, `PartiallyOpen`, `OpenFlat`), SpringBoard's last display transition has completed, and screenshots of both integrated displays show the expected one lit (outer when closed, inner otherwise). Exit 1 means sent but not confirmed, 2 a usage error, 3 the wrong device or a missing private interface. It takes an exact UDID and refuses names, `booted` and `all`, and devices that are not a booted iPhone Duo. `partial` is a 130 degree hinge, `open` 180 (flat). Each call takes about 4 to 10 seconds. `DUO_POSE_VERBOSE=1` prints each observation; `DUO_POSE_TIMEOUT` (default 30) bounds the wait.

The first run compiles `duo_pose.swift` with `xcrun swiftc` into `~/Library/Caches/ios-simulator-qa/` (once per source and compiler version; old builds are left in place, so delete that directory to reclaim space). No third-party dependencies.

**How it works.** Device Hub's pose buttons send a vendor-defined HID event carrying a hinge angle. `duo-pose` sends the same event from the Mac: it gets the simulator's `com.apple.coredevice.feature.remote.hid.vendordefined` Mach service from CoreSimulator (private framework, `-[SimDevice lookup:error:]`), connects to it with libxpc's private `*_4sim` calls, and sends an `IndigoVendorDefinedEvent` XPC message whose payload is usage page 0xFF61, usage 91 and an IOKit binary property list (`source: hinge-slider-control`, `type: range`, `value: <degrees>`). Inside the simulator, dtuhidd turns it into a HID event, locationd reads the angle and SpringBoard moves the UI between displays. Device Hub's process is not involved, but it was running during all testing; running without it is untested.

**Opening goes through a waypoint.** SpringBoard animates a fold as a continuous transition and only completes a stalled one at an intermediate angle. A single jump from closed to 180 degrees starts a transition that never completes, and the next close is then silently ignored. So `open` from closed first stops at 130 degrees and waits for SpringBoard to log the transition completed. If a transition was already left open (by a direct jump from some other tool), `closed` and `open` do the same first. Interrupting a completing transition with another angle can wedge SpringBoard so the displays never follow again; restarting SpringBoard (`xcrun simctl spawn <UDID> launchctl kickstart -k user/$(id -u)/com.apple.SpringBoard`) or rebooting cleared it in testing, and the tool says so instead of sending more events.

**Self-test.** `test_duo_pose.sh` with no argument creates a temporary iPhone Duo on the newest runtime that has one, boots it, sets and reads back closed, open, closed, partial and open, checks that PosterBoard did not crash or respawn (its verdict logic is first checked against fixed readings), then deletes the simulator. `test_duo_pose.sh <UDID>` runs the same on a booted Duo you own (leaving it open). A failure names the likely cause: a new Xcode or runtime that changed the private event, or a missing interface.

**From an XCUITest.** The test runner lives inside the simulator and cannot send this host-side event (duo-fold-control reports that a connection opened from inside the simulator never reached the service). Set the pose from the script that runs the tests, between `xcodebuild test -only-testing:` invocations, one pose per invocation. For a pose change in the middle of a test, duo-fold-control's approach is a small HTTP server on the Mac that the test calls on 127.0.0.1 with its `SIMULATOR_UDID`; that bridge is not included here.

**Limits.** It relies on private, undocumented interfaces and log text (CoreSimulator, libxpc `*_4sim`, the HID payload, SpringBoard's log lines), so expect a new Xcode or runtime to break it; run the self-test after each upgrade. Device Hub's own controls may not reflect a pose set this way. Rotation is separate (not handled). A reboot resets the pose to closed. Never substitute `simctl io screenConfig ... power`: it blanks a display without folding.

**Credits.** The event, its payload and the host-side connection were worked out and published by [tosbaha/duo-fold-control](https://github.com/tosbaha/duo-fold-control) (MIT) and [michael-palmes/offsider PR #87](https://github.com/michael-palmes/offsider/pull/87) (MIT). `duo-pose` is an independent implementation written from their descriptions; no code was copied.
