# Roadmap

## Ideas
- **Long-range direction: a user-owned model of the person.** One portable model of a person's beliefs, values, decision style and revealed choices that domain skills read from and write back to (ballots, job search, coaching, journaling, life design), rather than sibling skills that each re-interview. Learns mainly from observed choices, not intake questionnaires. Guardrails borrowed from the policy-twin principles: advisory first, current self overrides, every action logged with its reasoning, user-owned and inspectable. Sharing means sharing the practice, not pushing conclusions. Decide product vs. published practice vs. personal tool before building.
- **Beliefs skill** (separate, linked to ballot-coach). Elicits a person's beliefs in their own words, logs tensions, challenges them adversarially (steelmanned critiques from rival traditions), and compares stated beliefs with revealed choices (votes, decisions). Owns the beliefs file; ballot-coach reads it at start and writes votes back at the end. Asks before it answers. Ballot-coach's interview and challenge pass would move into it.

## Hardening
- No evaluations yet. Anthropic's checklist asks for at least three per skill, run with and without the skill, and testing on Haiku, Sonnet and Opus.
- Not yet submitted to Anthropic's plugin directory; decide after the first outside users.
- Plugin versions are omitted on purpose, so installs track commits; add semver once a skill has outside users who need stability.
- ballot-coach has not yet been run end to end with a real user.
- voter-guides.md is California-heavy; research agents find local equivalents elsewhere, but the offered list should broaden after a non-California run.
- app-store-media preview pipeline (`preview_overlays.swift`, `preview_cut.py`, `check_preview.py`):
  - No bundled recorder. Booting the simulator, pinning the status bar, running the UI test under `simctl io recordVideo` and turning its log into marks files is described in references/preview-video.md, not scripted; a sibling app's shell script is the model for a generic `record_preview.sh`.
  - Proven end to end on synthetic sparse takes only (`scripts/test_preview_pipeline.sh`), not on a real simulator take; the defect regression is a synthetic sparse take, not a retained real one.
  - A piece's start is only as exact as the recorder-start poll (up to six frames); lengths are machine-checked, start alignment is a visual check.
  - 886x1920 portrait only in practice; iPad (1200x1600) and landscape sizes are accepted by the checker but untested, and the sibling app's Google Play landscape layout was not ported.
  - Layout is one shape (band above, footage below) with fixed text fractions plus `textScale`; captions set over the footage, and per-beat layout, are not supported.
  - Normalised takes are re-encoded on every run (no cache), and the band-default rule is restated in Swift and Python (the overlays.json comparison catches drift).
- ios-simulator-qa describes per-simulator audio routing (the CoreSimulator selectors and scope values) but bundles no tool for it; a small `simaudio <udid> get|route` script would make the reboot re-check a command. Its scope findings ('glob' setting output only) come from a few simulators on Xcode 27.1.
- app-store-media: the framer's iPhone Duo corner radius and font scale are starting values, not yet checked against real Duo captures. The uploader is described, not bundled: a generic `upload_store_media.py` (config-driven, display types looked up rather than hard-coded) would remove the copy-and-edit step. The contact-sheet builder is still per-app.
