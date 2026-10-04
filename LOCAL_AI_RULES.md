# Rules for the local AI helper (Aider + a model on this PC)

You make SMALL, clearly described changes to this project: a Python/tkinter chat app (chat.pyw) and a Godot 4.7
game (godot_world/). Bigger features are done by Claude; keep to the task you are given.

- The game's parts are GDScript files in godot_world/scene/, one per thing (village.gd = the village, castle.gd =
  the castle, villagers.gd = the people, rpg.gd = levels/inventory/quests, ...). They reload live when saved.
- GDScript 4: tabs for indentation; `var x := ...` needs a typed value: when the value comes from `W.box(...)` or
  another untyped call, write `var x: MeshInstance3D = W.box(...)` instead.
- W is the world (world.gd): W.box(parent, position, size, Color) makes a box, W.glow(...) a glowing one,
  W.light(...) a light, W.ground_y(x, z) the ground height. Colours like Color("#7a5a3a").
- Change only what was asked. Keep the style: short comments that say why.
- After editing a file in godot_world/, the user checks claude-world.log (next to chat.pyw) for errors.
