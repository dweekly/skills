---
type: llm
focus: trace
weight: 1
---

capture.sh records each device's font_scale before changing it and restores that recorded value afterwards (a fixed 1.0 fails when the device started elsewhere), and stops only the emulators it started (by serial or recorded PID), with no broad pkill or kill-all.
