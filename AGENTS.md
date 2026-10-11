# Codex Chat + Godot world

A Windows desktop app: a black chat window (chat.pyw, Python/tkinter) that talks to Codex through
`Codex -p`, plus a 3D world (Godot 4.7, godot_world/) where the user walks around and talks to characters
(Barnaby, Marigold) by voice. Read PROJECT_NOTES.md first: it describes how everything fits together, the
user's preferences, and the history.

## What runs where
- chat.pyw: Windows only (ctypes for mouse buttons / Tab / focus, tkinter window, PowerShell voices,
  Whisper speech recognition on the user's NVIDIA GPU). It runs `Codex -p` processes for the assistant,
  the characters (Haiku) and the "builder" (Sonnet), and starts the world through godot_bridge.py.
- godot_world/world.gd: the world's engine side (player, HUD, link to the chat, helpers for parts).
- godot_world/scene/*.gd: the world's parts, one file per thing, rebuilt live when saved.
- godot_world/models/*.json: box models (Barnaby is 275 textured boxes) built by world.gd's build_model().
- barnaby_commands.txt / marigold_commands.txt: the commands each character can use (the chat window runs
  them; the parts' handle() functions carry them out).
- Textures (*.png) sit next to chat.pyw and are loaded at runtime with W.tex().

## Checking your work (do this after every change)
    python tools/check.py           # compiles the Python and loads the whole Godot world headless
    python tools/check.py --shot    # also renders shot.png (Linux: needs xvfb + mesa; see the script)
The check downloads the Linux build of Godot by itself if it is missing. It cannot test the parts that need
Windows, a microphone, a GPU or a logged-in Codex (voice, mouse buttons, the Codex processes): reason
carefully about those and keep changes to them small and safe.

## Rules
- Keep every file valid; never leave the project half-converted. The user runs it live: chat.pyw and the
  world parts are reloaded while the app is open, so a broken file shows up immediately.
- Match the surrounding style: plain, readable code with short comments that explain why.
- Don't commit chat_state.json, world_state.json or logs (they are in .gitignore).
- Update PROJECT_NOTES.md when you change how something works.
