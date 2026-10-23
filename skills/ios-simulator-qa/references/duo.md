# Duo-specific testing notes

Observed September 18, 2026 with Xcode 27.1 beta build 27A9269, iOS 27.1 Simulator, and Maestro 2.10.0. Revalidate on later betas; these are not permanent API guarantees.

## Multiple displays and pose

`xcrun simctl io "$SIM_UDID" enumerate` identifies connected screens and selectors for `screenshot --display=...`. On the tested simulator, outer and inner were screen IDs 1 and 3. Discover them each time; those numbers are observations, not configuration defaults. Enumeration's power state alone did not identify the visually active display.

`app.screenshot` sometimes captured the inactive outer display as black while the inner display showed a healthy app. Before diagnosing a black screen as a launch failure, capture each integrated display and check app/process logs. Conversely, a successful launch PID is not proof the process stayed alive.

Native XCTest evidence worked by iterating all screens:

```swift
for (index, screen) in XCUIScreen.screens.enumerated() {
    let shot = XCTAttachment(screenshot: screen.screenshot())
    shot.name = "checkpoint-screen-\(index)"
    shot.lifetime = .keepAlways
    add(shot)
}
let tree = XCTAttachment(string: app.debugDescription)
tree.name = "checkpoint-hierarchy"
tree.lifetime = .keepAlways
add(tree)
```

The equivalent Objective-C implementation was exercised; adapt the Swift syntax to the local XCTest SDK. Include stage names and device/pose metadata. Retain all screens in the result, then inspect the active image.

A full screenshot can be rotated relative to native pixel dimensions. XCTest frames are in points, screenshot dimensions may be pixels, and driver coordinates may use another orientation. Do not infer a scale-and-rotate tapping workaround without checking the coordinate spaces.

The tested `simctl io` help exposed display power/geometry but no fold-pose operation. Display resizing or powering a screen is not proof of a fold. Use a supported simulator UI/tool to select the pose; if unavailable, ask the user to select it once and run the rest unattended. Check current help before concluding pose automation is unavailable.

## XCUITest selectors on the Duo

`app.tabBars.buttons["Name"]` finds no `TabBar` on the Duo under iOS 27.1, the
same as iPad since iOS 18: 27 of 33 UI-test failures in one app's run
(2026-09-18) were that single selector, with no crash. Fall back to
`app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch`
on any device where the tab bar query finds nothing (code in SKILL.md).

## Layout and lifecycle checks

A legacy AppDelegate-only app reproduced a launch crash on this beta with UIKit reporting that the SDK requires UIScene lifecycle adoption. Diagnose from the actual runtime log; do not attribute every Duo launch failure to that cause.

For a scene migration, check one owner of window/root creation, URL and universal-link delivery on cold and warm launch, auth callback interception, notification navigation, foreground work, and background-only launches. Background URLSession completion delivery must still work without a foreground scene. Test an older supported OS too; removing full-screen compatibility also warrants iPad windowing QA.

Choose layouts using usable window geometry, traits, and safe/reserved regions. The inner display is still an iPhone; an iPad-only branch can miss it. A wide layout may have a persistent sidebar and no menu button, so test navigation must accommodate both forms. Fold regions are internal occlusions, not merely edge safe-area insets.

Short height plus a software keyboard and error/help text is a particularly useful stress case. Confirm the keyboard is actually visible in the screenshot; text input success can occur with a hardware keyboard and does not establish keyboard-open layout coverage. Prefer scrolling and wrapped text to shrinking essential controls.

Apple describes system vertical navigation controls for supported standard navigation/toolbar arrangements. Custom header stacks do not automatically become those controls. Moving actions into that bar is a product/navigation change, separate from a basic compatibility pass.

## A practical matrix

Select scenarios relevant to the app rather than exhaustively combining every dimension:

- Outer display: normal content, short landscape, keyboard open with validation error.
- Inner display: wide and tall, transient sheets, list/sidebar navigation, long content.
- Live transitions: change display/pose with draft input, selection, playback, or recording active; verify content and operation continuity without relaunching.
- Partially folded: essential controls clear the reserved region and remain tappable.
- Accessibility and shared-window sizes: large text, scrolling, safe areas, camera occlusions where applicable.
- Older supported iPhone OS and iPad windows affected by scene/full-screen changes.

For recording apps, starting closed, opening/folding, entering a note, closing, saving, and playing the complete recording is a separate continuity test. Avoid equating a surviving timer or view with continuous captured audio.

## Maestro: confirmed symptom, limited diagnosis

In the tested landscape pose, Maestro detected a native notification prompt and reported its tap complete, but the prompt remained. Native XCTest dismissed it. Bounds were inconsistent; the exact cause was not established. This does not prove that Maestro targeted a different Duo display, nor that all Maestro/Duo flows fail.

Related upstream reports:

- [Issue 2065](https://github.com/mobile-dev-inc/Maestro/issues/2065): native iOS popup elements detected with unusable bounds/taps in landscape.
- [Discussion 2499](https://github.com/mobile-dev-inc/Maestro/discussions/2499): notification permission visible to assertions but Allow taps ineffective, mostly on landscape iPads.

Recheck current versions and issue status before proposing a workaround. Preserve a minimal reproduction if a new bug report is requested; do not file one merely because this skill was invoked.

## Primary references

- [Preparing your app for iPhone Duo](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)
- [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
- Installed SDK headers and `xcrun simctl io help` for the selected Xcode.

The initial design review used the user's full Apple documentation PDFs because the web reader exposed only a JavaScript shell. If that happens again, try Apple's linked Markdown or an accessible official/local copy; do not claim to have read content unavailable to the tool.
