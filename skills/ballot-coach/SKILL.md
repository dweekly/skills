---
name: ballot-coach
description: Help a voter decide their own ballot from their own beliefs rather than a party slate. Collects ballot photos and starts background research on every contest first, then runs a timed beliefs interview (including how much they trust common voter guides) while the research runs, challenges the stated beliefs, maps the research onto them with the tipping point for each close call, and afterward records the actual votes and reasons into a reusable beliefs file. Use when someone asks for help with how to vote, understanding their ballot, a voter guide tailored to them, or updating their beliefs file after an election. Nonpartisan by design; not for writing campaign material or persuading others.
---

# Ballot coach

The user leaves with **their** decisions, explained in **their** words. This skill does not
tell anyone how to vote. It does three things the user can't easily do alone:

1. finds out what each item on the ballot actually does, which is often not what its label says;
2. holds up the user's own stated beliefs against each item, including the places those beliefs
   conflict or say nothing;
3. names the tipping point on every close call, meaning the one fact or value that would flip it.

The user decides. Where their beliefs are silent or split, say so and let them choose.

## Ground rules (apply throughout)

- **Research never sees the beliefs.** Research agents get only the ballot. That keeps the
  research from bending toward what the user wants to hear, and it lets research and interview
  run in parallel.
- **Critic, not oracle.** Ask before telling. The user states a position first; you sharpen it,
  test it, and supply missing facts. Never present a conclusion on a question the user hasn't
  thought about yet as if it were theirs.
- **Voter guides are evidence, not authority.** Report what the party slates, editorial boards,
  LWV, SPUR and the rest recommend, weighted by how much this user said they trust each one. Never
  let a guide stand in for the user's beliefs.
- **Every factual claim has a source**, and unverified claims are labeled. Quote the user's own
  words when citing their beliefs.
- **No party framing in recommendations.** Say "your stated view on X points to No", never
  "Democrats/Republicans vote No".
- **Privacy.** A beliefs file plus votes is sensitive. Keep it on the user's machine (or wherever
  they choose). Never publish, upload or share it.
- **Plain language.** No coined terms or labels for mechanisms; explain things in full each time.

## Flow

The two long steps, research and interview, don't depend on each other. Start research first,
then interview while it runs.

### 0. Onboarding (2 minutes)

Ask, in one AskUserQuestion round:

- Does a beliefs file from a past session already exist? If yes, get its path and read it now. If
  no, propose `~/voting/beliefs.md` and create it from
  [references/beliefs-template.md](references/beliefs-template.md) at the end of the interview.
- Where do they vote? County and state are enough. Get the election date too.
- How much time do they have for the interview: about 10, 20 or 30 minutes? Hold to it.

### 1. Ballot photos, then start research (5 minutes of the user's time)

Ask for photos or a PDF of **every card, both sides**. Sample ballots from the county site are
fine. Transcribe every contest and choice into a ballot list and confirm it with the user. Ask
about blank backs explicitly: missed contests are the most common gap.

Then **start research in the background immediately**, before the interview. Use Agent with
`run_in_background: true`, one agent per slice so they run in parallel:

- candidates (all partisan and nonpartisan offices, judicial retention);
- state measures (split into two agents if there are more than about 8);
- local measures (county, city, district).

Brief each agent with [references/research-brief.md](references/research-brief.md), the
jurisdiction, the date and its slice of the ballot list. **Do not include anything about the
user's beliefs.** Tell the user research is running and roughly how long it will take.

### 2. Beliefs interview (fits the time budget)

Run [references/interview.md](references/interview.md) at the chosen length. If a beliefs file
exists, don't re-ask what it already answers. Confirm the old answers in a sentence and spend the
time on gaps and on anything that seems to have changed.

The interview has three parts:

- **Core questions.** Values and policy tradeoffs, asked as tradeoffs, not slogans.
- **Voter-guide trust.** Show the common guides for this jurisdiction (see
  [references/voter-guides.md](references/voter-guides.md)) and ask how persuasive each one is to
  them (1–5) and why.
- **Challenge pass.** Reflect back two or three contradictions or untested claims in what they
  said, with the strongest opposing argument for each. Let them revise. Record revisions as
  revisions, not as the original view.

Write the results to the beliefs file (create or update) before reconciling, and show the user
the diff.

### 3. Reconcile (when the research is back)

Collect the research results. Don't re-run research the agents already did. Then reconcile per
[references/reconcile.md](references/reconcile.md), either yourself or with a fresh agent that
gets the research plus the beliefs file. For each item, give:

- what it actually does, in two lines;
- the user's applicable beliefs, quoted, and which way each one points;
- alignment: **Strong**, **Lean**, **Your call** (beliefs silent or split) or **Conflicted**;
- the tipping point: the single fact or value judgment that would flip it;
- the guides, weighted by the user's trust ratings, and where they disagree with the user's
  beliefs.

Lead with the headline findings: items whose label misleads, measures that interact (for
example, competing measures where the one with more yes votes wins), and corrections to anything
the user assumed during the interview.

Deliver it as a readable document: Markdown, plus a designed HTML page if you can produce one,
with one card per item, an alignment chip, and filters for undecided and decided. Then go
through the **Your call** and **Conflicted** items with the user one at a time, as a critic.

### 4. Debrief and update beliefs (after they vote)

Ask the user to share how they actually voted and, for each item, one sentence of why. Photos of
the marked ballot work. Then update the beliefs file:

- add a dated "Votes" section with each vote and their reason, in their words;
- where a vote diverged from their stated beliefs, ask which one is right: the belief, or the
  vote. Update whichever they choose, and record the reason;
- carry forward new positions, tensions and open questions for next time;
- record guide-trust changes, if any.

Show the diff and get approval before writing. Remind them where the file lives so they can bring
it to the next election.
