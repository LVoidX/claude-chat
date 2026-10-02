"""Starts the Godot world and connects it to the chat window.

chat.pyw runs this exactly like it ran world.py: commands come in on stdin and messages go out on stdout,
one JSON object per line. Godot can't read a pipe while it runs, so this opens a local TCP socket, starts
Godot with its port, and passes lines back and forth. Godot's own output (errors included) goes to stderr,
which chat.pyw writes to claude-world.log. When either side goes away, the other is shut down too.
"""
import glob
import os
import socket
import subprocess
import sys
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.join(HERE, "godot_world")


def find_godot():
    """The newest Godot in D:\\Claude\\godot (the GUI exe, not the _console one)."""
    found = [p for p in glob.glob(os.path.join(os.path.dirname(HERE), "godot", "Godot_v*_win64.exe"))
             if not p.endswith("_console.exe")]
    return max(found) if found else None


def main():
    godot_exe = find_godot()
    if not godot_exe:
        print("Godot not found in D:\\Claude\\godot", file=sys.stderr, flush=True)
        sys.exit(1)
    server = socket.socket()
    server.bind(("127.0.0.1", 0))
    server.listen(1)
    server.settimeout(60)
    port = server.getsockname()[1]
    args = ([godot_exe] + (["--headless"] if "--headless" in sys.argv else [])  # --headless: for tests
            + ["--path", PROJECT, "--", f"--port={port}"] + (["--hidden"] if "--hidden" in sys.argv else []))
    godot = subprocess.Popen(args, stdout=sys.stderr, stderr=sys.stderr, stdin=subprocess.DEVNULL)
    try:
        conn, _ = server.accept()
    except OSError:
        print("Godot did not connect within 60 s", file=sys.stderr, flush=True)
        godot.kill()
        sys.exit(1)

    def to_godot():  # chat -> Godot; the chat closing our stdin means "quit"
        try:
            for line in sys.stdin:
                conn.sendall(line.encode("utf-8"))
        except OSError:
            pass
        godot.kill()
        os._exit(0)

    threading.Thread(target=to_godot, daemon=True).start()
    out = sys.stdout
    with conn.makefile("r", encoding="utf-8") as reader:  # Godot -> chat
        for line in reader:
            out.write(line)
            out.flush()
    godot.kill()  # Godot closed (window closed or it crashed)


if __name__ == "__main__":
    main()
