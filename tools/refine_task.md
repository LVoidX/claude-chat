# Task: refine the project

Refine this project; do not add new features. The goal is to make what is already here as good as it can be.

Read CLAUDE.md and PROJECT_NOTES.md first: they explain the project (a Windows chat app, chat.pyw, that talks
to Claude, plus a Godot 4.7 world in godot_world/ with the characters Barnaby and Marigold), how the pieces fit
together, and the user's preferences.

Then go through chat.pyw, godot_bridge.py, godot_world/world.gd and every part in godot_world/scene/:
- fix bugs and edge cases (state that can get stuck, things that break after a live reload, errors that are
  swallowed silently, race conditions between the two conversation lanes in chat.pyw);
- remove dead or duplicated code and make the parts consistent (shared helpers in world.gd instead of copies
  in several parts; e.g. one shared speech bubble / talker for both characters);
- smooth out rough behaviour in the world: character movement and turning, the speech bubble, the hotbar and
  weapons, goblins, the sea, parkour, the HUD;
- keep comments short and accurate, matching the existing style.

Keep everything the user can do working exactly as now. Every command in barnaby_commands.txt and
marigold_commands.txt must keep working with the same name and arguments. Keep the live-reload contract of the
scene parts (build/handle/key/describe/is_near/npc_id/quest_progress) and the JSON messages between chat.pyw
and the world.

Run `python tools/check.py` after each change and fix anything it reports. For visual changes, install xvfb
and mesa drivers (`apt-get install -y xvfb mesa-vulkan-drivers libgl1-mesa-dri`), run
`python tools/check.py --shot` and look at shot.png. The Windows-only parts of chat.pyw (voice, Whisper,
mouse buttons, window focus, the claude processes) cannot be tested here: change them only for clear bugs,
and keep those changes small.

Work on a branch named `refine`. Commit in small steps with clear messages and PUSH AFTER EVERY COMMIT, so
nothing is lost if the session stops early. When done, open a pull request against main that summarizes what
you changed and why, grouped by area, and lists anything you were unsure about or could not test. Update
PROJECT_NOTES.md where you change how something works.
