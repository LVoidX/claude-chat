extends Node3D
## The main story: chapters whose quests change the world, written live by the storyteller (a Claude process the
## chat window starts when a chapter ends). This part runs the current chapter from story/chapter.json (or
## story/seed.json before the first one is written), tracks its quests, and keeps the world's story flags.
##
## Flags are the world's memory: {"troll": "slain", "castle": "burnt", ...}. Other parts read them with W.flag(name)
## and build differently, so whatever happened
## stays visible (W.flag("castle") works anywhere, even before this part is built). Finishing a story quest applies its "sets" flags, rebuilds the world at once, writes a line to
## story/log.md, and when the chapter is over tells the chat window, which has the storyteller write the next.
##
## chapter.json: {"chapter": 2, "title": "...", "intro": "...", "ends_when": "any" | "all",
##   "start_sets": {flag: value},  (applied once when the chapter begins)
##   "quests": [{"id", "title", "text", "kind", ..., "sets": {flag: value}, "outcome": "what this means happened",
##               "xp", "gold", "items": {item: n}}]}
## Quest kinds: "kill" (what = creature kind, n), "reach" (pos [x, z], radius), "bring" (what = item, n, pos, radius:
## hand it over there), "event" (done when a part calls ctx.parts["story"].complete(id)).
## Markers: a tall light beam shows where reach / bring quests lead.

const STORY_DIR := "res://story"

var ctx: Dictionary
var W
var data := {}  # the current chapter
var data_sig := ""
var beams := []  # [node, quest id]
var t := 0.0
var writing := false  # the storyteller is busy with the next chapter


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	var s: Dictionary = ctx.state.get_or_add("story", {})
	for key in ["flags", "done", "kills"]:
		if not s.has(key):
			s[key] = {} if key != "done" else []
	if not s.has("chapter"):
		s["chapter"] = 0
	load_chapter()
	build_beams()
	if st().get("finished", false):  # still waiting for the next chapter: (re)ask, the chat window ignores repeats
		W.send({"t": "story_next", "chapter": int(st().chapter)})
	var rpg = ctx.parts.get("rpg")  # (built before this part: refresh its quest list now that we're here)
	if rpg and rpg.has_method("refresh_hud"):
		rpg.refresh_hud.call_deferred()


## False until build() has run (other parts are built first and may ask early).
func built() -> bool:
	return not ctx.is_empty()


func st() -> Dictionary:
	return ctx.state["story"]


## A story flag ("" if never set). Use this in any part to build the world as the story left it.
func flag(name: String) -> String:
	return str(st().flags.get(name, ""))


func chapter_file() -> String:
	var path := STORY_DIR.path_join("chapter.json")
	return path if FileAccess.file_exists(path) else STORY_DIR.path_join("seed.json")


func load_chapter() -> void:
	var path := chapter_file()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		printerr("story: ", path, " is not valid JSON, keeping the old chapter")
		return
	data_sig = path + str(FileAccess.get_modified_time(path))
	var number := int(parsed.get("chapter", 1))
	if number > int(st().chapter) and int(st().chapter) > 0 and not st().get("interlude", {}).get("heard", false):
		if not st().get("finished", false):  # (the game stopped before the chapter's end was saved: it did end)
			st().finished = true
			st().interlude = {"told": false, "heard": false}
			build_beams.call_deferred()
		return  # written, but it waits until Barnaby has heard your tale and told you the news (the interlude)
	data = parsed
	if number != int(st().chapter):  # a new chapter begins
		if number < int(st().chapter) and int(st().chapter) > 0:  # the story was sent back: forget what happened since
			st().flags = {}
			set_flags({})
		st().chapter = number
		st().done = []
		st().kills = {}
		st().erase("finished")
		st().erase("interlude")
		var start: Dictionary = data.get("start_sets", {})
		if not start.is_empty():
			set_flags(start)
		W.show_notice("CHAPTER %d: %s" % [number, data.get("title", "")], 7.0)
		var music = ctx.parts.get("music")
		if music:
			music.play_sfx.call_deferred("chapter")
		# the story text no longer fills the top of the screen: it is in the journal (J), under the chapter title
		get_tree().create_timer(7.5).timeout.connect(W.show_notice.bind("Press J to read the story so far.", 6.0))
		log_line("\n## Chapter %d: %s\n%s\n" % [number, data.get("title", ""), data.get("intro", "")])
		writing = false


func quests() -> Array:
	return data.get("quests", [])


func is_done(id: String) -> bool:
	return id in st().done


func open_quests() -> Array:
	if st().get("finished", false):
		return []
	return quests().filter(func(q): return not is_done(q.id))


## Called by rpg.gd for every kill / pickup ("kill", "wolf").
func event(kind: String, what: String) -> void:
	if kind != "kill":
		return
	for q in open_quests():
		if q.get("kind") == "kill" and q.get("what") == what:
			var n := int(st().kills.get(q.id, 0)) + 1
			st().kills[q.id] = n
			if n >= int(q.get("n", 1)):
				complete(q.id)
			else:
				W.show_notice("%s %d/%d" % [q.title, n, int(q.get("n", 1))])


func progress_text(q: Dictionary) -> String:
	match q.get("kind"):
		"kill":
			return " (%d/%d)" % [int(st().kills.get(q.id, 0)), int(q.get("n", 1))]
		"bring":
			var rpg = ctx.parts.get("rpg")
			return " (%d/%d)" % [rpg.count(q.what) if rpg else 0, int(q.get("n", 1))]
	return ""


## A story quest is done: rewards, its consequences for the world, and maybe the end of the chapter.
func complete(id: String) -> void:
	if is_done(id) or st().get("finished", false):
		return
	var q := {}
	for each in quests():
		if each.id == id:
			q = each
	if q.is_empty():
		return
	st().done.append(id)
	var rpg = ctx.parts.get("rpg")
	if rpg:
		if int(q.get("gold", 0)) > 0:
			rpg.add_gold(int(q.gold), true)
		var items: Dictionary = q.get("items", {})
		for item in items:
			rpg.give(item, int(items[item]), true)
		if int(q.get("xp", 0)) > 0:
			rpg.add_xp(int(q.xp))
	W.show_notice("%s - done." % q.title, 6.0)
	var music = ctx.parts.get("music")
	if music:
		music.play_sfx.call_deferred("quest")
	log_line("- %s" % q.get("outcome", "The wanderer completed: " + q.title))
	var sets: Dictionary = q.get("sets", {})
	var ends: bool = data.get("ends_when", "all") == "any" or open_quests().is_empty()
	if ends:
		st().finished = true
		W.save_state.call_deferred()  # (right away: a story moment must never be lost)
	if not sets.is_empty():
		set_flags(sets)
	if ends:
		writing = true
		st().interlude = {"told": false, "heard": false}  # something to do while the next chapter is written
		get_tree().create_timer(6.5).timeout.connect(W.show_notice.bind("Barnaby will want to hear about this. Sit with him by the campfire at the crossroads and tell him what happened.", 9.0))
		W.send({"t": "story_next", "chapter": int(st().chapter), "quest": id})
	build_beams()
	if rpg:
		rpg.refresh_hud()


## Change the world's memory and rebuild every part so the change shows at once.
func set_flags(sets: Dictionary) -> void:
	for key in sets:
		st().flags[key] = str(sets[key])
	var f := FileAccess.open(W.project_file("godot_world/story/flags.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(st().flags, "  "))
	if W.has_method("refresh_flags"):  # only the parts that build by these flags are rebuilt
		W.refresh_flags.call_deferred(sets.keys())
	else:
		W.load_parts.call_deferred()


func log_line(text: String) -> void:
	var path: String = W.project_file("godot_world/story/log.md")
	var f := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_string(text + "\n")


func quest_pos(q: Dictionary) -> Vector3:
	var p: Array = q.get("pos", [0, 0])
	return Vector3(float(p[0]), W.ground_y(float(p[0]), float(p[1])), float(p[1]))


func build_beams() -> void:
	for b in beams:
		b[0].queue_free()
	beams.clear()
	var spots := []  # [position, quest id or interlude step]
	for q in open_quests():
		if q.get("kind") in ["reach", "bring"] and q.has("pos"):
			spots.append([quest_pos(q), q.id])
	var il := interlude()
	if not il.is_empty() and not il.get("told", false):
		spots.append([Vector3(CAMPFIRE.x, W.ground_y(CAMPFIRE.x, CAMPFIRE.y), CAMPFIRE.y), "tell"])
	for spot in spots:
		var node := Node3D.new()
		node.position = spot[0]
		add_child(node)
		var beam: MeshInstance3D = W.glow(node, Vector3(0, 30, 0), Vector3(0.6, 60, 0.6), Color("#ffd24d"), 1.2)
		beam.transparency = 0.6
		beams.append([node, spot[1]])


func _process(delta: float) -> void:
	t += delta
	if fmod(t, 1.0) < delta:  # the storyteller wrote a new chapter?
		var path := chapter_file()
		if path + str(FileAccess.get_modified_time(path)) != data_sig:
			load_chapter()
			build_beams()
			var rpg = ctx.parts.get("rpg")
			if rpg:
				rpg.refresh_hud()
	var player: Vector3 = W.player.global_position
	update_news_mark()
	for q in open_quests():
		var kind: String = q.get("kind", "")
		if not kind in ["reach", "bring"] or not q.has("pos"):
			continue
		var p := quest_pos(q)
		if Vector2(player.x - p.x, player.z - p.z).length() > float(q.get("radius", 4.0)):
			continue
		if kind == "reach":
			complete(q.id)
		else:
			var rpg = ctx.parts.get("rpg")
			if rpg and rpg.count(q.what) >= int(q.get("n", 1)):
				rpg.take(q.what, int(q.get("n", 1)))
				complete(q.id)
	for b in beams:
		b[0].get_child(0).transparency = 0.55 + sin(t * 2.0) * 0.1


## Lines for the HUD's quest list and the journal.
func tracker_lines() -> Array:
	var out := []
	for q in open_quests():
		out.append(q.title + progress_text(q))
	if st().get("finished", false):
		var il := interlude()
		if not il.is_empty() and not il.get("told", false):
			out.append("Sit by the campfire and tell Barnaby what happened")
		elif not il.is_empty() and not news_ready():
			out.append("(Barnaby is pondering what comes next... explore, help the villagers)")
		elif not il.is_empty():
			out.append("Barnaby has news: talk to him")
	return out


# --- the interlude between chapters: you sit with Barnaby at the campfire and tell him what happened (by voice);
# meanwhile the storyteller writes the next chapter. When it is ready Barnaby has a gold ! over his head: E (or just
# talking to him) and he tells you what happens next, and the new chapter begins. Barnaby is the story's teller.

const CAMPFIRE := Vector2(9, 6)  # (travel.gd FIRE)
var news_mark: Label3D


func interlude() -> Dictionary:
	if not st().get("finished", false):
		return {}
	var il: Dictionary = st().get("interlude", {})
	if il.has("tell") or (il.is_empty() and st().has("interlude")):  # (from an older version: start it the new way)
		il = {"told": false, "heard": false}
		st().interlude = il
	return il


func interlude_done() -> bool:
	var il := interlude()
	return il.is_empty() or il.get("heard", false)


## Is the next chapter written (and waiting)?
func news_ready() -> bool:
	var path := chapter_file()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed is Dictionary and int(parsed.get("chapter", 0)) > int(st().chapter)


## barnaby.gd calls this whenever Barnaby speaks. Sitting with him at the fire and him answering you = you told him.
func barnaby_spoke() -> void:
	var il := interlude()
	if il.is_empty() or il.get("told", false):
		return
	var b = ctx.parts.get("barnaby")
	var fire := Vector3(CAMPFIRE.x, 0, CAMPFIRE.y)
	if not ctx.get("seated", false) or not b or Vector2(b.body.position.x - fire.x, b.body.position.z - fire.z).length() > 5.0:
		return
	il.told = true
	W.save_state.call_deferred()
	var rpg = ctx.parts.get("rpg")
	if rpg:
		rpg.add_xp(25)
	interlude_step()


func hear_news() -> void:
	var il := interlude()
	if il.is_empty() or not il.get("told", false) or not news_ready():
		return
	il.heard = true
	W.save_state.call_deferred()
	load_chapter()  # the new chapter begins now
	build_beams()
	var rpg = ctx.parts.get("rpg")
	if rpg:
		rpg.refresh_hud()
	var titles := quests().map(func(q): return str(q.title))
	W.send({"t": "event", "who": "barnaby", "label": "news", "text": ("You have news for the wanderer: tell them, in your own words and briefly, " +
		"what happens next in the story (Chapter %d, \"%s\": %s). Their choices: %s." % [int(st().chapter), data.get("title", ""),
		data.get("intro", ""), "; ".join(titles)])})


func interlude_step() -> void:
	build_beams()
	var rpg = ctx.parts.get("rpg")
	if rpg:
		rpg.refresh_hud()



func chapter_title() -> String:
	return "Chapter %d: %s" % [int(st().chapter), data.get("title", "")]


func seen_from(_from: Vector3, _viewer: Node) -> Array:
	var seen := ["the story so far is in %s; the wanderer's main quests: %s" % [chapter_title(),
		"; ".join(open_quests().map(func(q): return q.title)) if not open_quests().is_empty() else "none right now"]]
	if not st().flags.is_empty():
		seen.append("how the world has changed (story flags): %s" % JSON.stringify(st().flags))
	return seen


func handle(c: Dictionary) -> bool:
	match c.get("cmd", ""):
		"story_writing":  # the chat window: the storyteller started / finished
			writing = c.get("on", false)
		"story_complete":  # [story_complete id] from a character or the storyteller's own parts
			var args: Array = c.get("args", [])
			if not args.is_empty():
				complete(str(args[0]))
		_:
			return false
	return true


## The gold ! over Barnaby when he has news; also what E does next to him then.
func update_news_mark() -> void:
	var b = ctx.parts.get("barnaby")
	var il := interlude()
	var show: bool = b != null and b.body != null and not il.is_empty() and il.get("told", false) and news_ready()
	if show and not is_instance_valid(news_mark):
		news_mark = Label3D.new()
		news_mark.text = "!"
		news_mark.font_size = 48
		news_mark.outline_size = 10
		news_mark.pixel_size = 0.0008
		news_mark.fixed_size = true
		news_mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		news_mark.no_depth_test = true
		news_mark.modulate = Color("#ffd24d")
		add_child(news_mark)
	if is_instance_valid(news_mark):
		news_mark.visible = show
		if show:
			news_mark.global_position = b.body.global_position + Vector3(0, 2.95 + sin(t * 3.0) * 0.06, 0)


func interactables() -> Array:
	var out := []
	var b = ctx.parts.get("barnaby")
	var il := interlude()
	if b and b.body and not il.is_empty() and il.get("told", false) and news_ready():
		out.append({"pos": b.body.global_position, "label": "Hear Barnaby's news", "act": hear_news, "range": 3.0})
	var rpg = ctx.parts.get("rpg")
	for q in open_quests():  # a bargain: hand it over right there with E (walking in with it also does it)
		if q.get("kind") == "bring" and q.has("pos") and rpg:
			var n := int(q.get("n", 1))
			var what: String = rpg.ITEMS[q.what].name.to_lower() if q.what in rpg.ITEMS else str(q.what)
			if rpg.count(q.what) >= n:
				out.append({"pos": quest_pos(q), "label": "Hand over %d %s (%s)" % [n, what, q.title], "act": pay.bind(q.id), "range": float(q.get("radius", 4.0)) + 3.0})
	return out


func pay(id: String) -> void:
	var rpg = ctx.parts.get("rpg")
	for q in open_quests():
		if q.id == id and rpg and rpg.count(q.what) >= int(q.get("n", 1)):
			rpg.take(q.what, int(q.get("n", 1)))
			complete(id)

