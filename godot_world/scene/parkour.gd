extends Node3D
## A glowing spiral of floating platforms to the east, for when you are idle: jump up it to the gold platform at the
## top. The timer starts when you leave the start pad, there are green checkpoints on the way, and falling to the
## ground sends you back to the last checkpoint. P brings you back to the last checkpoint (or the start) any time.
## The best time is kept in state["parkour_best"].

const CENTER := Vector3(40, 0, 5)
const COUNT := 44  # platforms in the spiral
const SIZE := 2.6
const CHECKPOINT_EVERY := 11

var ctx: Dictionary
var W
var pads := []  # [centre x, centre z, top y, half size, kind] where kind is "start", "plat", "check" or "goal"
var checkpoint := -1  # index of the last checkpoint reached (-1 = the start pad)
var started := false
var run_time := 0.0
var finished_at := -1.0
var spin := 0.0
var lamps := []
var extras := {}  # pad index -> data for the pads that move ("move") or fall away ("crumble")


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	add_pad(CENTER + Vector3(-12, 0, 0), 0.3, 3.2, "start")
	var top := 0.3
	var angle := PI
	for i in COUNT:
		var t := float(i) / (COUNT - 1)  # 0 at the bottom .. 1 at the top: everything gets harder as it goes up
		var section := i / CHECKPOINT_EVERY  # 0..3, each ends in a checkpoint
		var j := i % CHECKPOINT_EVERY
		angle += 0.38 + 0.12 * t  # wider gaps higher up (the last ones need a running jump)
		var radius := 12.0 + sin(i * 0.7) * 1.5
		top += rng.randf_range(0.3, 0.7) + 0.3 * t
		var size := lerpf(2.6, 1.5, t)
		var kind := "plat"
		if i == COUNT - 1:
			kind = "goal"
		elif (i + 1) % CHECKPOINT_EVERY == 0:
			kind = "check"
		elif section == 1 and j in [2, 5, 8]:
			kind = "move"  # slides in and out
		elif section == 2 and j in [1, 3, 5, 7, 9]:
			kind = "crumble"  # falls away shortly after you land
		elif section == 3 and j in [1, 4, 8]:
			kind = "move"
		elif section == 3 and j in [2, 6, 9]:
			kind = "crumble"
		if kind == "move":
			size = maxf(size, 2.0)
		add_pad(CENTER + Vector3(cos(angle) * radius, 0, sin(angle) * radius), top,
			5.0 if kind == "goal" else 4.0 if kind == "check" else size, kind)
	var goal: Array = pads[pads.size() - 1]
	add_beam(Vector3(goal[0], goal[2], goal[1]), Color(1.0, 0.85, 0.35, 0.18))
	var start: Array = pads[0]
	add_beam(Vector3(start[0], start[2], start[1]), Color(0.55, 0.95, 1.0, 0.14))


func add_pad(pos: Vector3, top: float, size: float, kind: String) -> void:
	var i := pads.size()
	var hue := fmod(0.52 + i * 0.012, 1.0)
	var color := Color.from_hsv(hue, 0.55, 0.9)
	if kind == "start":
		color = Color("#6fe8ff")
	elif kind == "check":
		color = Color("#4dff88")
	elif kind == "goal":
		color = Color("#ffd24d")
	elif kind == "move":
		color = Color("#b48cff")
	elif kind == "crumble":
		color = Color("#ff7a6b")
	var thick := 0.4
	# each pad is its own node (at its x/z), so sliding or dropping one carries its collider along
	var root := Node3D.new()
	root.position = Vector3(pos.x, 0, pos.z)
	add_child(root)
	var node: MeshInstance3D = W.box(root, Vector3(0, top - thick / 2.0, 0), Vector3(size, thick, size), color, "cube", true)
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.35)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.9 if kind == "plat" else 1.6
	node.material_override = m
	if kind in ["start", "check", "goal"]:
		var lamp := OmniLight3D.new()
		lamp.light_color = color
		lamp.light_energy = 1.5
		lamp.omni_range = 7.0
		lamp.position = Vector3(0, top + 1.2, 0)
		root.add_child(lamp)
		lamps.append(lamp)
	if kind == "move":  # slides in and out along the spiral's radius; the speed and phase differ per pad
		var out := Vector2(pos.x - CENTER.x, pos.z - CENTER.z).normalized()
		extras[i] = {"root": root, "mat": m, "base": Vector2(pos.x, pos.z), "dir": out, "amp": 1.9,
			"period": 3.2 + (i % 3) * 0.7, "phase": i * 1.3}
	elif kind == "crumble":
		extras[i] = {"root": root, "mat": m, "base": Vector2(pos.x, pos.z), "top": top, "timer": 0.0, "fall": -1.0}
	pads.append([pos.x, pos.z, top, size / 2.0, kind])


func add_beam(base: Vector3, color: Color) -> void:
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.1
	cyl.bottom_radius = 0.3
	cyl.height = 40.0
	beam.mesh = cyl
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = color
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = bm
	beam.position = base + Vector3(0, 20, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)


func pad_under_feet() -> int:
	var p: Vector3 = ctx.player.position
	var feet := p.y  # the player's origin is at its feet
	for i in pads.size():
		var pad: Array = pads[i]
		if feet - pad[2] > -0.25 and feet - pad[2] < 0.5 and absf(p.x - pad[0]) < pad[3] + 0.5 and absf(p.z - pad[1]) < pad[3] + 0.5:
			return i
	return -1


func send_to(index: int) -> void:
	var pad: Array = pads[index + 1]  # pads[0] is the start pad, so platform i is pads[i + 1]
	ctx.player.position = Vector3(pad[0], pad[2] + 0.05, pad[1])
	ctx.player.velocity = Vector3.ZERO
	if index < 0:
		started = false  # back at the start: the clock starts again on the first platform


func key(event: InputEventKey) -> void:
	if event.keycode == KEY_P and (started or checkpoint >= 0):
		send_to(checkpoint)
		W.show_notice("Back to the %s." % ("last checkpoint" if checkpoint >= 0 else "start"), 2.0)


func crumble(idx: int, delta: float) -> void:
	for i in extras:
		var e: Dictionary = extras[i]
		var pad: Array = pads[i]
		if pad[4] != "crumble":
			continue
		var root: Node3D = e["root"]
		if e["fall"] >= 0.0:  # fallen: drops away, then comes back after a few seconds
			e["fall"] += delta
			root.position.y = -9.0 * e["fall"] * e["fall"]
			if e["fall"] > 3.0:
				e["fall"] = -1.0
				e["timer"] = 0.0
				pad[2] = e["top"]
				root.position = Vector3(pad[0], 0, pad[1])
				e["mat"].emission_energy_multiplier = 0.9
			continue
		if idx == i:
			e["timer"] += delta
		else:
			e["timer"] = maxf(e["timer"] - delta, 0.0)
		var t: float = e["timer"]
		e["mat"].emission_energy_multiplier = 0.9 + t * 4.0 + (sin(spin * 40.0) * 0.8 if t > 0.3 else 0.0)
		root.position.x = pad[0] + (sin(spin * 70.0) * 0.04 if t > 0.3 else 0.0)
		if t > 0.8:
			e["fall"] = 0.0
			pad[2] = -100.0  # no longer something to stand on


func fmt(t: float) -> String:
	return "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]


func seen_from(from: Vector3, _viewer: Node) -> Array:
	return ["a spiral tower of glowing floating platforms %s, with a golden platform at the top, which the wanderer jumps up for fun" % W.where(from, CENTER)]


func _process(delta: float) -> void:
	if pads.is_empty():
		return
	spin += delta
	for l in lamps:
		l.light_energy = 1.3 + sin(spin * 3.0) * 0.4
	var standing := pad_under_feet()  # found before the pads slide, so the player is still where it was
	var carry := {}  # pad index -> how far it slid this frame
	for i in extras:
		var e: Dictionary = extras[i]
		var pad: Array = pads[i]
		if pad[4] == "move":
			var off: float = sin(spin * TAU / e["period"] + e["phase"]) * e["amp"]
			var nx: float = e["base"].x + e["dir"].x * off
			var nz: float = e["base"].y + e["dir"].y * off
			carry[i] = Vector2(nx - pad[0], nz - pad[1])
			pad[0] = nx
			pad[1] = nz
			e["root"].position = Vector3(nx, 0, nz)
	if carry.has(standing):  # standing on a sliding pad: ride along
		ctx.player.position += Vector3(carry[standing].x, 0, carry[standing].y)
	var idx := pad_under_feet()
	crumble(idx, delta)
	var p: Vector3 = ctx.player.position
	var feet := p.y
	if idx > 0 and not started and finished_at < 0.0:  # stepped onto the first platform: the clock starts
		started = true
		run_time = 0.0
		W.show_notice("Go! Reach the golden platform. Green pads are checkpoints (P goes back to one), purple pads slide, red pads crumble.", 6.0)
	if started:
		run_time += delta
		if idx > 0:
			var kind: String = pads[idx][4]
			if kind == "check" and idx - 1 > checkpoint:
				checkpoint = idx - 1
				W.show_notice("Checkpoint! %s" % fmt(run_time), 2.5)
			elif kind == "goal":
				started = false
				finished_at = run_time
				var best: float = ctx.state.get("parkour_best", 0.0)
				var msg := "You made it to the top in %s!" % fmt(run_time)
				if best <= 0.0 or run_time < best:
					ctx.state["parkour_best"] = run_time
					msg += " New best!"
				else:
					msg += " (best %s)" % fmt(best)
				W.show_notice(msg, 6.0)
				checkpoint = -1
		elif idx < 0 and feet < 0.3 and Vector2(p.x - CENTER.x, p.z - CENTER.z).length() < 20.0 and ctx.player.is_on_floor():
			send_to(checkpoint)  # fell to the ground
			W.show_notice("You fell! Back to the %s." % ("last checkpoint" if checkpoint >= 0 else "start"), 2.0)
	elif finished_at >= 0.0 and idx == 0:  # back on the start pad: ready for another run
		finished_at = -1.0
		checkpoint = -1
