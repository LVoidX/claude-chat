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

Done tonight (2026-10-11): graphics presets (quality.gd, F8); small-detail culling in W.box (-28% draws); time-sliced pathfinding map;
Blender pipeline (tools/blender/, README) -> painted low-poly oak/pine/rocks/bushes (-60% triangles), thatched cottage roofs,
grass tufts + wildflowers, props (barrel, crate, hay_bale, bucket, sack, stool; W.prop), reeds, bird/butterfly/duck;
a winding stream + pond with animated water (terrain.gd); wildlife.gd. Batching boxes into merged meshes was tried and is WORSE
(shadow cascades draw merged meshes whole): don't redo it. Lessons: glTF vertex colours are sRGB (hex_rgb); call faces.index_update()
before painting (paint() does); bmesh refuses duplicate faces; use the Write tool + python file for big patches (heredocs with
triple quotes broke the shell once).
Test rig (session scratchpad, NOT in the repo; recreate if missing): sync.sh copies the project to a scratch copy, cam.gd = zz_test part that
puts the player at state["test_cam"]=[x,y,z,yaw,pitch], shots.sh renders views (--shot), runprof.sh profiles six spots, side.py compares.
Blender: D:\Toolslenderlender-5.2.2-windows-x64lender.exe.

Also done: clouds (base.gd CLOUD_SHADER dome + noise texture; value-noise from sin hashes looked faceted, use noise textures),
stream + pond water, wildlife (birds/butterflies/ducks), Blender reeds. Profile after all that: 3.3 ms worst spot (4070 Super), fine.

Also done since: lampposts + fences (Blender), volumetric light shafts (quality presets). STYLE PHASE IS DONE ENOUGH: switch to FEATURES.
Next (roadmap, in order): more Blender props to replace remaining boxes (signpost, well, cart, furniture: bed,
table, bench, chest, shelf, anvil; castle banners), chimneys/windows/doors for cottages, stone bridge over the stream, sheep/chicken
models; then features (START HERE): combat feel (hit-stop, enemy reactions), journal polish, onboarding
tutorial, new chapters' content, fishing in the pond (new!), ambient sounds (generated, quiet: user disliked wind/rain hiss).
Keep committing after each step; check usage every few commits (>=98% on 5-hour OR weekly -> final push, then `shutdown /s /t 30`).
