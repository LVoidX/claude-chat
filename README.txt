CLAUDE CHAT
===========

A black chat window that talks to Claude, with a 3D medieval world where you walk around and talk to
the characters (Barnaby and Marigold) by voice. Ask them, or the assistant in the chat, to build or change
anything, and it appears live.

NEEDS
- Windows
- Python 3 (https://www.python.org/downloads/ - tick "Add python.exe to PATH")
- Claude Code with a Claude account (the Claude desktop app has it built in). Everything the characters
  and the assistant say uses your own Claude plan.
- A microphone for talking (typing works too)

SETUP (once)
1. Unzip this folder somewhere, e.g. your Documents.
2. Double-click setup.bat. It installs the Python packages, downloads Godot (the 3D engine, ~80 MB)
   next to this folder, and puts a "Claude Chat" shortcut on your desktop.
3. If you never used Claude Code: open a terminal, run  claude  once and sign in.

PLAY
- Start "Claude Chat" (or Start.bat).
- Tab: switch between the chat and the 3D world.
- In the world: WASD walk, Shift run, Space jump, mouse look, Esc frees the mouse, R back to the middle.
- Walk up to Barnaby or Marigold and just talk: they listen when you stand next to them.
- Mouse button 5 or M (with an empty text box): talk to the assistant. Mouse button 4 or N: stop / cancel.
- Chat commands: /new (fresh conversation), /model haiku | sonnet | opus.
