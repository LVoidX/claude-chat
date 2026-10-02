"""Checks the project without needing its Windows-only parts: run it after every change.

    python tools/check.py            compile the Python, then load the Godot world headless and fail on errors
    python tools/check.py --shot     also render a screenshot (needs a display; on Linux it uses xvfb-run)

Godot: uses $GODOT if set, else D:\\Claude\\godot on Windows, else downloads the Linux build of the same
version to ~/.cache/godot (about 60 MB, once).
"""
import glob
import os
import platform
import py_compile
import shutil
import subprocess
import sys
import urllib.request
import zipfile

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT = os.path.join(HERE, "godot_world")
VERSION = "4.7.2-stable"
ERROR_MARKERS = ("SCRIPT ERROR", "Parse Error", "ERROR:", "has an error")


def find_godot():
    if os.environ.get("GODOT"):
        return os.environ["GODOT"]
    if platform.system() == "Windows":
        found = glob.glob(os.path.join(os.path.dirname(HERE), "godot", "Godot_v*_win64_console.exe"))
        if found:
            return max(found)
    cache = os.path.join(os.path.expanduser("~"), ".cache", "godot")
    exe = os.path.join(cache, f"Godot_v{VERSION}_linux.x86_64")
    if not os.path.exists(exe):
        os.makedirs(cache, exist_ok=True)
        url = f"https://github.com/godotengine/godot/releases/download/{VERSION}/Godot_v{VERSION}_linux.x86_64.zip"
        print("downloading Godot", VERSION, "...", flush=True)
        path = os.path.join(cache, "godot.zip")
        urllib.request.urlretrieve(url, path)
        with zipfile.ZipFile(path) as z:
            z.extractall(cache)
        os.remove(path)
        os.chmod(exe, 0o755)
    return exe


def run_godot(args, timeout=120):
    proc = subprocess.run(args, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=timeout)
    return proc.returncode, proc.stdout + proc.stderr


def main():
    ok = True
    for f in ("chat.pyw", "godot_bridge.py"):
        try:
            py_compile.compile(os.path.join(HERE, f), doraise=True)
            print(f"ok      {f} compiles")
        except py_compile.PyCompileError as e:
            ok = False
            print(f"FAILED  {f}: {e.msg}")
    godot = find_godot()
    # The world loads every part in godot_world/scene/, runs for ~5 s (300 frames) and quits.
    # A part with an error is reported by world.gd ("... has an error") and Godot prints SCRIPT ERROR lines.
    code, out = run_godot([godot, "--headless", "--path", PROJECT, "--quit-after", "300"])
    errors = [line for line in out.splitlines() if any(m in line for m in ERROR_MARKERS)]
    if errors:
        ok = False
        print("FAILED  the Godot world reported errors:")
        print("\n".join("        " + line for line in out.splitlines()[-60:]))
    else:
        print(f"ok      the Godot world loads and runs headless (exit code {code})")
    if "--shot" in sys.argv:
        shot = os.path.join(HERE, "shot.png")
        args = [godot, "--path", PROJECT, "--", f"--shot={shot}"]
        if platform.system() != "Windows":
            if not shutil.which("xvfb-run"):
                print("skipped screenshot: no display (install xvfb: apt-get install -y xvfb mesa-vulkan-drivers)")
                return 0 if ok else 1
            args = ["xvfb-run", "-a", godot, "--rendering-driver", "opengl3", "--path", PROJECT, "--", f"--shot={shot}"]
        code, out = run_godot(args)
        print(f"ok      screenshot saved to {shot}" if os.path.exists(shot) else "FAILED  no screenshot:\n" + out[-2000:])
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
