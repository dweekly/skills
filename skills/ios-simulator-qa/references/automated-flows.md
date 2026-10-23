# Turn a walkthrough into a repeatable flow

Keep the cross-project technique in this skill; keep selectors, fixtures, credentials, and test cases in the app repository. Preserve a working runner instead of introducing another automation stack by default.

## Make the result independent of an LLM

A durable command should resolve explicit inputs, build/run the selected tests, save logs and results, and return nonzero for an assertion or cleanup failure. It should not need the agent to decide the next tap. A one-time manually selected pose can be an explicit precondition without making the rest of the flow manual.

For native XCTest, the runner typically sets the requested `DEVELOPER_DIR`, a pinned UDID, project/workspace and scheme, a fixed DerivedData directory, a fresh `.xcresult` path, and an explicit test selection. Disable parallel device testing when validating the current physical simulator pose; cloned destinations can defeat that assumption. Avoid selecting an entire legacy suite without reading it: old tests may mutate unrelated backend records.

```bash
xcodebuild test -workspace "$QA_WORKSPACE" -scheme "$QA_SCHEME" \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -derivedDataPath "$QA_DERIVED_DATA" \
  -resultBundlePath "$QA_RESULT_BUNDLE" \
  -parallel-testing-enabled NO \
  "-only-testing:$QA_TEST_IDENTIFIER"
```

Set these project-specific values before using the example. Handle build failure without a log formatter or `tee` masking its exit code. Save raw logs even if the console prints only a useful tail. `.xcresult` destinations must be fresh. Check local `xcrun xcresulttool export attachments --help` for exporting screenshots and hierarchies.

## Fixture and cleanup contract

- Use a documented synthetic account or emulator and uniquely named records for this run. Pass only the needed credentials; do not embed another project's account in a reusable skill.
- Create a private/single-member fixture when interaction with other people is unnecessary. Opening a share sheet is a sufficient UI test when sending externally is out of scope.
- Check relaunch persistence with reset flags removed. Keep first-run permission/tutorial behavior separate from returning-user behavior.
- Cleanup only records whose identity is established as belonging to this run. Use an exact ID/name guard before a destructive UI action. Never “delete all” as a convenient cleanup strategy on a shared account.
- Use `defer`, `@finally`, or teardown to attempt cleanup after failures. Recover from an open modal by relaunching without resetting authentication when needed. Bound retries; fail and report the remaining fixture identifier if cleanup cannot complete. Preserve the original assertion failure as well.

## Useful assertions and evidence

Check outcomes rather than mirroring implementation: a saved item survives relaunch; a selected room remains selected; elapsed playback advances; a required action is hittable; a previously truncated explanation has sufficient rendered height. A full accessibility label alone does not catch visual truncation.

Capture named checkpoints and failure state in the result bundle, including every relevant display. Distinguish a share menu opening from an actual transmission, and a playback time advancing from proof of audible sound. Avoid recording ambient host microphone audio merely to test playback; use the project's known media fixture. If microphone capture is in scope, make input routing explicit and restore any host audio routing changes.

Run the new command unattended once end to end. Inspect the artifacts and verify fixture cleanup. Report the exact tested pose and important exclusions. Retire temporary interactive command drivers when the durable test replaces them; do not leave polling servers or debug backdoors just to preserve a walkthrough.

## App test hooks

Read the existing launch contract before adding hooks. Names such as `isUITest` have no standard meaning. Keep debug-only hooks gated by the project's actual compiler configuration; an Objective-C DEBUG macro does not prove Swift has an equivalent active compilation condition. Stateful persistence tests must not relaunch through a hook that wipes state.
