# Handoff (keep this current)

Work is driven by **todo.txt** (the user's to-do book; also editable in-game with key 9). Each line is a task.
Remove a line when it is done and commit + push straight away, so a session that picks this up (local or cloud)
never redoes or loses work.

How to continue:
1. Read CLAUDE.md, PROJECT_NOTES.md, then todo.txt.
2. Take the next task, fix it, check with `python tools/check.py` (it loads the whole Godot world headless).
3. Remove the task from todo.txt, update PROJECT_NOTES.md if something works differently, commit and push.
4. When todo.txt is empty: refine (the user asked e.g. for better-looking village roofs), one commit per change.

Currently working on (2026-10-04): the to-do book has two items left.
- (Sword revamp: done.)
  the swing; the blade colour follows the equipped weapon in rpg.gd). The user still doesn't like it: give it a better
  shape (tapered blade, fuller, proper crossguard and grip, pommel), maybe hold it lower and angled, and a weightier swing.
- Bandit camp looks messy: scene/creatures.gd build_bandit_camp() (and build_camp() under it, Gorrak's old camp, which it
  sits on). Tidy it: fewer, well placed tents, a proper palisade with a gate, a central fire, crates/barrels in order.
  Check every state of the "camp" flag ("bandits", "cleared", "tolled").
Then refine: the user asked e.g. for better-looking cottage roofs (scene/village.gd cottage(): the thatch PrismMesh).
Test visually: run Godot with `--path godot_world -- --shot=out.png` (the scratch copy trick: copy the project, set the
player in world_state.json, render) and look at the screenshot; always `python tools/check.py`.
