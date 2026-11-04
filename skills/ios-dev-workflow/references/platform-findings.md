# Platform findings

Behaviors measured during a November 2026 release sprint. Each says where it was seen and
how it was established; "measured" means reproduced and observed, not read in Apple's
documentation. Recheck on a newer OS or Xcode before relying on one.

## Signing, keychain and sign-in

- **An unsigned simulator build cannot use the keychain.** Built with
  `CODE_SIGNING_ALLOWED=NO`, the app's keychain calls fail with -34018, so Firebase Auth
  sign-in fails (it stores its session in the keychain). Any test runner that builds
  unsigned cannot run tests that sign in. Build with ordinary simulator signing (no Apple
  account needed). Measured, Xcode 27.2, iOS 26.5 simulator.
- **The keychain survives an uninstall; UserDefaults does not.** After
  `simctl uninstall` and reinstall, a Firebase Auth user is still signed in, but every
  UserDefaults flag (for example "intro shown") is gone, so the app shows onboarding to a
  signed-in user. To start a simulator truly fresh: uninstall the app and
  `xcrun simctl keychain <udid> reset`. Measured, iOS 26.5 simulator.
- **Firebase Auth reports specific error codes** (wrong code, expired session, network,
  too many requests, quota, keychain); map them to distinct messages rather than one
  generic "code is not correct". The names exist in the Firebase iOS SDK 12.16.

## View-controller tests

- **Stand-in view controllers must stub `viewIsAppearing:`** (iOS 17+) along with
  `viewWillAppear:`, `viewDidAppear:`, `viewWillDisappear:` and `viewDidDisappear:`. A
  test that stubbed the other four let the real `viewIsAppearing:` present a sign-in
  screen on a signed-out simulator; the covered test page stopped receiving trait and
  layout updates and five layout tests failed. Measured, iOS 26.5.
- **A test stand-in that skips `viewDidLoad`** keeps storyboard placeholder content and
  misses runtime layout (bars, headers). Do the screen-shaping part of `viewDidLoad` in
  the stand-in, or don't show its screenshots as the app.

## Status bar

See also ios-simulator-qa's layout-and-transitions reference.

- **iPadOS animates the first adaptive status-bar change in a process.** The glyphs fade
  over about 5 frames (about 80 ms) from the previous colour; later switches into the same
  style are instant. In-app attempts to avoid it (adaptive from launch, delaying, a dark
  Info.plist default, hiding the bar while the system picks) did not remove it or made it
  worse. Measured, iPadOS 26.5 simulator, three cold launches.
- **System sheets draw their own status bar.** iOS 26's "How do you want to share
  contacts?" sheet draws black glyphs whatever the app's style; the first style change the
  app makes while the sheet is up turns that bar white and nothing restores it. The app
  cannot distinguish that sheet from the permission alert before it (both just make the
  app inactive). Measured, iOS 26.2 and 26.5 simulators, iPhone and iPad.
- **UIKit can ask `presentationControllerShouldDismiss:` without dismissing.** A tap that
  passed through a popover-style tip to a header button triggered the delegate call, but
  the tip stayed up; clearing "the active popover" there made the next presentation fail
  ("already presenting"), while status-bar code had already switched style for it. Clear
  presentation state in `presentationControllerDidDismiss:`, and ignore presentations UIKit
  refused. Measured, iPadOS 26.5.

## Windows and safe area (iPad)

- **Compact window back to full screen can leave stale safe-area insets.** On the first
  compact-to-full change after a simulator boot, the app received the compact window's
  insets ({10,0,10,0} instead of {32,0,20,0}), shifting the header into the status bar
  until the next rotation; Apple's Settings app shifted the same way. Later changes did not
  reproduce it (0 of 7). Measured, iPadOS 26.5 simulator; not checked on a device.

## Analytics

- **Firebase Analytics' automatic screen reporting logs every on-screen view controller**,
  including `UIAlertController` and SwiftUI's alert host, and logs the page underneath
  again when an alert closes. There is no per-screen opt-out; removing those entries means
  turning automatic reporting off and logging screens yourself. Read in
  GoogleAppMeasurement 12.16's screen-class rule and observed with `-FIRDebugEnabled`.
- **Your own screen tracker can double-log** when a stack unwinds and a presenter that was
  released is treated as "no presenter", or when a full-screen presentation makes the page
  underneath reappear. Log a screen only if it is still frontmost after a dismissal
  settles.

## SwiftUI hosting

- **An `@Observable` model read while measuring a hosting view can lag.** A card measured
  synchronously after its data changed read SwiftUI's previous (empty) state and sized to
  0 pt. Pass the data to the view directly when you measure it in the same run-loop turn.
  Measured, iOS 26.5.

## Text input in SwiftUI

- **`onChange(of:)` is not a reliable place to act on text-field input.** On a code field bound
  to `@State`, SwiftUI sometimes did not call `onChange` for the keystroke that completed a
  six-digit code, although the field and the state both held all six digits; the next
  keystroke delivered it late. Seen 2 of 13 entries with probe logging, iOS 26.5 simulator,
  typing through AXe. Act in the field's binding setter (`Binding(get:set:)`), which sees every
  edit, and keep `onChange` for display clean-up only. Measured.
- **Writing the state directly bypasses that setter.** An alert that cleared the field with
  `code = ""` left the "already submitted" marker set, so a pasted replacement did nothing.
  Reset derived state wherever the value is written directly, and test a whole-value
  replacement (paste, AutoFill), not only typing. Found by review, confirmed with a paste take
  (`xcrun simctl pbcopy` then Cmd-V via `axe key-combo --modifiers 227 --key 25`).

## Labels

- **A one-line `UILabel` is centred vertically in a taller frame.** A status label whose
  frame reserved two lines (for its longest wording) jumped 31 pt when the text changed to
  one line. Pin the text to an edge and reserve space separately.

## Devices and drivers

- `xcrun devicectl device capture screenshot` works on iOS 26.7.2; `capture
  screen-record` reports "Screen Recording is not supported by this device" (iPhone 15 Pro
  Max, iPad Pro M4). Use the XCTest result's screen recording for frame checks.
- XCUITest on a device stalls on "Enter iPhone Passcode for XCTest: Enable UI Automation"
  until Settings > Developer > Enable UI Automation is on.
- AXe's default simulator-style taps were dropped intermittently on iOS 26.5;
  `--tap-style physical` worked every time.
