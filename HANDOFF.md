# Handoff (keep this current)

Work is driven by **todo.txt** (the user's to-do book; also editable in-game with key 9). Each line is a task.
Remove a line when it is done and commit + push straight away, so a session that picks this up (local or cloud)
never redoes or loses work.

How to continue:
1. Read CLAUDE.md, PROJECT_NOTES.md, then todo.txt.
2. Take the next task, fix it, check with `python tools/check.py` (it loads the whole Godot world headless).
3. Remove the task from todo.txt, update PROJECT_NOTES.md if something works differently, commit and push.
4. When todo.txt is empty: refine (the user asked e.g. for better-looking village roofs), one commit per change.

Currently working on (2026-10-11): the user is asleep and asked for ALL remaining usage to go into improving the game, with no
summaries / stopping. Order: (1) core code + efficiency, (2) style revamp (Blender models), (3) new features.
STANDING RULES: commit + push after every finished step; check usage (get_usage tool) every few commits; if the 5-hour OR weekly usage
is >= 98%: final commit + push, then `shutdown /s /t 30` (user's order). Never ask the user anything; decide yourself.

Done tonight: graphics presets (quality.gd, F8), small-detail culling in W.box (-28% draws), time-sliced pathfinding map,
Blender pipeline (tools/blender/, README) with painted low-poly oak/pine/rocks/bushes (-60% triangles). Batching boxes into merged
meshes was tried and is WORSE (shadow cascades draw merged meshes whole): don't redo it.
Test rig (outside the repo, in the session scratchpad): sync.sh copies the project to a scratch copy, runprof.sh profiles six spots,
shots.sh renders views from cc / cc_old (git HEAD) to compare. Blender: D:\Toolslenderlender-5.2.2-windows-x64lender.exe.

Next (roadmap, in order): Blender props to replace boxes (barrel, crate, chest, bench, table, stool, bucket, lantern, fence,
hay bale, cart, well), cottage roofs + chimneys, grass tufts/flowers/ferns/stumps/logs; water (a stream through the meadow);
sky/clouds + volumetric light; wildlife (birds, butterflies); then features: better combat feel, more quests/chapters,
journal polish, onboarding. Use `python tools/check.py` after each change; compare screenshots before/after.
