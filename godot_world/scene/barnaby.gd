extends Node3D
## Barnaby Finch, the old lighthouse keeper looking for the sea. His look is models/barnaby.json (about 275
## textured boxes; named parts: leg_l, leg_r, arm_l, arm_r, rod). He wanders, stops and faces you when you
## come close (the chat window then listens hands-free and he answers), and does what his commands say.
## His commands are listed for him in barnaby_commands.txt (next to chat.pyw); each one is handled in
## handle() below. describe() is what he "sees" and gets with every message: add new things there.

var npc_id := "barnaby"
const NEAR := 4.0  # how close you must be for him to stop and listen
const WANDER := 20.0  # he roams within this distance of the middle
const SPEED := 1.5  # walking speed (m/s); following you he goes faster

var ctx: Dictionary
var W
var body: Node3D
var limbs := []  # [node, direction]: legs and arms swing opposite ways while he walks
var target := Vector3.ZERO
var phase := 0.0
const ATOP_SECONDS := 8.0  # how long he stays on top of an object before roaming again
var atop_time := 0.0
const LOOK_SECONDS := 7.0  # how long one slow turn on the spot takes
var throw_from := Vector3.ZERO  # [throw] (Marigold flings him to the wanderer): start, landing spot, flight
var throw_to := Vector3.ZERO
var throw_t := 0.0
var throw_time := 1.0
var throw_height := 3.0
var thrown_y := 0.0
var throw_phase := "fetch"
const HELI_SECONDS := 5.0  # how long the helicopter lasts (seconds)
var heli_time := 0.0
var look_time := 0.0
var look_yaw := 0.0
var lift := 0.0  # height he is standing above the ground (on top of an object)


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	var named: Dictionary = W.build_model("barnaby", self)
	body = named["root"]
	for pair in [["leg_l", 1], ["leg_r", -1], ["arm_l", -1], ["arm_r", 1]]:
		if named.has(pair[0]):
			limbs.append([named[pair[0]], pair[1]])
	build_talk()
	var s: Dictionary = ctx.state.get_or_add("barnaby", {"x": 6.0, "z": -6.0, "mode": "wander"})
	body.position = Vector3(s.x, 0, s.z)
	target = body.position


## --- talking: the mouth opens and closes and a chat bubble shows the sentence being spoken -------------------
const CHARS_PER_SECOND := 15.0  # about how fast his voice reads
const MOUTH_Y := 1.558  # where the lips are (the dark line in the mustache)
var mouth: MeshInstance3D
var bubble: Node3D
var bubble_vp: SubViewport  # the speech bubble is drawn 2D in here and shown on a billboard sprite
var bubble_canvas: Control
var bubble_sprite: Sprite3D
var bubble_text := ""
var bubble_lines := []  # the sentence cut into lines
var bubble_shown := -1  # letters shown so far (they appear one by one while he speaks)
var bubble_size := Vector2(100, 100)
var bubble_font: SystemFont
# the bubble is pixel art: it is drawn tiny (one unit = one big pixel) and scaled up without smoothing
const BUBBLE_FONT := 16
const BUBBLE_WRAP := 190.0
const BUBBLE_PAD := 9
const BUBBLE_TAIL := 8
const BUBBLE_INK := Color("#2b1d12")
const BUBBLE_PAPER := Color("#fff3d6")
var lines := []  # [start, end, text] of the sentences he is (about to be) saying
var talk_end := 0.0


func build_talk() -> void:
	# a dark oval pressed onto the front of the mustache (its face is at z = -0.22), ahead of the dark bits there
	mouth = W.box(body, Vector3(-0.01, MOUTH_Y, -0.232), Vector3(0.07, 0.02, 0.014), Color("#3a0f12"), "sphere")
	mouth.visible = false
	bubble = Node3D.new()
	bubble.position = Vector3(0, 2.25, 0)
	bubble.visible = false
	body.add_child(bubble)
	bubble_vp = SubViewport.new()
	bubble_vp.transparent_bg = true
	bubble_vp.size = Vector2i(100, 100)
	bubble_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	bubble.add_child(bubble_vp)
	bubble_canvas = Control.new()
	bubble_canvas.draw.connect(draw_bubble)
	bubble_vp.add_child(bubble_canvas)
	bubble_sprite = Sprite3D.new()
	bubble_sprite.texture = bubble_vp.get_texture()
	bubble_sprite.pixel_size = 0.0065
	bubble_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble_sprite.shaded = false
	bubble_sprite.no_depth_test = true
	bubble_sprite.render_priority = 5
	bubble_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	bubble_font = SystemFont.new()
	bubble_font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	bubble_font.font_weight = 700
	bubble_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	bubble_font.hinting = TextServer.HINTING_NONE
	bubble_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	bubble.add_child(bubble_sprite)
	build_mind()


## A symbol above his head: "?" while he thinks, a pulsing "..." while he listens (nothing while he talks).
var mind_state := ""
var mind_label: Label3D


func build_mind() -> void:
	mind_label = Label3D.new()
	mind_label.position = Vector3(0, 2.2, 0)
	mind_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mind_label.no_depth_test = true
	mind_label.render_priority = 6
	mind_label.shaded = false
	mind_label.font_size = 160
	mind_label.pixel_size = 0.004
	mind_label.outline_size = 36
	mind_label.outline_modulate = BUBBLE_INK
	mind_label.font = bubble_font
	mind_label.visible = false
	body.add_child(mind_label)


func update_mind() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var talking: bool = bubble.visible
	if mind_state == "" or talking:
		mind_label.visible = false
		return
	mind_label.visible = true
	if mind_state == "thinking":
		mind_label.text = "?"
		mind_label.modulate = Color("#ffd24d")
		mind_label.position.y = 2.2 + sin(now * 4.0) * 0.06
		mind_label.rotation.z = sin(now * 3.0) * 0.15
	else:
		mind_label.text = ".".repeat(1 + int(now * 3.0) % 3)
		mind_label.modulate = Color("#4dff88")
		mind_label.position.y = 2.2
		mind_label.rotation.z = 0.0


func set_bubble_text(text: String) -> void:
	bubble_text = text
	bubble_shown = -1
	bubble_lines.clear()
	var cur := ""
	for word in text.split(" ", false):
		var test: String = word if cur == "" else cur + " " + word
		if cur != "" and bubble_font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT).x > BUBBLE_WRAP:
			bubble_lines.append(cur)
			cur = word
		else:
			cur = test
	bubble_lines.append(cur)
	var widest := 0.0
	for l in bubble_lines:
		widest = maxf(widest, bubble_font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT).x)
	var h := bubble_font.get_height(BUBBLE_FONT) * bubble_lines.size()
	bubble_size = Vector2(ceilf(widest) + BUBBLE_PAD * 2, ceilf(h) + BUBBLE_PAD * 2 + BUBBLE_TAIL)
	bubble_size = Vector2(roundf(bubble_size.x / 2.0) * 2.0, bubble_size.y)  # even width, so the tail is centred
	bubble_vp.size = Vector2i(bubble_size)
	bubble_canvas.size = bubble_size
	bubble_sprite.offset = Vector2(0, bubble_size.y / 2.0)  # the tail's tip sits at the bubble's anchor


func show_letters(count: int) -> void:
	if count != bubble_shown:
		bubble_shown = count
		bubble_canvas.queue_redraw()


func px(r: Rect2, c: Color) -> void:
	bubble_canvas.draw_rect(r, c)


func draw_bubble() -> void:
	var w := bubble_size.x
	var bh := bubble_size.y - BUBBLE_TAIL  # height of the box without the tail
	# a chunky outline with stepped (square) corners, like a pixel-art speech box
	px(Rect2(2, 0, w - 4, bh), BUBBLE_INK)
	px(Rect2(0, 2, w, bh - 4), BUBBLE_INK)
	px(Rect2(4, 2, w - 8, bh - 4), BUBBLE_PAPER)
	px(Rect2(2, 4, w - 4, bh - 8), BUBBLE_PAPER)
	var cx := w / 2.0
	for i in 4:  # the tail: a little staircase pointing down
		px(Rect2(cx - 7 + 2 * i, bh + 2 * i, 14 - 4 * i, 2), BUBBLE_INK)
		if i < 3:
			px(Rect2(cx - 5 + 2 * i, bh + 2 * i, 10 - 4 * i, 2), BUBBLE_PAPER)
	px(Rect2(cx - 5, bh - 2, 10, 2), BUBBLE_PAPER)  # opens the outline where the tail joins
	var lh := bubble_font.get_height(BUBBLE_FONT)
	var left := bubble_shown
	var y := float(BUBBLE_PAD)
	for l in bubble_lines:
		if left <= 0:
			break
		var part: String = l.substr(0, left)
		bubble_canvas.draw_string(bubble_font, Vector2(BUBBLE_PAD, y + bubble_font.get_ascent(BUBBLE_FONT)), part,
			HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT, BUBBLE_INK)
		left -= l.length() + 1
		y += lh


func say(text: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if text.strip_edges() == "":  # the voice was stopped
		lines.clear()
		talk_end = 0.0
		return
	var sentence := ""
	var pieces := []
	for i in text.length():
		sentence += text[i]
		if text[i] in ".!?" and (i + 1 >= text.length() or text[i + 1] == " "):
			pieces.append(sentence.strip_edges())
			sentence = ""
	if sentence.strip_edges() != "":
		pieces.append(sentence.strip_edges())
	for piece in pieces:
		var start := maxf(now + 0.3, talk_end)
		var end := start + clampf(piece.length() / CHARS_PER_SECOND, 0.8, 25.0)
		lines.append([start, end, piece])
		talk_end = end + 0.15


## Sentence timing straight from the voice: the chat sends say_start when his voice begins a sentence and
## say_end when it finishes, so the bubble and mouth follow what is really being spoken.
var cps := 14.0  # letters per second his voice actually reads (learned from finished sentences)


func say_start(text: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	lines.clear()
	lines.append([now, now + 60.0, text, true])  # the end is set by say_end (60 s = safety net)
	talk_end = 0.0


func say_end() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if lines.is_empty() or lines[0].size() < 4:
		return
	var elapsed: float = now - lines[0][0]
	var n: int = lines[0][2].length()
	if elapsed > 0.6 and n > 8:
		cps = lerpf(cps, clampf(n / elapsed, 6.0, 40.0), 0.5)
	lines[0][1] = now


func update_talk() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	while lines.size() > 1 and lines[1][0] <= now:
		lines.pop_front()
	if lines.is_empty() or now < lines[0][0] or now > lines[0][1] + 1.5:
		if not lines.is_empty() and now > lines[0][1] + 1.5:
			lines.pop_front()
		if lines.is_empty() or now < lines[0][0]:
			mouth.visible = false
			bubble.visible = false
			return
	var line: Array = lines[0]
	if bubble_text != line[2]:
		set_bubble_text(line[2])
	bubble.visible = true
	# the letters appear one by one, about twice as fast as his voice reads
	var progress := clampf((now - line[0]) * 2.0 / maxf(line[1] - line[0], 0.1), 0.0, 1.0)
	if line.size() > 3:  # timed by the real voice: type at his reading speed, all shown once he finishes
		progress = 1.0 if now >= line[1] else clampf((now - line[0]) * cps * 1.7 / maxf(bubble_text.length(), 1), 0.0, 1.0)
	show_letters(ceili(bubble_text.length() * progress))
	var speaking: bool = now <= line[1]
	mouth.visible = speaking
	if speaking:
		var open := absf(sin(now * 13.0)) * (0.55 + 0.45 * sin(now * 4.7 + 1.0))
		mouth.scale.y = 0.02 + open * 0.035
		mouth.position.y = MOUTH_Y - open * 0.0175


func st() -> Dictionary:
	return ctx.state["barnaby"]


func is_near() -> bool:
	var p: Vector3 = ctx.player.position
	return Vector2(p.x - body.position.x, p.z - body.position.z).length() < NEAR


func describe() -> String:
	var here := body.position
	var seen := ["an endless dark field with a faint green grid, under a dark sky with a red moon"]
	var base = ctx.parts.get("base")
	if base:
		seen.append_array(base.describe_placed(here))
	var sea = ctx.parts.get("sea")
	if sea:
		seen.append_array(sea.describe_sea(here))
	var stall = ctx.parts.get("marigold")
	if stall:
		seen.append_array(stall.describe_stall(here))
	var course = ctx.parts.get("parkour")
	if course:
		seen.append_array(course.describe_course(here))
	var goblins = ctx.parts.get("goblins")
	if goblins:
		seen.append_array(goblins.describe_goblins(here))
	var polish = ctx.parts.get("conchpolish")
	if polish:
		seen.append(polish.describe())
	var hotbar = ctx.parts.get("hotbar")
	if hotbar:
		seen.append_array(hotbar.describe_hotbar())
	var builder = ctx.parts.get("builder")
	if builder:
		seen.append_array(builder.describe_blocks(here))
	if ctx.state.get("hammer", false):
		seen.append("the wanderer is holding a builder's hammer")
	if st().get("mode") == "atop":
		seen.append("you are standing on top of the placed object")
	if st().get("mode") == "look":
		seen.append("you are slowly turning on the spot to look all around you right now: say what you notice")
	seen.append("the wanderer is %s" % W.where(here, ctx.player.position))
	return "; ".join(seen)


## Walk toward `goal`, stopping `stop` m short. Returns true while still walking.
func walk_to(goal: Vector3, speed: float, stop: float, delta: float) -> bool:
	var d := Vector3(goal.x - body.position.x, 0, goal.z - body.position.z)
	var dist := d.length()
	if dist <= stop + 0.1:  # (a margin, so rounding can't keep him "not there yet")
		return false
	body.position += d / dist * minf(dist - stop, speed * delta)
	W.face(body, goal)
	return true


func _process(delta: float) -> void:
	if not body:
		return
	var player: Vector3 = ctx.player.position
	var moving := false
	match st().get("mode", "wander"):
		"follow":
			moving = walk_to(player, 4.0, 2.5, delta)
			if not moving:
				W.face(body, player)
		"stay":
			if is_near():
				W.face(body, player)
		"climb":  # walk up to the chosen object, then hop onto it
			moving = walk_to(Vector3(st().cx, 0, st().cz), 3.0, 1.0, delta)
			if not moving:
				st()["mode"] = "atop"
		"look":  # stand still and turn slowly all the way round, taking in the surroundings
			look_time += delta
			var t := clampf(look_time / LOOK_SECONDS, 0.0, 1.0)
			body.rotation.y = look_yaw + TAU * smoothstep(0.0, 1.0, t)
			if look_time > LOOK_SECONDS + 0.8:
				st()["mode"] = "stay"
				W.face(body, player)
		"thrown":  # flung through the air (somersaulting), lands on his back, lies dazed a moment, then gets up
			# phases: fetch (Marigold walks over to him) -> carry (she lifts him overhead and turns to the wanderer)
			# -> fly (the throw) -> lie (flat on his back, dazed) -> back to wandering
			throw_t += delta
			var mari = ctx.parts.get("marigold")
			if mari == null or mari.body == null:  # no Marigold: nothing to be thrown by
				st()["mode"] = "wander"
				target = body.position
			elif throw_phase == "fetch":
				var to_her: Vector3 = mari.body.position - body.position
				to_her.y = 0
				W.face(body, mari.body.position)  # he watches her come
				thrown_y = 0.0
				mari.errand_goal = body.position + to_her.normalized() * 0.9  # she walks up to him
				if to_her.length() < 1.3 or throw_t > 30.0:
					throw_phase = "carry"
					throw_t = 0.0
					mari.errand_goal = null
			elif throw_phase == "carry":
				var u := clampf(throw_t / 0.8, 0.0, 1.0)
				mari.arms_up = true
				W.face(mari.body, player)  # she turns to the wanderer and hoists him up
				body.position.x = lerpf(body.position.x, mari.body.position.x, minf(delta * 8.0, 1.0))
				body.position.z = lerpf(body.position.z, mari.body.position.z, minf(delta * 8.0, 1.0))
				thrown_y = u * 1.9
				if u >= 1.0:
					var fwd: Vector3 = -ctx.player.global_transform.basis.z
					throw_from = Vector3(body.position.x, thrown_y, body.position.z)
					throw_to = Vector3(player.x + fwd.x * 2.0, 0, player.z + fwd.z * 2.0)
					var dist := Vector2(throw_to.x - throw_from.x, throw_to.z - throw_from.z).length()
					throw_time = clampf(dist / 11.0, 0.9, 3.0)
					throw_height = 2.0 + dist * 0.12
					throw_phase = "fly"
					throw_t = 0.0
					mari.arms_up = false
			elif throw_phase == "fly":
				var u := minf(throw_t / throw_time, 1.0)
				body.position.x = lerpf(throw_from.x, throw_to.x, u)
				body.position.z = lerpf(throw_from.z, throw_to.z, u)
				thrown_y = lerpf(throw_from.y, 0.0, u) + 4.0 * throw_height * u * (1.0 - u)
				body.rotation.x = -u * TAU * 2.0
				if u >= 1.0:
					throw_phase = "lie"
					throw_t = 0.0
			else:  # lie
				thrown_y = 0.0
				body.rotation.x = -deg_to_rad(88)  # flat on his back
				if throw_t > 1.6:
					body.rotation.x = 0.0
					st()["mode"] = "wander"
					target = body.position
					W.face(body, player)
		"heli":  # arms out like rotor blades, spinning fast and hovering, then back to what he was doing
			heli_time += delta
			body.rotation.y += delta * 18.0
			if heli_time > HELI_SECONDS:
				var back: String = st().get("heli_prev", "wander")
				st()["mode"] = back if back in ["follow", "stay", "wander"] else "wander"
				target = body.position
		"atop":  # standing on top of the object
			moving = walk_to(Vector3(st().cx, 0, st().cz), 2.0, 0.0, delta)
			if not moving and is_near():
				W.face(body, player)
			atop_time += delta
			if atop_time > ATOP_SECONDS:  # had enough of the view: hop down and roam again
				st()["mode"] = "wander"
				target = body.position
		_:  # wander, but stop and face you when you are close
			if is_near():
				W.face(body, player)
			else:
				moving = walk_to(target, SPEED, 0.0, delta)
				if not moving:  # pick somewhere new to stroll to
					target = Vector3(randf_range(-WANDER, WANDER), 0, randf_range(-WANDER, WANDER))
	var lift_goal: float = st().get("top", 0.0) if st().get("mode") == "atop" else 0.0
	if st().get("mode") == "heli":
		lift_goal = 2.5
	if absf(lift - lift_goal) > 0.01:  # hop up (with a little arc) or drop down
		lift = move_toward(lift, lift_goal, 5.0 * delta)
		body.position.y = lift + (0.4 * sin(clampf(lift / maxf(lift_goal, 0.1), 0, 1) * PI) if lift_goal > 0 else 0.0)
	else:
		lift = lift_goal
		body.position.y = lift
	if st().get("mode") == "thrown":
		lift = 0.0
		body.position.y = thrown_y
	body.position.y += 0.021  # boot soles reach 2 cm below his feet; keep them out of the ground
	phase += delta * 8 if moving else 0.0
	var swing := sin(phase) * deg_to_rad(30) if moving else 0.0
	for pair in limbs:
		pair[0].rotation.x = swing * pair[1]
	if limbs.size() == 4:  # arms straight out sideways while he is a helicopter
		var out := deg_to_rad(90) if st().get("mode") == "heli" else 0.0
		limbs[2][0].rotation.z = -out
		limbs[3][0].rotation.z = out
		if out != 0.0:
			limbs[2][0].rotation.x = 0.0
			limbs[3][0].rotation.x = 0.0
	update_talk()
	update_mind()
	st()["x"] = body.position.x
	st()["z"] = body.position.z


func handle(c: Dictionary) -> bool:
	match c.get("cmd", ""):
		"say_start":  # his voice begins a sentence
			if c.get("who", "barnaby") != "barnaby":
				return false
			say_start(str(c.get("text", "")))
		"say_end":  # his voice finished the sentence
			if c.get("who", "barnaby") != "barnaby":
				return false
			say_end()
		"say":  # sent by the chat for every sentence he speaks aloud
			if c.get("who", "barnaby") != "barnaby":
				return false
			say(str(c.get("text", "")))
		"npc_state":  # what he is doing with your words: "listening", "thinking" or ""
			if c.get("who", "barnaby") != "barnaby":
				return false
			mind_state = str(c.get("state", ""))
		"follow":
			st()["mode"] = "follow"
		"wander":
			st()["mode"] = "wander"
			target = body.position
		"stay":
			st()["mode"] = "stay"
		"throw":  # [throw] (used by Marigold): he is picked up at her and flung in an arc to land in front of the wanderer
			var mari = ctx.parts.get("marigold")
			if mari == null or mari.body == null or st().get("mode") == "thrown":
				return true
			mari.errand_active = true  # she walks over to him first (see "thrown" in _process)
			mari.errand_goal = null
			throw_phase = "fetch"
			throw_t = 0.0
			st()["mode"] = "thrown"
			W.show_notice("Marigold goes to fetch Barnaby...", 3.0)
		"helicopter":  # [helicopter]: spin with arms out, hover for a few seconds, then carry on
			if st().get("mode") != "heli":
				st()["heli_prev"] = st().get("mode", "wander")
			st()["mode"] = "heli"
			heli_time = 0.0
		"look":  # [look]: stop and turn slowly round to take in the surroundings
			st()["mode"] = "look"
			look_time = 0.0
			look_yaw = body.rotation.y
		"climb":  # [climb color/shape]: onto the matching placed object, else the nearest one
			var best = null
			var best_d := INF
			var best_top := 1.0
			var args: Array = c.get("args", [])
			for spec in ctx.state.get("placed", []):
				var d := Vector2(spec.x - body.position.x, spec.z - body.position.z).length()
				if str(spec.get("color", "")) in args or str(spec.get("shape", "")) in args:
					d -= 10000.0
				if d < best_d:
					best_d = d
					best = Vector2(spec.x, spec.z)
					var shape: String = spec.get("shape", "box")
					best_top = 4.0 if shape == "pillar" else (1.2 if shape in ["sphere", "ball"] else 1.0)
			var names: Array = ctx.parts["builder"].COLOR_NAMES if ctx.parts.has("builder") else []
			var lone := false
			for w in ["single", "lone", "one", "solo", "alone", "lonely"]:
				lone = lone or w in args
			for b in ctx.state.get("blocks", []):  # blocks built with the hammer count too
				var bx: float = float(b[0]) + 0.5
				var bz: float = float(b[2]) + 0.5
				var d := Vector2(bx - body.position.x, bz - body.position.z).length()
				var same := []  # the blocks of that colour on that level: he stands in the middle of them
				for o in ctx.state.get("blocks", []):
					if int(o[1]) == int(b[1]) and int(o[3]) == int(b[3]) and absf(float(o[0]) - float(b[0])) <= 3.0 \
							and absf(float(o[2]) - float(b[2])) <= 3.0:
						same.append(Vector2(float(o[0]) + 0.5, float(o[2]) + 0.5))
				if names.size() > 0 and str(names[int(b[3]) % names.size()]) in args:
					d -= 10000.0
					if lone:  # "the single one": a block of that colour with no same-coloured neighbours
						d -= 5000.0 if same.size() == 1 else 0.0
					else:  # otherwise the highest ones win
						d -= 100.0 * float(b[1])
				if d < best_d:
					best_d = d
					best = Vector2(bx, bz)
					best_top = float(b[1]) + 1.0
					var sum := Vector2.ZERO
					for v in same:
						sum += v
					best = sum / same.size()
			if best == null:
				return true
			st()["cx"] = best.x
			st()["cz"] = best.y
			st()["top"] = best_top
			st()["mode"] = "climb"
			atop_time = 0.0
		_:
			return false
	return true
