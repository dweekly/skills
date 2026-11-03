---
name: ios-dev-workflow
description: "How to run iOS and iPadOS app work end to end with an owner and several agents, so it lands fast without rework. Covers reading Apple's primary sources first (the skills and guides bundled with Xcode, SDK headers and Swift interfaces, official documentation), learning APIs hands-on with small instrumented probe apps whose results you look at, not only unit tests, setting the bar for what gets fixed before anything is dispatched, settling every visual decision in one sitting with real screenshots and a tradeoff table, labelling where evidence comes from, sizing agent jobs (one bug, about an hour, one checkpoint), sharing builds and queueing simulators, landing order and standing landing authority, conflict-prone tracker files, CI simulators that hide state-dependent tests, release-candidate gates, physical-device prerequisites, and platform behaviors measured on iOS 26 and Xcode 27. Use for any iOS or iPadOS development work: a bug fix, a feature, a fix batch, a release candidate, a QA pass, or planning one. Pair with ios-simulator-qa for the mechanics of driving simulators."
license: MIT
---

# iOS development workflow

Earned on a two-day release-candidate sprint for a shipping iPhone and iPad app in November
2026 (Xcode 27.2, iOS and iPadOS 26.5 simulators, iOS 26.7 devices): about thirty defects,
a dozen agents, one owner reachable by phone. Most lost time came from the process, not the
code. Each section below is a rule plus the failure that taught it.

For driving simulators (UDIDs, audio routing, frame-by-frame capture, XCUITest), use the
ios-simulator-qa skill. Platform behaviors measured during the sprint are in
[references/platform-findings.md](references/platform-findings.md).

## 0. Go to the source, then try it

Before designing around an API, asserting how UIKit or SwiftUI behaves, or explaining a
defect, read the primary sources on this machine, in this order. A remembered or
summarised API is the usual root of a confident wrong answer.

1. **Apple's skills that ship with Xcode.** `xcrun agent plugin path --plugin-format claude`
   writes them out and prints the directory
   (`~/Library/Developer/Xcode/CodingAssistant/ExportedPlugins/<build>/claude/`; the skills
   are its subfolders). On Xcode 27.2 (27B52) they include `swiftui-specialist`,
   `swiftui-whats-new-27`, `app-resizability`, `accessibility-dynamic-type-specialist`,
   `accessibility-sufficient-contrast-specialist`, `accessibility-voiceover-specialist`,
   `device-interaction`, `modernize-tests`, `xctrace`, `app-intents-specialist` and
   `translation`. The set changes with each Xcode build, so list the directory rather than
   trusting a name, and load the ones that match the task. String-catalog skills live
   separately in `Xcode.app/Contents/PlugIns/IDEXCStringsSupport.framework/Resources/Skills/`.
2. **Xcode's bundled guides.** Markdown that Apple ships for its coding assistant:
   `Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Resources/AdditionalDocumentation/*.md`
   (20 on Xcode 27.2: Liquid Glass for UIKit and SwiftUI, the new SwiftUI toolbar, Swift
   concurrency updates, StoreKit, WidgetKit and more). `ls` it; read the matching file whole.
3. **The SDK's headers and Swift interfaces**, the ground truth for what the SDK declares,
   its availability and Apple's doc comments:
   ```sh
   SDK=$(xcrun --sdk iphoneos --show-sdk-path)
   grep -rn "viewIsAppearing" "$SDK/System/Library/Frameworks/UIKit.framework/Headers/"
   ls "$SDK/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/"*.swiftinterface
   ```
   Objective-C frameworks: `<F>.framework/Headers/*.h`. Swift frameworks:
   `<F>.framework/Modules/<F>.swiftmodule/*.swiftinterface`. Check the SDK version the app
   actually builds with (`xcrun --sdk iphoneos --show-sdk-version`).
4. **Apple's official documentation**: `developer.apple.com/documentation/<framework>`, the
   Human Interface Guidelines, Xcode and iOS release notes, and WWDC session pages and
   transcripts. With Xcode open on the workspace, Xcode's MCP server offers a
   `DocumentationSearch` tool.
5. **Third-party SDKs**: read their source where you have it (Swift Package checkouts under
   `DerivedData/<project>/SourcePackages/checkouts/`, `Pods/`) and the vendor's docs and
   issue tracker. For binary-only SDKs, read the shipped headers and observe behavior with
   the SDK's debug logging (for Firebase, `-FIRDebugEnabled`).

Say which source a claim rests on: documented, read in a header or interface, measured
(with device, OS and build), or inferred. [references/platform-findings.md](references/platform-findings.md)
uses those labels.

### Then learn it by building

Documentation says what an API is meant to do; only running it shows what it does on this
OS, in this window, under this load. Whenever behavior matters (presentation and dismissal,
status-bar style, safe areas, Dynamic Type, keyboard, permissions, analytics callbacks),
learn it hands-on before building on it:

- **Build a small probe app or stub** that does only the thing in question: one view
  controller presenting a sheet over a popover, one SwiftUI view measured in a hosting
  controller, one permission request during a transition. Keep it out of the product repo
  (or in a clearly named scratch target) and record what it showed.
- **Instrument it end to end.** Log the callbacks in order with timestamps (`os_log` or
  `NSLog` with a tag), give every element an accessibility identifier, and drive it with
  XCUITest or a simulator driver so the same sequence reruns on demand and on the next OS.
- **Look at the result.** Capture screenshots and every-frame video across the transition
  (ios-simulator-qa covers the mechanics), open them, and judge them by eye as well as by
  measurement. A passing unit test proves the logic you wrote, not what the person sees.
- **Then write the unit test** that pins the behavior you observed, and see it fail without
  your change. Keep the UI-level check too: unit tests and test stand-ins missed what only
  the running app showed (a card drawn over the timeline after a text-size change, a status
  line jumping half a line, a sign-in screen covering a test page).
- **Promote what you learn** into the platform findings with the OS, device and build it
  was measured on.

## 1. Set the bar before dispatching anything

Ask the owner these in one message, each with a recommended answer, before the first agent
starts:

- **Who uses it, on what?** The share of users by device class (iPhone, iPad, Mac), by
  age or accessibility text size if known, and by OS version. An agent spent an afternoon
  on an 80 ms iPad-only status-bar fade before learning iPad was under 1% of users and
  cosmetic iPad issues were out of scope.
- **What is below the bar for this release?** For example: "cosmetic issues on a device
  class under N%", "anything visible for under a quarter second once per launch", "system
  UI we cannot style". Write the answer into the plan; triage every finding against it
  before dispatching a fix.
- **Which areas need the owner at landing?** Typically recording or data integrity,
  sign-in and accounts, sharing and privacy, migrations, background transfer. Everything
  else gets a standing rule (section 5).
- **What ships this release, and what is deferred by name?** Deferred items go into the
  repo's roadmap at once, not into a session log.

## 2. Settle visual decisions in one sitting

Design questions asked one at a time cost a round trip each, and the answer often reopens
the question. On the sprint one card took two rounds of stills, one status line three, and
two questions came back because the word "clock" meant nothing to the owner.

- Collect every finding that needs the owner's eye into **one decision page** before any
  fix is built: a rendered page or an image, not a wall of chat.
- For each decision show a **real screenshot of today's state**, then each option as a
  still (a mock from real screenshots is fine; label it a mock), with a small table: what
  the person sees at default text size, what they see at the largest size, consistency,
  and the cost in time and re-testing. State your recommendation and why.
- Use the words a user would: "the status bar at the top (time, Wi-Fi, battery)", not
  "glyphs", "clock", "adaptive style", "safe-area inset".
- Open images where the owner can see them (Preview, an inline file), and say exactly
  which panel to look at.
- When the owner reacts to a picture with a general complaint ("this layout is ugly"),
  record it in the roadmap in their words, say what it will and won't block, and move on.

## 3. Label where every picture comes from

A stand-in view controller in a unit test is not the app. The owner judged a card "pooping
over the artwork" from a test that skipped `viewDidLoad`, so artwork the real app hides
was still on screen; the real app never showed the overlap. A round trip was lost.

- Design review uses **live-app** screenshots, captioned with device, OS, text size,
  build SHA and account state.
- If a test's screenshots are shown, caption them "test stand-in" and fix the stand-in to
  do the screen-shaping part of the real setup, then assert the layout property (no
  overlap with bars or artwork) rather than relying on someone looking.
- Fixture-driven states (a forced error, an upload stuck at 99%) are labelled as such,
  with how they were forced.

## 4. Size agent jobs small

Multi-hour briefs covering several bugs ran long, queued behind each other for simulators,
and were fragile: one expired login stopped four agents mid-run.

- **One bug per brief, about an hour, one checkpoint.** The brief states the goal, the
  owner's decision verbatim, what is out of scope, the proof required, and when to stop
  and report instead of pushing on.
- **Do it yourself** when it is under about fifteen minutes: a docs line, a merge, a
  rebase, reading a log.
- **Before each dispatch ask whether it is worth an agent** given the bar from section 1.
  A cosmetic defect seen in one of two takes is a tracker line, not an agent.
- **Checkpoints write state to files** (a STATUS.md in the agent's evidence folder), so a
  killed agent can be resumed or its work picked up. When stopping an agent, commit its
  work-in-progress to its branch with a WIP message, push, and delete its simulators.
- **Stills before the PR** for anything visual: the agent stops at a checkpoint with a
  contact sheet, the owner looks, then the agent finishes tests, review and the PR.

## 5. Land as you go, in the right order

- **Standing landing authority.** Agree at the start: changes outside the sensitive areas
  land when CI is green and the review gate passes, without a per-PR ask. Sensitive-area
  changes come to the owner as a batch with one sentence each. Twelve green PRs waited
  hours for approval while the base moved under them.
- **Land test-infrastructure changes first.** A PR that changed how the CI simulator is
  prepared (signed out, app removed) left the shared simulator in that state, so every
  other open PR went red until it landed. Anything that changes shared test state lands
  before the fixes start, or runs on its own simulator.
- **Expect append-only files to conflict.** When every fix also adds an entry at the end
  of the bug tracker or roadmap, each landing conflicts with the next. Each re-merge
  changes the head SHA, which invalidates the review receipt and the CI result, so every
  PR pays a full re-run. Either keep tracker edits out of fix PRs and land them in one
  docs PR, or land in quick succession with a scripted "merge base, resolve append
  conflicts by keeping both, re-review, wait for CI, preflight" loop.
- **Reserve IDs** (bug numbers) centrally when several agents file at once, or tell each
  agent to check open PRs for claimed IDs. Two agents claimed the same three IDs.
- **Merge commits into the release branch** from the landed develop heads only, and check
  afterwards that the release branch's app directory equals develop's
  (`git diff --stat origin/develop <release> -- <app-dir>` prints nothing).

## 6. Share builds and queue simulators

Every agent built the app from scratch (about ten minutes and 2.5 GB of DerivedData each)
and polled the simulator count by hand.

- Build once per head: `xcodebuild build-for-testing` into one DerivedData, then each
  checker runs `test-without-building` with its own `-destination`. Rebuild only when the
  head changes.
- Hand out simulators with a lock (a directory of slot files and `mkdir`-based locking is
  enough), not by agents counting booted devices. Respect a cap of two or three booted
  simulators on a loaded Mac; timing-sensitive tests fail under load.
- Each agent names and deletes its own simulators; never touch CI's or another agent's.

## 7. Keep CI honest

- **Reused CI simulators hide state-dependent tests.** Five layout tests passed on CI for
  weeks only because the CI simulator had a signed-in user; on any fresh simulator they
  failed. Start CI's app as a new install would: uninstall it and reset the simulator's
  keychain (auth sessions live in the keychain and survive an uninstall).
- **A test that did not run is not a pass.** Check the executed count, not only the exit
  status; a shell quoting slip once ran zero tests and reported no failures.
- **When CI fails on a PR whose diff cannot explain it**, compare with the last green run
  on the same runner before blaming the PR; the cause is often shared state.

## 8. Release-candidate gates

- Cut the candidate from an exact SHA, and run every gate on that SHA: unit tests, script
  tests, a Release build, the transition and status-bar sweeps, analytics attribution,
  and a full walkthrough with screenshots the owner looks at.
- Each gate is a command that passes or fails, recorded in the build's QA record with its
  evidence path. A gate that could not run is a gap, written down as one.
- "Known issue", "pre-existing", "flaky" and "simulator problem" are never a disposition.
  Find the cause, fix it, or bring the owner a decision with the bar from section 1.
- Uploading to App Store Connect is the owner's step unless they say otherwise.

## 9. Physical devices

Before dispatching a device run, confirm with the owner (one message, all at once):

- Xcode has a signed-in account on the team, so automatic signing can register the
  device. Without it the build fails with "No Accounts" and the profile lacks the UDID.
- Developer Mode is on; Settings > Developer > Enable UI Automation is on (otherwise the
  first XCUITest run stalls on a passcode prompt); Auto-Lock is Never for the run.
- The device is unlocked on USB.
- What is already installed: if the normal app holds data that may not have reached the
  server (local recordings, queued writes), install only a separate bundle identity for
  testing, never over it.

`xcrun devicectl device capture screenshot` works; `capture screen-record` was unsupported
on iOS 26.7.2 (iPhone and iPad), so frame checks on a device come from the XCTest result's
screen recording.

## 10. Talk to the owner

- Lead with what they need to decide, in plain words, with the picture.
- Keep every pending question in one short list at the end of each update, numbered, with
  your recommendation; the owner answers by number.
- When the owner says they lack the tradeoffs, stop and lay them out (section 2) before
  doing anything else.
- Record each decision, verbatim where possible, in the repo's plan or roadmap the moment
  it is made.
