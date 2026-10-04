# Project notes

Long-term memory for the Claude running inside chat.pyw. Conversations get reset when they grow too big
(they become very slow), so anything worth remembering across resets goes here. Keep it short: add a line
when you finish a notable feature or learn a preference, and fix lines that become wrong.

## The user's preferences
- Keep replies SHORT. No long explanations, no headings unless really needed.
- Don't add "I haven't tested this" disclaimers; the user knows.
- Voice input is transcribed by Whisper and is often garbled or picks up background audio (games, streams).
  Interpret generously; if it's clearly not meant for you, ask briefly.
- Prefers things to just work: fix root causes, don't make them ask twice.
- Robotic Windows voice (fast) is preferred over edge-tts (USE_EDGE_TTS = False; Sonia kept as an option).
- Doesn't want paid API keys; everything goes through `claude -p` on their plan.
- NPCs must never answer "nothing to do" when asked for a task: they invent their own quest each time (but
  never offer one unasked). This is in NPC_PERSONA / MARIGOLD_PERSONA.
- Model parts (boxes) must never share an exact position or coplanar face: stack them touching, not overlapping, and
  make accessories stand slightly proud of what they sit on. He keeps spotting clipping.
- Happy to start the world from (near) scratch; not attached to old features.

## How the app is built
- chat.pyw: the chat window (tkinter, black). Live-reloads itself in place when edited (no window restart).
  Two lanes (class Lane), each with its own text pane, typing queue, voice and busy flag: "main" (left,
  you and the assistant: typed messages, mouse-5/M recordings) and "npc" (right, you and Barnaby:
  hands-free next to him, plus world events and builder handoffs). They run at the same time, so
  Barnaby answers while the assistant is still working. Turn state lives on the Lane, not on ChatApp.
  Long-running `claude -p` processes per role (stream-json in/out), kept warm between messages:
  - "main" = you, the coding assistant (model chosen with /model).
  - "npc" = Barnaby (and "npc2" = Marigold, not in the world right now): Haiku, persona REPLACES the system
    prompt (--system-prompt), no tools/skills/MCP, no extended thinking (first words ~0.5 s instead
    of ~1.4 s): ~1k tokens of context instead of ~33k. Their command list
    goes along only when it changed (only_if_new); otherwise a short "unchanged" note.
  - "builder" = Sonnet helper that the characters hand requests to with [ask sonnet]; builds in the Godot world.
    Tools limited to Read/Edit/Write/Glob/Grep/Bash/PowerShell.
  Changing these claude flags: bump PROC_SETUP_VERSION so those sessions start fresh (old system prompt sticks).
  Session ids are saved in chat_state.json and resumed with --resume. A resumed session keeps its OLD system
  prompt, so changing a persona starts that character's conversation fresh (persona_sigs).
  Sessions whose context grows past CONTEXT_LIMIT are dropped automatically and start fresh.
  Cancel kills only the processes that are answering; the others stay warm.
- Speech recognition: Whisper large-v3-turbo on the GPU (RTX 4070 SUPER, ~0.2 s per message), loaded at launch
  and kept loaded; falls back to small.en on the CPU (~1.5 s) if CUDA fails. CUDA libs come from the pip
  packages nvidia-cublas-cu12 + nvidia-cudnn-cu12. Bump WHISPER_VERSION when changing WHISPER_WORKER.
- You may run `pip install` yourself; other shell commands are blocked.
- Logs you can read: claude-world.log (world errors + received commands), chat-debug.log (listening, errors).

## The 3D world (Godot 4.7.2, in godot_world/)
- Godot itself: D:\Claude\godot\Godot_v4.7.2-stable_win64.exe. chat.pyw runs godot_bridge.py, which starts
  Godot and passes the chat's JSON lines over a local TCP socket.
- godot_world/world.gd = engine: player (CharacterBody3D), HUD (status top-center, notices top-right, quests
  top-left), show/hide (only chat or world on screen), the link, and helpers for parts: box(), glow(),
  light(), build_model(), mat(), tex(), where(), face(), add_collider(), seen_around(), send(), quest_done()
  (throttled: safe every frame), show_notice(). Editing it swaps the engine in place (reload_engine/take_over: link, player spot, window and ctx carry over; an error keeps the old one). Only godot_bridge.py edits restart the world. Errors in a part name its file
  (res://scene/x.gd:line) in claude-world.log.
- godot_world/scene/*.gd = the world's parts, one file per thing, all rebuilt live when any part or model is
  saved; a file with an error is refused and the old world keeps running. See the top of scene/base.gd for the
  hooks (build, handle, key, seen_from, quest_progress, describe/is_near/npc_id for characters).
  What the characters "see": every part reports itself with seen_from(from, viewer) -> Array of phrases, and
  both characters' describe() use W.seen_around(). A new thing only needs a seen_from() to be noticed.
  Talking (bubble, mouth, "?"/"..." symbol) is the shared Talker in scene/talk.gd, used by both characters.
  - base.gd: night sky panorama (sky_night.png), lighting (moon with shadows, glow, SSAO, distance fog),
    movement settings, placed objects (spawn/remove), sky command.
  - The look is medieval (2026-10-03): terrain.gd = flat grassy meadow (radius 58, ground y = 0 there, which
    everything in the middle relies on) ringed by wooded hills and snowy mountains, dirt roads with lanterns,
    swaying grass, trees/boulders (MultiMesh), fireflies. height_at(x, z) / W.ground_y() give the ground height
    (characters, goblins and placed objects use it). Heavy parts are cached in ctx (bump VERSION to rebuild).
    castle.gd = castle on the levelled hill to the north (walls, towers, gatehouse, keep, banners, torches).
    village.gd = cottages, well, fences, cart to the west, plus the windmill on the eastern hills.
    kit.gd = shared building materials drawn in code (stone, dark_stone, plaster, timber, planks, thatch,
    slate), mapped in world space: kit.mat("stone") or kit.block(W, parent, pos, size, "stone").
    The parkour pads are floating stone slabs with a glowing rune in their colour.
  - animals.gd: sheep in the pasture (-40, 24) and chickens around the village; they graze/peck and shy away.
  - villagers.gd: villagers with step routines ([place, "work"/"idle", seconds]): farmer (wheat field with a
    scarecrow at (-30, -28)), woodcutter (log pile at (-54, -20)), water carrier, shepherd, guards at the castle
    gate and on the south wall. Add a villager = add an entry to plan(). A base for a colony-sim direction.
  - Day and night (base.gd): state["time"] = hour 0..24, a day = DAY_MINUTES (40) real minutes, starts at night.
    A sky shader blends the red-moon panorama into a day sky with sun and dusk colours. ctx["night"] (1 night ..
    0 day) is read by lanterns, torches, windows and fireflies. [sky day/sunset/night/...] sets the time.
- The user hasn't decided the game's core concept yet (maybe a 3D RimWorld-like). Keep additions generic:
  world, life, systems; don't lock in one game loop.
- avatar.gd: first-person body has a stitched green tunic, articulated sleeves/forearms, cuffs and gloves, with the right arm brought forward when the sword is equipped; leg gait and sitting are animated. barnaby.gd: Barnaby Finch (model: models/barnaby.json, 275 textured boxes, textures barnaby_*.png);
    wanders, stops and faces you when near (hands-free listening), commands follow / wander / stay.
- ctx.state is saved to world_state.json (next to chat.pyw) every few seconds and on exit: keep plain values.
- Textures: PNGs next to chat.pyw, loaded at runtime with W.tex() (no Godot import step).
- Test screenshots: run Godot with `-- --shot=<path.png>` to save a picture after 3 s and quit.
- North is -z. Faces/fronts of models point to -z; W.face(node, target) turns a node toward a point.

## Controls
- Tab or the ⇄ button: switch chat / world. Esc frees the mouse, click locks it. F11 fullscreen. R recenter.
- World: WASD, Shift run, Space jump, Ctrl crouch (hold; slower, stays down under low ceilings), mouse look.
- Mouse button 5 or M: record / stop+send / cancel transcription. Mouse button 4 or N: stop speaking.
  (M/N only act in the chat when the text box is empty.)
- Cancel a running request: Esc in the chat, or N / mouse button 4.
- Chat commands: /new, /model haiku|sonnet|opus, /center, /mousetest.
- Standing near Barnaby makes the chat listen hands-free (0.5 s pause ends a sentence).

## History
- 2026-10-02: the world moved from Ursina (Python) to Godot and was restarted from scratch with only Barnaby
  (the user's choice). Gone: Marigold, Fenwick, Jet, the lake, pillars, factories, zeppelins, planes,
  goblins, inventory/hotbar, tea/mushroom/water quests. They can be rebuilt on request.

- Barnaby clipping fixes: arms at x=±0.4 (hands/cuffs were inside the coat skirt and belt, now 0.62 wide), scarf no
  longer coplanar with the collar, face quad 1.5 mm further out, body y=0.021 (boot soles dipped into the ground).
  When textures clip: look for coplanar faces and parts that overlap swinging arms/legs.

- scene/sea.gd: a glowing conch on a rock at (-16, -22) with a light beam; press E near it and the sea rises
  knee-deep over the whole field (wave shader), E again drains it. state["sea"]; the characters are told via its seen_from().
- The speech bubble (talk.gd) is pixel art (SubViewport on a billboard Sprite3D), letters typed out ~1.7x voice
  speed; say_start/say_end from the chat time it to the real voice, say() estimates.

- Bubble sync: the tts PowerShell process prints "S" when a sentence starts and "." when it ends; chat.pyw turns
  those into say_start / say_end for the world (texts queued in t.texts). Barnaby learns his reading speed (cps).
- [look] command: Barnaby turns slowly 360° (mode "look") and is told to say what he sees.

- Three lanes now: "main", "npc" (Barnaby) and "npc2" (Marigold, own text pane, own voice/process); use self.lane_for(who). Both can think/talk at once; the Sonnet helper is shared (builder_lock). Symbols above heads are per character (self.npc_states).

- scene/moonbread.gd: [bread] Marigold gives a glowing loaf in hand; F eats it (30 s glow).

- scene/knockback.gd: gun shots (hotbar.shoot) shove Barnaby/Marigold back, no damage.
- scene/throwmari.gd: [throwmari] Barnaby fetches Marigold, lifts her and flings her to the user (mirror of [throw]).

- scene/parkour.gd: spiral of 44 floating pads east at (40, 5); gets harder with height (smaller pads, wider gaps, bigger
  rises), purple pads slide (section 2 and 4), red pads crumble 0.8 s after landing and return after 3 s (section 3 and 4).

- Parkour checkpoints (pads 11, 22, 33): user suspected an upper one didn't register. No logic bug found; made pad detection more lenient (feet -0.25..+0.5 of top, 0.5 m edge margin) and checkpoint pads 4 m wide.

- Parkour root cause: the player's origin is at its FEET (capsule offset 0.95), so feet = player.position.y. Moving pads now carry the player.

- Work queue: messages to the assistant while it is busy are queued (self.jobs) and sent one after another when it finishes; the world shows "WORKING ON" (current + queued, short titles = first ~38 chars) under the quests, top left (cmd "jobs").

- Conch in hand (sea.gd): a small held conch shows on the camera while state["conch"] == "carried". Bug fixed: Barnaby giving it
  made you "carried" next to him, which instantly handed it back; the hand-over now needs you to walk >6 m away first (armed).

- Whisper often heard "Barnaby" as "Barnabas": the worker now gets an initial_prompt with the names (WHISPER_VERSION 3) and
  heard() rewrites misspellings via NAME_FIXES.

- Barnaby said "wanderer" in nearly every line (the user's complaint): persona now forbids it. (The Barnabas name-fix above was a misreading.)

- Ambient sound (scene/ambience.gd: wind hiss, crickets, birds) is switched off (ENABLED := false) because the user found the noise annoying.

- Non-medieval stuff switched off temporarily (2026-10-03): world.gd DISABLED_PARTS (parkour,
  knockback, sea, conchpolish) and base.gd SHOW_PLACED := false (spawned objects). Files and saved state are untouched; remove
  the names / set true to bring them back.

- scene/fly.gd: [fly] / [land] toggle state["flying"]; world.gd physics then lets Space rise, Ctrl descend, Shift faster.

- scene/todo.gd: to-do book on hotbar slot 9 (key 9, Esc closes). Text lives in todo.txt next to chat.pyw (also state["todo"]); read or edit that file and the book updates within a second. "[x] " prefix = done. Commands [todo add X], [todo done N], [todo remove N], [todo clear]. While it is open ctx["typing"] = the part, and world.gd's _input sends keys only to it.

- Journal reset button restores story/seed.json as chapter.json and resets story flags, character to level 1, 10 gold, 2 potions, rusty sword, no armour, and all quests; it asks for confirmation first.

- Rocket shove: world.gd sets the player's x/z velocity from the keys every frame, so adding to player.velocity.x/z does nothing. Sideways shoves go into W.push (fades out, zeroed on walls); vertical still goes into player.velocity.y (rocket.gd).

## Ideas mentioned but not done
- Zipping the project for the user's laptop (needs Python, `pip install faster-whisper sounddevice`, Godot,
  Claude Code signed in; leave out chat_state.json, world_state.json, logs).
- Goblins (scene/goblins.gd, [goblins] / [goblins away]): harmless ring army, 3 sword hits each. Hotbar + sword in scene/hotbar.gd ([sword] gives; key 1 sword, key 2 rocket when owned).

- barnaby_chat.txt / marigold_chat.txt: plain-text copies of the characters talks, written by save_state(). When the user says "read Barnaby", read barnaby_chat.txt (Marigold: marigold_chat.txt).
- scene/rocket.gd: [rocket] launcher on slot 2 (key 2), rockets explode and shove the user/characters (rocket jump).
- Builder hammer and placed block structures removed; the hotbar is now key 1 sword, key 2 rocket (when owned), key 9 to-do book. Barnaby's [climb] still targets other placed objects.

## Story flags
- troll: slain | appeased (ch.1). camp: bandits | cleared | tolled (ch.2): bandits (kind "bandit", creatures.gd) hold Gorrak's camp (96, 12); build_bandit_camp() draws tents/flag per state; "tolled" bandits are tame.
- barrow: stirring | sealed | laid | bargain (ch.3): creatures.gd build_tomb_marks() dresses the barrow; "stirring" = 11 skeletons + Barrow Wight (kind "wight") at the door, "bargain" = tame wight and 4 tame skeletons, sealed/laid = no dead.

- castle: burnt | ruin | tolled (ch.4): castle.gd build_ruin() (no roofs, soot, rubble, fire/smoke); "burnt" = 8 raiders (kind "raider") in the yard, "tolled" = 4 tame raiders + black banner; guards move to the village (villagers.gd plan_all). Ch.5 idea: rebuild the castle ("rebuilt"), or who moves into the ruin.
- host: camped | broken | gone (ch.5, with castle): "camped" = toll barrier + tents on the north road (creatures.gd build_toll_camp), 3 tame raiders and Varga (kind "captain", hostile) in the yard. Kill him -> castle "ruin", host "broken"; bring 12 ore -> castle "rebuilt" (castle.gd build_rebuilt: timber hoardings, new door, blue pennants; guards return), host "gone". Ch.6 idea: refill the ruin (who moves in), or what the Host's masters do.

- Ch.2 rewritten after the story reset (2026-10-04): start_sets camp=bandits; kill 5 bandits -> cleared, or bring 120 gold to (96, 12) -> tolled. barks.gd has camp=bandits lines.

- Ch.3 after the reset (2026-10-04): reuses the barrow flag (start_sets barrow=stirring; kill wight -> sealed, bring 6 bones -> laid, bring 150 gold -> bargain), framed as the tolled bandits having looted the barrow. barks.gd has an extra stirring line.

- Ch.3 after camp=cleared (2026-10-04): again the barrow flag (start_sets stirring; kill wight -> sealed, 6 bones -> laid, 150 gold -> bargain), framed as blood on the east road waking the dead. No new code needed.

- Ch.4 after barrow=sealed (2026-10-04): reuses the castle flag (start_sets burnt; kill 8 raiders -> ruin, 250 gold at the gate -> tolled). No new code needed.

- Ch.5 after castle=ruin (2026-10-04): "The Captain Returns", reuses host/castle code (start_sets host=camped; kill Varga -> host broken; 12 ore -> castle rebuilt + host gone). No new code needed.

## RPG layer (2026-10-03)
- scene/rpg.gd: level/xp/health/gold, inventory (I), quest journal (J), quest board by the village road (E), the smith's
  shop across the road (E: buy, sell for half), Q drinks a potion, death = wake at the well minus 10% gold. State in
  state["rpg"]. API for other parts: give/take/count/add_xp/add_gold/hurt/event; parts can offer E actions with
  interactables(). Commands [give item n], [xp n], [heal] (Barnaby and Marigold have them).
- scene/creatures.gd: wolf dens (E, S, W woods), the barrow with skeletons (NW), Gorrak the troll's camp (E forest).
  hotbar.gd's sword calls creatures.sword_hit(); damage = weapon + level - 1. Loot drops are picked up by walking over.
- scene/gathering.gd: silverleaf herbs (meadow edge), mushrooms (woods), fractured iron outcrops (three E strikes per exposed seam, two ore each), the
  miller's ring near the windmill (only while that quest is active).
- New quests: add an entry to QUESTS in rpg.gd (kinds kill / bring / find). New items: ITEMS. terrain.keep_clear keeps
  trees out of the camps.

- scene/sounds.gd: code-made sounds: level-up and quest hand-in jingles (rpg.gd sfx()) and a soft wind loop (AMBIENT_DB). ambience.gd stays off.

- Ambient wind removed (user hated it). (The old sounds.gd was removed: music.gd does music and jingles.)
- Music and jingles (scene/music.gd): CC0 medieval tracks in godot_world/music/ (day: Market Day, The Bard's Tale; night: The Old Tower Inn), K toggles; jingles made in code: play_sfx("levelup" | "quest" | "chapter").

## Look and feel (2026-10-03 polish)
- base.gd: ACES tonemap, exposure 0.72, saturation/contrast grading, strong sun + weak fill. Keep colours rich, not pastel.
- terrain.gd ground shader: grass clumps, tiny wildflowers, pebbly roads (vertex colour alpha = road mask).
- world.gd W.mat(): every plain-colour box gets a faint grain texture (object-mapped). W.flag(name) reads story flags.
- style.gd: book-like serif UI font (Windows system font) for all text; ctx["ui_theme"] for HUD panels on CanvasLayers.
- landmarks.gd: nameplates over people, crossroads signpost, place names announced on entry (Thornvale Village,
  Highmoor Castle, the Old Mill, the Barrow of the Old Kings, Wolfwood dens, Gorrak's Camp), and the top compass with
  gold markers for story quest targets.
- gathering.gd: 8 framed, plank-built treasure chests with iron straps, rivets, hinges and a brass keyhole (E, refill after 30 min). creatures.gd: enemies topple and sink, sparks on hits.
- music.gd sounds: play_sfx("swing" | "hit" | "hurt" | "pickup" | "coin" | "levelup" | "quest" | "chapter").
- villagers.gd: hip pivot (body), two-handed hoe/axe strokes, guards in tabards and mail.
- travel.gd: waystones (touch to attune, E to travel; at the crossroads, Thornvale, Highmoor, the Old Mill, the Barrow) and
  a campfire at the crossroads (E: rest, full heal, night skips to morning). weather.gd: random rain showers (state
  "rain" 0..1), [rain] / [rain stop]. The sword in hand shows the equipped weapon (rusty / iron / blue Troll-Bane).
- barks.gd: villagers say a line as you pass, chosen by story flags (FLAG_LINES "flag=value"), level, rain, night.
  Storyteller: add lines for new flags there. Blocking: right mouse with the sword out (hotbar.blocking): 75% less damage.
- Live reload is per part now (world.gd reload_part): saving scene/x.gd swaps only part x; other parts keep running
  with their state. Story flag changes rebuild only the parts that called W.flag() for that flag during build()
  (world.gd flag_users). A part holding another part's nodes can implement part_reloaded(name) to catch up.
- Side quests come from villagers now (rpg.gd QUESTS "giver"; gold ! / ? over their heads; the board is gone).
- Between chapters there is an interlude (story.gd): bring the news to Thornvale, rest by the campfire; the next chapter
  (even if already written) starts only after that, so the storyteller has time and it fits the story.
- Interiors: cottages are hollow (doorway, floor, ceiling, hearth, bed, table, shelf; cottage 1 = the Gilded Goose
  tavern with a bar), castle.gd great_hall() is hollow (feast table, throne on a dais, hearth, banners, chandeliers;
  rubble when ruined). Barnaby: smoother walk, [sit] by the campfire (also on his own now and then).
- 2026-10-04 cleanup: removed the sea, the conch, the parkour tower, the gun (and its knockback) and the ambient
  wind (deleted parts and commands). Barnaby is no longer a lighthouse keeper: an old soldier and storyteller who
  keeps the campfire, recoloured (green cloak, staff); he is the main story's giver (story.gd interlude: sit with him
  at the fire, tell him what happened, he gets a ! when the next chapter is ready).
- Villagers can be talked to by voice like Barnaby: villagers.gd gives each a name/bio and a Talker, reports
  npc_id "folk:<who>" when you stand next to one; chat.pyw plays them all with ONE Haiku process (kind "npc3",
  FOLK_PERSONA, the "Folk" column), each message saying who is speaking and what they see. No commands or handoffs.
- NPC pathfinding (villagers.gd): a walkability grid (1.5 m cells, probed for anything solid + steep ground, built the
  first physics frame after a rebuild, ~0.16 s) and A* paths with line-of-sight smoothing. New buildings are avoided
  automatically as long as they have colliders.
- terrain.gd tree cache v15: pines have seven close overlapping bough tiers; oaks have fuller, smoother crowns and visible branches.
- 2026-10-05 fixes: the held sword has a tapered blade, fuller, guard, wrapped grip and pommel. Its ready pose is
  angled from the lower-right toward the upper-left; keep its model geometry unchanged. The repeated swing whoosh
  is quiet, fixed-pitch, and replaces itself instead of layering. Barnaby's [look]
  context asks for a direct description of the valley without narrating his own actions. Named sky presets blend over
  three seconds. Highmoor's rebuilding quest now explains where and how to mine ore, and 15 ore rocks are placed so
  its 12-ore goal is possible without waiting for regrowth. Grass is scattered over walkable hills across the map;
  Elsie's routine uses waypoints outside the cottages.
- Bandit camp cleanup: when chapter 2 has a camp flag, the old troll-camp clutter is omitted. The hostile state has
  two tents, an enclosed timber palisade and gate, a central fire, and ordered stores; the cleared and tolled states
  use simpler layouts appropriate to each outcome.
- Cottage roofs: the thatch prism has a wider overhang and steeper pitch, finished with timber eaves and a raised
  ridge cap.
