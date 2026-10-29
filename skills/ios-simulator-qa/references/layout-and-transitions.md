# Layout and transitions, checked frame by frame

Observed October 2026 on Xcode 27.1 with the iOS and iPadOS 26 and 27
simulators, while chasing a one-frame flash and a mis-coloured status bar.
Each item is what was seen; recheck on a new SDK.

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
