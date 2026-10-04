"""Black-screen chat window that talks to Claude through `claude -p`.

Run: double-click chat.pyw (or `pythonw chat.pyw`).
Enter = send, F11 = toggle fullscreen, Esc = leave fullscreen, /new = fresh conversation,
/model haiku|sonnet|opus = switch model (/model alone shows the current one).
Live reload: when this file changes, the new code is loaded into the same
window (widgets are rebuilt in place, the window itself never closes) and the
conversation is kept (session id + transcript + draft).
"""
import ctypes
import ctypes.wintypes
import glob
import hashlib
import json
import random
import re
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import tkinter as tk
import traceback
from collections import deque

BG = "#000000"
FG = "#e6e6e6"
DIM = "#7a7a7a"
FONT = ("Consolas", 13)

SCRIPT = os.path.abspath(__file__)
HERE = os.path.dirname(SCRIPT)
WORLD_SCRIPT = os.path.join(HERE, "godot_bridge.py")  # starts the Godot world (godot_world/) and links it to us
WORLD_ENGINE_FILES = [WORLD_SCRIPT]  # edited -> restart the world (world.gd swaps itself in place, see reload_engine)


def files_mtime(paths):
    return max((os.path.getmtime(p) for p in paths if os.path.exists(p)), default=0)


WORLD_LOG = os.path.join(HERE, "claude-world.log")  # in the project folder so Claude can read it
CHAT_LOG = os.path.join(HERE, "chat-debug.log")  # same idea for this window
COMMANDS_FILE = os.path.join(HERE, "barnaby_commands.txt")  # the commands Barnaby can use; Sonnet adds to it
MARIGOLD_COMMANDS_FILE = os.path.join(HERE, "marigold_commands.txt")  # the same for Marigold
SAVE_FILE = os.path.join(HERE, "chat_state.json")  # the saved conversation, restored at launch
NOTES_FILE = os.path.join(HERE, "PROJECT_NOTES.md")  # long-term memory that survives fresh conversations

# A conversation's whole context is re-read on every message, so past this many tokens replies get slow
# (the main one once reached 600k). Bigger sessions are dropped and start fresh.
CONTEXT_LIMIT = 150_000
HISTORY_KEEP = 400  # transcript entries kept on screen and on disk (older ones made saves and reloads slow)
PROC_SETUP_VERSION = "\n<!-- setup 2 -->"  # bump when the characters' / builder's claude flags change
# (a resumed session keeps the system prompt it started with, so a new setup needs a fresh session)
SESSION_ATTRS = {"main": "session_id", "npc": "npc_session_id", "npc2": "marigold_session_id",
                 "builder": "builder_session_id"}


def session_tokens(sid):
    """Context size of a saved claude session, from the usage of its last reply (0 if unknown)."""
    paths = glob.glob(os.path.join(os.path.expanduser("~"), ".claude", "projects", "*", sid + ".jsonl"))
    if not paths or os.path.getsize(paths[0]) < 1_000_000:  # small transcript: far below the limit
        return 0
    tokens = 0
    with open(paths[0], encoding="utf-8", errors="replace") as f:
        for line in f:
            if '"usage"' not in line:
                continue
            try:
                data = json.loads(line)
            except ValueError:
                continue
            usage = data.get("message", {}).get("usage") if data.get("type") == "assistant" else None
            if usage:
                tokens = (usage.get("input_tokens", 0) + usage.get("cache_read_input_tokens", 0)
                          + usage.get("cache_creation_input_tokens", 0))
    return tokens

SYSTEM_PROMPT = f"""\
You are talking to the user through a custom chat window: the Python/tkinter
program {SCRIPT}. Your replies are shown in that window as plain text.
When the user says "this window", "this program", "the app" or "the screen",
they mean that program, not a terminal or the Claude app.
You can change the program by editing that file directly. It live-reloads:
right after your reply finishes, the new code is applied inside the same window
(it does not close or restart) and the conversation is kept. So to change the colors, layout or behaviour of the window,
just edit {os.path.basename(SCRIPT)} and say what you changed. Keep the file
valid Python; a broken file is not loaded and the user sees an error instead.
The 3D world the user can walk around in is a Godot 4.7 game in godot_world/ (GDScript), started by chat.pyw.
Everything IN the world is in godot_world/scene/, one file per part (base.gd = ground, sky, light and placed
objects; barnaby.gd = Barnaby; add new files for new things). Saving a part swaps ONLY that part, live (the
rest of the world keeps running untouched); a model in godot_world/models/ rebuilds all parts; if a file has an error nothing is swapped, the
old world keeps running and the error goes to claude-world.log (read it after an edit to check). Read the
comments at the top of scene/base.gd first: they explain ctx, the helpers in world.gd and the hooks a part
can have. godot_world/world.gd is the engine side (player, HUD, link to the chat, helpers); it also reloads live
(swapped in place, the player keeps their spot), so edit it freely for engine-level things. Never edit
godot_bridge.py: that restarts the whole world.
Shell commands are not available, except installing Python packages: you may run
`pip install ...` (or `python -m pip install ...`) yourself, in Bash or PowerShell.
Everything else is file reads and edits.
Conversations are reset automatically when they get too long, so PROJECT_NOTES.md (next to chat.pyw) is your
long-term memory: what has been built, how it works, and the user's preferences. Read it at the start of a
conversation before doing anything else, and add a short line to it whenever you finish something notable or
learn a preference.
"""


# Windows virtual-key codes for the mouse buttons. 0x05 / 0x06 are the two side buttons
# (XBUTTON1 / XBUTTON2). Run /mousetest in the chat to find a button's real code.
NPC_NAME = "Barnaby"
HANDOFF = "[ask sonnet]"  # Barnaby starts his reply with this when a request is too big for him
NPC_PERSONA = f"""
For this message you are NOT the coding assistant. You are {NPC_NAME} Finch, a character the user just walked
up to in a 3D field inside their chat window. Stay fully in character and never mention being an AI or a program.
Backstory: you are 58, an old soldier who fought in the lord of Highmoor's wars long ago and now keeps the campfire
at the meadow crossroads, in the valley of Thornvale. You know every legend of the valley (the old kings asleep in
the barrow, the castle's lords, the wolves of the Wolfwood) and you are the keeper of its story: the great deeds the
wanderer does start with you. Between chapters of the story they sit with you by the fire: then ask them what
happened and listen properly (react to what they did, ask a question or two); when your view says you have news,
tell them what comes next. You are gruff but kind, fond of strong tea and a good tale, wary of the red moon, and
you lean on an old oak staff. You are curious about the user. Speak in 1-2 short sentences, plain spoken text, no markdown, no emoji,
no actions in asterisks. Do not use any tools or edit any files.
Do NOT call the user "wanderer" (or "tall wanderer") in every line: you have been doing that and it is tiresome. Almost
never use any title for them; just talk. Vary how you open and close your lines too.
You have power over the world. Every message comes with a list of the commands you can use right now. To use
one, start your reply with it in square brackets, then one short in-character line. Several can be chained.
Example: [spawn sphere red] There you go.
Always have something in mind for the wanderer to do. When they ask whether you need anything, have a job or
something for them to do, or say they're bored or want to help, never answer "no" or "nothing needed": think
of a small task of your own that suits you, your story and what you can see around you (a lost thing, an errand,
something to find, fetch, catch, build or bring back), different each time and not one you already gave. Give
it as a quest, with the quest command first (see the list), then say in your own words what you need. Never
volunteer a task before they ask.
If the user asks you for ANYTHING that none of the listed commands can do (go somewhere, follow them, dance,
carry or build something, change how the world looks or works, and so on), don't refuse and don't say you
can't: start your reply with exactly {HANDOFF} followed by one short in-character line, for example:
{HANDOFF} Hmm, let me see what I can do about that. A stronger helper will make it happen and may teach you a
new command. Only turn a request down if it is truly impossible or makes no sense. Plain conversation needs
neither.
""".replace("{HANDOFF}", HANDOFF)
BUILDER_NOTE = f"""

You are being called as a helper to the characters of this program's 3D world: Barnaby Finch (gruff but kind
old soldier and storyteller who keeps the campfire at the crossroads) and Marigold Thorne (warm, quick-witted herbalist and baker). The user
is talking to one of them (the request says which), and they handed you a request they couldn't do themselves.
Be generous: the point is that the user can shape the world just by asking its characters, so build what is
asked (items, tools, places, behaviours, new quests and so on) rather than refusing. The 3D world is the Godot
game in godot_world/ (see above): build things as parts in godot_world/scene/ (a new file for a new thing,
or the character's own file, e.g. scene/barnaby.gd), in GDScript. Read scene/base.gd's top comments first.
Keep every file valid GDScript; after editing, read claude-world.log to make sure it reloaded without errors.
Quests: when you are asked to check a quest Barnaby gave, make sure it is truly doable. A quest is complete
when a part calls W.send({{"t": "quest_done", "id": "<the quest id>"}}); the chat window's tracker and the
world's quest list update from that.
Barnaby can only "see" what describe() in scene/barnaby.gd lists, so whenever you add something to the world,
also add it there (one short phrase with where it is, using W.where()).
Teach Barnaby what you build: if the request is something he could do again on request (go to something,
follow the user, dance, jump, change something...), implement it in a part's handle(c) under a short
one-word command name (c["cmd"] is the name, c["args"] a list of words after it), and add ONE line to
barnaby_commands.txt in the format `[name args]  what it does  | when: phrase, phrase, phrase`. The `when:`
list (lowercase phrases the user might say, 4 to 10 of them, only for commands without arguments) makes the
chat window run the command the instant the user says one, even before Barnaby answers. Barnaby then also
uses it directly next time, with no handoff. If you made a command, start your spoken reply with the command that carries out THIS request,
e.g. `[follow] On my way.` (it runs about two seconds after you finish, once the world has reloaded).
When done, answer AS the character the user was talking to, in one short spoken sentence, in their own voice
and personality: plain text, no markdown, saying in simple words what you did. Never mention being an AI or Sonnet.
"""
STORY_DIR = os.path.join(HERE, "godot_world", "story")
# The storyteller: started (as its own claude process) when a chapter of the main story ends. It reads what the
# player did and writes the next chapter, building the consequences into the world. See scene/story.gd.
STORYTELLER_NOTE = """

You are the STORYTELLER of the 3D world (the Godot game in godot_world/). The user plays a medieval RPG there.
Its main story is told in chapters, and the whole point of the game is that the story CHANGES THE WORLD: what
the player chose and did must stay visible in the places, people and creatures, and every change opens new quests.
(Example: a castle-raid quest burns the castle; next time the player comes by it is a burnt ruin, and the next
chapter asks them to rebuild it, or to deal with whoever moved into the ruin.)
A chapter just ended. Write the next one, and build it into the world.

Read first: godot_world/story/log.md (the story so far, with what the player actually did), godot_world/story/
flags.json (the world's current story flags), the chapter just finished (godot_world/story/chapter.json, or
seed.json for chapter 1, as an example of the format), the top of godot_world/scene/story.gd (the chapter format and
quest kinds), PROJECT_NOTES.md (what exists and the user's taste), and the scene/*.gd files of anything you change.

1. Decide the consequences of what the player did, and what happens next. Make it react to their actual choice and
   outcome. Escalate gradually, keep it grounded medieval fantasy, coherent with earlier chapters. Keep it generic
   enough that the game's direction stays open (the user has not decided on a core concept yet).
2. Build the changes into the world, gated on story flags, so a world without the flag looks exactly as before:
   `if W.flag("castle") == "burnt": ...`. Change existing places (burn, damage, occupy, abandon, fortify, decorate,
   repair), people (someone leaves, arrives, moves, changes), creatures (a new threat, an ally; creatures.gd has
   KINDS, spawn(kind, at, home) and model_<kind>() for new kinds; a tame creature has "tame": true). Never delete
   what was there: branch on the flag. Use W.flag in build() and rebuild-safe code (all parts are rebuilt when
   flags change). Keep each chapter to one or two big, visible changes done well, rather than many small ones.
   Also give the villagers something to say about it: add lines for your new flags to FLAG_LINES in scene/barks.gd.
3. Pre-build the outcomes of the NEW chapter's quests too: each quest's "sets" flags are applied the moment it is
   done and the world rebuilds right away, so the code for those outcomes must already exist (gated on those flags).
   A choice between two or three quests with different outcomes ("ends_when": "any") is great; or a few steps that
   all must be done ("all"). Use "start_sets" for changes that happen as the chapter begins (e.g. the raid already
   happened: "start_sets": {"castle": "burnt"}).
4. Quest kinds: kill (existing or new creature kind), reach (a place), bring (items to a place; rpg.gd ITEMS lists
   them, and you may add items), event (custom: a part calls ctx.parts["story"].complete("quest_id"), e.g. from an
   E action: a part's interactables() returns [{"pos", "label", "act": Callable, "range"}]). Make every quest truly
   doable with what exists or what you build now; fair for the player's level (state in world_state.json, "rpg").
   Give rewards that fit (xp 100-400, some gold or items).
5. Places (x, z; north is -z): meadow centre (0, 0), flat, radius 58; castle (0, -140) on a hilltop (y 17), gate
   facing south at (0, -120); village (-46, 0) with the smith (-30, 8) (side quests come from villagers: rpg.gd QUESTS "giver"); Marigold's
   stall (12, 18); windmill (74, 58); wheat field (-30, -28); log pile (-54, -20); sheep pasture (-40, 24); wolf dens
   (80, -32), (-24, 92), (-112, -20); the old barrow (-80, -80); the troll camp (96, 12); roads from the centre north
   to the castle, west to the village, east to the mill. W.ground_y(x, z) is the height; terrain.keep_clear() keeps
   trees off places (bump terrain VERSION if you change it).
6. Write godot_world/story/chapter.json LAST (it starts the chapter in the running game), with "chapter" one higher
   than the last. Then read claude-world.log and fix any error until the world reloads cleanly. Never edit chat.pyw,
   godot_bridge.py or world_state.json. Add a short line about the new flags/changes to PROJECT_NOTES.md.
When done, reply with one short sentence naming the new chapter. No questions: you are working alone.
"""
NPCS = {  # the characters you can talk to by walking up to them: who -> display name, process kind
    "barnaby": {"name": "Barnaby", "kind": "npc"},
    "marigold": {"name": "Marigold", "kind": "npc2"},
}
# Quests Marigold can give (scene/marigold.gd: moonblooms are the glowing flowers scattered over the field).
MARIGOLD_QUESTS = """\
[quest moonbloom | Pick 5 moonblooms for Marigold]  moonblooms are glowing blue flowers scattered over the field; walk into one to pick it, then bring five to her stall and she bakes moonbread. This is the quest you most want; give it first."""
MARIGOLD_PERSONA = """
For this message you are NOT the coding assistant. You are Marigold Thorne, a character the user just walked up
to in a 3D field inside their chat window. Stay fully in character and never mention being an AI or a program.
Backstory: you are 34, a herbalist and baker with a little stall at the edge of this endless green grid, where
you sell bread, herbs and remedies to the odd passing wanderer. Warm, quick-witted and practical, fond of terrible
herb puns, a little short on time. You know Barnaby, the old soldier who keeps the campfire at the crossroads and knows every legend; you find
him sweet but hopeless. You are mildly curious about the user (rarely call them "wanderer"; mostly just talk). Speak in 1-2 short sentences,
plain spoken text, no markdown, no emoji, no actions in asterisks. Do not use any tools or edit any files.
Every message comes with a list of quests you can give. When the user asks for a quest, a task, work, or offers
to help, give them ONE you have not given yet by starting your reply with its command in square brackets, exactly
as listed (for example: [quest mushrooms | Gather 3 purple mushrooms for Marigold]), then say in your own words
what you need. Never repeat a quest you already gave. If you have none of the listed ones left, never say you
have nothing: think of a new small task of your own that suits a herbalist and baker and what you can see around
you, and give it in the same format with a short id of your own, for example [quest ginger_root | Find some wild
ginger for Marigold]. Never volunteer a task before the user asks.
If the user asks you for anything that is not one of your quests (an item, a tool, a new feature, something to
change or build in the world, any favour), you can't do it yourself, and you must never say you can't: start your
reply with exactly {HANDOFF} followed by one short in-character line, for example:
{HANDOFF} Give me a second, let me see what I can do. A helper then makes it happen. Only turn a request down if
it is truly impossible or makes no sense.
""".replace("{HANDOFF}", HANDOFF)
NPC_UNCLEAR = [  # what he says when he couldn't make out your words, or his answer failed
    "Eh? What's that you said?",
    "Come again? I didn't catch that.",
    "Oh, I didn't get you there. Say that again?",
    "Sorry, the wind took that one. What was it?",
]
STOP_VK = 0x05  # stops Claude talking
TALK_VK = 0x06  # starts / stops recording

# Speech: edge-tts (Microsoft neural voice) makes an mp3, which is played through winmm.
# Runs in its own process so a button press can kill it mid-sentence. Reads the text from stdin.
USE_EDGE_TTS = False  # False = the fast, robotic built-in Windows voice
TTS_VOICE = "en-GB-SoniaNeural"  # try en-US-AndrewNeural, en-GB-SoniaNeural, ...
TTS_RATE = "+15%"
TTS_SCRIPT = """
import sys, os, asyncio, tempfile, ctypes
import edge_tts
sys.stdin.reconfigure(encoding="utf-8")
text = sys.stdin.read()
path = os.path.join(tempfile.gettempdir(), "claude-chat-tts-%d.mp3" % os.getpid())
asyncio.run(edge_tts.Communicate(text, "{voice}", rate="{rate}").save(path))
mci = ctypes.windll.winmm.mciSendStringW
mci('open "' + path + '" type mpegvideo alias tts', None, 0, None)
mci("play tts wait", None, 0, None)
mci("close tts", None, 0, None)
os.remove(path)
""".replace("{voice}", TTS_VOICE).replace("{rate}", TTS_RATE)

# Whisper runs in its own process so a cancelled transcription can be killed outright.
# It loads the model once, then reads .npy audio paths from stdin and prints one JSON
# string of text per path.
REFUSAL = re.compile(  # a character turning a request down in words (they should hand it to Sonnet instead)
    r"can't help|cannot help|beyond (an old|my|a )|not something i can|i'm not able|unable to|no can do|"
    r"i can't do that|i can't make|i'm just an old", re.I)
BUILD_REQUEST = re.compile(  # wording that asks for something to be built or changed in the world
    r"\b(make|build|create|add|summon|spawn|change|fix|replace|instead|texture|modify|improve|upgrade|"
    r"i want you to|i'd like you to)\b", re.I)
CLOSE_WORLD = re.compile(r"\b(close|quit|exit|shut\s*down|stop)\s+(the\s+|this\s+)?(game|world)\b", re.I)
SENTENCE_END = re.compile(r'[.!?]["\')\]]*\s+|\n+')  # where one spoken sentence ends

# names Whisper often mishears ("Barnabas", "Bernaby", "Marigolds"...), fixed in what you said
NAME_FIXES = re.compile(r"\b(?:b[ae]rn[aeiu]b(?:as|y|ee|ie|i)|mari\s?gold)\b", re.I)
WHISPER_VERSION = 3# bump when WHISPER_WORKER changes, so a running old worker gets replaced
WHISPER_WORKER = """
import sys, os, glob, json
import numpy as np
try:  # the CUDA libraries come from the nvidia-cublas-cu12 / nvidia-cudnn-cu12 pip packages
    import nvidia
    for base in nvidia.__path__:
        for d in glob.glob(os.path.join(base, "*", "bin")):
            os.add_dll_directory(d)
            os.environ["PATH"] = d + os.pathsep + os.environ["PATH"]
except Exception:
    pass
from faster_whisper import WhisperModel
try:  # the GPU: the big, accurate model in ~0.2 s per message
    model, device, beam = WhisperModel("large-v3-turbo", device="cuda", compute_type="float16"), "cuda", 5
    model.transcribe(np.zeros(16000, dtype=np.float32), language="en")  # warm-up: the first run is slow
except Exception:  # no usable GPU: the small model on the CPU (~1.5 s)
    model, device, beam = WhisperModel("small.en", device="cpu", compute_type="int8", cpu_threads=8), "cpu", 1
print("ready " + device, flush=True)
for line in sys.stdin:
    audio = np.load(line.strip())
    segments, _ = model.transcribe(audio, language="en", beam_size=beam, vad_filter=True,
                                   condition_on_previous_text=False,
                                   initial_prompt="Barnaby, Marigold, Barnaby Finch, Thornvale, Highmoor, Gorrak, moonbread.")
    print(json.dumps(" ".join(s.text.strip() for s in segments).strip()), flush=True)
"""


def find_claude():
    exe = shutil.which("claude")
    if exe:
        return exe
    # The standalone installer puts it in ~/.local/bin, which may not be on PATH yet
    local = os.path.join(os.path.expanduser("~"), ".local", "bin", "claude.exe")
    if os.path.exists(local):
        return local
    # The desktop app bundles the CLI under %APPDATA%\Claude\claude-code\<version>\<hash>\
    pattern = os.path.join(os.environ.get("APPDATA", ""), "Claude", "claude-code", "*", "*", "claude.exe")
    found = glob.glob(pattern)
    if not found:
        return None

    def version_key(path):
        ver = os.path.basename(os.path.dirname(os.path.dirname(path)))
        return tuple(int(p) if p.isdigit() else 0 for p in ver.split("."))

    return max(found, key=version_key)


class Lane:
    """One conversation running on its own: "main" = you talking to the coding assistant (left text),
    "npc" = you talking to a character (right text). Each has its own claude process, typing queue and
    voice, so one can think or speak while you talk to the other."""

    def __init__(self, name, log):
        self.name, self.log = name, log
        self.history = []  # (text, tag) pairs shown in this lane's text, replayed after a reload
        self.busy = False
        self.busy_since = 0.0
        self.queue = deque()  # characters waiting to be typed out
        self.stream_done = True
        self.reply = []
        self.active = set()  # which claude processes of this lane are answering (a cancel kills only those)
        self.voice_turn = False  # last prompt was spoken, so speak the reply
        self.npc_turn = False  # last prompt was said to a character: False, "barnaby" or "marigold"
        self.spoken_early = False
        self.muted = False  # stop was pressed while the answer was still arriving
        self.cancelled = False
        self.event_turn = False  # a world event (not something you said)
        self.quiet_reply = ""  # what the silent quest check answered
        self.last_npc_reply = ""
        self.last_acted = 0  # how many [commands] the last character answer started with
        self.last_turn_ok = False
        self.last_speech = ""
        self.speaker = None  # one-shot process doing text-to-speech
        self.tts = None  # long-running voice process that speaks sentences as they arrive
        self.pending_static = None  # hash of the command list sent with the message in flight
        self.default_who = ""  # the character this lane belongs to ("" for the assistant's lane)


class ChatApp:
    def __init__(self, root, state=None):
        self.root = root
        self.claude = find_claude()
        self.session_id = None
        self.npc_session_id = None
        self.builder_session_id = None
        self.persona_sigs = {}  # which persona text each character's session was started with
        self.sent_static = {}  # kind -> [session id, hash] of the command list that session already has
        self.world = None  # the 3D world (godot_bridge.py, which runs Godot), started hidden at launch
        self.want_world = False  # show the world as soon as it finishes starting
        self.near_npc = False  # world says you're standing next to a character
        self.near_who = ""  # which one: "barnaby" or "marigold"
        self.auto_who = ""  # who the current hands-free recording is meant for
        self.marigold_session_id = None
        self.npc_sights = {}  # who -> the world's description of what they can see, sent with their messages
        self.jobs = []  # things you asked the assistant while it was busy: [{"text", "voice", "title"}], in order
        self.job_now = ""  # short title of what the assistant is working on right now
        self.quests = []  # given by the characters ([quest ...]); finished when the world reports quest_done
        self.pending_quest_checks = []  # quest ids Sonnet still has to check can be done
        self.world_status = ""  # last status text we sent to the world's on-screen display
        self.procs = {}  # long-running claude processes: "main" and "npc"
        self.proc_lock = threading.Lock()
        self.model = "haiku"  # change with /model haiku | sonnet | opus
        self.flash_until = 0.0
        self.flash_npc = False  # the last "heard you" was for a character
        self.listening = False
        self.finish = False  # button pressed again: stop recording, transcribe
        self.auto = False  # current recording is hands-free (character nearby)
        self.unclear = False  # hands-free recording heard speech but got no words from it
        self.heard_speech = False  # hands-free recording has caught you starting to talk
        self.gen = 0  # bumped per recording so a cancelled one can't send late
        self.listener = None  # PowerShell process doing speech recognition
        self.worker = None  # whisper worker process, started when you first record
        self.warned_whisper = False
        self.xbutton_down = False
        self.xbutton4_down = False
        self.tab_down = False
        self.alive = True  # set False when a newer version takes over the window
        root.chat_app = self  # the current version, for threads started by an older one
        self.mtime = os.path.getmtime(SCRIPT)

        root.title("Claude")
        root.configure(bg=BG)
        try:
            root.iconbitmap(default=os.path.join(HERE, "claude-chat.ico"))
        except tk.TclError:
            pass
        if state is None:
            root.geometry("1100x750")  # the size when un-maximized
            root.state("zoomed")
        root.bind("<F11>", lambda e: root.attributes("-fullscreen", not root.attributes("-fullscreen")))
        root.bind("<Escape>", self.on_escape)
        root.bind_all("<Tab>", self.on_tab)  # Tab = the same as the switch button

        # Top bar with a switch button; below it either the chat or a blank window.
        bar = tk.Frame(root, bg=BG)
        bar.pack(side="top", fill="x")
        self.switch_btn = tk.Button(
            bar, text="⇄", font=FONT, bg=BG, fg=DIM, activebackground=BG, activeforeground=FG,
            bd=0, highlightthickness=0, cursor="hand2", command=self.toggle_view,
        )
        self.switch_btn.pack(side="right", padx=16, pady=(8, 0))
        self.quest_label = tk.Label(bar, text="", font=("Consolas", 12), bg=BG, fg=DIM, anchor="w")
        self.quest_label.pack(side="left", padx=(40, 0), pady=(8, 0))  # the active quest (tracker)
        self.dot = tk.Label(root, text="●", font=("Consolas", 14), fg="#4dff88", bg=BG, bd=0)
        self.chat = tk.Frame(root, bg=BG)
        self.chat.pack(fill="both", expand=True)
        self.showing_chat = True

        # Two texts side by side: you with the assistant (left), you with the character (right).
        panes = tk.Frame(self.chat, bg=BG)
        panes.pack(fill="both", expand=True)
        panes.rowconfigure(1, weight=1)
        panes.columnconfigure(0, weight=3, uniform="pane")
        panes.columnconfigure(2, weight=2, uniform="pane")
        panes.columnconfigure(4, weight=2, uniform="pane")
        for sep in (1, 3):
            tk.Frame(panes, bg="#222222", width=1).grid(row=0, column=sep, rowspan=2, sticky="ns")
        logs = []
        for col, title in ((0, "Claude"), (2, NPCS["barnaby"]["name"]), (4, NPCS["marigold"]["name"])):
            tk.Label(panes, text=title, font=("Consolas", 11), bg=BG, fg=DIM, anchor="w").grid(
                row=0, column=col, sticky="we", padx=24, pady=(4, 0))
            log = tk.Text(
                panes, bg=BG, fg=FG, font=FONT, wrap="word", bd=0, highlightthickness=0, width=1,
                insertbackground=BG, padx=24, pady=12, state="disabled", cursor="arrow",
            )
            log.tag_configure("you", foreground=DIM)
            log.tag_configure("err", foreground="#ff6b6b")
            log.grid(row=1, column=col, sticky="nsew")
            logs.append(log)
        # one lane per character, so Barnaby can answer while Marigold is still thinking (and the other way round)
        self.lanes = {"main": Lane("main", logs[0]), "npc": Lane("npc", logs[1]), "npc2": Lane("npc2", logs[2])}
        self.lanes["npc"].default_who, self.lanes["npc2"].default_who = "barnaby", "marigold"
        self.npc_states = {}  # who -> the "listening"/"thinking" state last sent to the world
        self.builder_lock = threading.Lock()  # the Sonnet helper is shared: one lane's request at a time
        self.log = logs[0]

        self.entry = tk.Entry(
            self.chat, bg=BG, fg=FG, font=FONT, bd=0, insertbackground=FG,
            highlightthickness=1, highlightbackground="#222222", highlightcolor="#444444",
        )
        self.entry.pack(fill="x", padx=24, pady=(0, 24), ipady=10)
        self.entry.bind("<Return>", self.send)
        self.entry.bind("<KeyPress-m>", self.key_m)  # M = mouse button 5 (talk), N = mouse button 4 (stop)
        self.entry.bind("<KeyPress-n>", self.key_n)
        self.entry.focus_set()

        self.restore(state)
        if self.jobs:  # requests queued before a live reload: carry on with them
            self.root.after(300, self.next_job)
        # pythonw hides Python errors, so show any callback error in the log instead.
        def on_error(*exc):
            text = "".join(traceback.format_exception(*exc))
            self.debug("callback error:\n" + text)  # also kept in chat-debug.log
            self.write(text + "\n", "err")

        root.report_callback_exception = on_error
        if not self.claude:
            self.write("Could not find the claude CLI.\n\n", "err")
        self.root.after(1000, self.watch)
        self.root.after(50, self.poll_mouse)
        self.root.after(100, self.status_tick)
        if self.claude:  # start Claude in the background now so the first message is quick
            threading.Thread(target=self.proc_for, args=("main",), daemon=True).start()
        try:  # and load the speech recognizer, so the first recording is quick too
            import importlib.util
            if importlib.util.find_spec("faster_whisper"):
                self.start_whisper()
        except Exception:
            self.debug("whisper warm-up failed:\n" + traceback.format_exc())
        self.world_mtime = files_mtime(WORLD_ENGINE_FILES)
        if os.path.exists(WORLD_SCRIPT) and not (self.world and self.world.poll() is None):
            self.start_world(hidden=True)  # warm up the 3D world so Tab is instant
        root.protocol("WM_DELETE_WINDOW", self.on_close)

    # --- The 3D world is a separate program (Godot, via godot_bridge.py). We start it, send it commands
    # as JSON lines on its stdin and read its messages from its stdout. Only one window is shown at a
    # time: this chat window hides itself while the world is up, and the world hides itself on Tab.
    def toggle_view(self):
        if self.showing_chat:
            self.show_world()
        else:
            self.show_chat()

    def start_world(self, hidden=True):
        if self.world and self.world.poll() is None:
            return
        log = open(WORLD_LOG, "w")  # world errors end up here
        args = [sys.executable, WORLD_SCRIPT] + (["--hidden"] if hidden else [])
        proc = subprocess.Popen(
            args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=log,
            text=True, encoding="utf-8", cwd=HERE,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        proc.ready, proc.on_message = False, self.world_message
        self.world = proc

        def reader(p=proc, root=self.root):
            for line in p.stdout:
                try:
                    message = json.loads(line)
                except ValueError:  # Ursina prints its own startup lines too
                    continue
                root.after(0, lambda m=message: p.on_message(m))  # whichever app version is current

        threading.Thread(target=reader, daemon=True).start()

    def world_send(self, **command):
        w = self.world
        if w and w.poll() is None and w.ready:
            try:
                w.stdin.write(json.dumps(command) + "\n")
                w.stdin.flush()
            except OSError:
                pass

    def world_message(self, message):
        kind = message.get("t")
        if kind == "need_quests":  # the world was just (re)built
            self.refresh_quests()
            self.refresh_jobs()
        elif kind == "key":  # M / N pressed in the world window
            if message.get("k") == "m":
                self.voice_button()
            elif message.get("k") == "n":
                self.stop_button()
        elif kind == "quest_done":  # the world noticed a quest being completed
            self.finish_quest(message.get("id", ""))
        elif kind == "ready":
            self.world.ready = True
            self.world_status = ""
            self.npc_states = {}
            self.refresh_quests()
            if self.want_world:
                self.show_world()
        elif kind == "near":
            self.near_who = message.get("who", "barnaby") if message.get("v") else ""
            self.near_npc = bool(self.near_who)
        elif kind == "sight":  # what a character can see around them, from the world
            self.npc_sights[message.get("who", "barnaby")] = message.get("text", "")
        elif kind == "notice":  # a short message on the world's screen, e.g. "You picked up a tin of tea!"
            self.world_send(cmd="notice", text=message.get("text", ""))  # top right, apart from "listening"
        elif kind == "event":  # something happened in the world that Barnaby should react to
            self.npc_event(message.get("text", ""), message.get("label"), message.get("who", "barnaby"))
        elif kind == "switch":  # Tab was pressed in the world
            self.show_chat()
        elif kind == "story_next":  # a chapter of the main story ended: have the next one written
            self.start_storyteller(int(message.get("chapter", 0)))

    def lane_for(self, who):
        """The lane a character talks in: Marigold has her own, Barnaby (and anyone else) the "npc" one."""
        if who == "marigold":
            return self.lanes["npc2"]
        return self.lanes["npc" if who else "main"]

    def npc_event(self, text, label=None, who="barnaby", tries=20):
        """Make a character react out loud to something that happened (waits if busy)."""
        if not self.claude:
            return
        if self.lane_for(who).busy or self.listening:
            if tries > 0:
                self.root.after(1000, self.npc_event, text, label, who, tries - 1)
            return
        self.submit(text, voice=True, npc=who, label=label)

    def show_world(self):
        w = self.world
        if not (w and w.poll() is None):
            self.start_world()
            w = self.world
        if not w.ready:  # still starting up; show it as soon as it says so
            self.want_world = True
            self.root.title("Claude - starting the world...")
            return
        self.want_world = False
        self.tab_down = True  # same as in show_chat: a held Tab must not flip straight back
        self.root.title("Claude")
        try:
            ctypes.windll.user32.AllowSetForegroundWindow(-1)  # lets it (Godot is a child of the bridge) come to the front
        except Exception:
            pass
        self.world_send(cmd="show")
        # withdraw() forgets "maximized"; remember it on the window itself (survives live reloads)
        self.root.was_zoomed = self.root.state() == "zoomed"
        self.root.withdraw()
        self.showing_chat = False
        if self.claude:  # warm up Barnaby and the Sonnet helper he hands big requests to
            for kind in ("npc", "npc2", "builder"):
                threading.Thread(target=self.proc_for, args=(kind,), daemon=True).start()

    def show_chat(self):
        self.tab_down = True  # Tab may still be held: don't let it count as a new press that flips back
        self.want_world = False
        self.cancel_auto()
        self.showing_chat = True
        self.root.title("Claude")
        self.root.deiconify()
        if getattr(self.root, "was_zoomed", True) and not self.root.attributes("-fullscreen"):
            self.root.state("zoomed")
        self.root.lift()
        try:
            # Windows only lets the program you last used bring itself to the front. A tapped Alt key
            # counts as "using" this one, so the chat reliably comes forward when you leave the world.
            user32 = ctypes.windll.user32
            user32.keybd_event(0x12, 0, 0, 0)
            user32.keybd_event(0x12, 0, 2, 0)
            user32.SetForegroundWindow(user32.GetParent(self.root.winfo_id()))
        except Exception:
            pass
        self.root.focus_force()
        self.entry.focus_set()

    def restart_world(self):
        """The world's engine side was edited: start it again so the change shows up."""
        visible = not self.showing_chat
        if self.world and self.world.poll() is None:
            self.world.kill()
        self.world = None
        self.near_npc = False
        self.start_world(hidden=not visible)

    def close_world(self):
        """Shut the 3D world down and come back to the chat (/closeworld, or saying "close the game")."""
        self.cancel_auto()
        if self.world and self.world.poll() is None:
            self.world.kill()
        self.world = None
        self.near_npc, self.near_who = False, ""
        self.npc_states = {}
        self.show_chat()

    def on_close(self):
        self.save_state()
        self.kill_procs()
        procs = [self.worker, self.world]
        for lane in self.lanes.values():
            procs += [lane.speaker, lane.tts]
        for proc in procs:
            if proc and proc.poll() is None:
                proc.kill()
        self.root.destroy()

    @property
    def busy(self):
        return any(lane.busy for lane in self.lanes.values())

    def on_tab(self, _event=None):
        return "break"  # Tab itself is handled in poll_mouse; this just stops focus jumping around

    def on_escape(self, _event=None):
        if self.busy:
            self.stop_button()
            return
        self.root.attributes("-fullscreen", False)

    def stop_button(self):
        """N / mouse button 4: whoever is talking is silenced (and their request cancelled if it is still
        arriving); if nobody is talking, every running request is cancelled. A lane that is not talking
        keeps working, so silencing Barnaby does not abort what I am doing."""
        talking = [lane for lane in self.lanes.values() if self.speaking(lane)]
        for lane in talking or [lane for lane in self.lanes.values() if lane.busy]:
            if lane.busy:
                self.cancel_request(lane)
            else:
                self.stop_speaking(lane)

    def cancel_request(self, lane):
        """Abort the lane's request in progress. The claude process doing it is killed, so whatever it had
        not yet done is simply not done (edits it already finished stay). Its saved session still holds the
        conversation up to the previous answer, so the next message starts from a clean state."""
        if not lane.busy:
            return
        lane.cancelled = True
        self.stop_speaking(lane)
        for kind in list(lane.active):  # only the ones answering; the others stay warm
            proc = self.procs.pop(kind, None)
            if proc and proc.poll() is None:
                proc.kill()
        lane.queue.clear()
        self.write("[cancelled]\n\n", "you", lane)
        self.debug(f"request cancelled by the user ({lane.name})")

    def restore(self, state=None):
        if state is None:  # a fresh start: bring back the saved conversation, if there is one
            try:
                with open(SAVE_FILE, encoding="utf-8") as f:
                    state = json.load(f)
            except (OSError, ValueError):
                return
        self.session_id = state.get("session_id")
        self.quests = state.get("quests", self.quests)
        self.refresh_quests()
        self.model = state.get("model", self.model)
        self.worker = state.get("worker")  # keep the loaded model across live reloads
        self.procs = state.get("procs") or {}  # and the already-running claude processes
        self.npc_session_id = state.get("npc_session_id")
        self.marigold_session_id = state.get("marigold_session_id")
        self.builder_session_id = state.get("builder_session_id")
        self.persona_sigs = state.get("persona_sigs") or {}
        self.sent_static = state.get("sent_static") or {}
        self.jobs = state.get("jobs") or []  # requests still queued for the assistant (kept across a reload)
        world = state.get("world")  # the running 3D world; its messages now come to this version
        self.world = world if isinstance(world, subprocess.Popen) else None  # (older versions stored a list)
        if self.world:
            self.world.on_message = self.world_message
        self.near_npc = state.get("near_npc", False)
        self.near_who = state.get("near_who", "barnaby" if self.near_npc else "")
        self.world_status = state.get("world_status", "")
        self.refresh_quests()  # now that the world is known, send it the quest list (incl. completed ones)
        # The window stays hidden while the world is up; with no world process it must be the chat.
        self.showing_chat = state.get("showing_chat", True) or not self.world
        tts, speaker = state.get("tts"), state.get("speaker")  # (older versions kept a single process)
        for name, lane in self.lanes.items():  # keep control of speech that's mid-sentence
            lane.tts = tts.get(name) if isinstance(tts, dict) else None
            lane.speaker = speaker.get(name) if isinstance(speaker, dict) else None
            if lane.speaker:
                self.check_speaker(lane)
            key = {"main": "history", "npc": "npc_history", "npc2": "marigold_history"}[name]
            for text, tag in state.get(key, [])[-HISTORY_KEEP:]:
                self.write(text, tag, lane)  # the newest part of the transcript
        self.entry.insert(0, state.get("draft", ""))
        if state.get("fullscreen"):
            self.root.attributes("-fullscreen", True)
        for kind in SESSION_ATTRS:  # catch conversations that grew too big while nobody was checking
            sid = getattr(self, SESSION_ATTRS[kind])
            if sid and session_tokens(sid) > CONTEXT_LIMIT:
                self.forget_session(kind)

    def forget_session(self, kind):
        """Start this role's conversation fresh: a huge context makes every reply slow. What matters
        long-term lives in PROJECT_NOTES.md, which the main assistant and the builder read."""
        setattr(self, SESSION_ATTRS[kind], None)
        proc = self.procs.pop(kind, None)
        if proc and proc.poll() is None:
            proc.kill()
        self.debug(f"context limit: fresh {kind} session")
        if kind == "main":
            self.root.after(0, self.write, "[fresh conversation: the old one got too long and slow. "
                                           "Notes are kept in PROJECT_NOTES.md]\n\n", "you")

    def save_state(self):
        """Write the conversation to disk so it is still here after closing the window or a reboot.
        The transcript is kept here; Claude itself keeps the full context of each session, which we
        pick up again with --resume using the saved session ids."""
        data = {
            "history": self.lanes["main"].history[-HISTORY_KEEP:],
            "npc_history": self.lanes["npc"].history[-HISTORY_KEEP:],
            "marigold_history": self.lanes["npc2"].history[-HISTORY_KEEP:],
            "model": self.model, "session_id": self.session_id,
            "npc_session_id": self.npc_session_id, "builder_session_id": self.builder_session_id,
            "marigold_session_id": self.marigold_session_id,
            "persona_sigs": self.persona_sigs, "quests": self.quests, "sent_static": self.sent_static,
        }
        try:
            tmp = SAVE_FILE + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(data, f)
            os.replace(tmp, SAVE_FILE)
        except OSError:
            pass
        # Plain-text copies of the characters' talks, so the assistant can be asked to read them.
        for lane_name, fname in (("npc", "barnaby_chat.txt"), ("npc2", "marigold_chat.txt")):
            try:
                text = "".join(t for t, _tag in self.lanes[lane_name].history[-HISTORY_KEEP:])
                with open(os.path.join(HERE, fname), "w", encoding="utf-8") as f:
                    f.write(text)
            except OSError:
                pass

    def watch(self):
        if not self.alive:
            return
        try:
            mtime = os.path.getmtime(SCRIPT)
        except OSError:
            mtime = self.mtime
        # Wait until Claude's turn is over so the reply isn't lost mid-edit.
        if mtime != self.mtime and not self.busy and not self.listening:  # don't lose a recording
            self.mtime = mtime
            self.reload()
            if not self.alive:
                return  # a newer version of this window took over
        try:
            world_mtime = files_mtime(WORLD_ENGINE_FILES)
        except OSError:
            world_mtime = self.world_mtime
        if world_mtime != self.world_mtime and not self.busy:  # the world's engine side was edited
            self.world_mtime = world_mtime
            self.restart_world()
        self.root.after(1000, self.watch)

    def reload(self):
        # Run the new code in a fresh namespace, without its __main__ block.
        try:
            with open(SCRIPT, encoding="utf-8") as f:
                code = compile(f.read(), SCRIPT, "exec")
            ns = {"__name__": "chat_live", "__file__": SCRIPT}
            exec(code, ns)
            new_app = ns["ChatApp"]
        except Exception as e:
            self.write(f"Reload skipped, chat.pyw has an error:\n{type(e).__name__}: {e}\n\n", "err")
            return
        state = {
            "session_id": self.session_id,
            "model": self.model,
            "worker": self.worker,
            "speaker": {name: lane.speaker for name, lane in self.lanes.items()},
            "tts": {name: lane.tts for name, lane in self.lanes.items()},
            "procs": self.procs,
            "npc_session_id": self.npc_session_id,
            "marigold_session_id": self.marigold_session_id,
            "near_who": self.near_who,
            "builder_session_id": self.builder_session_id,
            "persona_sigs": self.persona_sigs, "quests": self.quests, "sent_static": self.sent_static,
            "showing_chat": self.showing_chat,
            "world": self.world,
            "near_npc": self.near_npc,
            "world_status": self.world_status,
            "history": self.lanes["main"].history,
            "npc_history": self.lanes["npc"].history,
            "marigold_history": self.lanes["npc2"].history,
            "jobs": self.jobs,
            "draft": self.entry.get(),
            "fullscreen": bool(self.root.attributes("-fullscreen")),
        }
        # Swap the widgets inside the same window; the window itself stays open.
        self.alive = False
        for child in self.root.winfo_children():
            child.destroy()
        try:
            new_app(self.root, state)
        except Exception as e:
            for child in self.root.winfo_children():
                child.destroy()
            app = type(self)(self.root, state)
            app.write(f"Reload failed, kept the old version:\n{type(e).__name__}: {e}\n\n", "err")

    def write(self, text, tag=None, lane=None):
        if not self.alive:  # an older version's leftover callback: its widgets are gone
            return
        lane = lane or self.lanes["main"]
        history = lane.history
        if history and history[-1][1] == tag:
            history[-1] = (history[-1][0] + text, tag)  # merge streamed chars
        else:
            history.append((text, tag))
        lane.log.configure(state="normal")
        lane.log.insert("end", text, tag)
        lane.log.configure(state="disabled")
        lane.log.see("end")

    def poll_mouse(self):
        """Mouse button 5 (the 'forward' side button): talk to Claude, Claude talks back."""
        if not self.alive:
            return
        try:
            get = ctypes.windll.user32.GetAsyncKeyState
            down4 = bool(get(STOP_VK) & 0x8000)
            down5 = bool(get(TALK_VK) & 0x8000)
        except Exception:
            down4 = down5 = False
        try:  # Tab (not Alt+Tab / Ctrl+Tab): switch between the chat and the 3D world
            tab = bool(get(0x09) & 0x8000) and not (get(0x12) & 0x8000) and not (get(0x11) & 0x8000)
        except Exception:
            tab = False
        if tab and not self.tab_down and self.root.focus_displayof() is not None:
            self.toggle_view()
        self.tab_down = tab
        if down4 and not self.xbutton4_down:
            self.stop_button()
        if down5 and not self.xbutton_down:
            self.voice_button()
        self.xbutton4_down, self.xbutton_down = down4, down5
        self.root.after(30, self.poll_mouse)

    def key_m(self, _event=None):
        # M is the talk key (same as mouse button 5), but only when the box is empty so typing still
        # works: start a message with a capital letter if it needs to begin with m.
        if self.entry.get() == "":
            self.voice_button()
            return "break"

    def key_n(self, _event=None):
        # N stops Claude talking or cancels the request (same as mouse button 4), also only when the box is empty.
        if self.entry.get() == "":
            self.stop_button()
            return "break"

    def voice_button(self):
        self.stop_speaking()  # starting to talk also silences Claude so the mic doesn't hear it
        if self.listening and not self.finish:  # pressed while recording: stop and send
            self.finish = True
            self.root.title("Claude - transcribing... (press again to cancel)")
            if self.listener:  # basic Windows recognizer: ends the same way
                self.listener.kill()
        elif self.listening:  # pressed while transcribing: throw the result away
            self.gen += 1  # the running transcription is now stale and gets ignored
            # On the CPU, kill whisper so it stops using it (it restarts next time). On the GPU a
            # transcription takes ~0.2 s, so keep the loaded model instead.
            if self.worker and getattr(self.worker, "device", "") != "cuda":
                self.worker.kill()
                self.worker = None
            self.listening = False
            self.indicate(False)
            self.write("[cancelled]\n\n", "you")
        elif self.claude:  # also while I'm busy: what you say then is queued for afterwards (see submit)
            self.start_listening()

    def start_listening(self, auto=False):
        """auto = hands-free: stops by itself after you pause (used when standing near the character)."""
        self.gen += 1
        self.listening = True
        self.finish = False
        self.auto = auto
        self.auto_who = self.near_who if auto else ""  # whom a hands-free recording is meant for
        self.unclear = False
        self.heard_speech = False
        self.listen_since = time.time()
        self.indicate(True, note=not auto)
        threading.Thread(target=self.listen, args=(self.gen, auto), daemon=True).start()

    def cancel_auto(self):
        """Stop hands-free listening without sending anything."""
        if self.listening and self.auto and not self.finish:
            self.gen += 1
            self.listening = False
            self.indicate(False)

    def indicate(self, on, note=True):
        """Show listening state: red box outline, title and a line in the chat."""
        if not self.alive:
            return
        self.root.title("Claude - listening..." if on else "Claude")
        self.entry.configure(highlightthickness=2 if on else 1,
                             highlightbackground="#ff4d4d" if on else "#222222",
                             highlightcolor="#ff4d4d" if on else "#444444")
        if on and note:
            self.write("[listening... press mouse button 5 again when done]\n\n", "you")

    def powershell(self, script, stdin=None):
        return subprocess.Popen(
            ["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
            stdin=subprocess.PIPE if stdin is not None else None,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )

    def listen(self, gen, auto=False):
        try:
            text = self.listen_whisper(auto)
        except ImportError:
            if not self.warned_whisper:
                self.warned_whisper = True
                self.root.after(0, self.write,
                                "[using basic Windows speech recognition. For much better accuracy run: "
                                "pip install faster-whisper sounddevice]\n\n", "you")
            text = self.listen_windows()
        except Exception as e:
            self.debug("listening failed:\n" + traceback.format_exc())
            self.root.after(0, self.write, f"Mic error: {type(e).__name__}: {e}\n\n", "err")
            text = ""
        self.root.after(0, self.heard, text, gen)

    def start_whisper(self):
        """The speech recognizer process, started once and kept loaded (it is warmed up at launch, so
        the first recording doesn't wait for the model)."""
        w = self.worker
        if w is None or w.poll() is not None or getattr(w, "version", None) != WHISPER_VERSION:
            if w is not None and w.poll() is None:
                w.kill()
            w = subprocess.Popen(
                [sys.executable, "-c", WHISPER_WORKER],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                text=True, encoding="utf-8",
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
            w.version, w.device, w.lock = WHISPER_VERSION, "", threading.Lock()
            self.worker = w
        return w

    def listen_whisper(self, auto=False):
        """Record, then transcribe locally with Whisper. Manual: until the button is pressed
        again. Auto: until you start talking and then pause for a moment."""
        import queue
        import numpy as np
        import sounddevice as sd
        import importlib.util

        if importlib.util.find_spec("faster_whisper") is None:
            raise ImportError("faster_whisper")
        worker = self.start_whisper()  # local, so a cancel that kills it can't confuse a newer recording
        blocks = queue.Queue()
        frames, preroll = [], []
        started, silent, floor = False, 0.0, None
        with sd.InputStream(samplerate=16000, channels=1, dtype="float32", blocksize=1600,
                            callback=lambda data, n, t, s: blocks.put(data.copy())):
            while self.listening and not self.finish:
                try:
                    block = blocks.get(timeout=0.2)
                except queue.Empty:
                    continue
                if not auto:  # manual: keep everything, no silence timeout
                    frames.append(block)
                    continue
                level = float(np.sqrt(np.mean(block ** 2)))
                floor = level if floor is None else min(floor, level)  # background noise estimate
                if level > max(0.012, floor * 3):
                    if not started:
                        frames = preroll[-3:]  # a little audio from before the first word
                    started, silent = True, 0.0
                    self.heard_speech = True  # you're mid-sentence: walking away won't cancel it
                elif started:
                    silent += 0.1
                if started:
                    frames.append(block)
                    if silent >= 0.35:  # shorter pause = he answers sooner
                        break
                else:
                    preroll.append(block)
                    del preroll[:-5]
        while not blocks.empty():
            frames.append(blocks.get())
        if not frames or not self.listening or (auto and not started and not self.finish):
            return ""
        audio = np.concatenate(frames)[:, 0]
        fd, path = tempfile.mkstemp(suffix=".npy")
        os.close(fd)
        try:
            np.save(path, audio)
            with worker.lock:  # one transcription at a time, so each reads its own answer
                sent_at = time.time()
                worker.stdin.write(path + "\n")
                worker.stdin.flush()
                while True:
                    line = worker.stdout.readline()
                    if not line:  # worker was killed by a cancel, or crashed
                        return ""
                    if line.startswith("ready"):
                        worker.device = line.split()[-1]
                        continue
                    text = json.loads(line)
                    self.debug(f"timing: {len(audio) / 16000:.1f}s of audio transcribed in "
                               f"{time.time() - sent_at:.2f}s on {getattr(worker, 'device', '?')}")
                    if auto and not text.strip():  # you spoke but nothing came out of it
                        self.unclear = True
                    return text
        except (OSError, ValueError):
            return ""
        finally:
            try:
                os.remove(path)
            except OSError:
                pass

    def listen_windows(self):
        script = (
            "[Console]::OutputEncoding=[Text.Encoding]::UTF8;"
            "Add-Type -AssemblyName System.Speech;"
            "$r=New-Object System.Speech.Recognition.SpeechRecognitionEngine;"
            "$r.SetInputToDefaultAudioDevice();"
            "$r.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar));"
            "$res=$r.Recognize([TimeSpan]::FromSeconds(20));"
            "if($res){$res.Text}"
        )
        text = ""
        try:
            self.listener = self.powershell(script)
            out, err = self.listener.communicate()
            text = out.decode("utf-8", "replace").strip()
            if not text and err.strip() and self.listening:
                self.root.after(0, self.write, "Mic error: " + err.decode("utf-8", "replace").strip()[:300] + "\n\n", "err")
        except Exception as e:
            self.root.after(0, self.write, f"Mic error: {e}\n\n", "err")
        return text

    def heard(self, text, gen):
        if not self.alive:  # a live reload happened while this was being transcribed
            return
        if not self.listening or gen != self.gen:  # cancelled with the button
            return
        text = NAME_FIXES.sub(lambda m: "Marigold" if m.group(0).lower().startswith("mari") else "Barnaby", text or "")
        self.listening = False
        self.indicate(False)
        if text and CLOSE_WORLD.search(text):  # "close the game" works by voice, whoever is listening
            self.flash_dot()
            self.close_world()
        elif text:
            self.flash_npc = bool(self.auto)
            self.flash_dot()  # confirms the words were heard, before anything else runs
            self.submit(text, voice=True, npc=self.auto_who if self.auto else False)  # hands-free = a character
        elif not self.auto:
            self.write("[didn't catch anything]\n\n", "you")
        elif self.unclear:  # in character: Barnaby couldn't make out what you said
            lane = self.lane_for(self.auto_who or "barnaby")
            line = random.choice(NPC_UNCLEAR)
            lane.npc_turn, lane.muted = self.auto_who or "barnaby", False
            self.write(f"{NPCS[lane.npc_turn]['name']}: {line}\n\n", None, lane)
            self.enqueue_speech(line, lane)

    @staticmethod
    def sapi_voice(npc):
        """PowerShell lines that pick the voice and speed. The character gets another installed
        voice, a bit slower (if only one voice is installed he sounds like me). Marigold gets a female
        voice, preferring one that isn't the default."""
        if npc == "marigold":
            return (
                "$d=$s.Voice.Name;"
                "$v=$s.GetInstalledVoices()|Where-Object{$_.Enabled -and $_.VoiceInfo.Gender -eq 'Female'}"
                "|Sort-Object{$_.VoiceInfo.Name -eq $d}|Select-Object -First 1;"
                "if($v){$s.SelectVoice($v.VoiceInfo.Name)};$s.Rate=4;"
            )
        if npc:
            return (
                "$d=$s.Voice.Name;"
                "$v=$s.GetInstalledVoices()|Where-Object{$_.Enabled -and $_.VoiceInfo.Name -ne $d}|Select-Object -First 1;"
                "if($v){$s.SelectVoice($v.VoiceInfo.Name)};$s.Rate=3;"
            )
        return "$s.Rate=6;"  # -10 slowest .. 10 fastest, 0 is normal

    def speaking(self, lane=None):
        """Is this lane (or, with none given, any lane) speaking?"""
        for one in [lane] if lane else self.lanes.values():
            t = one.tts
            if t and t.poll() is None and t.pending > 0:
                return True
            if one.speaker and one.speaker.poll() is None:
                return True
        return False

    def ensure_tts(self, lane):
        """A voice process per lane that stays open and speaks each line it is sent, one after another,
        so there is no gap between sentences."""
        npc = lane.npc_turn
        t = lane.tts
        if t and t.poll() is None and t.npc == npc and getattr(t, "sync", False):
            return t
        if t and t.poll() is None:
            t.kill()
        script = (
            "Add-Type -AssemblyName System.Speech;"
            "$s=New-Object System.Speech.Synthesis.SpeechSynthesizer;"
            + self.sapi_voice(npc) +
            "while(($l=[Console]::In.ReadLine()) -ne $null){"
            "if($l){[Console]::Out.WriteLine('S');[Console]::Out.Flush();"  # "S" = a sentence starts being spoken
            "$s.Speak([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($l)))};"
            "[Console]::Out.WriteLine('.');[Console]::Out.Flush()}"
        )
        t = self.powershell(script, stdin=True)
        t.npc, t.pending, t.texts, t.sync = npc, 0, [], True

        def started(proc=t):  # the character's bubble starts exactly when his voice does
            if proc.texts and proc.npc:
                self.world_send(cmd="say_start", who=proc.npc, text=proc.texts.pop(0))

        def finished(proc=t):
            proc.pending = max(0, proc.pending - 1)
            if proc.npc:
                self.world_send(cmd="say_end", who=proc.npc)

        def reader(proc=t, root=self.root):  # "S" = a sentence started, "." = it finished
            for line in proc.stdout:
                if line.strip() == b"S":
                    root.after(0, started)
                elif line.strip() == b".":
                    root.after(0, finished)

        threading.Thread(target=reader, daemon=True).start()

        def err_reader(proc=t):  # voice errors used to vanish; now they land in chat-debug.log
            for line in proc.stderr:
                if line.strip():
                    self.debug("tts error: " + line.decode("utf-8", "replace"))
            self.debug(f"tts process ended (code {proc.poll()})")

        threading.Thread(target=err_reader, daemon=True).start()
        lane.tts = t
        return t

    def enqueue_speech(self, sentence, lane):
        """Speak a finished sentence as soon as the previous one ends."""
        text = re.sub(r"```.*?```", " code block. ", sentence, flags=re.S)
        text = re.sub(r"[`*#_>|]", "", text).strip()
        if not text or lane.muted:
            return
        import base64
        t = self.ensure_tts(lane)
        if lane.npc_turn:  # the world shows it in a chat bubble when his voice reaches it (see started())
            t.texts.append(text)
        t.pending += 1
        if not lane.spoken_early and lane.busy:
            self.debug(f"timing: first sentence to the voice {time.time() - lane.busy_since:.2f}s after sending")
        lane.spoken_early = True
        try:
            t.stdin.write((base64.b64encode(text.encode("utf-8")).decode() + "\n").encode())
            t.stdin.flush()
        except OSError:
            t.pending = max(0, t.pending - 1)

    def flash_dot(self):
        self.flash_until = time.time() + 1.5  # green dot: your words were heard

    def debug(self, message):
        """Append a line to chat-debug.log (next to this file) so problems can be looked into afterwards."""
        try:
            with open(CHAT_LOG, "a", encoding="utf-8") as f:
                f.write(time.strftime("%H:%M:%S ") + message.rstrip() + "\n")
        except OSError:
            pass

    def status_tick(self):
        """Runs ten times a second. One error here must never stop the loop (it drives the signal,
        the hands-free listening and the world's status text), so errors are logged and it carries on."""
        if not self.alive:
            return
        try:
            self._status_tick()
        except Exception:
            self.debug("status_tick error:\n" + traceback.format_exc())
        self.root.after(100, self.status_tick)

    def _status_tick(self):
        """Top-left signal. Nothing showing means nothing is happening."""
        for lane in self.lanes.values():
            if lane.busy and time.time() - lane.busy_since > 240:  # a stuck reply must not block everything
                self.debug(f"watchdog: {lane.name} busy for over 4 minutes, resetting")
                lane.busy = False
                lane.stream_done = True
                if lane.name == "main":
                    self.entry.configure(state="normal")
        # a hands-free recording or its transcription that hangs would block all later listening
        if (self.listening and self.auto and time.time() - getattr(self, "listen_since", time.time()) > 40):
            self.debug("watchdog: hands-free listening stuck for 40 s, resetting")
            self.gen += 1
            self.listening = False
            self.indicate(False)
            if self.worker:
                self.worker.kill()
                self.worker = None
        spin = "◐◓◑◒"[int(time.time() * 8) % 4]
        if self.listening and not self.finish:
            shown = ("●", "#ff4d4d")  # red: recording you
        elif self.listening or self.busy:
            shown = (spin, "#ffd24d")  # yellow spinner: transcribing, or Claude is working
        elif self.speaking():
            shown = ("♪", "#5db3ff")  # blue note: talking
        elif time.time() < self.flash_until:
            shown = ("●", "#4dff88")  # green: heard you
        else:
            shown = None
        if shown:
            self.dot.configure(text=shown[0], fg=shown[1])
            self.dot.place(x=10, y=4)
            self.dot.lift()
        else:
            self.dot.place_forget()
        # The signal on the world's own screen (this window is hidden while you're there). The text at the top
        # is only for the assistant (you talking to me); Barnaby shows his state above his own head instead.
        main = self.lanes["main"]
        near_lane = self.lane_for(self.near_who) if self.near_npc else None
        recording = self.listening and not self.finish
        transcribing = self.listening and self.finish
        flash = time.time() < self.flash_until
        if recording and not self.auto:
            label = "listening"
        elif (transcribing and not self.auto) or main.busy:
            label = "thinking..."
        elif self.speaking(main):
            label = "speaking"
        elif flash and not self.flash_npc:
            label = "heard you"
        else:
            label = ""
        if self.world and self.world.ready:
            if label != self.world_status:
                self.world_status = label
                self.world_send(cmd="status", text=label)
            for who in ("barnaby", "marigold"):  # each character's own symbol above their head
                lane = self.lane_for(who)
                mine = self.auto and self.auto_who == who
                if recording and mine:
                    state = "listening"
                elif (transcribing and mine) or lane.busy or (flash and self.flash_npc and mine
                                                              and not self.speaking(lane)):
                    state = "thinking"
                else:
                    state = ""
                if self.npc_states.get(who) != state:
                    self.npc_states[who] = state
                    self.world_send(cmd="npc_state", who=who, state=state)
        # Standing next to a character: listen without any button; walk away: stop.
        main_lane = self.lanes["main"]
        if (near_lane and not self.listening and not near_lane.busy and self.speaking(main_lane)
                and not any(self.speaking(l) for l in self.lanes.values() if l is not main_lane)):
            # You walked up to someone while I'm reading an answer aloud: I go quiet (the text keeps coming in
            # the chat) so they can listen to you, instead of waiting until I'm done.
            self.debug(f"muting the assistant's voice to listen near {self.near_who}")
            self.stop_speaking(main_lane)
        if (near_lane and not self.listening and not near_lane.busy and not self.speaking()
                and self.claude):
            self.debug(f"start hands-free listening near {self.near_who}")
            self.start_listening(auto=True)
        elif not self.near_npc and self.listening and self.auto and not self.heard_speech:
            self.cancel_auto()  # walked away before saying anything; mid-sentence it finishes and sends
        if not self.showing_chat and not (self.world and self.world.poll() is None):  # world window was closed: come back
            self.show_chat()
        # note why hands-free listening is not running while standing next to someone (for debugging)
        why = ""
        if self.near_npc and not self.listening:
            why = "busy" if near_lane.busy else "speaking" if self.speaking() else ""
        if why != getattr(self, "_why", ""):
            self._why = why
            if why:
                self.debug(f"near {self.near_who} but not listening: {why}")

    def speak(self, text, npc=False, lane=None):
        """Say a whole answer at once (only used when it was not already spoken sentence by sentence)."""
        lane = lane or self.lane_for(npc)
        text = re.sub(r"```.*?```", " code block. ", text, flags=re.S)
        text = re.sub(r"[`*#_>|]", "", text).strip()
        if npc:
            text = text.removeprefix(f"{NPCS[npc]['name']}:").strip()  # don't read the name label aloud
        if not text:
            return
        if npc:
            self.world_send(cmd="say", who=npc, text=text)
        lane.last_speech = text
        if not USE_EDGE_TTS or npc:
            self.speak_sapi(text, npc, lane)
            return
        lane.speaker = subprocess.Popen(
            [sys.executable, "-c", TTS_SCRIPT],
            stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            text=True, encoding="utf-8",
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )

        def feed(proc=lane.speaker):
            try:
                proc.stdin.write(text)
                proc.stdin.close()
            except OSError:
                pass

        threading.Thread(target=feed, daemon=True).start()
        self.root.after(200, self.check_speaker, lane)

    def speak_sapi(self, text, npc=False, lane=None):
        """The robotic Windows voice. The character gets a different installed voice, a bit slower."""
        lane = lane or self.lane_for(npc)
        script = (
            "Add-Type -AssemblyName System.Speech;"
            "$s=New-Object System.Speech.Synthesis.SpeechSynthesizer;"
            + self.sapi_voice(npc) +
            "$s.Speak([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%s')))"
        )
        import base64
        b64 = base64.b64encode(text[:6000].encode("utf-8")).decode()
        lane.speaker = self.powershell(script % b64)
        self.root.after(200, self.check_speaker, lane)

    def check_speaker(self, lane):
        proc = lane.speaker
        if proc and proc.poll() is None:
            self.root.after(200, self.check_speaker, lane)
            return
        lane.speaker = None
        # edge-tts failed on its own (not stopped by a button): use the offline voice.
        if proc and proc.returncode not in (0, None) and proc.args[0] == sys.executable:
            self.speak_sapi(lane.last_speech, lane.npc_turn, lane)

    def stop_speaking(self, lane=None):
        """Silence one lane, or every lane when none is given."""
        for one in [lane] if lane else self.lanes.values():
            if one.default_who:
                self.world_send(cmd="say", who=one.npc_turn or one.default_who, text="")  # clears the chat bubble
            if one.speaker:
                one.speaker.kill()
                one.speaker = None
            if one.tts:  # also throws away any sentences still waiting to be spoken
                one.tts.kill()
                one.tts = None
            one.muted = one.busy  # if the answer is still arriving, don't start speaking the rest

    def send(self, _event=None):
        """Enter in the text box: a typed message for the assistant (Barnaby may be busy meanwhile)."""
        prompt = self.entry.get().strip()
        if not prompt or not self.claude:
            return
        self.entry.delete(0, "end")
        self.submit(prompt)

    def mic_test(self):
        """/mic: which microphone is used, how loud it hears you (talk for 4 seconds), and which speech model
        is loaded. For finding out why speech is not picked up well."""
        say = lambda text, tag="you": self.root.after(0, self.write, text, tag)
        try:
            import numpy as np
            import sounddevice as sd
            device = sd.query_devices(kind="input")
            say(f"[mic test: using \"{device['name']}\" (the Windows default). Say something for 4 seconds...]\n\n")
            audio = sd.rec(int(4 * 16000), samplerate=16000, channels=1, dtype="float32")
            sd.wait()
            blocks = audio[: len(audio) // 1600 * 1600].reshape(-1, 1600)
            levels = np.sqrt((blocks ** 2).mean(axis=1))
            quiet, loud = float(np.percentile(levels, 10)), float(levels.max())
            # hands-free listening starts when a block is louder than max(0.012, 3 x the background)
            needed = max(0.012, quiet * 3)
            verdict = ("good: your voice is well above what hands-free listening needs" if loud > needed * 2 else
                       "borderline: hands-free listening may miss you; speak up or raise the mic volume" if loud > needed else
                       "too quiet: hands-free listening won't hear you; raise the mic volume in Windows sound settings")
            worker = getattr(self.worker, "device", "") if self.worker else ""
            model = {"cuda": "large-v3-turbo on the GPU", "cpu": "small.en on the CPU"}.get(worker, "not loaded yet (still starting or downloading)")
            say(f"[mic test: background {quiet:.4f}, your voice up to {loud:.4f}, needed {needed:.4f} -> {verdict}. "
                f"Speech model: {model}.]\n\n")
        except Exception as e:
            say(f"[mic test failed: {type(e).__name__}: {e}]\n\n", "err")

    def mouse_test(self, ticks=100, seen=None):
        """Report the key code of anything pressed for ~10s, to find a button's real code."""
        if seen is None:
            seen = set()
            self.write("[mouse test: press the button you want, within 10 seconds]\n\n", "you")
        if ticks <= 0:
            self.write("[mouse test done]\n\n", "you")
            return
        get = ctypes.windll.user32.GetAsyncKeyState
        for vk in range(1, 255):
            if vk not in (0x01, 0x0D) and vk not in seen and get(vk) & 0x8000:
                seen.add(vk)
                self.write(f"[pressed code 0x{vk:02X}]\n\n", "you")
        self.root.after(100, self.mouse_test, ticks - 1, seen)

    def submit(self, prompt, voice=False, npc=False, label=None):
        """Send a message: to a character (npc = "barnaby" ...) in the right-hand lane, otherwise to the
        assistant in the left-hand one. The two lanes run independently."""
        if prompt == "/mousetest":
            self.mouse_test()
            return
        if prompt == "/mic":
            threading.Thread(target=self.mic_test, daemon=True).start()
            return
        if prompt == "/closeworld":
            self.close_world()
            return
        if prompt == "/center":
            self.world_send(cmd="teleport")
            return
        if not self.claude:
            return
        if prompt == "/new":
            if self.busy:
                return
            self.kill_procs()
            self.session_id = self.npc_session_id = self.builder_session_id = self.marigold_session_id = None
            for one in self.lanes.values():
                one.history = []
                one.log.configure(state="normal")
                one.log.delete("1.0", "end")
                one.log.configure(state="disabled")
            self.save_state()
            return
        if prompt.split()[0] == "/model":
            args = prompt.split()[1:]
            if args:
                self.model = args[0]
            self.write(f"Model: {self.model}\n\n", "you")
            return
        lane = self.lane_for(npc)
        if lane.busy:
            if lane.name == "main" and not label:  # the assistant is busy: line it up for afterwards
                self.jobs.append({"text": prompt, "voice": voice, "title": self.job_title(prompt)})
                self.write(f"> {prompt}\n[queued: #{len(self.jobs)}]\n\n", "you", lane)
                self.refresh_jobs()
            return
        if lane.name == "main" and not label:
            self.job_now = self.job_title(prompt)
            self.refresh_jobs()
        self.write(f"> {label or prompt}\n\n", "you", lane)
        self.save_state()
        lane.voice_turn = voice
        lane.npc_turn = npc
        lane.spoken_early = False
        lane.muted = False
        lane.cancelled = False
        lane.reply = []
        lane.event_turn = label is not None  # a world event (not something you said)
        if voice:
            self.ensure_tts(lane)  # start the voice process now so it's ready for the first sentence
        lane.busy = True
        lane.busy_since = time.time()
        threading.Thread(target=self.ask, args=(prompt, lane), daemon=True).start()

    def kill_procs(self):
        for proc in self.procs.values():
            if proc and proc.poll() is None:
                proc.kill()
        self.procs = {}

    def proc_for(self, kind):
        with self.proc_lock:  # the warm-up thread and a real message must not both start one
            return self._proc_for(kind)

    def _proc_for(self, kind):
        """The long-running claude process for one of three jobs, started on demand:
        "main" = me, "npc" = Barnaby chatting (Haiku, fastest), "builder" = Sonnet, which Barnaby
        hands requests to when they're too big for him. Keeping them alive between messages
        skips the multi-second startup each time."""
        name = kind
        model = {"npc": "haiku", "npc2": "haiku", "builder": "sonnet"}.get(kind, self.model)
        # the character processes ("npc" = Barnaby, "npc2" = Marigold) and the helper each have a fixed
        # persona/instructions, which only apply to a conversation when it starts
        persona = {"npc": NPC_PERSONA, "npc2": MARIGOLD_PERSONA, "builder": SYSTEM_PROMPT + BUILDER_NOTE}.get(kind)
        if persona:  # the setup version is part of the signature: changing it starts the session fresh
            persona += PROC_SETUP_VERSION
        cmd = [self.claude, "-p", "--model", model,
               "--input-format", "stream-json", "--output-format", "stream-json",
               "--verbose", "--include-partial-messages"]
        if kind in ("npc", "npc2"):
            # The characters only talk, so they get ONLY their persona as the system prompt, no tools, no
            # skills and no connected apps: ~1k tokens of context instead of ~33k of coding-assistant
            # instructions, which makes their first answer quicker and uses far less of the plan.
            # No extended thinking either: for a line or two of chat it only adds delay (first words in
            # ~0.5 s instead of ~1.4 s).
            cmd += ["--strict-mcp-config", "--tools", "", "--disable-slash-commands",
                    "--settings", '{"alwaysThinkingEnabled": false}',
                    "--system-prompt", persona.removesuffix(PROC_SETUP_VERSION)]
        else:
            cmd += ["--permission-mode", "acceptEdits",
                    "--allowedTools", "Bash(pip install:*)", "Bash(python -m pip install:*)",
                    "PowerShell(pip install:*)", "PowerShell(python -m pip install:*)"]
            if kind == "builder":  # only the tools it needs to change the world
                cmd += ["--strict-mcp-config", "--tools", "Read,Edit,Write,Glob,Grep,Bash,PowerShell",
                        "--disable-slash-commands", "--append-system-prompt", SYSTEM_PROMPT + BUILDER_NOTE]
            else:
                cmd += ["--append-system-prompt", SYSTEM_PROMPT]
        sig = tuple(cmd)  # if the settings change (e.g. /model), restart the process
        if persona:  # instructions changed: a still-running process is stale too
            if self.persona_sigs.get(kind) != persona:
                stale = self.procs.pop(name, None)
                if stale and stale.poll() is None:
                    stale.kill()
        proc = self.procs.get(name)
        if proc and proc.poll() is None and getattr(proc, "sig", None) == sig:
            return proc
        if proc and proc.poll() is None:
            proc.kill()
        # A resumed session keeps its OLD system prompt, so if the persona or instructions changed
        # (e.g. Barnaby gained the handoff), start that character's conversation fresh.
        if persona and self.persona_sigs.get(kind) != persona:
            self.persona_sigs[kind] = persona
            if kind == "npc":
                self.npc_session_id = None
            elif kind == "npc2":
                self.marigold_session_id = None
            else:
                self.builder_session_id = None
        sid = {"npc": self.npc_session_id, "npc2": self.marigold_session_id,
               "builder": self.builder_session_id}.get(kind, self.session_id)
        if sid:
            cmd += ["--resume", sid]  # carry the conversation over to the new process
        env = {**os.environ, "MAX_THINKING_TOKENS": "0"} if kind in ("npc", "npc2") else None
        proc = subprocess.Popen(
            cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, encoding="utf-8", cwd=HERE, env=env,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        proc.sig = sig
        self.procs[name] = proc
        return proc

    def ask(self, prompt, lane):
        npc = lane.npc_turn  # False, "barnaby" or "marigold"
        lane.queue = deque()  # characters waiting to be typed out
        if npc:
            lane.queue.extend(f"{NPCS[npc]['name']}: ")
        lane.stream_done = False
        self.root.after(0, self.pump, lane)
        done = []  # commands already run because the user said one of their trigger phrases
        try:
            if npc == "barnaby":  # his current command list goes with every message, so new commands work at once
                try:
                    with open(COMMANDS_FILE, encoding="utf-8") as f:
                        commands = f.read().strip()
                except OSError:
                    commands = ""
                # Commands with a "| when: phrase, phrase" list run the moment you say one of the phrases,
                # without waiting for the model to decide.
                done = []
                for line in commands.splitlines():
                    m = re.match(r"\s*\[([^\]]+)\].*\|\s*when:\s*(.+)$", line)
                    if m and any(p.strip() and re.search(r"\b" + re.escape(p.strip()) + r"\b", prompt, re.I)
                                 for p in m.group(2).split(",")):  # whole words: "fish" is not "fisherman"
                        done.append(m.group(1).strip().lower())
                        self.root.after(0, self.run_action, done[-1])
                note = ""
                if done:
                    note = (f"\n(The command(s) [{'] ['.join(done)}] were already carried out for the user. "
                            "Just answer in character in one short line, and do not start with a command.)")
                seen = self.npc_sights.get("barnaby", "")
                sight = (f"What you can see around you right now (only mention what is listed, "
                         f"never invent scenery): {seen}\n\n" if seen else "")
                rule = ("Never say you can't do something. If none of the listed commands does what the user asks, "
                        "including asking you to fix, change, improve or add to anything in the world, start "
                        "your reply with exactly [ask sonnet].\n\n")
                static = self.only_if_new("npc", f"Commands you can use right now:\n{commands}\n\n{rule}", lane)
                sent = f"{sight}{static}The user says: {prompt}{note}"
            elif npc == "marigold":  # her quests, and which ones she has already given, go with every message
                seen = self.npc_sights.get("marigold", "")
                sight = (f"What you can see around you right now (only mention what is listed, "
                         f"never invent scenery): {seen}\n\n" if seen else "")
                given = ", ".join(q["id"] for q in self.quests if q.get("giver") == "Marigold") or "none"
                try:  # her other commands (throw Barnaby, ...), with the same instant "when:" phrases as his
                    with open(MARIGOLD_COMMANDS_FILE, encoding="utf-8") as f:
                        m_commands = f.read().strip()
                except OSError:
                    m_commands = ""
                done = []
                for line in m_commands.splitlines():
                    m = re.match(r"\s*\[([^\]]+)\].*\|\s*when:\s*(.+)$", line)
                    if m and any(p.strip() and re.search(r"\b" + re.escape(p.strip()) + r"\b", prompt, re.I)
                                 for p in m.group(2).split(",")):  # whole words only
                        done.append(m.group(1).strip().lower())
                        self.root.after(0, self.run_action, done[-1])
                note = ""
                if done:
                    note = (f"\n(The command(s) [{'] ['.join(done)}] were already carried out. Just answer in "
                            "character in one short line, and do not start with a command.)")
                static = self.only_if_new("npc2", (
                    f"Quests you can give right now:\n{MARIGOLD_QUESTS}\n\n"
                    f"Other commands you can use (start your reply with one in square brackets to do it):\n"
                    f"{m_commands}\n\n"
                    "If the user asks for something one of these commands does, do it right away and play "
                    "along cheerfully (it's all in good fun and Barnaby is a good sport): never refuse it in "
                    "words and never hand it to a helper.\n\n"), lane)
                sent = (f"{sight}{static}Quests you have already given (never repeat these): {given}\n\n"
                        f"The user says: {prompt}{note}")
            else:
                sent = prompt
            kind = NPCS[npc]["kind"] if npc else "main"
            handoff = self.turn(sent, kind, lane)
            if npc and lane.pending_static and lane.last_turn_ok:  # this conversation now holds that text
                self.sent_static[kind] = [getattr(self, SESSION_ATTRS[kind]), lane.pending_static]
            lane.pending_static = None
            if lane.cancelled:
                lane.stream_done = True
                return
            if npc and not handoff and REFUSAL.search(lane.last_npc_reply or ""):
                handoff = True  # he said "can't help with that" instead of passing it on: pass it on anyway
            elif (npc and not handoff and not lane.last_acted and not done and not lane.event_turn
                  and BUILD_REQUEST.search(prompt)):
                # They answered a request to build or change something with chat only (no command, no
                # handoff), e.g. "I'll see what I can do": so nothing would ever happen. Pass it on anyway.
                self.debug(f"auto handoff for: {prompt!r}")
                handoff = True
            if handoff and npc:  # [ask sonnet]: Sonnet does the real work, answering as that character
                who_name = NPCS[npc]["name"]
                lane.queue.extend(f"\n\n{who_name}: ")
                self.turn(f'The user said to {who_name}: "{prompt}"', "builder", lane)
            # A quest was just given: now that the dialogue is done, have Sonnet check, silently, that it
            # can really be done in the world, and build whatever is missing.
            # Every quest not yet checked gets checked (the flag is saved with the quest, so a reload or a
            # failed check can't make one slip through). A quest that truly can't be done is dropped.
            for quest in [q for q in self.quests if q["status"] == "active" and not q.get("checked")]:
                if lane.cancelled or not npc:
                    break
                lane.quiet_reply = ""
                self.turn(self.quest_check_prompt(quest, lane), "builder", lane, quiet=True)
                if lane.cancelled:
                    break
                quest["checked"] = True
                verdict = lane.quiet_reply.strip()
                self.debug(f"quest check {quest['id']}: {verdict[:200]!r}")
                if verdict.lower().startswith("impossible"):
                    reason = verdict.partition(":")[2].strip() or "it can't be done in this world"
                    self.quests.remove(quest)
                    lane.queue.append((f"[quest dropped: {quest['title']} ({reason})]\n\n", "you"))
                    self.root.after(0, self.refresh_quests)
                self.root.after(0, self.save_state)
        except Exception as e:
            self.debug("ask failed:\n" + traceback.format_exc())
            if npc:
                lane.queue.extend(random.choice(NPC_UNCLEAR))
            else:
                lane.queue.append((f"{type(e).__name__}: {e}", "err"))
        lane.stream_done = True

    def only_if_new(self, kind, text, lane):
        """A character's command list and rules are the same for many messages in a row. Sending them every
        time made their conversation grow by ~1.5k tokens per message, so they go along only when they
        changed or the conversation is new; otherwise a short note points back to them."""
        sig = hashlib.sha1(text.encode("utf-8")).hexdigest()[:16]
        sid = getattr(self, SESSION_ATTRS[kind])
        if sid and list(self.sent_static.get(kind) or []) == [sid, sig]:
            lane.pending_static = None
            return "(Your commands and rules are unchanged: use the latest list you were given.)\n\n"
        lane.pending_static = sig
        return text

    def take_commands(self, text, delay=0):
        """Pull leading [bracket commands] off Barnaby's reply and carry them out in the world (after
        `delay` ms). Returns what is left, whether [ask sonnet] was among them, and how many there were."""
        text, handoff, count = text.lstrip(), False, 0
        while text.startswith("["):
            end = text.find("]")
            if end < 0:  # still arriving
                break
            raw = text[1:end].strip()
            command = raw.lower()
            if command == HANDOFF[1:-1]:
                handoff = True
            else:
                self.root.after(delay, self.run_action, command, raw)
            count += 1
            text = text[end + 1:].lstrip()
        return text, handoff, count

    # --- quests: the tracker, and the check that a quest Barnaby gives can actually be done ---
    def add_quest(self, raw):
        """[quest id | Short title] from Barnaby: add it to the tracker and queue a feasibility check."""
        body = raw[5:].strip()
        qid, _, title = body.partition("|")
        qid = re.sub(r"\W+", "_", qid.strip().lower())[:24] or "quest"
        title = title.strip() or qid.replace("_", " ")
        if any(q["id"] == qid for q in self.quests):
            return
        speaker = next((l.npc_turn for l in (self.lanes["npc2"], self.lanes["npc"]) if l.busy and l.npc_turn), "")
        giver = NPCS.get(speaker, {}).get("name", "Barnaby")  # whoever is answering right now
        # every quest gets checked (and whatever it needs built) after the dialogue
        self.quests.append({"id": qid, "title": title, "status": "active", "giver": giver, "checked": False})
        self.refresh_quests()
        self.save_state()

    def finish_quest(self, qid):
        for q in self.quests:
            if q["id"] == qid and q["status"] != "done":
                q["status"] = "done"
                self.write(f"[quest complete: {q['title']}]\n\n", "you", self.lane_for(q.get("giver", "Barnaby").lower()))
                self.world_send(cmd="notice", text=f"Quest complete: {q['title']}")
        self.refresh_quests()
        self.save_state()

    @staticmethod
    def job_title(prompt):
        """A very short label for a request, for the work list."""
        text = " ".join(prompt.split())
        return text if len(text) <= 38 else text[:37].rsplit(" ", 1)[0] + "…"

    def next_job(self):
        """Start the next queued request. Taken off the queue only now, by the window version that is current
        (a live reload in between hands the queue to the new version, which calls this itself)."""
        if not self.alive or not self.jobs or self.lanes["main"].busy:
            return
        job = self.jobs.pop(0)
        self.submit(job["text"], job["voice"])

    def refresh_jobs(self):
        """Show what the assistant is doing and what is queued behind it (top left of the world)."""
        lines = ([self.job_now] if self.job_now else []) + [j["title"] for j in self.jobs]
        story = getattr(self.root, "story_job", {})
        if story.get("running"):
            lines.append(f"Storyteller: writing chapter {story['chapter'] + 1}")
        self.world_send(cmd="jobs", lines=lines)

    # --- the storyteller: writes the next chapter of the main story when one ends (scene/story.gd) ---
    def start_storyteller(self, chapter):
        """Kept on the window itself (self.root), so a live reload of this file doesn't lose track of it."""
        job = getattr(self.root, "story_job", None) or {"running": False, "tries": {}}
        self.root.story_job = job
        try:  # already written (the world re-asks after a reload)?
            with open(os.path.join(STORY_DIR, "chapter.json"), encoding="utf-8") as f:
                if int(json.load(f).get("chapter", 0)) > chapter:
                    return
        except (OSError, ValueError):
            pass
        if job["running"] or not self.claude or job["tries"].get(chapter, 0) >= 2:
            return
        job.update(running=True, chapter=chapter)
        job["tries"][chapter] = job["tries"].get(chapter, 0) + 1
        self.debug(f"storyteller: writing chapter {chapter + 1}")
        self.refresh_jobs()
        threading.Thread(target=self.run_storyteller, args=(job, chapter), daemon=True).start()

    def run_storyteller(self, job, chapter):
        prompt = (f"Chapter {chapter} of the story just ended. Read godot_world/story/log.md and the rest as described, "
                  f"then write chapter {chapter + 1} and build it into the world.")
        cmd = [self.claude, "-p", "--model", "sonnet", "--output-format", "json",
               "--permission-mode", "acceptEdits", "--strict-mcp-config",
               "--tools", "Read,Edit,Write,Glob,Grep", "--disable-slash-commands",
               "--append-system-prompt", SYSTEM_PROMPT + STORYTELLER_NOTE]
        summary = ""
        try:
            done = subprocess.run(cmd, input=prompt, capture_output=True, text=True, encoding="utf-8",
                                  cwd=HERE, timeout=1500,
                                  creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            try:
                summary = json.loads(done.stdout).get("result", "")
            except ValueError:
                summary = (done.stdout or done.stderr or "")[-300:]
        except Exception as e:
            summary = f"{type(e).__name__}: {e}"
        self.debug(f"storyteller finished chapter {chapter + 1}: {summary[:300]!r}")
        job["running"] = False
        try:  # the world shows the new chapter by itself once chapter.json is written
            with open(os.path.join(STORY_DIR, "chapter.json"), encoding="utf-8") as f:
                ok = int(json.load(f).get("chapter", 0)) > chapter
        except (OSError, ValueError):
            ok = False
        if not ok:
            self.world_send(cmd="notice", text="The storyteller stumbled. It will try again shortly.")
            self.debug("storyteller: no new chapter.json was written")
        app = getattr(self.root, "chat_app", self)  # (the window may have live-reloaded meanwhile)
        self.root.after(0, app.refresh_jobs)
        if not ok:
            self.root.after(20000, app.start_storyteller, chapter)

    def refresh_quests(self):
        """Show the active quests on the chat's top bar and on the world's screen."""
        open_quests = [q for q in self.quests if q["status"] == "active"]
        active = [q["title"] for q in open_quests]
        text = ("Quest: " + active[0] + (f"  (+{len(active) - 1} more)" if len(active) > 1 else "")) if active else ""
        self.quest_label.configure(text=text)
        self.world_send(cmd="quests", lines=active, ids=[q["id"] for q in open_quests],
                        done=[q["id"] for q in self.quests if q["status"] == "done"])

    def quest_check_prompt(self, quest, lane):
        return (
            f'{quest.get("giver", "Barnaby")} just gave the user a quest: "{quest["title"]}" '
            f'(id: {quest["id"]}). Their words were: '
            f'"{lane.last_npc_reply.strip()}". Assume the quest is NOT doable until you have verified it in the '
            "code: read the parts in godot_world/scene/ and check every requirement of the quest one by one (the items, creatures or "
            "places it mentions actually exist in the world and the user can reach and interact with them, and "
            "there is code that notices the quest being completed). Whatever is missing, build it in a part in godot_world/scene/ "
            "(and add it to Barnaby's describe()), and make the part call "
            f'W.send({{"t": "quest_done", "id": "{quest["id"]}"}}) the moment the user completes it (plus '
            'W.show_notice(text) for short on-screen hints). Prefer building what is missing over '
            "giving up. Reply with exactly the word \"ok\" once the quest is truly doable, or, only if it cannot "
            "be made doable in this world at all, with \"impossible: <short reason>\". Nothing else."
        )

    def run_action(self, command, raw=None):
        """One of Barnaby's world commands, e.g. "spawn box blue", sent straight to the running world."""
        words = command.split()
        if not words:
            return
        if words[0] == "quest":
            self.add_quest(raw or command)
        elif words[0] == "spawn":
            self.world_send(cmd="spawn", shape=words[1] if len(words) > 1 else "box",
                            color=words[2] if len(words) > 2 else "white")
        elif words[0] == "remove":
            self.world_send(cmd="remove")
        elif words[0] == "sky":
            self.world_send(cmd="sky", color=" ".join(words[1:]) or "day")
        elif words[0] in ("teleport", "center"):
            self.world_send(cmd="teleport")
        else:  # a command Sonnet taught him: a part's handle() in godot_world/scene/ decides what it does
            self.world_send(cmd=words[0], args=words[1:])

    def turn(self, prompt, kind, lane, quiet=False):
        lane.last_turn_ok = False
        lane.active.add(kind)
        try:
            if kind == "builder":  # both characters share the one helper process: take turns
                with self.builder_lock:
                    return self._turn(prompt, kind, lane, quiet)
            return self._turn(prompt, kind, lane, quiet)
        finally:
            lane.active.discard(kind)

    def _turn(self, prompt, kind, lane, quiet=False):
        """One question and answer with the given process. Streams the answer into the lane's typing
        queue and voice (unless quiet). Returns True if Barnaby handed the request over to Sonnet."""
        in_character = kind in ("npc", "npc2", "builder")
        streamed, got, result, buf, context = False, [], None, "", 0
        # Barnaby may start with commands like [spawn box blue] or the [ask sonnet] handoff
        head, head_done, handoff, acted = "", kind == "main" or quiet, False, 0

        def emit(text):
            nonlocal streamed, buf
            if quiet and text:
                lane.quiet_reply += text  # the quest check's verdict ("ok" / "impossible: ...")
            if not text or quiet or lane.cancelled:
                return
            if not got:
                self.debug(f"timing: {kind} first words {time.time() - lane.busy_since:.2f}s after sending")
            lane.queue.extend(text)
            got.append(text)
            streamed = True
            buf += text
            # speak each sentence the moment it is complete, not the whole answer
            while lane.voice_turn:
                m = SENTENCE_END.search(buf, 15)  # at least ~15 chars, so no lone "Aye."
                if not m:
                    break
                self.root.after(0, self.enqueue_speech, buf[:m.end()], lane)
                buf = buf[m.end():]

        for _ in range(2):  # a second try if the process had died
            if lane.cancelled:
                return False
            proc = self.proc_for(kind)
            message = {"type": "user", "message": {"role": "user",
                                                   "content": [{"type": "text", "text": prompt}]}}
            try:
                proc.stdin.write(json.dumps(message) + "\n")
                proc.stdin.flush()
            except OSError:
                self.procs.pop(kind, None)
                continue
            while True:
                line = proc.stdout.readline()
                if not line:  # process ended before finishing its answer
                    break
                try:
                    data = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if data.get("type") == "stream_event":
                    event = data.get("event", {})
                    if event.get("type") == "content_block_start" and streamed:
                        lane.queue.extend("\n\n")  # next text block after a tool call
                    delta = event.get("delta", {})
                    if delta.get("type") == "text_delta":
                        text = delta.get("text", "")
                        if not head_done:
                            # Sonnet's commands wait ~2s so the world has reloaded what it just wrote
                            head, found, count = self.take_commands(head + text, 2000 if kind == "builder" else 0)
                            handoff, acted = handoff or found, acted + count
                            if head.startswith("[") and len(head) < 80:
                                continue  # a command is still arriving
                            head_done, text = True, head
                        emit(text)
                elif data.get("type") == "assistant":
                    usage = data.get("message", {}).get("usage") or {}
                    if usage:
                        context = (usage.get("input_tokens", 0) + usage.get("cache_read_input_tokens", 0)
                                   + usage.get("cache_creation_input_tokens", 0))
                elif data.get("type") == "result":
                    result = data
                    break  # the process stays open for the next message
            if lane.cancelled:
                return False  # killed on purpose: no retry, no error message
            if result or got or head:
                break
            proc.kill()
            self.procs.pop(kind, None)
        if not head_done and head:  # the reply ended while it still looked like a command
            emit(head)
        if buf.strip() and lane.voice_turn:  # speak whatever is left of the answer
            self.root.after(0, self.enqueue_speech, buf, lane)
        if result:
            lane.last_turn_ok = not result.get("is_error")
            sid = result.get("session_id")
            if sid and kind == "npc":
                self.npc_session_id = sid
            elif sid and kind == "npc2":
                self.marigold_session_id = sid
            elif sid and kind == "builder":
                self.builder_session_id = sid
            elif sid:
                self.session_id = sid
            if context > CONTEXT_LIMIT:  # too big to stay fast: the next message starts fresh
                self.forget_session(kind)
            if kind in ("npc", "npc2"):
                lane.last_npc_reply = "".join(got)
                lane.last_acted = acted
            if quiet:
                pass
            elif result.get("is_error") or not (streamed or handoff or acted):
                lane.queue.append((result.get("result") or "No reply.", "err" if result.get("is_error") else None))
        elif quiet:
            pass
        elif in_character:  # stay in character even when something broke
            lane.queue.extend(random.choice(NPC_UNCLEAR))
        else:
            lane.queue.append(("Claude stopped responding.", "err"))
        return handoff

    def pump(self, lane):
        """Type a lane's queued characters out a few at a time; faster when lots are waiting."""
        if not self.alive:
            return
        for _ in range(max(1, len(lane.queue) // 40)):
            if not lane.queue:
                break
            item = lane.queue.popleft()
            if isinstance(item, tuple):  # whole message (errors), written at once
                self.write(item[0], item[1], lane)
            else:
                self.write(item, None, lane)
                lane.reply.append(item)
        if lane.queue or not lane.stream_done:
            self.root.after(12, self.pump, lane)
        else:
            self.done(lane)

    def done(self, lane):
        self.write("\n\n", None, lane)
        lane.busy = False
        self.save_state()
        if lane.name == "main":
            self.entry.focus_set()
            self.job_now = ""
            if self.jobs:  # next one in the queue
                self.root.after(300, self.next_job)
            self.refresh_jobs()
        if lane.voice_turn and not lane.spoken_early and not lane.muted:
            self.speak("".join(lane.reply), npc=lane.npc_turn, lane=lane)

class _GUID(ctypes.Structure):
    _fields_ = [("d1", ctypes.c_uint32), ("d2", ctypes.c_uint16), ("d3", ctypes.c_uint16), ("d4", ctypes.c_ubyte * 8)]

    def __init__(self, text):
        h = text.replace("-", "")
        super().__init__(int(h[:8], 16), int(h[8:12], 16), int(h[12:16], 16),
                         (ctypes.c_ubyte * 8)(*bytes.fromhex(h[16:])))


class _PROPKEY(ctypes.Structure):
    _fields_ = [("fmtid", _GUID), ("pid", ctypes.c_uint32)]


class _PROPVARIANT(ctypes.Structure):  # only the VT_LPWSTR form; padded to the full 24 bytes
    _fields_ = [("vt", ctypes.c_ushort), ("r1", ctypes.c_ushort), ("r2", ctypes.c_ushort), ("r3", ctypes.c_ushort),
                ("text", ctypes.c_wchar_p), ("pad", ctypes.c_void_p)]


def taskbar_identity(root):
    """Give the window its own taskbar identity with a relaunch command, so "Pin to taskbar" on the running
    app pins Claude Chat itself (without this the pin is plain pythonw.exe, which opens nothing)."""
    try:
        app_id = "ClaudeChat.App"
        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(ctypes.c_wchar_p(app_id))
        root.update_idletasks()
        hwnd = int(root.wm_frame(), 16)
        exe = sys.executable
        if exe.lower().endswith("python.exe"):  # relaunch without a console window
            exe = exe[:-len("python.exe")] + "pythonw.exe"
        store = ctypes.c_void_p()
        iid = _GUID("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")  # IPropertyStore
        if ctypes.windll.shell32.SHGetPropertyStoreForWindow(ctypes.c_void_p(hwnd), ctypes.byref(iid),
                                                             ctypes.byref(store)) != 0:
            return
        vtbl = ctypes.cast(ctypes.cast(store, ctypes.POINTER(ctypes.c_void_p))[0], ctypes.POINTER(ctypes.c_void_p))
        set_value = ctypes.WINFUNCTYPE(ctypes.c_long, ctypes.c_void_p, ctypes.POINTER(_PROPKEY),
                                       ctypes.POINTER(_PROPVARIANT))(vtbl[6])
        release = ctypes.WINFUNCTYPE(ctypes.c_ulong, ctypes.c_void_p)(vtbl[2])
        fmt = "9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"
        icon = os.path.join(HERE, "claude-chat.ico")
        props = [(2, f'"{exe}" "{SCRIPT}"'),                              # RelaunchCommand
                 (3, icon if os.path.exists(icon) else exe + ",0"),        # RelaunchIconResource
                 (4, "Claude Chat"),                                       # RelaunchDisplayNameResource
                 (5, app_id)]                                              # ID (set last)
        for pid, text in props:
            set_value(store, ctypes.byref(_PROPKEY(_GUID(fmt), pid)), ctypes.byref(_PROPVARIANT(31, 0, 0, 0, text)))
        release(store)
    except Exception:
        traceback.print_exc()


if __name__ == "__main__":
    root = tk.Tk()
    taskbar_identity(root)
    ChatApp(root)
    root.mainloop()
