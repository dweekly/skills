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
