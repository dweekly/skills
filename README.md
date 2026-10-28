# Agent skills

Skills for Claude Code and other agents that support the [Agent Skills](https://agentskills.io) format. Each one was earned on a real project and contains checks and procedures, not generic advice.

## Install (Claude Code)

One step (Claude Code 2.1.275 or later):

```
/plugin install ballot-coach --marketplace dweekly/skills
/plugin install a2p-campaign --marketplace dweekly/skills
/plugin install ios-simulator-qa --marketplace dweekly/skills
/plugin install app-store-media --marketplace dweekly/skills
```

Or add the marketplace once, then install by name: `/plugin marketplace add dweekly/skills`, then `/plugin install ballot-coach@dweekly-skills`.

Or copy any `skills/<name>/` directory into `~/.claude/skills/`.

## Skills

- [ballot-coach](skills/ballot-coach/SKILL.md): nonpartisan voting coach. It researches every item on your actual ballot from photos while interviewing you about your beliefs, challenges those beliefs, maps the research onto them with the tipping point for each close call, and keeps a reusable beliefs file. It never tells you how to vote. (updated 2026-10-23; update when: it is run on a real ballot and the flow changes)
- [a2p-campaign](skills/a2p-campaign/SKILL.md): registering US A2P 10DLC SMS campaigns and WhatsApp senders on Twilio so they pass carrier review the first time, including rejection codes, required website disclosures and inbound webhook wiring. (updated 2026-10-23; update when: Twilio or TCR changes its review requirements)
- [ios-simulator-qa](skills/ios-simulator-qa/SKILL.md): building, driving and visually verifying iPhone and iPad apps on the Simulator, and turning a verified walkthrough into an unattended XCTest or Maestro flow. (updated 2026-10-23; update when: a new Xcode major release changes simulator behavior)
- [app-store-media](skills/app-store-media/SKILL.md): App Store screenshots from simulator captures, end to end: which sizes are required, clean capture, scripted framing with brand captions, caption layout and ordering with the evidence behind them, a contact sheet for approval, machine validation, upload and measuring the result; plus App Preview video requirements. (updated 2026-10-28; update when: Apple's screenshot specification page changes its required sizes, or a new device class appears)

## Other docs

- [Roadmap](ROADMAP.md): planned skills (a standalone beliefs skill linked to ballot-coach) and known hardening gaps. (updated 2026-10-23; update when: a planned skill ships or a gap is closed)

## License

MIT. No personal data belongs in this repo; a pre-commit check enforces that.
