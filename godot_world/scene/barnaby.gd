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
var talker: Node3D  # his speech bubble, mouth and listening / thinking symbol (scene/talk.gd)
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
	# the mouth: a dark oval pressed onto the front of the mustache (its face is at z = -0.22)
	talker = ctx.parts["talk"].make(W, body, 2.25, Vector3(-0.01, 1.558, -0.232), Vector3(0.07, 0.02, 0.014))
	var s: Dictionary = ctx.state.get_or_add("barnaby", {"x": 6.0, "z": -6.0, "mode": "wander"})
	body.position = Vector3(s.x, 0, s.z)
	target = body.position


func st() -> Dictionary:
	return ctx.state["barnaby"]


func is_near() -> bool:
	var p: Vector3 = ctx.player.position
	return Vector2(p.x - body.position.x, p.z - body.position.z).length() < NEAR


func describe() -> String:
	var here := body.position
	var seen := ["a wide grassy meadow in a valley"]
	seen.append_array(W.seen_around(here, self))  # everything the other parts report (see world.gd)
	if st().get("mode") == "atop":
		seen.append("you are standing on top of the placed object")
	if st().get("mode") == "look":
		seen.append("you are slowly turning on the spot to look all around you right now: say what you notice")
	seen.append("the wanderer is %s" % W.where(here, ctx.player.position))
	return "; ".join(seen)


## What the other characters see of him.
func seen_from(from: Vector3, viewer: Node) -> Array:
	if viewer == self or not body:
		return []
	return ["Barnaby, the old lighthouse keeper, %s" % W.where(from, body.position)]


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
	elif body.rotation.x != 0.0:  # a throw cut short by another command: back on his feet
		body.rotation.x = 0.0
	body.position.y += 0.021 + W.ground_y(body.position.x, body.position.z)  # (boot soles reach 2 cm below his feet)
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
	st()["x"] = body.position.x
	st()["z"] = body.position.z


func handle(c: Dictionary) -> bool:
	match c.get("cmd", ""):
		"say_start", "say_end", "say", "npc_state":  # his voice and mind, from the chat (see talk.gd)
			if c.get("who", "barnaby") != "barnaby":
				return false
			match c["cmd"]:
				"say_start":
					talker.say_start(str(c.get("text", "")))
				"say_end":
					talker.say_end()
				"say":
					talker.say(str(c.get("text", "")))
				_:  # "listening", "thinking" or ""
					talker.set_mind(str(c.get("state", "")))
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
