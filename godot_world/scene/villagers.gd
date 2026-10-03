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
	return [
		{"name": "the farmer", "tunic": "#6a7d3a", "hat": "straw", "tool": "hoe", "steps": [
			[FIELD + Vector3(-4, 0, -2), "work", 6.0], [FIELD + Vector3(0, 0, -2), "work", 6.0], [FIELD + Vector3(4, 0, 2), "work", 6.0],
			[FIELD + Vector3(-2, 0, 2), "work", 5.0], [village + Vector3(2, 0, -4), "idle", 5.0]]},
		{"name": "the woodcutter", "tunic": "#7a3b2a", "hat": "hood", "tool": "axe", "steps": [
			[LOGS + Vector3(0.9, 0, 0.6), "work", 9.0], [LOGS + Vector3(-1.5, 0, 2.5), "idle", 3.0], [LOGS + Vector3(0.9, 0, 0.6), "work", 7.0],
			[village + Vector3(-1, 0, -3), "idle", 6.0]]},
		{"name": "the water carrier", "tunic": "#3d5a7a", "hat": "", "tool": "bucket", "steps": [
			[village + Vector3(1.6, 0, 0.4), "work", 4.0], [village + Vector3(-5, 0, -7.2), "idle", 3.0], [village + Vector3(1.6, 0, 0.4), "work", 4.0],
			[village + Vector3(5.5, 0, 6.5), "idle", 3.0], [village + Vector3(-9.5, 0, 2.5), "idle", 3.0]]},
		{"name": "the shepherd", "tunic": "#8a6a3a", "hat": "straw", "tool": "crook", "steps": [
			[pasture + Vector3(-9, 0, -3), "idle", 8.0], [pasture + Vector3(-6, 0, 8), "idle", 8.0], [pasture + Vector3(8, 0, 9), "idle", 8.0],
			[pasture + Vector3(10, 0, -4), "idle", 8.0]]},
		{"name": "a guard", "tunic": "#9e2230", "hat": "helmet", "tool": "spear", "steps": [
			[gate + Vector3(-3.2, 0, 0.5), "idle", 20.0], [gate + Vector3(-3.2, 0, 4.0), "idle", 6.0]]},
		{"name": "a guard", "tunic": "#9e2230", "hat": "helmet", "tool": "spear", "steps": [
			[gate + Vector3(3.2, 0, 0.5), "idle", 18.0], [gate + Vector3(3.2, 0, 4.5), "idle", 5.0]]},
		{"name": "a guard on the wall", "tunic": "#9e2230", "hat": "helmet", "tool": "spear", "steps": [
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
	var head := Node3D.new()
	head.position = Vector3(0, 1.66 - HIP, 0)
	body.add_child(head)
	W.box(head, Vector3.ZERO, Vector3(0.26, 0.28, 0.26), skin)
	for side in [-1, 1]:
		W.box(head, Vector3(side * 0.06, 0.03, -0.131), Vector3(0.04, 0.04, 0.01), Color("#1a1410"))  # eyes
	var hair := Color(["#3a2618", "#6b4423", "#1e1a16", "#a07040", "#8a8580"][rng.randi() % 5])
	match p.hat:
		"straw":
			W.box(head, Vector3(0, 0.17, 0), Vector3(0.5, 0.04, 0.5), Color("#c9a85a"))
			W.box(head, Vector3(0, 0.25, 0), Vector3(0.26, 0.14, 0.26), Color("#c9a85a"))
		"hood":
			W.box(head, Vector3(0, 0.05, 0.03), Vector3(0.3, 0.36, 0.3), tunic.darkened(0.15))
			W.box(head, Vector3(0, 0.02, -0.12), Vector3(0.22, 0.24, 0.04), skin)  # the face shows through
		"helmet":
			W.box(head, Vector3(0, 0.13, 0), Vector3(0.3, 0.12, 0.3), Color("#8d939a"))
			W.box(head, Vector3(0, 0.05, -0.14), Vector3(0.04, 0.16, 0.03), Color("#8d939a"))  # nose guard
			W.box(body, Vector3(0, 1.2 - HIP, -0.135), Vector3(0.2, 0.2, 0.01), Color("#e8c25a"))  # a badge on the tabard
		_:
			W.box(head, Vector3(0, 0.12, 0.02), Vector3(0.28, 0.1, 0.28), hair)
	var arms := []
	var tool_arm: Node3D
	for side in [-1, 1]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.27, 1.38 - HIP, 0)
		body.add_child(arm)
		W.box(arm, Vector3(0, -0.26, 0), Vector3(0.11, 0.52, 0.11), tunic.darkened(0.1))
		W.box(arm, Vector3(0, -0.56, 0), Vector3(0.1, 0.1, 0.1), skin)
		arms.append(arm)
		if side > 0:
			tool_arm = arm
	make_tool(tool_arm, p.tool)
	folk.append({"node": node, "body": body, "tool": p.tool, "offset": rng.randf(), "legs": legs, "arms": arms,
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
		if to.length() > 0.12:
			var dir := to.normalized()
			var me := Vector3(player.x - node.position.x, 0, player.z - node.position.z)
			if me.length() < 1.6 and me.normalized().dot(dir) > 0.3:  # you're in the way: step around you
				dir = (dir + me.normalized().cross(Vector3.UP) * 1.2).normalized()
			node.position += dir * minf(to.length(), 1.3 * delta)
			node.position.y = goal.y if step[0].y > 0.0 else W.ground_y(node.position.x, node.position.z)
			node.rotation.y = lerp_angle(node.rotation.y, atan2(-dir.x, -dir.z), minf(delta * 7.0, 1.0))
			moving = true
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
			if Vector2(player.x - node.position.x, player.z - node.position.z).length() < 4.0:
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
