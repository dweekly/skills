# Validating a set before upload

## Automated

```bash
python3 scripts/check_screenshots.py <framed-dir> --ipad --duo   # flags as they apply to the app
python3 scripts/check_screenshots.py --self-test                 # proves each check can fail
```

It checks exact accepted sizes, no alpha (PNG colour types 4 and 6, any
`tRNS` chunk), 1 to 10 files per folder, one class and orientation per
folder, and coverage of the required classes, and lists which classes Apple
will fill by scaling. It exits non-zero on any failure.

## Visual checklist

Look at every framed image at full size, and at the first three together at
search-result scale (about 200 px tall). Adapted in part from the screenshot
validator in [Axiom](https://github.com/CharlesWiltgen/Axiom/blob/main/docs/agents/screenshot-validator.md)
(see [further-reading.md](further-reading.md)).

| Severity | Check |
|---|---|
| Critical | No placeholder content: "Lorem ipsum", "TODO", "Test", "Sample", "John Doe", 555 numbers, example.com addresses |
| Critical | No debug artifacts: STAGING or DEBUG badges, FPS or performance overlays, console text, Xcode debug bars, the iPadOS resize mark |
| Critical | No prices, no other platforms' devices or names, no competitor brands or trademarks (Guidelines 2.3.7, 2.3.10, 5.2.1) |
| Critical | Nothing the shipped build does not do |
| High | Status bar present and clean: 9:41, full signal, Wi-Fi and battery, no "Carrier" |
| High | Settled UI: no spinners, skeletons, permission prompts, broken images, truncated text, "Untitled" or still-loading names, empty states that look like errors |
| High | Status bar legible on every screen (dark on light backgrounds) |
| Medium | Consistent across the set: one theme (light or dark), one frame style, one orientation per device |
| Medium | Captions fit their zone (the framer warns), no orphaned single words, readable at thumbnail size |
| Medium | Order: strongest benefit first; each shot makes sense alone |

Not problems: the 9:41 time, marketing captions over a gradient, a stylised
generic device frame, realistic demo content.

## Record

Write the result into the app's run record: the checker's output, who looked
at the visual checklist, and anything accepted as a known imperfection.
