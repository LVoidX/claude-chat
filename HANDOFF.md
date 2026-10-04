# Handoff (keep this current)

Work is driven by **todo.txt** (the user's to-do book; also editable in-game with key 9). Each line is a task.
Remove a line when it is done and commit + push straight away, so a session that picks this up (local or cloud)
never redoes or loses work.

How to continue:
1. Read CLAUDE.md, PROJECT_NOTES.md, then todo.txt.
2. Take the next task, fix it, check with `python tools/check.py` (it loads the whole Godot world headless).
3. Remove the task from todo.txt, update PROJECT_NOTES.md if something works differently, commit and push.
4. When todo.txt is empty: refine (the user asked e.g. for better-looking village roofs), one commit per change.

Currently working on (2026-10-05): all nine lines in todo.txt are complete and removed. See PROJECT_NOTES.md and the
local commits for sword audio/grip, chests, player model, ore mining, hammer removal, trees, chapter reset, and smith
voice interaction. The active, ignored story/chapter.json remains the user's current chapter unless they use the new
reset button. These changes have not been pushed; the previous push was rejected by automatic review.

The bandit camp and cottage roof refinements are complete; see PROJECT_NOTES.md. Keep refining when a new request or a
clear issue comes up. Use `python tools/check.py` after each change.
