# Layout and transitions, checked frame by frame

The first four sections were observed October 2026 on Xcode 27.1 with the
iOS and iPadOS 26 and 27 simulators, while chasing a one-frame flash and a
mis-coloured status bar. Each item is what was seen; recheck on a new SDK.
The last section summarises Apple's account of resizing on iOS 27.

## Measure short events on every frame

- A 30 fps resample skipped the failing frames of a 33 ms flash. For
  anything shorter than a few frames, record with `simctl io <udid>
  recordVideo` and extract every recorded frame without resampling:
  `ffmpeg -i take.mov -fps_mode passthrough frames/%05d.png`.
- To prove a screen never appears (a placeholder, sample text, the wrong
  screen), OCR every extracted frame and search the text, rather than
  looking at a few frames by eye.
- Check the settled screen and the transition separately: a correct final
  frame says nothing about the frames before it.

## Status bar glyph colour

- On iOS 17 and later, `UIStatusBarStyleDefault` is adaptive: the glyph
  colour is chosen from the content under the bar and changed about 0.1 s
  after a new screen arrived.
- With view-controller-based status bar appearance, the glyphs faded through
  grey during a slide transition.
- A push slide puts the bar over two backgrounds at once, so no single glyph
  colour is legible on both for the whole slide. A cross-fade transition
  avoided the problem.
- An `animated:NO` push wrapped in a `CATransition` ran `viewDidAppear` before
  the first frame was drawn, so anything shown only until `viewDidAppear`
  (a cover view, a placeholder) never rendered.

## iPad window controls (iPadOS 26)

The window controls in the top-left corner of a resizable window overlap
content that ignores them. Apple's guidance is the `app-resizability` skill
that ships with Xcode 27.1 (its safe-area reference, "Corner intrusions");
see SKILL.md for how to find it.

- SwiftUI: inside a `ScrollView` the container corner insets read zero
  (outside it they were 66 by 43 pt). Apply
  `.containerCornerOffset(.top, sizeToFit: true)` to the scroll view, not to
  the button inside it.
- UIKit: measure the corner-adapted safe-area region
  (`layoutGuide(for: .safeArea(cornerAdaptation: .horizontal))` or
  `directionalEdgeInsets(for:)`) across the control's own row, not the whole
  superview. Measuring the superview shifted iPhone layouts near the rounded
  display corner.

## Compact-window tests on iPad

The window resize gesture shrank the window on the iPad Pro 13-inch
simulator, but on one iPad Air 13-inch simulator the window stayed 1024 pt
wide. Before trusting a compact-width result on iPad, read the window width
from the hierarchy or a screenshot; if it did not shrink, use another iPad
model.

## Resizable iPhone apps (iOS 27)

From Apple's [What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2026/269/) (WWDC26 session 269), the parts a layout pass should check. What the session says is Apple's account, not something this skill has measured.

- **iPhone apps resize on iOS 27**, so an iPhone app now meets widths other than its device's: iPhone Mirroring, an iPhone app running on iPad, and the Duo's displays. Test more than the native screen sizes. Xcode 27's Live Previews have resize handles for a fast first look; they do not replace a simulator run.
- **Mixed UIKit and SwiftUI apps** need checking for screen geometry read from the screen instead of the window or scene, sizing by idiom instead of size class, and missed interface-orientation changes. Xcode's `app-resizability` skill has a reference for each (`uiscreen-task.md`, `idiom-task.md`, `orientation-task.md`); the session also points to "Modernize your UIKit app".
- **Inactive iPad windows dim** their icons and text. A custom control that ignores the `appearsActive` environment value stays bright; check by putting the app next to another one and making the other active.
- **Toolbars shed items as the window narrows**, and on iPhone even Undo, Redo and Share ended up in the overflow menu in Apple's demo. Apps can rank items (`visibilityPriority`), force some into overflow (`ToolbarOverflowMenu`) or pin one (`topBarPinnedTrailing`). At the narrowest width, check that every important action is either visible or in the overflow menu. `toolbarMinimizeBehavior(.onScrollDown)` hides the navigation bar while scrolling; check its actions come back.
- **Behavior that changed under unchanged code.** `AsyncImage` now honours HTTP caching by default, so an image may come back from the cache instead of the network when scrolled back into view. A class stored in `@State` is now created once rather than on every parent update (Apple says this reaches back to iOS 17), so side effects in its initialiser run less often than before. When a build from Xcode 27 behaves differently from an older one, check these before suspecting the app's own change.
