extends Node3D
## Villagers going about their day: each has a little routine of places to walk to and things to do there
## ("work" swings their tool, "idle" just stands and looks around). A farmer hoes the wheat field, a woodcutter
## chops at the log pile, a water carrier goes between the well and the cottages, a shepherd watches the flock,
## and guards stand at the castle gate and walk the south wall. They step aside a little when you are in their way.
## Also builds the wheat field (with a scarecrow) and the woodcutter's log pile they work at.
##
## A routine is a list of steps [place, action, seconds]; places are world positions (y is filled in from the
## ground unless given, e.g. on the castle wall). New villagers: add an entry to plan().

const FIELD := Vector3(-30, 0, -28)  # the wheat field (centre), 12 x 8 m
const LOGS := Vector3(-54, 0, -20)  # the woodcutter's log pile and chopping block

var ctx: Dictionary
var W
var kit
var folk := []  # {node, legs, arms, tool_arm, steps, step, wait, phase, name}
var spin := 0.0


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	kit = ctx.parts["kit"]
	build_field()
	build_logs()
	for p in plan():
		add_person(p)


func plan() -> Array:
	var village: Vector3 = ctx.parts["terrain"].VILLAGE
	var castle: Vector3 = ctx.parts["terrain"].CASTLE
	var top: float = ctx.parts["terrain"].CASTLE_TOP
	var gate := Vector3(castle.x, top, castle.z + 20.0)
	var wall_y := top - 0.3 + 7.0 # walking along the top of the south wall, behind the battlements
	var wall_z := castle.z + 15.6
	var pasture: Vector3 = ctx.parts["animals"].PASTURE if ctx.parts.has("animals") else village + Vector3(6, 0, 24)
	return plan_all(village, gate, wall_y, wall_z, castle, pasture)


## (Chapter 4: with the castle burnt, the guards are no longer at the castle: they camp in the village instead.)
func plan_all(village: Vector3, gate: Vector3, wall_y: float, wall_z: float, castle: Vector3, pasture: Vector3) -> Array:
	var people := base_plan(village, gate, wall_y, wall_z, castle, pasture)
	if W.flag("castle") in ["burnt", "ruin", "tolled"]:
		var out := []
		for p in people:
			if p.name == "a guard":
				p.name = "a refugee guard"
				var spot: Vector3 = village + Vector3(-6.0 + out.size() * 3.0, 0, -9.0)
				p.steps = [[spot, "idle", 20.0], [spot + Vector3(2.0, 0, 1.5), "idle", 8.0]]
			elif p.name == "a guard on the wall":
				continue
			out.append(p)
		return out
	return people


func base_plan(village: Vector3, gate: Vector3, wall_y: float, wall_z: float, castle: Vector3, pasture: Vector3) -> Array:
	return [
		{"who": "wat", "display": "Wat", "bio": "Wat the farmer: cheerful, sunburnt, forever fighting crows and worrying about the harvest; gossips about everyone", "name": "the farmer", "tunic": "#6a7d3a", "hat": "straw", "tool": "hoe", "steps": [
			[FIELD + Vector3(-4, 0, -2), "work", 6.0], [FIELD + Vector3(0, 0, -2), "work", 6.0], [FIELD + Vector3(4, 0, 2), "work", 6.0],
			[FIELD + Vector3(-2, 0, 2), "work", 5.0], [village + Vector3(2, 0, -4), "idle", 5.0]]},
		{"who": "osric", "display": "Osric", "bio": "Osric the woodcutter: big, quiet, few words, knows the Wolfwood better than anyone and respects the wolves", "name": "the woodcutter", "tunic": "#7a3b2a", "hat": "hood", "tool": "axe", "steps": [
			[LOGS + Vector3(0.9, 0, 0.6), "work", 9.0], [LOGS + Vector3(-1.5, 0, 2.5), "idle", 3.0], [LOGS + Vector3(0.9, 0, 0.6), "work", 7.0],
			[village + Vector3(-1, 0, -3), "idle", 6.0]]},
		{"who": "elsie", "display": "Elsie", "bio": "Elsie the water carrier: a quick, sharp-tongued young woman who hears all the village news at the well", "name": "the water carrier", "tunic": "#3d5a7a", "hat": "", "tool": "bucket", "steps": [
			[village + Vector3(1.6, 0, 0.4), "work", 4.0], [village + Vector3(-5, 0, -7.2), "idle", 3.0], [village + Vector3(1.6, 0, 0.4), "work", 4.0],
			[village + Vector3(5.5, 0, 6.5), "idle", 3.0], [village + Vector3(-9.5, 0, 2.5), "idle", 3.0]]},
		{"who": "tam", "display": "Tam", "bio": "Tam the shepherd: an anxious old man who counts his sheep constantly and hates wolves and trolls", "name": "the shepherd", "tunic": "#8a6a3a", "hat": "straw", "tool": "crook", "steps": [
			[pasture + Vector3(-9, 0, -3), "idle", 8.0], [pasture + Vector3(-6, 0, 8), "idle", 8.0], [pasture + Vector3(8, 0, 9), "idle", 8.0],
			[pasture + Vector3(10, 0, -4), "idle", 8.0]]},
		{"who": "bram", "display": "Sergeant Bram", "bio": "Sergeant Bram of the Highmoor guard: gruff, proud of his castle, suspicious of strangers until they prove themselves", "name": "a guard", "tunic": "#9e2230", "hat": "helmet", "tool": "spear", "steps": [
			[gate + Vector3(-3.2, 0, 0.5), "idle", 20.0], [gate + Vector3(-3.2, 0, 4.0), "idle", 6.0]]},
		{"who": "hugh", "display": "Hugh", "bio": "Hugh, a young castle guard: bored on duty, eager for any news or adventure", "name": "a guard", "tunic": "#9e2230", "hat": "helmet", "tool": "spear", "steps": [
			[gate + Vector3(3.2, 0, 0.5), "idle", 18.0], [gate + Vector3(3.2, 0, 4.5), "idle", 5.0]]},
		{"who": "piers", "display": "Piers", "bio": "Piers, a guard who walks the castle wall: chatty, superstitious about the red moon and the barrow", "name": "a guard on the wall", "tunic": "#9e2230", "hat": "helmet", "tool": "spear", "steps": [
			[Vector3(castle.x - 12.0, wall_y, wall_z), "idle", 4.0], [Vector3(castle.x - 4.0, wall_y, wall_z), "idle", 1.0],
			[Vector3(castle.x + 4.0, wall_y, wall_z), "idle", 1.0], [Vector3(castle.x + 12.0, wall_y, wall_z), "idle", 4.0],
			[Vector3(castle.x - 4.0, wall_y, wall_z), "idle", 1.0]]},
	]


# --- the places they work ---------------------------------------------------------------------------------

func build_field() -> void:
	var field := Node3D.new()
	field.position = FIELD
	add_child(field)
	W.box(field, Vector3(0, 0.02, 0), Vector3(12.0, 0.04, 8.0), Color("#4a3826"))  # tilled earth
	var mm := MultiMesh.new()  # rows of wheat, swaying a little (one MultiMesh, cheap)
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var stalk := BoxMesh.new()
	stalk.size = Vector3(0.06, 0.9, 0.06)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color("#d9b65a")
	sm.vertex_color_use_as_albedo = true
	stalk.material = sm
	mm.mesh = stalk
	var spots := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for row in 9:
		for k in 34:
			spots.append(Vector3(-5.6 + k * 0.34 + rng.randf_range(-0.06, 0.06), 0.45, -3.5 + row * 0.85 + rng.randf_range(-0.08, 0.08)))
	mm.instance_count = spots.size()
	for i in spots.size():
		var tilt := Basis(Vector3(1, 0, 0), rng.randf_range(-0.12, 0.12)) * Basis(Vector3(0, 0, 1), rng.randf_range(-0.12, 0.12))
		var h := rng.randf_range(0.75, 1.1)
		mm.set_instance_transform(i, Transform3D(tilt.scaled(Vector3(1, h, 1)), spots[i] * Vector3(1, h, 1)))
		mm.set_instance_color(i, Color.WHITE.darkened(rng.randf_range(0.0, 0.25)))
	var wheat := MultiMeshInstance3D.new()
	wheat.multimesh = mm
	field.add_child(wheat)
	# a scarecrow in the middle of the field
	var crow := Node3D.new()
	crow.position = Vector3(0.3, 0, 0.2)
	field.add_child(crow)
	kit.block(W, crow, Vector3(0, 1.1, 0), Vector3(0.1, 2.2, 0.1), "timber", false)
	kit.block(W, crow, Vector3(0, 1.75, 0), Vector3(1.5, 0.08, 0.08), "timber", false)
	W.box(crow, Vector3(0, 1.45, 0), Vector3(0.42, 0.6, 0.24), Color("#5b6e8a"))  # an old shirt
	W.box(crow, Vector3(0, 2.05, 0), Vector3(0.28, 0.3, 0.26), Color("#d8c48a"))  # a sack head
	W.box(crow, Vector3(0, 2.25, 0), Vector3(0.5, 0.05, 0.5), Color("#b8954f"))  # straw hat
	W.box(crow, Vector3(0, 2.36, 0), Vector3(0.26, 0.16, 0.26), Color("#b8954f"))
	for side in [-1, 1]:
		W.box(crow, Vector3(side * 0.07, 2.08, -0.14), Vector3(0.05, 0.05, 0.02), Color("#1a1a1a"))  # button eyes


func build_logs() -> void:
	var pile := Node3D.new()
	pile.position = LOGS
	add_child(pile)
	pile.rotation.y = 0.4
	for row in 3:  # a stack of logs
		for k in 4 - row:
			var log := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.22
			cyl.bottom_radius = 0.22
			cyl.height = 2.4
			cyl.radial_segments = 8
			log.mesh = cyl
			log.material_override = kit.mat("timber", Color("#b08a64"))
			log.rotation.z = PI / 2.0
			log.position = Vector3(0, 0.22 + row * 0.38, -1.6 + k * 0.44 + row * 0.22)
			pile.add_child(log)
	W.add_collider(pile, Transform3D(Basis(), Vector3(0, 0.6, -1.0)), Vector3(2.4, 1.2, 1.8))
	var block := MeshInstance3D.new()  # the chopping block, with a split log on it
	var stump := CylinderMesh.new()
	stump.top_radius = 0.32
	stump.bottom_radius = 0.36
	stump.height = 0.55
	block.mesh = stump
	block.material_override = kit.mat("timber", Color("#a07a52"))
	block.position = Vector3(1.0, 0.27, 1.3)
	pile.add_child(block)
	W.box(pile, Vector3(0.9, 0.62, 1.3), Vector3(0.18, 0.16, 0.5), Color("#c8a070"))


# --- the villagers themselves ------------------------------------------------------------------------------

const HIP := 0.86  # the body pivots here


func add_person(p: Dictionary) -> void:
	var node := Node3D.new()
	var first: Array = p.steps[0]
	node.position = place(first[0])
	add_child(node)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(p.name + str(folk.size()))
	var skin := Color("#e8b896").darkened(rng.randf_range(0.0, 0.35))
	var tunic := Color(p.tunic)
	var beard := false
	var legs := []
	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.1, 0.8, 0)
		node.add_child(leg)
		W.box(leg, Vector3(0, -0.36, 0), Vector3(0.13, 0.72, 0.14), Color("#4a3d30"))  # hose
		W.box(leg, Vector3(0, -0.76, -0.03), Vector3(0.15, 0.1, 0.22), Color("#2b2119"))  # shoes
		legs.append(leg)
	var body := Node3D.new()  # everything above the hips, so they can lean into their work
	body.position.y = HIP
	node.add_child(body)
	W.box(body, Vector3(0, 1.12 - HIP, 0), Vector3(0.42, 0.62, 0.26), tunic)  # tunic
	W.box(body, Vector3(0, 0.86 - HIP, 0), Vector3(0.44, 0.08, 0.28), Color("#3b2a1e"))  # belt
	W.box(body, Vector3(0, 1.48 - HIP, 0), Vector3(0.12, 0.08, 0.12), skin)  # neck
	W.box(body, Vector3(0, 1.41 - HIP, 0), Vector3(0.44, 0.05, 0.28), tunic.darkened(0.25))  # collar
	W.box(body, Vector3(0.17, 0.86 - HIP, -0.12), Vector3(0.1, 0.12, 0.07), Color("#5a3d24"))  # a pouch on the belt
	var guard: bool = p.hat == "helmet"
	if guard:  # a long red tabard over mail, and a gold lion badge
		W.box(body, Vector3(0, 0.95 - HIP, -0.135), Vector3(0.3, 0.75, 0.02), tunic.darkened(0.08))
		W.box(body, Vector3(0, 0.95 - HIP, 0.135), Vector3(0.3, 0.75, 0.02), tunic.darkened(0.08))
	if p.tool == "crook":  # the shepherd's cloak
		W.box(body, Vector3(0, 1.0 - HIP, 0.15), Vector3(0.46, 0.95, 0.04), Color("#5a4632"))
	if p.tool == "axe" or (p.hat != "helmet" and rng.randf() < 0.35):
		beard = true
	var head := Node3D.new()
	head.position = Vector3(0, 1.66 - HIP, 0)
	body.add_child(head)
	W.box(head, Vector3.ZERO, Vector3(0.26, 0.28, 0.26), skin)
	for side in [-1, 1]:
		W.box(head, Vector3(side * 0.06, 0.03, -0.131), Vector3(0.04, 0.04, 0.01), Color("#1a1410"))  # eyes
	if p.hat != "helmet":  # (a helmet's nose guard covers it)
		W.box(head, Vector3(0, -0.02, -0.14), Vector3(0.04, 0.06, 0.03), skin.darkened(0.08))  # nose
	var hair := Color(["#3a2618", "#6b4423", "#1e1a16", "#a07040", "#8a8580"][rng.randi() % 5])
	if beard:
		W.box(head, Vector3(0, -0.12, -0.11), Vector3(0.24, 0.12, 0.08), hair)
		W.box(head, Vector3(0, -0.07, -0.135), Vector3(0.14, 0.03, 0.02), hair)  # moustache
	match p.hat:
		"straw":
			W.box(head, Vector3(0, 0.13, 0), Vector3(0.5, 0.04, 0.5), Color("#c9a85a"))  # brim, resting on the head
			W.box(head, Vector3(0, 0.2, 0), Vector3(0.28, 0.12, 0.28), Color("#c9a85a"))
			W.box(head, Vector3(0, 0.16, 0), Vector3(0.285, 0.03, 0.285), Color("#7a3a2a"))  # a band
		"hood":
			W.box(head, Vector3(0, 0.05, 0.03), Vector3(0.3, 0.36, 0.3), tunic.darkened(0.15))
			W.box(head, Vector3(0, 0.02, -0.12), Vector3(0.22, 0.24, 0.04), skin)  # the face shows through
		"helmet":
			W.box(head, Vector3(0, 0.13, 0), Vector3(0.3, 0.12, 0.3), Color("#8d939a"))
			W.box(head, Vector3(0, 0.03, -0.15), Vector3(0.045, 0.17, 0.035), Color("#8d939a"))  # nose guard
			W.box(body, Vector3(0, 1.2 - HIP, -0.135), Vector3(0.2, 0.2, 0.01), Color("#e8c25a"))  # a badge on the tabard
		_:
			W.box(head, Vector3(0, 0.12, 0.02), Vector3(0.28, 0.1, 0.28), hair)
	var arms := []
	var tool_arm: Node3D
	for side in [-1, 1]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.27, 1.38 - HIP, 0)
		body.add_child(arm)
		W.box(arm, Vector3(0, -0.26, 0), Vector3(0.11, 0.52, 0.11), Color("#8d939a") if guard else tunic.darkened(0.1))  # (mail on guards)
		W.box(arm, Vector3(0, -0.47, 0), Vector3(0.125, 0.06, 0.125), tunic.darkened(0.3))  # cuff
		W.box(arm, Vector3(0, -0.56, 0), Vector3(0.1, 0.1, 0.1), skin)
		arms.append(arm)
		if side > 0:
			tool_arm = arm
	make_tool(tool_arm, p.tool)
	var talker: Node3D = ctx.parts["talk"].make(W, node, 2.45, Vector3(0, 1.585, -0.132), Vector3(0.07, 0.02, 0.012)) if ctx.parts.has("talk") else null
	folk.append({"node": node, "body": body, "tool": p.tool, "offset": rng.randf(), "legs": legs, "arms": arms,
		"who": p.get("who", ""), "display": p.get("display", p.name), "bio": p.get("bio", ""), "talker": talker,
		"tool_arm": tool_arm, "steps": p.steps, "step": 0,
		"wait": randf_range(0.0, float(first[2])), "phase": randf() * TAU, "name": p.name, "work": first[1] == "work",
		"look": 0.0})


func make_tool(arm: Node3D, tool: String) -> void:
	var hand := Vector3(0, -0.58, -0.05)
	var wood := Color("#6b4a2b")
	match tool:
		"axe":
			W.box(arm, hand + Vector3(0, -0.05, -0.25), Vector3(0.05, 0.05, 0.75), wood)
			W.box(arm, hand + Vector3(0, -0.05, -0.6), Vector3(0.04, 0.22, 0.14), Color("#9aa0a8"))
		"hoe":  # held at the hand, the shaft slanting forward and down so the blade reaches the ground
			var grip := Node3D.new()
			grip.position = hand
			grip.rotation.x = -0.61
			arm.add_child(grip)
			W.box(grip, Vector3(0, 0, -0.55), Vector3(0.045, 0.045, 1.4), wood)
			var blade: MeshInstance3D = W.box(grip, Vector3(0, -0.07, -1.24), Vector3(0.2, 0.17, 0.03), Color("#7c828a"))
			blade.rotation.x = 0.61  # the blade hangs straight down
		"bucket":
			W.box(arm, hand + Vector3(0, -0.22, 0), Vector3(0.22, 0.24, 0.22), Color("#7a5530"))
			W.box(arm, hand + Vector3(0, -0.1, 0), Vector3(0.02, 0.12, 0.02), Color("#333333"))
		"crook":
			W.box(arm, hand + Vector3(0, 0.5, 0), Vector3(0.04, 1.7, 0.04), wood)
			W.box(arm, hand + Vector3(0, 1.35, -0.1), Vector3(0.04, 0.04, 0.22), wood)
		"spear":
			W.box(arm, hand + Vector3(0, 0.55, 0), Vector3(0.04, 2.0, 0.04), wood)
			W.box(arm, hand + Vector3(0, 1.62, 0), Vector3(0.07, 0.22, 0.04), Color("#aab0b8"))


## Is this spot inside (or brushing) a house? Uses the village's house footprints (village.gd house_nodes).
func in_house(p: Vector3) -> bool:
	var village = ctx.parts.get("village")
	if not village or not "house_nodes" in village:
		return false
	for h in village.house_nodes:
		var node: Node3D = h[0]
		if not is_instance_valid(node):
			continue
		var l := node.to_local(Vector3(p.x, node.global_position.y, p.z))
		if absf(l.x) < h[1] / 2.0 + 0.45 and absf(l.z) < h[2] / 2.0 + 0.45:
			return true
	return false


## The way to walk: straight at the goal, unless a house is in the way; then turn (left or right, whichever
## clears the house and heads more toward the goal) until the way ahead is free.
func steer(at: Vector3, dir: Vector3, goal: Vector3) -> Vector3:
	if not in_house(at + dir * 1.0):
		return dir
	var best := dir
	var best_score := -INF
	for k in range(1, 7):
		for sgn in [-1, 1]:
			var d := dir.rotated(Vector3.UP, sgn * k * 0.4)
			if not in_house(at + d * 1.0):
				var score := d.dot((goal - at).normalized()) - k * 0.05
				if score > best_score:
					best_score = score
					best = d
		if best_score > -INF:
			return best
	return -dir  # boxed in: back out


func place(p: Vector3) -> Vector3:
	return Vector3(p.x, p.y if p.y > 0.0 else W.ground_y(p.x, p.z), p.z)


func _process(delta: float) -> void:
	spin += delta
	var player: Vector3 = ctx.player.position
	for f in folk:
		var node: Node3D = f.node
		var step: Array = f.steps[f.step]
		var goal := place(step[0])
		var to := Vector3(goal.x - node.position.x, 0, goal.z - node.position.z)
		var moving := false
		var by_you := Vector2(player.x - node.position.x, player.z - node.position.z).length() < 2.6
		if to.length() > 0.12 and not by_you:  # (they stop to talk when you stand right by them)
			var aim := next_waypoint(f, goal, step[0].y > 0.0)  # (a path round walls and houses, see below)
			var to_aim := Vector3(aim.x - node.position.x, 0, aim.z - node.position.z)
			var dir := to_aim.normalized() if to_aim.length() > 0.01 else to.normalized()
			var me := Vector3(player.x - node.position.x, 0, player.z - node.position.z)
			if me.length() < 1.6 and me.normalized().dot(dir) > 0.3:  # you're in the way: step around you
				dir = (dir + me.normalized().cross(Vector3.UP) * 1.2).normalized()
			node.position += dir * minf(to.length(), 1.3 * delta)
			node.position.y = goal.y if step[0].y > 0.0 else W.ground_y(node.position.x, node.position.z)
			node.rotation.y = lerp_angle(node.rotation.y, atan2(-dir.x, -dir.z), minf(delta * 7.0, 1.0))
			moving = true
		elif by_you:
			f.work = false  # (puts the tool down and turns to you, below)
		else:
			f.wait -= delta
			if f.wait <= 0.0:
				f.step = (f.step + 1) % f.steps.size()
				f.wait = float(f.steps[f.step][2])
			f.work = step[1] == "work"
		f.phase += delta * (8.0 if moving else 0.0)
		var swing := sin(f.phase) * 0.55 if moving else 0.0
		f.legs[0].rotation.x = swing
		f.legs[1].rotation.x = -swing
		f.arms[0].rotation.x = -swing * 0.8
		f.arms[0].rotation.z = 0.0
		f.tool_arm.rotation.z = 0.0
		f.body.rotation.x = 0.0
		if moving:
			f.tool_arm.rotation.x = swing * 0.8
		elif f.work:
			work_pose(f)
		else:  # standing about: tool held, and a slow look around now and then
			f.tool_arm.rotation.x = lerpf(f.tool_arm.rotation.x, 0.15, minf(delta * 4.0, 1.0))
			if Vector2(player.x - node.position.x, player.z - node.position.z).length() < 4.0 or by_you:
				node.rotation.y = lerp_angle(node.rotation.y, atan2(-(player.x - node.position.x), -(player.z - node.position.z)), minf(delta * 3.0, 1.0))


## Working: (positive x rotation lifts a hand forward, towards -z where they face.)
## Hoe and axe: both hands on the handle, a slow lift over the head, a fast strike down, a short rest.
## Bucket: lower it into the well and haul it up. Others: a gentle swing of the tool.
func work_pose(f: Dictionary) -> void:
	var u := fmod(spin * 0.75 + f.offset, 1.0)  # where in the stroke they are, 0..1
	match f.tool:
		"hoe", "axe":
			var lift := 0.0
			if u < 0.55:
				lift = ease(u / 0.55, 0.5)  # rising, slowing near the top
			elif u < 0.66:
				lift = 1.0 - (u - 0.55) / 0.11  # the strike
			var top := 2.75 if f.tool == "axe" else 2.5
			var low := 0.55 if f.tool == "axe" else 0.35
			var angle := lerpf(low, top, lift)
			f.tool_arm.rotation.x = angle
			f.arms[0].rotation.x = angle  # the other hand on the handle too
			f.arms[0].rotation.z = -0.38  # (hands come together in front)
			f.tool_arm.rotation.z = 0.2
			f.body.rotation.x = -0.18 * (1.0 - lift)  # leaning into the stroke
		"bucket":
			f.tool_arm.rotation.x = 0.6 + sin(u * TAU) * 0.5
		_:
			f.tool_arm.rotation.x = 0.3 + sin(u * TAU) * 0.3


func seen_from(from: Vector3, _viewer: Node) -> Array:
	var near := []
	for f in folk:
		if f.node.position.distance_to(from) < 60.0:
			near.append(f.name)
	var seen := ["a field of wheat with a scarecrow %s" % W.where(from, FIELD)]
	if not near.is_empty():
		seen.append("villagers going about their work nearby: " + ", ".join(near))
	return seen


# --- talking to the villagers (by voice, like Barnaby): the chat window plays whoever you stand next to ------------
# world.gd asks is_near() and npc_id like for the characters; the reply's voice and bubble come back as
# say_start / say_end / say / npc_state with who = "folk:<who>".

const TALK_RANGE := 2.6
var npc_id := ""  # "folk:wat" while you stand next to Wat, else ""
var npc_name := ""


func near_person() -> Dictionary:
	var me: Vector3 = ctx.player.position
	var best := {}
	var best_d := TALK_RANGE
	for f in folk:
		var d := Vector2(me.x - f.node.position.x, me.z - f.node.position.z).length()
		if d < best_d and f.who != "":
			best = f
			best_d = d
	return best


func is_near() -> bool:
	var f := near_person()
	npc_id = ("folk:" + f.who) if not f.is_empty() else ""
	npc_name = f.get("display", "")
	return not f.is_empty()


func person(id: String) -> Dictionary:
	for f in folk:
		if "folk:" + f.who == id:
			return f
	return {}


## Who you are talking to and what they see (sent to the chat window with each line you say to them).
func describe() -> String:
	var f := person(npc_id)
	if f.is_empty():
		return ""
	var here: Vector3 = f.node.position
	var seen := [str(f.bio)]
	seen.append_array(W.seen_around(here, self))
	seen.append("the wanderer is %s" % W.where(here, ctx.player.position))
	return "; ".join(seen)


func handle(c: Dictionary) -> bool:
	var who := str(c.get("who", ""))
	if not who.begins_with("folk:") or not c.get("cmd", "") in ["say_start", "say_end", "say", "npc_state"]:
		return false
	var f := person(who)
	if f.is_empty() or f.talker == null:
		return true
	match c.cmd:
		"say_start":
			f.talker.say_start(str(c.get("text", "")))
		"say_end":
			f.talker.say_end()
		"say":
			f.talker.say(str(c.get("text", "")))
		"npc_state":
			f.talker.set_mind(str(c.get("state", "")))
	return true


# --- pathfinding: a walkability map of the valley floor, and A* paths across it ---------------------------------
# The map is made by probing for anything solid every CELL metres (walls, fences, the well, barrels, logs, steep
# ground): so whatever the other parts or the storyteller build is avoided without being listed anywhere.
# Made once the physics world has everything in it (the first physics frame after a rebuild).

const CELL := 1.5
const GRID_FROM := Vector2(-95.0, -180.0)  # covers the village, the meadow, the road and the castle
const GRID_CELLS := Vector2i(127, 167)
var grid: AStarGrid2D
var grid_ready := false


func _physics_process(_delta: float) -> void:
	if not grid_ready:
		grid_ready = true
		build_grid()
		for f in folk:
			f.path = []


func cell_of(p: Vector3) -> Vector2i:
	var c := Vector2i(int((p.x - GRID_FROM.x) / CELL), int((p.z - GRID_FROM.y) / CELL))
	return c.clamp(Vector2i.ZERO, GRID_CELLS - Vector2i.ONE)


func cell_centre(c: Vector2i) -> Vector3:
	var x := GRID_FROM.x + (c.x + 0.5) * CELL
	var z := GRID_FROM.y + (c.y + 0.5) * CELL
	return Vector3(x, W.ground_y(x, z), z)


func build_grid() -> void:
	grid = AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, GRID_CELLS)
	grid.cell_size = Vector2(CELL, CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	var space: PhysicsDirectSpaceState3D = W.get_world_3d().direct_space_state
	var probe := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(CELL * 0.7, 1.0, CELL * 0.7)
	probe.shape = shape
	probe.exclude = [W.player.get_rid()]
	var terrain = ctx.parts.get("terrain")
	for cx in GRID_CELLS.x:
		for cz in GRID_CELLS.y:
			var c := cell_centre(Vector2i(cx, cz))
			var steep := false
			if terrain:
				var h0: float = c.y
				steep = absf(terrain.height_at(c.x + 1.0, c.z) - h0) > 0.75 or absf(terrain.height_at(c.x, c.z + 1.0) - h0) > 0.75
			probe.transform = Transform3D(Basis(), c + Vector3(0, 1.1, 0))  # (above the ground, so the ground itself isn't "solid")
			if steep or not space.intersect_shape(probe, 1).is_empty():
				grid.set_point_solid(Vector2i(cx, cz), true)


## Where to head next on the way to `goal`: the next point of an A* path (planned when the goal changes), skipping
## ahead whenever the way to a later point is clear. Straight at the goal when there is no map, or for spots
## up on the castle wall (`raised`).
func next_waypoint(f: Dictionary, goal: Vector3, raised: bool) -> Vector3:
	if grid == null or raised:
		return goal
	var node: Node3D = f.node
	if f.get("path_goal", Vector3.INF) != goal or f.get("path", []).is_empty():
		f.path_goal = goal
		var from := cell_of(node.position)
		var to := cell_of(goal)
		if grid.is_point_solid(from):  # standing in a "solid" cell (a doorway, by a wall): start from a free neighbour
			from = nearest_free(from)
		if grid.is_point_solid(to):
			to = nearest_free(to)
		var pts := grid.get_id_path(from, to, true)
		var path := []
		for c in pts:
			path.append(cell_centre(c))
		path.append(goal)
		f.path = path
	var path: Array = f.path
	while path.size() > 1 and (Vector2(path[0].x - node.position.x, path[0].z - node.position.z).length() < 0.5 			or clear_line(node.position, path[1])):
		path.pop_front()  # reached it, or can already see the next one
	return path[0]


func nearest_free(c: Vector2i) -> Vector2i:
	for r in range(1, 6):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var n := c + Vector2i(dx, dz)
				if grid.region.has_point(n) and not grid.is_point_solid(n):
					return n
	return c


func clear_line(a: Vector3, b: Vector3) -> bool:
	var steps := int(Vector2(b.x - a.x, b.z - a.z).length() / (CELL * 0.5)) + 1
	for i in range(1, steps + 1):
		var p := a.lerp(b, float(i) / steps)
		if grid.is_point_solid(cell_of(p)):
			return false
	return true

