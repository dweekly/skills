---
type: llm
focus: trace
weight: 1
---

Every adb call inside a while-read loop in capture.sh is protected from consuming the loop's stdin (</dev/null or adb shell -n), or the script has no while-read loop around adb calls.
