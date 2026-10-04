# Handoff (keep this current)

Work is driven by **todo.txt** (the user's to-do book; also editable in-game with key 9). Each line is a task.
Remove a line when it is done and commit + push straight away, so a session that picks this up (local or cloud)
never redoes or loses work.

How to continue:
1. Read CLAUDE.md, PROJECT_NOTES.md, then todo.txt.
2. Take the next task, fix it, check with `python tools/check.py` (it loads the whole Godot world headless).
3. Remove the task from todo.txt, update PROJECT_NOTES.md if something works differently, commit and push.
4. When todo.txt is empty: refine (the user asked e.g. for better-looking village roofs), one commit per change.

Currently working on (2026-10-05): all six lines in todo.txt are done and removed. The latest fixes are recorded in
PROJECT_NOTES.md. The active, ignored story/chapter.json was clarified locally for the current Highmoor quest.

The bandit camp and cottage roof refinements are complete; see PROJECT_NOTES.md. All three camp states were loaded
in scratch copies, and a rendered village screenshot was inspected. Keep refining when a new request or a clear issue
comes up. Use `python tools/check.py` after each change.
