extends Node3D
## The 3D world's engine side: the window, the player, the on-screen text, the link to the chat window,
## and the loader that runs the world's parts (the files in scene/).
##
## Started by chat.pyw through godot_bridge.py, which connects us to the chat over a local TCP socket:
## commands come in as JSON lines, and we report back as JSON lines.
##
## What is IN the world lives in scene/*.gd, one file per thing (base.gd = ground and sky, barnaby.gd =
## Barnaby, ...). When any of them, or a model in models/, is saved, all parts are rebuilt inside the same
## window without restarting. If a file has an error, nothing is swapped: the old world keeps running and
## the error goes to the log (claude-world.log). Editing THIS file swaps the engine in place too (reload_engine):
## the new version takes over the link, the player's spot and view, the window and ctx, then rebuilds the
## parts. If it has an error, the old engine keeps running. Only godot_bridge.py edits restart the world.
##
## Controls: WASD move, Shift run, Space jump, mouse look, Esc frees the mouse (click to grab it again),
## Tab back to the chat, R back to the middle, F11 fullscreen, M / N = talk / stop (like the mouse buttons).

const ENGINE_FILE := "res://world.gd"  # this file: saving it swaps the engine in place
const PARTS_DIR := "res://scene"
const MODELS_DIR := "res://models"
const GRAVITY := 18.0
const EYE_HEIGHT := 1.8
const STAND_HEIGHT := 1.9  # capsule height standing / crouching (Ctrl)
const CROUCH_HEIGHT := 1.1
const CROUCH_EYE := 1.0
var player_shape: CollisionShape3D
var push := Vector3.ZERO  # sideways shove from blasts (rockets), added to walking and fading out
var crouch_amount := 0.0  # 0 = standing .. 1 = fully crouched (eases)
var walk_bob := 0.0
var walk_phase := 0.0
const QUIET_COMMANDS := ["quests", "say", "say_start", "say_end", "npc_state"]  # too frequent to log
const COMPASS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]

var tcp := StreamPeerTCP.new()
var connected := false
var inbox := PackedByteArray()  # bytes received but not yet a whole line
var outbox: Array = []  # messages waiting for the connection

var player: CharacterBody3D
var head: Node3D  # turns up and down; the player body turns left and right
var camera: Camera3D
var hud: CanvasLayer  # parts can add their own UI here
var status_label: Label  # top center: listening / thinking / speaking
var notice_label: Label  # top right: short messages that fade after a few seconds
var quest_label: Label  # top left: the active quests
var notice_until := 0.0

## Shared with the parts and kept across reloads (a part's own variables are reset by a reload).
## ctx.state is also saved to world_state.json, so it survives closing the world too.
var ctx := {}
var parts: Array = []  # the part nodes built from scene/*.gd, in file name order
var parts_sig := ""
var part_mtimes := {}  # part file -> when it was saved (so only the saved part is swapped)
var next_parts_check := 0.0
var was_fullscreen := false
var near_who := ""  # the character the player is standing next to ("" = nobody)
var near_name := ""
var sights := {}  # character -> what they could see last time we told the chat
var next_sight := 0.0
var next_save := 0.0
var saved_json := ""
var state_path := ""
var _meshes := {}
var _materials := {}
var _textures := {}
var engine_mtime := 0
var retired := false  # replaced by a newer version of this file; stop doing anything


func _ready() -> void:
	engine_mtime = FileAccess.get_modified_time(ENGINE_FILE)
	if has_meta("handover"):  # a newer world.gd taking over from the running one
		take_over(get_meta("handover"))
		return
	var port := 0
	var start_hidden := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.substr(7))
		elif arg == "--hidden":
			start_hidden = true
		elif arg.begins_with("--shot="):  # for testing: save a screenshot after 3 s, then quit
			var path := arg.substr(7)
			get_tree().create_timer(3.0).timeout.connect(func():
				get_viewport().get_texture().get_image().save_png(path)
				get_tree().quit())
	if port:
		tcp.connect_to_host("127.0.0.1", port)
	if start_hidden:  # minimized from the start; the chat window shows us when asked
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	build_player()
	build_hud()
	state_path = project_file("world_state.json")
	var saved = JSON.parse_string(FileAccess.get_file_as_string(state_path)) if FileAccess.file_exists(state_path) else null
	ctx = {"world": self, "player": player, "camera": camera, "hud": hud,
		"state": saved if saved is Dictionary else {}, "parts": {}, "quest_ids": [], "quest_lines": []}
	if ctx.state.has("player"):
		var p: Array = ctx.state["player"]
		player.position = Vector3(p[0], p[1], p[2])
		player.rotation.y = p[3]
	parts_sig = parts_signature()
	load_parts(true)
	if start_hidden:
		hide_world.call_deferred()
	else:
		show_world.call_deferred()
	send({"t": "ready"})


## world.gd was saved: compile it, and if it is fine, put a node running it in our place.
func reload_engine() -> void:
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(ENGINE_FILE)
	script.take_over_path(ENGINE_FILE)
	if script.reload() != OK:
		printerr("world.gd has an error, so the engine was not swapped (the old one keeps running). Details are above.")
		return
	save_state()
	retired = true
	state_path = ""  # the new one saves from now on
	var next := Node3D.new()
	next.set_script(script)
	next.set_meta("handover", {"tcp": tcp, "connected": connected, "inbox": inbox, "outbox": outbox, "ctx": ctx,
		"state_path": project_file("world_state.json"), "was_fullscreen": was_fullscreen, "near_who": near_who,
		"player": player.transform, "head_x": head.rotation.x, "velocity": player.velocity,
		"status": status_label.text})
	_swap_in.call_deferred(next)


func _swap_in(next: Node3D) -> void:
	var tree := get_tree()
	var root := get_parent()
	root.remove_child(self)
	next.name = "World"
	root.add_child(next)  # runs its _ready -> take_over()
	tree.current_scene = next
	queue_free()


## The other half of reload_engine, in the new version: carry on exactly where the old one was.
func take_over(h: Dictionary) -> void:
	tcp = h.tcp
	connected = h.connected
	inbox = h.inbox
	outbox = h.outbox
	was_fullscreen = h.was_fullscreen
	near_who = h.near_who
	state_path = h.state_path
	build_player()
	build_hud()
	player.transform = h.player
	head.rotation.x = h.head_x
	player.velocity = h.velocity
	camera.make_current()
	status_label.text = h.status
	ctx = h.ctx  # same state and caches; the engine-side entries point to us now
	ctx.merge({"world": self, "player": player, "camera": camera, "hud": hud, "parts": {}}, true)
	parts_sig = parts_signature()
	load_parts(true)
	draw_quests()
	print("[world] engine (world.gd) reloaded in place")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		save_state()


# --- the link to the chat window --------------------------------------------------------------------

func send(message: Dictionary) -> void:
	if connected:
		tcp.put_data((JSON.stringify(message) + "\n").to_utf8_buffer())
	else:
		outbox.append(message)


func poll_link() -> void:
	if tcp.get_status() == StreamPeerTCP.STATUS_NONE and not connected:
		return  # started on its own (no chat window): just a world to walk around in
	tcp.poll()
	var status := tcp.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED:
		if not connected:
			connected = true
			for message in outbox:
				send(message)
			outbox.clear()
		var available := tcp.get_available_bytes()
		if available > 0:
			var got := tcp.get_data(available)
			if got[0] == OK:
				inbox.append_array(got[1])
		# split on newline bytes, then decode: a letter like "é" cut in two between reads stays whole
		var end := inbox.find(10)
		while end >= 0:
			var command = JSON.parse_string(inbox.slice(0, end).get_string_from_utf8())
			inbox = inbox.slice(end + 1)
			if command is Dictionary:
				handle(command)
			end = inbox.find(10)
	elif status == StreamPeerTCP.STATUS_ERROR or (connected and status == StreamPeerTCP.STATUS_NONE):
		save_state()
		get_tree().quit()  # the chat window closed


func handle(c: Dictionary) -> void:
	var kind: String = c.get("cmd", "")
	match kind:
		"status":
			status_label.text = c.get("text", "")
			return
		"show":
			show_world()
			return
		"hide":
			hide_world()
			return
		"quit":
			save_state()
			get_tree().quit()
			return
		"notice":
			show_notice(c.get("text", ""))
			return
		"quests":  # the quest list from the chat window
			ctx["quest_ids"] = c.get("ids", [])
			ctx["quest_lines"] = c.get("lines", [])
			draw_quests()
		"jobs":  # the assistant's work queue from the chat window
			ctx["job_lines"] = c.get("lines", [])
			draw_quests()
			return
		"teleport", "center":
			recenter()
			return
	if not kind in QUIET_COMMANDS:
		print("[world] command received: ", c)  # shows up in the world log
	for part in parts:  # parts that only watch the commands go by (net.gd passes characters' speech on to friends)
		if part.has_method("observe"):
			part.observe(c)
	for part in parts:  # the first part that knows the command handles it
		if part.has_method("handle") and part.handle(c):
			return


# --- the world's parts (scene/*.gd), reloaded live ---------------------------------------------------

# Parts that are switched off for now (everything that isn't medieval). Delete a name to bring it back.
const DISABLED_PARTS := []


func part_files() -> Array:
	var files := []
	for f in DirAccess.get_files_at(PARTS_DIR):
		if f.ends_with(".gd") and f not in DISABLED_PARTS:
			files.append(f)
	files.sort()
	return files


## When each part file was last saved: {file: time}. Models count as one entry (a model change rebuilds all).
func part_times() -> Dictionary:
	var times := {}
	for f in part_files():
		times[f] = FileAccess.get_modified_time(PARTS_DIR.path_join(f))
	var models := ""
	for f in DirAccess.get_files_at(MODELS_DIR):
		models += "%s:%d;" % [f, FileAccess.get_modified_time(MODELS_DIR.path_join(f))]
	times["<models>"] = models
	return times


func parts_signature() -> String:  # (kept for the handover check)
	return str(part_times())


func compile_part(f: String) -> GDScript:
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(PARTS_DIR.path_join(f))
	script.take_over_path(PARTS_DIR.path_join(f))  # so errors name the file (a plain resource_path breaks reloads)
	return script if script.reload() == OK else null


## Swap ONE part for a fresh build of its file (or add a new part, or remove a deleted one). Every other part keeps
## running untouched: no world reset, no freeze. If the file has an error, the old part stays.
func reload_part(f: String) -> void:
	var name := f.get_basename()
	var old: Node = ctx["parts"].get(name)
	var index := parts.find(old) if old else -1
	if not FileAccess.file_exists(PARTS_DIR.path_join(f)) or f in DISABLED_PARTS:
		if old:
			parts.erase(old)
			ctx["parts"].erase(name)
			retire_part(old)
			print("[world] part removed: ", name)
		return
	var script := compile_part(f)
	if script == null:
		printerr("scene/", f, " has an error, so it was not reloaded (the old one keeps running). Details are above.")
		return
	if old:
		retire_part(old)  # (its _exit_tree cleans up what it made outside itself, before the new one builds)
	var part := Node3D.new()
	part.name = name
	part.set_script(script)
	add_child(part)
	if index >= 0:
		parts[index] = part
		move_child(part, index)  # same place in the order (parts run in file-name order)
	else:
		parts.append(part)
	ctx["parts"][name] = part
	build_part(part)
	for other in parts:  # parts that keep hold of another part's nodes can catch up
		if other != part and other.has_method("part_reloaded"):
			other.part_reloaded(name)
	print("[world] part reloaded: ", name)
	send({"t": "need_quests"})


## A mesh made in Blender (tools/blender/*.py -> models3d/<name>.glb): the first mesh in the file, with its vertex
## colours (the look is painted into the vertices). null if the file is missing. Cached in ctx, so reloads are free.
## Give it a material yourself: vertex_color_use_as_albedo = true, or a shader that reads COLOR.
func load_mesh(name: String) -> ArrayMesh:
	var key := "mesh3d|" + name
	if ctx.has(key):
		return ctx[key]
	var path := ProjectSettings.globalize_path("res://models3d/%s.glb" % name)
	if not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		printerr("models3d/", name, ".glb could not be read")
		return null
	var scene: Node = doc.generate_scene(state)
	var found: ArrayMesh = null
	var stack: Array = [scene]
	while not stack.is_empty() and found == null:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.mesh is ArrayMesh:
			found = n.mesh
		stack.append_array(n.get_children())
	scene.free()
	ctx[key] = found
	return found


## The material for Blender models whose colours are painted into the vertices (roofs, props): the colour comes
## from the mesh. One shared instance.
func painted_mat() -> StandardMaterial3D:
	if not ctx.has("painted_mat"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.95
		ctx["painted_mat"] = m
	return ctx["painted_mat"]


## A Blender prop (models3d/<name>.glb, painted colours) placed under `parent`. Returns the MeshInstance3D, or null when
## the model is missing (so the caller can build its plain-boxes version instead).
func prop(name: String, parent: Node, pos: Vector3, yaw := 0.0, scale := 1.0) -> MeshInstance3D:
	var mesh: ArrayMesh = load_mesh(name)
	if mesh == null:
		return null
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = painted_mat()
	m.position = pos
	m.rotation.y = yaw
	m.scale = Vector3.ONE * scale
	parent.add_child(m)
	return m


## Take an old part out of the world now (its _exit_tree runs, so it tidies up first), but delete it only at the end
## of the frame: freeing it on the spot crashed the engine when a story flag swapped the creatures mid-fight.
func retire_part(old: Node) -> void:
	old.process_mode = Node.PROCESS_MODE_DISABLED
	old.name = String(old.name) + "_old"
	remove_child(old)
	old.queue_free()


var building := ""  # the part whose build() is running (W.flag notes who reads which flag)
var flag_users := {}  # flag name -> {part name: true}: the parts to rebuild when that flag changes


func build_part(part: Node) -> void:
	if part.has_method("build"):
		building = part.name
		part.build(ctx)
		building = ""


## Story flags changed: rebuild only the parts that read those flags while building (see flag()).
func refresh_flags(names: Array) -> void:
	var who := {}
	for n in names:
		for part_name in flag_users.get(n, {}):
			who[part_name] = true
	for part_name in who:
		reload_part(part_name + ".gd")


## (Re)build every part (at start, after an engine swap, or when a model changes). All files are checked first:
## if one has an error, the old world keeps running. Saving a single part only swaps that part (reload_part).
func load_parts(first := false) -> void:
	var scripts := []
	for f in part_files():
		var script := compile_part(f)
		if script == null:
			printerr("scene/", f, " has an error (", "parse error", "), so nothing was reloaded. Details are above.")
			return
		scripts.append([f.get_basename(), script])
	for part in parts:
		part.queue_free()
	parts.clear()
	_meshes.clear()
	_materials.clear()
	_textures.clear()
	flag_users.clear()
	ctx["parts"] = {}
	for entry in scripts:
		var part := Node3D.new()
		part.name = entry[0]
		part.set_script(entry[1])
		add_child(part)
		parts.append(part)
		ctx["parts"][entry[0]] = part
	for part in parts:
		build_part(part)
	part_mtimes = part_times()
	sights.clear()
	if not first:
		print("[world] parts reloaded")
	send({"t": "need_quests"})  # the chat window resends the quest list


func _process(_delta: float) -> void:
	if retired:
		return
	poll_link()
	var now := Time.get_ticks_msec() / 1000.0
	if now > next_parts_check:  # a part or model saved? rebuild in place
		next_parts_check = now + 0.5
		var engine_time := FileAccess.get_modified_time(ENGINE_FILE)
		if engine_time != engine_mtime:  # this file itself was saved: swap the engine, keep everything else
			engine_mtime = engine_time
			reload_engine()
			return
		var times := part_times()
		if times != part_mtimes:
			if times.get("<models>") != part_mtimes.get("<models>"):
				load_parts()  # a model changed: the parts using it rebuild (all, simplest)
			else:
				var changed := []
				for f in times:
					if times[f] != part_mtimes.get(f):
						changed.append(f)
				for f in part_mtimes:
					if not times.has(f):
						changed.append(f)  # deleted
				part_mtimes = times
				for f in changed:
					reload_part(f)
			part_mtimes = times
	if notice_label.text != "":  # fades out over its last half second
		notice_label.modulate.a = clampf((notice_until - now) / 0.5, 0.0, 1.0)
		if now > notice_until:
			notice_label.text = ""
	# whom is the player standing next to? (the chat window listens hands-free while you are)
	var who := ""
	var who_name := ""
	for part in parts:
		if "npc_id" in part and part.has_method("is_near") and part.is_near():
			who = part.npc_id
			who_name = str(part.get("npc_name")) if "npc_name" in part else ""
			break
	if who != near_who:
		near_who = who
		near_name = who_name
		send({"t": "near", "v": who != "", "who": who, "name": who_name})
	if now > next_sight:  # what each character can see, for their next answer
		next_sight = now + 1.0
		for part in parts:
			if "npc_id" in part and str(part.npc_id) != "" and part.has_method("describe"):
				var text: String = part.describe()
				if sights.get(part.npc_id, "") != text:
					sights[part.npc_id] = text
					send({"t": "sight", "who": part.npc_id, "text": text})
	if now > next_save:
		next_save = now + 5.0
		save_state()


func save_state() -> void:
	if not player or state_path == "":
		return
	ctx.state["player"] = [player.position.x, player.position.y, player.position.z, player.rotation.y]
	var text := JSON.stringify(ctx.state)
	if text != saved_json:
		saved_json = text
		var f := FileAccess.open(state_path, FileAccess.WRITE)
		if f:
			f.store_string(text)


# --- helpers for the parts ---------------------------------------------------------------------------

## A file in the folder next to chat.pyw (one level above this project).
func project_file(file: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(file).simplify_path()


## A PNG from the folder next to chat.pyw, loaded directly (no Godot import step needed).
func tex(file: String) -> Texture2D:
	if not file.ends_with(".png"):
		file += ".png"
	if not file in _textures:
		var image := Image.load_from_file(project_file(file))
		if image:
			image.generate_mipmaps()
		_textures[file] = ImageTexture.create_from_image(image) if image else null
	return _textures[file]


## A shared material for a colour (and optional texture, repeated `tiles` times per face).
func mat(color: Color, texture := "", tiles := Vector2.ONE, double_sided := false) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [color.to_html(), texture, tiles, double_sided]
	if not key in _materials:
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		if texture != "":
			m.albedo_texture = tex(texture)
			m.uv1_triplanar = true  # one picture per box face, like before
			m.uv1_scale = Vector3(tiles.x, tiles.y, tiles.x)
		elif color.a >= 1.0:  # plain colours get a faint grain, so boxes read as wood / cloth / hide, not plastic
			m.albedo_texture = grain_texture()
			m.uv1_triplanar = true  # mapped on the object itself, so it moves with characters
			m.uv1_scale = Vector3.ONE * 1.5
			m.albedo_color = color.lightened(0.06)  # (the grain darkens a little on average)
		if color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if double_sided:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = m
	return _materials[key]


## The grain every plain box gets: soft blotches plus fine speckle, 0.84..1.0 grey (multiplies the colour).
## Kept on the ctx so world reloads reuse it.
func grain_texture() -> Texture2D:
	if ctx.has("grain_texture"):
		return ctx["grain_texture"]
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.045
	noise.fractal_octaves = 4
	var fine := FastNoiseLite.new()
	fine.seed = 5
	fine.frequency = 0.5
	var s := 128
	var soft := noise.get_seamless_image(s, s)  # (seamless, so the repeats don't show an edge)
	var speck := fine.get_seamless_image(s, s)
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	for y in s:
		for x in s:
			var v := 0.8 + soft.get_pixel(x, y).r * 0.16 + speck.get_pixel(x, y).r * 0.05
			v = clampf(v, 0.8, 1.0)
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	ctx["grain_texture"] = t
	return t


func mesh(kind: String) -> Mesh:
	if not kind in _meshes:
		match kind:
			"sphere":
				var s := SphereMesh.new()
				s.radius = 0.5
				s.height = 1.0
				_meshes[kind] = s
			"quad":
				_meshes[kind] = QuadMesh.new()
			"plane":
				var p := PlaneMesh.new()
				p.size = Vector2.ONE
				_meshes[kind] = p
			_:
				_meshes[kind] = BoxMesh.new()
	return _meshes[kind]


## A plain box (or "sphere") of `size` at `pos` under `parent`; collide = you can't walk through it.
func box(parent: Node, pos: Vector3, size: Vector3, color: Color, kind := "cube", collide := false) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh(kind)
	m.material_override = mat(color)
	m.position = pos
	m.scale = size
	var biggest := maxf(size.x, maxf(size.y, size.z))
	if biggest < 0.3:  # tiny details (pegs, handles, buckles) don't need to throw shadows...
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# ...and are not drawn from far away: the smaller they are, the sooner they go (the GPU skips them entirely)
	var reach := 22.0 if biggest < 0.12 else (42.0 if biggest < 0.3 else (80.0 if biggest < 0.8 else 0.0))
	if reach > 0.0:
		m.visibility_range_end = reach
	parent.add_child(m)
	if collide:
		add_collider(parent, Transform3D(Basis(), pos), size, kind)
	return m


func add_collider(parent: Node, xform: Transform3D, size: Vector3, kind := "cube") -> void:
	var body := StaticBody3D.new()
	body.transform = xform
	var shape := CollisionShape3D.new()
	if kind == "sphere":
		var s := SphereShape3D.new()
		s.radius = max(size.x, max(size.y, size.z)) / 2
		shape.shape = s
	else:
		var b := BoxShape3D.new()
		b.size = size
		shape.shape = b
	body.add_child(shape)
	parent.add_child(body)


## Build a model from models/<name>.json under `parent`. Returns its named parts (e.g. "arm_l") and "root".
func build_model(name: String, parent: Node3D) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(MODELS_DIR.path_join(name + ".json")))
	var named := {}
	var root := Node3D.new()
	root.name = name
	parent.add_child(root)
	named["root"] = root
	if data is Dictionary:
		for child in data.get("ch", []):
			_model_node(child, root, named)
	return named


func _model_node(d: Dictionary, parent: Node3D, named: Dictionary) -> void:
	var node: Node3D
	if d.has("m"):
		var m := MeshInstance3D.new()
		m.mesh = mesh(d["m"])
		var tl: Array = d.get("tl", [1, 1])
		m.material_override = mat(Color.html(d.get("c", "#ffffff")), d.get("t", ""), Vector2(tl[0], tl[1]), d.get("ds", false))
		node = m
	else:
		node = Node3D.new()
	var b: Array = d.get("b", [1, 0, 0, 0, 1, 0, 0, 0, 1])
	var o: Array = d.get("o", [0, 0, 0])
	node.transform = Transform3D(Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Vector3(b[6], b[7], b[8])),
		Vector3(o[0], o[1], o[2]))
	if d.get("e", true) == false:
		node.visible = false
	if d.has("n"):
		node.name = d["n"]
		named[d["n"]] = node
	parent.add_child(node)
	if d.get("col", false):  # a solid part: a collider with the same place and size (physics dislikes scaling)
		add_collider(parent, Transform3D(node.basis.orthonormalized(), node.position), node.basis.get_scale(), d.get("m", "cube"))
	for child in d.get("ch", []):
		_model_node(child, node, named)


## A box that glows in `color` (emissive), e.g. lamps, magic flowers, embers. Same arguments as box().
func glow(parent: Node, pos: Vector3, size: Vector3, color: Color, energy := 1.5, kind := "cube") -> MeshInstance3D:
	var key := "glow|%s|%s" % [color.to_html(), energy]
	if not key in _materials:
		var m := StandardMaterial3D.new()
		m.albedo_color = color.darkened(0.3)
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
		_materials[key] = m
	var node := box(parent, pos, size, color, kind)
	node.material_override = _materials[key]
	return node


## A point light (lamps, ovens, glowing things).
func light(parent: Node, pos: Vector3, color: Color, energy: float, reach: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = reach
	l.position = pos
	parent.add_child(l)
	return l


## Everything the parts say can be seen from `from`, for a character's describe(). Each part may have
## seen_from(from, viewer) -> Array of short phrases ("a red box the wanderer made, about 3 m to the west");
## `viewer` is the character part asking, so a part can leave itself out or word things for them.
## New things in the world only need a seen_from() to be noticed by every character.
func seen_around(from: Vector3, viewer: Node) -> Array:
	var seen := []
	for part in parts:
		if part.has_method("seen_from"):
			for phrase in part.seen_from(from, viewer):
				if str(phrase) != "":
					seen.append(phrase)
	return seen


var _quest_sent := {}  # quest id -> when quest_done was last sent


## Tell the chat window a quest is complete. Safe to call every frame: sent at most once every 3 seconds per
## quest (the chat drops the quest from its list a moment later, which stops the calls).
func quest_done(id: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_quest_sent.get(id, -10.0)) < 3.0:
		return
	_quest_sent[id] = now
	send({"t": "quest_done", "id": id})


## A story flag: what the main story has done to the world ("" = never happened). Parts build by it, e.g.
## if W.flag("castle") == "burnt": build the ruin instead. Set by scene/story.gd when story quests finish.
func flag(name: String) -> String:
	if building != "":  # a part reads this flag while building: rebuild it when the flag changes
		flag_users.get_or_add(name, {})[building] = true
	return str(ctx.get("state", {}).get("story", {}).get("flags", {}).get(name, ""))


## The height of the ground at x, z (0 in the flat meadow; the hills come from scene/terrain.gd).
func ground_y(x: float, z: float) -> float:
	var terrain = ctx.get("parts", {}).get("terrain")
	return terrain.height_at(x, z) if terrain and terrain.has_method("height_at") else 0.0


## Where `to` is, seen from `from`, in words ("about 12 m to the north-west"). North is -z.
func where(from: Vector3, to: Vector3) -> String:
	var d := Vector2(to.x - from.x, to.z - from.z)
	if d.length() < 1.5:
		return "right next to you"
	var angle := rad_to_deg(atan2(d.x, -d.y))  # 0 = north, 90 = east
	return "about %d m to the %s" % [roundi(d.length()), COMPASS[posmod(roundi(angle / 45.0), 8)]]


## Turn `node` (left/right only) so its front (-z) faces `target`.
func face(node: Node3D, target: Vector3) -> void:
	var d := target - node.global_position
	if absf(d.x) + absf(d.z) > 0.01:
		node.rotation = Vector3(0, atan2(-d.x, -d.z), 0)


# --- the player --------------------------------------------------------------------------------------

func build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.9
	shape.shape = capsule
	shape.position.y = 0.95
	player.add_child(shape)
	player_shape = shape
	head = Node3D.new()
	head.position.y = EYE_HEIGHT
	player.add_child(head)
	camera = Camera3D.new()
	camera.fov = 80
	camera.far = 1000
	head.add_child(camera)
	add_child(player)
	recenter()


func recenter() -> void:
	player.position = Vector3(-38, 0.5, 2)  # by Thornvale's well: a safer, more useful starting point than the empty crossroads
	player.velocity = Vector3.ZERO
	player.rotation.y = PI / 2.0  # face into the village square
	head.rotation.x = 0


## Movement settings live in scene/base.gd (so they can be changed live), with these defaults.
func setting(name: String, default):
	var base = ctx.get("parts", {}).get("base")
	if base and name in base:
		return base.get(name)
	return default


## True when there is room above the player to stand up.
func head_room() -> bool:
	var from := player.global_position + Vector3(0, CROUCH_HEIGHT - 0.1, 0)
	var query := PhysicsRayQueryParameters3D.create(from, player.global_position + Vector3(0, STAND_HEIGHT + 0.05, 0))
	query.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _physics_process(delta: float) -> void:
	if retired:
		return
	var playing := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var dir := Vector3.ZERO
	if playing:
		var x := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		var z := float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
		dir = (player.transform.basis * Vector3(x, 0, z)).normalized()
	var want_crouch := playing and Input.is_physical_key_pressed(KEY_CTRL)
	if not want_crouch and crouch_amount > 0.0 and not head_room():
		want_crouch = true  # something is overhead: stay down
	crouch_amount = move_toward(crouch_amount, 1.0 if want_crouch else 0.0, delta * 8.0)
	var capsule_shape: CapsuleShape3D = player_shape.shape
	capsule_shape.height = lerpf(STAND_HEIGHT, CROUCH_HEIGHT, crouch_amount)
	player_shape.position.y = capsule_shape.height / 2.0
	head.position.y = lerpf(EYE_HEIGHT, CROUCH_EYE, crouch_amount)
	var speed: float = setting("RUN_SPEED", 10.0) if Input.is_physical_key_pressed(KEY_SHIFT) else setting("WALK_SPEED", 5.0)
	speed *= lerpf(1.0, 0.4, crouch_amount) if crouch_amount > 0.0 else 1.0
	if ctx.get("state", {}).get("flying", false):  # flight (Barnaby's [fly]): Space up, Ctrl down, no gravity
		var up := float(playing and Input.is_physical_key_pressed(KEY_SPACE)) - float(want_crouch)
		var fly_speed: float = 60.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 20.0
		var fly_dir := dir
		if playing:  # W/S go where you look (up or down too), A/D strafe level; Space/Ctrl still work
			var fx := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
			var fz := float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
			fly_dir = (head.global_transform.basis * Vector3(0, 0, fz) + player.transform.basis * Vector3(fx, 0, 0)).normalized()
		player.velocity = fly_dir * fly_speed + Vector3(0, up * fly_speed, 0)
		player.move_and_slide()
		camera_motion(delta, false, false)
		return
	player.velocity.x = dir.x * speed + push.x  # (walking sets the speed every frame, so a blast's sideways shove lives in push)
	player.velocity.z = dir.z * speed + push.z
	if player.is_on_floor():
		if playing and Input.is_physical_key_pressed(KEY_SPACE):
			player.velocity.y = setting("JUMP_SPEED", 6.6)
	else:
		player.velocity.y -= GRAVITY * delta
	player.move_and_slide()
	camera_motion(delta, playing and dir.length() > 0.05 and player.is_on_floor(), speed > setting("WALK_SPEED", 5.0))
	push *= exp(-delta * (4.0 if player.is_on_floor() else 1.0))  # slides to a stop quickly on the ground, carries in the air
	if player.is_on_wall():
		push = Vector3.ZERO
	if player.position.y < -50:  # fell off the world
		recenter()


func camera_motion(delta: float, moving: bool, running: bool) -> void:
	walk_bob = move_toward(walk_bob, 1.0 if moving else 0.0, delta * 5.0)
	if moving:
		walk_phase += delta * (11.0 if running else 8.0)
	camera.position.y = sin(walk_phase) * 0.018 * walk_bob
	camera.rotation.z = sin(walk_phase * 0.5) * 0.003 * walk_bob


func _input(event: InputEvent) -> void:
	if retired:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = deg_to_rad(setting("LOOK_SENSITIVITY", 0.08))  # degrees per pixel
		player.rotate_y(-event.relative.x * sens)
		head.rotation.x = clamp(head.rotation.x - event.relative.y * sens, deg_to_rad(-89), deg_to_rad(89))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not ctx.get("ui_open", false):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # click to grab the mouse again
	elif event is InputEventKey and event.pressed and not event.echo:
		var typing = ctx.get("typing")  # a part with a text box open (the to-do book): only it gets the keys
		if typing and is_instance_valid(typing):
			typing.key(event)
			return
		match event.keycode:  # by key name (WASD movement uses the physical key position instead)
			KEY_TAB:
				go_to_chat()
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_R:
				recenter()
			KEY_F11:
				set_fullscreen(DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN)
			KEY_M:
				send({"t": "key", "k": "m"})
			KEY_N:
				send({"t": "key", "k": "n"})
		for part in parts:
			if part.has_method("key"):
				part.key(event)  # keys the parts add (inventory, ...)


# --- showing and hiding (only one of the chat and the world is on screen at a time) -------------------

func set_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


func show_world() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if was_fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_move_to_foreground()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func hide_world() -> void:
	was_fullscreen = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


func go_to_chat() -> void:
	send({"t": "switch"})
	hide_world()


# --- on-screen text ----------------------------------------------------------------------------------

func make_label(anchor_preset: int, align: int, color: Color, size: int) -> Label:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(anchor_preset, Control.PRESET_MODE_KEEP_SIZE, 16)
	label.horizontal_alignment = align
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_size_override("font_size", size)
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	return label


func build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	status_label = make_label(Control.PRESET_CENTER_TOP, HORIZONTAL_ALIGNMENT_CENTER, Color("#ff4d4d"), 28)
	notice_label = make_label(Control.PRESET_TOP_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT, Color("#8ef0a4"), 22)
	quest_label = make_label(Control.PRESET_TOP_LEFT, HORIZONTAL_ALIGNMENT_LEFT, Color("#ffd24d"), 20)
	quest_label.position.y = 284  # chat-provided tasks sit below the RPG story tracker
	for label in [status_label, notice_label, quest_label]:
		hud.add_child(label)


func show_notice(text: String, seconds := 3.5) -> void:
	notice_label.text = text
	notice_label.modulate.a = 1.0
	notice_until = Time.get_ticks_msec() / 1000.0 + seconds


## The quest list, top left. A part can add progress to a quest with quest_progress(id) -> " (2/3)".
func draw_quests() -> void:
	var ids: Array = ctx.get("quest_ids", [])
	var lines: Array = ctx.get("quest_lines", [])
	var out := []
	for i in lines.size():
		var line: String = lines[i]
		for part in parts:
			if i < ids.size() and part.has_method("quest_progress"):
				line += part.quest_progress(ids[i])
		out.append("- " + line)
	var text := ("QUESTS\n" + "\n".join(out)) if out else ""
	var jobs: Array = ctx.get("job_lines", [])  # the assistant's work queue (first = being worked on)
	if not jobs.is_empty():
		var rows := []
		for i in jobs.size():
			rows.append(("> " if i == 0 else "%d. " % i) + jobs[i])
		text += ("\n\n" if text != "" else "") + "WORKING ON\n" + "\n".join(rows)
	quest_label.text = text
