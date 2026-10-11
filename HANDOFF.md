# Handoff (keep this current)

Work is driven by **todo.txt** (the user's to-do book; also editable in-game with key 9). Each line is a task.
Remove a line when it is done and commit + push straight away, so a session that picks this up (local or cloud)
never redoes or loses work.

How to continue:
1. Read CLAUDE.md, PROJECT_NOTES.md, then todo.txt.
2. Take the next task, fix it, check with `python tools/check.py` (it loads the whole Godot world headless).
3. Remove the task from todo.txt, update PROJECT_NOTES.md if something works differently, commit and push.
4. When todo.txt is empty: refine (the user asked e.g. for better-looking village roofs), one commit per change.

Currently working on (2026-10-05): the user asked for a broad game revamp. The chosen direction is a grounded,
voice-led medieval story adventure; see PROJECT_NOTES.md. First-pass work tightens first-person feel, readability,
weather and the new-game hub while preserving the user's current save. Continue by improving the chapter/quest loop,
world art consistency, and in-game onboarding. The older todo.txt items are all complete and removed. These changes
have not been pushed; the previous push was rejected by automatic review.

The bandit camp and cottage roof refinements are complete; see PROJECT_NOTES.md. The latest visual pass adds close-up
detail to villagers, animals, hostile models, the cart and barrels, and improves the first-person glove/forearm and
sword facets. It also clears grass from the village paths. Keep bringing the remaining world props and landmarks up to
the Barnaby model's layered detail standard. Use `python tools/check.py` after each change.
