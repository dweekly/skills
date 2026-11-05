---
tags: [skill-creator]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

I'm doing an accessibility review of my kids' math app (package com.example.mathgame, launcher activity .MainActivity) and need screenshots of its home screen at 100%, 130% and 200% system text size, in both portrait and landscape, on three phone emulators at once. All three can be the same AVD, "QA_Phone". Write me a bash script, capture.sh, that boots them, installs app-debug.apk, takes every screenshot into shots/<emulator>/<scale>-<orientation>.png, and cleans up after itself. I'll run it on my Mac later, so don't run it, just write it. Explain anything non-obvious in comments.
