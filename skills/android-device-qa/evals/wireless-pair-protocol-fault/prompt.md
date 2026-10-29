---
tags: [skill-creator]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

my pixel 7a won't pair with my macbook over wireless debugging. `adb pair 192.168.1.40:37199 123456` just says `protocol fault (couldn't read status message)`. weird thing is `nc -vz 192.168.1.40 37199` connects fine from the same terminal. `adb mdns services` also lists nothing even though the pairing dialog is open on the phone. what's going on and what exactly should I do? write up the answer in answer.md
