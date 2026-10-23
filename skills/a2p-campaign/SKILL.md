---
name: a2p-campaign
description: Gives a playbook for registering US A2P 10DLC SMS campaigns (Twilio/TCR) and WhatsApp senders that pass carrier review on the first try. Use when setting up texting for a new project or number (e.g. "register a campaign", "light up SMS", "10DLC", "campaign rejected", "WhatsApp sender", "WABA"), or when diagnosing a TCR rejection. Distilled from a real campaign that was approved after two rejections.
license: MIT
---

# A2P 10DLC Campaign & WhatsApp Sender Playbook

Everything below was learned the hard way getting a real campaign approved
(2 rejections → approved) and its WhatsApp senders unblocked. Follow this and a
new campaign should pass on the first submission.

## Structure (who registers what)

- **Brand** = the legal entity (one-time). Register your LLC (legal name, EIN and address exactly as on IRS
  records) as a **Standard / Low Volume Standard** brand — never Sole Proprietor (1 campaign / 1 number / 1 MPS
  cap). Brand registers once per Twilio account; enable brand sharing with
  subaccounts. Legal name must match IRS records exactly. Brand website should
  be the *project's* site (the thing reviewers verify), not a holding page.
- **Campaign** = the messaging use case ($15 one-time vetting + monthly fee;
  each resubmission after rejection costs another $15). "Low Volume Mixed"
  ($1.50/mo) suits conversational/informational services under 6,000
  segments/day. One campaign can hold up to 49 numbers — register all numbers on
  one campaign; numbers pre-associated to the campaign's Messaging Service
  auto-register on approval.
- Timeline observed: brand approval ~1 minute (automated EIN match); campaign
  review ran ~5 business days per attempt (Twilio banner says up to 2–3 weeks).

## The reviewer verifies EVERYTHING against the live website

This is the #1 rejection source. Before submitting, the brand's website MUST
publicly show, at the exact URLs cited in the registration:

1. **The phone number(s)** with the call-to-action ("Call or text ...").
2. **Consent language at the point of the CTA**, containing verbatim:
   - "Message and data rates may apply" — **exact words; "Msg & data rates" was
     rejected**; never the word "standard" (implies premium messaging).
   - Message frequency (e.g. "Message frequency varies").
   - "Reply STOP to opt out, HELP for help".
   - Consent statement ("By texting you agree to receive ...").
3. **Brand attribution** connecting the site to the registered legal entity
   (e.g. site footer: "a project of <Your Company LLC>").
4. **Privacy policy page** that discloses data collected/used and contains BOTH:
   - "No mobile information will be shared with third parties or affiliates for
     marketing or promotional purposes." (CTIA)
   - "All the above categories exclude text messaging originator opt-in data
     and consent; this information will not be shared with any third parties."
5. **Terms page** with: program name, description, verbatim rates line, message
   frequency, support contact, **HELP and STOP instructions in bold**, link to
   privacy policy, and "Carriers are not liable for **any** delayed or
   undelivered messages" (include the word "any").
6. Host a **screenshot of the CTA** at a stable public URL and cite it in the
   message_flow as proof (required for text-initiated opt-in).

## Registration field rules

- **Description**: answer who sends / who receives / why. Lead with the legal
  entity and tie it to the site: "<Your Company LLC> operates <site>, ...".
  English only. No PII. If replies can be non-English, say so here.
- **message_flow ("How do end-users consent?")**: name the exact URL where the
  number + disclosures appear, quote the CTA text word-for-word, include the
  proof-screenshot URL, then explain the consent model (for conversational
  services: "texting a question constitutes the opt-in; every message is a
  direct reply; no marketing or recurring messages").
- **Sample messages** (2–5): English ONLY (error 30910 fires on non-English
  samples even with inline translations — mention bilingual replies in the
  description instead). Use [bracketed] variables for dynamic content, start
  each with the brand/service name, include the verbatim rates line in at least
  one and STOP language in all. Links must be on the brand's own domain.
- **Content flags**: declare embedded links / phone numbers honestly.
- **Opt-in keywords/message**: leave BLANK for conversational (response-only)
  services — keyword opt-in + confirmation messages are for *recurring*
  campaigns; inventing one contradicts a response-only description.
- The final "I agree" checkbox gates the submit button (easy to miss).

## Rejection codes seen

- **30909** — CTA verification failed: reviewer couldn't verify the opt-in on a
  public URL, or disclosures missing/incomplete at point of number collection.
- **30910** — invalid sample content: non-English samples, missing brand/STOP,
  or wrong rates wording.
- Rejections show per-field red flags on the campaign page (Console →
  Messaging → Regulatory Compliance → Campaigns). Fix Campaign → edit → agree →
  Update resubmits. Read https://www.twilio.com/docs/api/errors/309XX for the
  specific code before editing.
- Reference: Twilio "A2P 10DLC Campaign Onboarding Guide"
  (help.twilio.com article 11847054539547) — re-read it before each submission;
  the requirements are literal.

## WhatsApp senders (after/parallel to SMS)

- Senders register in the Twilio account that OWNS the number (Console →
  Messaging → Senders → WhatsApp senders → New). Don't move numbers to a
  subaccount for this — moving detaches the A2P campaign and any voice
  trunk/webhook configuration.
- **One WABA binding per Twilio account**: if any WhatsApp Business Account
  was ever connected (even a dead experiment), the wizard forces it. Deleting
  the old sender does NOT release the binding — a Twilio support ticket
  ("please disconnect WABA <id> from account <SID>") does, ~1-day turnaround.
  After the first new sender registers, the account binds to that WABA and
  every later sender must join it (which is what you want).

The registration flow, per number (verified end to end, mid-2026):

1. Wizard: New Sender → pick the Twilio number → Continue → step 2 stages the
   number and shows "Continue with Facebook". Keep the Twilio window open the
   whole time — the SMS verification code auto-fills back into it.
2. Meta popup, "Enter business information for new assets" screen:
   **Name = the LEGAL entity** (must match what business verification will
   approve, e.g. "<Your Company>") — NOT the brand. **Website = the
   BRAND's site** (e.g. the project domain): Meta's display-name review
   uses it to justify a brand display name that differs from the legal name,
   via the site's footer attribution. Category: pick honestly
   ("Media/News Company" for an info service). Timezone: local.
3. Select/create the WABA under the **legal-entity business portfolio**. For
   the FIRST number let it create a new WABA; for every subsequent number
   select the SAME WABA (one WABA holds many numbers).
4. **Display name is per-number** and set on a later screen — this is where
   the brand goes (e.g. "<Brand>", "<Brand> (<language>)" for a second-language
   line). Verify via SMS; the code auto-fills in Twilio.
5. Sender shows **Online immediately** in limited mode. Full messaging limits
   and final display-name approval land after Meta **business verification**
   on the portfolio (EIN letter upload in Security Center — the long pole,
   days–2 weeks; start it first).
6. Platform hookup last: in Synthflow, each chat agent's Deploy panel has a
   per-agent WhatsApp toggle that appears once the sender exists. Then wire
   the Twilio-side webhooks (next section) — the toggle alone is not enough.

## Inbound message routing (the platform does NOT wire this)

Synthflow provisions Twilio VOICE automatically (elastic SIP trunk) when a
number is attached in its UI, but never touches Twilio's *messaging* webhooks.
Until you set them by hand, inbound texts get Twilio's default "Configure your
number's SMS URL" auto-reply — even though the campaign is approved and the
chat agent shows deployed. Verified on a production deployment, mid-2026:

- **SMS** — configure once at the **Messaging Service** level (Console →
  Messaging → Services → *the A2P campaign's service* (its SID starts with `MG`) → Integration): set Incoming Messages =
  "Send a webhook", Request URL =
  `https://chat.synthflow.ai/webhooks/twilio/inbound` (HTTP POST), Delivery
  Status Callback = `https://chat.synthflow.ai/webhooks/twilio/status`.
  Service-level webhooks override number-level config and cover every number
  on the service.
- **WhatsApp** — configure **per sender** (WhatsApp senders → sender detail →
  Messaging Endpoint Configuration): the same two URLs go in "Webhook URL for
  incoming messages" and "Status callback URL". Leave the "Messaging service"
  selector empty — attaching a Service makes its webhooks take priority over
  the sender's.
  - Gotcha: the sender form won't save without **"Profile about"** (the
    139-char WhatsApp profile tagline) — it's the one required field on the
    page; Update just flags it red and does nothing. Localize it per line
    (a localized tagline on each language's number).
- Synthflow's URLs above are the Global cluster; regional clusters use
  different hosts (see their "Launch Chat Agents" doc).
- Test every channel end-to-end after wiring — a working voice line proves
  nothing about SMS, and working SMS proves nothing about WhatsApp.

## Post-approval checklist

- Confirm numbers show the campaign's Messaging Service in Console.
- Wire an autoresponder/agent BEFORE publicizing texting — an approved campaign
  with no inbound handler means users text into a void.
- Keep the CTA/terms/privacy pages stable: reviewers re-check on audits, and
  the pages are cited in the registration.
