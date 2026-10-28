# What makes a screenshot set work

This file separates what is known from what is commonly said. Most ASO advice
online comes from vendors selling screenshot tools, and their numbers are
unverified. Where a claim has no independent evidence it says so.

## Ordering

- **Lead with the strongest benefit.** App Store search results show the first
  three screenshots beside the icon (portrait apps), and most people never
  swipe further. Apple's own guidance is to lead with your best features.
- Show the core action first (the thing the app exists to do), then its payoff,
  then the view that organises the user's history.
- Each shot must make sense alone. Someone may only ever see one.

## Captions

- **A short headline that adds to the picture rather than describing it**
  (Apple: "a short phrase that enhances the visual"). Two short lines at most
  on iPhone; a smaller sub-headline can carry the specific.
- Lead with the benefit to the user, not the feature name. "Hear it again. Read
  every word." rather than "Transcripts".
- Readable at thumbnail size: the headline is the only text most people will read.
- Write for the actual audience. For an older audience: plain words, no jargon,
  no clever wordplay, high contrast (white on a dark brand colour, about 6:1).
- No prices (Guideline 2.3.7), no seasonal references, no superlatives the
  app cannot back up, no claims the shipped build does not support.

## Caption placement: fixed versus alternating

- **There is no independent study comparing them.** A search in October 2026
  found only vendor blogs, which consistently recommend *one* caption
  placement, type style and palette across the set so it reads as one system.
- Alternating (above, below, above) is a common stylistic choice that some
  top apps use to create rhythm. It is not shown to convert better.
- Fixed placement keeps the three search-result shots aligned and matches the
  reading order people expect (headline, then picture).
- **Decide with data, not taste:** App Store Connect's **Product Page
  Optimization** runs up to three treatments against the default page with real
  traffic and reports conversion for each. Ship the safer default and test the
  alternative. The framer renders both layouts from the same config
  (`--captions top|alternate`), so a treatment costs nothing to produce.
- When alternating, flip the gradient so text always sits on the darker
  colour, and fit the device whole in every shot; a device that hangs off the
  top edge hides the app's header and status bar.

## Panoramas

A background or device that continues across adjacent screenshots looks
polished in the browse view, but each panel must still stand alone, and a
seam that cuts through text looks broken. Worth it only when the story is
genuinely sequential.

## Device frame

A drawn, generic bezel is safe and keeps the pipeline scriptable. Apple's own
product bezels are licence-clean but come with strict rules (no added
shadows, no cropping, latest device only). Third-party device renderings
(fastlane frameit's set) depict Apple products, which Apple's marketing
guidelines discourage. Detail in [framing.md](framing.md).

## Header and search-results creative assets

Learned from App Store Connect's Device Preview (Header and Search Results >
Preview), October 2026:

- **A search-results card replaces the three screenshots** in search with one
  3:2 image shown whole (not cropped to the safe area). Use one only if it
  beats the first three screenshots, which already carry three benefits at a
  readable size. Empty margin around safe-area-only content shows as dead space.
- **The header crops differently per device.** iPhone: above the app name and
  Get button (no overlap), about the centre half of the width, full height.
  iPad: full width, cut off a little below the safe area, with the store's tab
  bar over the top. Put the whole message inside the safe area and let
  supporting art run below it.
- **Size for a phone.** A one-line headline across the safe area read at about
  11 pt on an iPhone; two lines filling the safe area's height roughly doubled
  it. Check the preview on iPhone and iPad before submitting.

## Measuring after release

- **Do not read the weekly App Analytics email's conversion figure as a listing
  verdict.** It is downloads divided by impressions, and organic search
  impressions spike by 10 times or more on some days (an app surfacing for a
  broad or trending query) without bringing downloads. One medical app saw
  search impressions swing between about 100 and 2,000 a day over a month while
  first-time downloads from search stayed at 10 to 30 a day.
- Track **first-time downloads per week by source** (App Store Search, App
  Store Browse, Web Referrer, App Referrer) and **product-page views to
  downloads**. App Store Connect > Analytics > Acquisition > Sources.
- Separate paid from organic: Apple Ads reports in UTC and counts redownloads
  and view-through installs; App Analytics "App Units" counts first-time
  downloads only. Compare the same dates and the same definitions.
- Record the week before a new set goes live as the baseline, in the app's repo.
