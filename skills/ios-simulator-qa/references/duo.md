# Duo-specific testing notes

Observed with Xcode 27.1 beta build 27A9269 and Xcode 27.1 (27A9275), the iOS 27.1 Simulator, AXe 1.8.0 and Maestro 2.10.0. Revalidate on later releases; these are not permanent API guarantees.

## Multiple displays and pose

`xcrun simctl io "$SIM_UDID" enumerate` identifies connected screens and selectors for `screenshot --display=...`. On the 27.1 runtime `--display=1` was the outer display and `--display=3` the inner one (2853 by 2007 pixels in landscape, partially open). Discover them each time; those numbers are observations, not configuration defaults. Enumeration's power state alone did not identify the visually active display.

AXe taps reported success but never reached the outer display (AXe `type` and `describe-ui` worked); drive the outer display with XCUITest or Xcode's `device-interaction` tools.

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

### Setting the pose

The pose (closed, partially open, fully open) is set by hand in Device Hub (`/Applications/Xcode.app/Contents/Applications/DeviceHub.app`), with the buttons at the bottom of the device's window. It is not in Simulator.app's menus, and neither `simctl` nor XCTest has an API for it (Xcode 27.1). Device Hub may open showing a physical device; pick the simulator first. Display resizing or powering a screen with `simctl io` is not a fold, and `screenConfig power` on a Duo display crashed SpringBoard. So a pose is a precondition: ask the person to set it once in Device Hub, confirm it in a screenshot of every display, then run the rest unattended. A simulator reboot puts the pose back to closed (see SKILL.md, "A reboot resets more than the app"). Check current `simctl io help` and Device Hub on a new Xcode before concluding pose automation is still unavailable.

## XCUITest selectors on the Duo

`app.tabBars.buttons["Name"]` finds no `TabBar` on the Duo under iOS 27.1, the
same as iPad since iOS 18: most UI-test failures in one run were that single selector, with no crash. Fall back to
`app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch`
on any device where the tab bar query finds nothing (code in SKILL.md).

## Layout and lifecycle checks

A legacy AppDelegate-only app reproduced a launch crash on this beta with UIKit reporting that the SDK requires UIScene lifecycle adoption. Diagnose from the actual runtime log; do not attribute every Duo launch failure to that cause.

For a scene migration, check one owner of window/root creation, URL and universal-link delivery on cold and warm launch, auth callback interception, notification navigation, foreground work, and background-only launches. Background URLSession completion delivery must still work without a foreground scene. Test an older supported OS too; removing full-screen compatibility also warrants iPad windowing QA.

Choose layouts using usable window geometry, traits, and safe/reserved regions. The inner display is still an iPhone; an iPad-only branch can miss it. A wide layout may have a persistent sidebar and no menu button, so test navigation must accommodate both forms. Fold regions are internal occlusions, not merely edge safe-area insets.

Short height plus a software keyboard and error/help text is a particularly useful stress case. Confirm the keyboard is actually visible in the screenshot; text input success can occur with a hardware keyboard and does not establish keyboard-open layout coverage. Prefer scrolling and wrapped text to shrinking essential controls.

Apple describes system vertical navigation controls for supported standard navigation/toolbar arrangements. Custom header stacks do not automatically become those controls. Moving actions into that bar is a product/navigation change, separate from a basic compatibility pass.

## Apple's design guidance, as checks

Summarised from Apple's tech talk [Design for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111466/). What the talk says the system does is the expected behavior; each bullet ends with what to verify.

- **Controls live in a side column.** On the closed outer display the tab bar, toolbars, back button, status bar and Dynamic Island sit in a column on the right; in a 50/50 split, an app on the left half gets that column on its left edge. Only the inner display in portrait keeps horizontal bars. Check that no app content or control sits under the column, and that the left-half split mirrors it.
- **Two size classes, not per-pose layouts.** Apple's advice is to target compact width (outer) and regular width (inner) with layout margins and horizontal safe-area insets, and to avoid fixed widths, breakpoints and screen-specific metrics. Content aligned to the horizontal safe-area insets is offset from the column automatically. Check for clipped or off-centre content on the outer display; a fixed width or a device check is the usual cause.
- **Full-width background, inset foreground.** A full-width background or header with inset scrolling content is an accepted pattern, as long as every interactive element stays in the inset area. Immersive screens that do not scroll may centre on the full display if nothing interactive lands under the column. Check every button's frame against the column, not just the visual balance.
- **The column overflows.** App controls share the column with Live Activities and the status bar, and collapse into an overflow menu when crowded. Toolbar items too wide for the column (a text button, a segmented control) stay in the navigation bar. Check each action is still reachable, through the overflow menu if need be, with a Live Activity running.
- **Sheets.** On the outer display a sheet's controls move to the side by default, unless the sheet disables its vertical bar; on the inner display sheets keep horizontal bars in both orientations. Check each sheet in both displays.
- **The fold.** When partially folded, system components (sheets, alerts, menus, toolbar buttons and others) move out of the fold region on their own, and in portrait interactive elements move to the bottom half. Scrolling content may cross the fold. Custom controls get none of this. Check that no custom control rests in the fold when partially open; prefer system components.
- **Inner display.** The talk calls a stretched iPhone layout the thing to avoid, and offers split views, a layout that reflows into columns, or a tab bar shown as a sidebar, with the same hierarchy as the outer display. Check that opening and closing the device keeps the user at the same place in the hierarchy.
- **Never tie functionality to a pose.** An optional tabletop layout (media on top, controls on a stable base) is fine if it has the same controls and hierarchy as every other pose. Check that every action available in one pose is available in all of them.

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
- [Design for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111466/) (Apple tech talk 111466)
- Xcode's `app-resizability` skill (see SKILL.md, "Apple's skills that ship with Xcode").
- Installed SDK headers and `xcrun simctl io help` for the selected Xcode.

If Apple's web reader exposes only a JavaScript shell, try Apple's linked Markdown or an accessible official/local copy; do not claim to have read content unavailable to the tool.
