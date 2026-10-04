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

Next refinement: tidy the bandit camp in scene/creatures.gd (build_bandit_camp() sits over Gorrak's old build_camp()):
fewer, well placed tents, a palisade with a gate, a central fire, and orderly crates/barrels. Check all camp flag
states ("bandits", "cleared", "tolled"). After that, improve the thatch PrismMesh cottage roofs in scene/village.gd.
Test visually with `--path godot_world -- --shot=out.png` and `python tools/check.py`.
