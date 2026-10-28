# Other public tools and skills worth studying

Noted 2026-10-28 for future research. None is a dependency of this skill.

- [adamlyttleapps/claude-skill-aso-appstore-screenshots](https://github.com/adamlyttleapps/claude-skill-aso-appstore-screenshots)
  (MIT): a Claude Code skill that reads the codebase to find three to five
  core benefits, rates the user's simulator screenshots and pairs each with a
  benefit, builds a deterministic scaffold (`compose.py`: caption, device frame,
  screenshot) and then has an image model add a photorealistic frame and
  "breakout" elements; `showcase.py` makes a side-by-side preview. Worth
  borrowing: the benefit-discovery pass and screenshot rating before captions
  are written. Different here: an image model in the loop (nondeterministic,
  and it can invent UI), a pre-rendered Apple device frame, and a default
  1290x2796 output only.
- [Axiom screenshot-validator](https://github.com/CharlesWiltgen/Axiom/blob/main/docs/agents/screenshot-validator.md)
  (no licence shown on the page): an agent that audits a screenshot set for
  exact sizes, placeholder content, debug artifacts, competitor and
  other-platform content, status bar and price problems, UI completeness,
  consistency, and device-class coverage including 6.3" and iPhone Duo, with
  CRITICAL/HIGH/MEDIUM severities. [validation.md](validation.md) adapts its
  checklist; the size and coverage checks are automated in `check_screenshots.py`.
- [hypersocialinc/shots](https://github.com/hypersocialinc/shots) (licence not
  stated on the page): an agent skill that researches the app (App Store page,
  repository, competitors) into a saved strategy brief, writes problem-first
  benefit headlines ranked for install intent, then has an image model generate
  wide panoramic composites cut into three panels (iPhone 1284x2778, iPad
  2048x2732, Android 1080x1920), about $0.50 per run. Worth borrowing: the
  saved brief reused across revisions and translations. Different here:
  generated imagery rather than real captures, and panels that depend on their neighbours.

Open questions to test with these in hand: whether a benefit-ranking pass
changes which screen leads; whether alternating captions or panoramas move
conversion in a Product Page Optimization test.
