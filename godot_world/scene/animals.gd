extends Node3D
## Animals: a flock of sheep grazing in the pasture south of the village, and chickens pecking around the
## cottages. They wander within their area, stop to graze or peck, and shy away when you come close (chickens
## flap and hop). Each animal is a small box model built here. Positions are not saved (they wander anyway).

const PASTURE := Vector3(-40, 0, 24)  # the sheep's grazing ground (centre, radius)
const PASTURE_R := 11.0
const COOP := Vector3(-46, 0, 0)  # the chickens keep near the village centre
const COOP_R := 9.0
const SHEEP := 9
const CHICKENS := 7

var ctx: Dictionary
var W
var herd := []  # {node, head, legs, kind, target, wait, speed, phase, flee}
var spin := 0.0


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	for i in SHEEP:
		add_animal("sheep", PASTURE + ring(rng, PASTURE_R * 0.8), rng)
	for i in CHICKENS:
		add_animal("chicken", COOP + ring(rng, COOP_R * 0.8), rng)


func ring(rng: RandomNumberGenerator, r: float) -> Vector3:
	var a := rng.randf() * TAU
	var d := sqrt(rng.randf()) * r
	return Vector3(cos(a) * d, 0, sin(a) * d)


func add_animal(kind: String, at: Vector3, rng: RandomNumberGenerator) -> void:
	var node := Node3D.new()
	node.position = at
	node.rotation.y = rng.randf() * TAU
	add_child(node)
	var head := Node3D.new()
	var legs := []
	if kind == "sheep":
		var wool := Color("#e8e2d4").darkened(rng.randf_range(0.0, 0.15))
		var face := Color("#2e2a27")
		W.box(node, Vector3(0, 0.62, 0.05), Vector3(0.62, 0.5, 0.9), wool)  # woolly body
		W.box(node, Vector3(0, 0.82, 0.05), Vector3(0.5, 0.18, 0.75), wool.lightened(0.05))  # fluffy back
		head.position = Vector3(0, 0.78, -0.48)
		node.add_child(head)
		W.box(head, Vector3(0, 0, -0.08), Vector3(0.26, 0.26, 0.3), face)
		W.box(head, Vector3(0, 0.12, 0.02), Vector3(0.3, 0.12, 0.22), wool)  # a tuft on top
		for side in [-1, 1]:
			var ear: MeshInstance3D = W.box(head, Vector3(side * 0.18, 0.04, 0.0), Vector3(0.14, 0.05, 0.08), face)
			ear.rotation.z = side * -0.4
			W.box(head, Vector3(side * 0.07, 0.04, -0.235), Vector3(0.04, 0.04, 0.01), Color("#111111"))  # eyes
		for x in [-0.18, 0.18]:
			for z in [-0.28, 0.32]:
				var leg := Node3D.new()
				leg.position = Vector3(x, 0.42, z)
				node.add_child(leg)
				W.box(leg, Vector3(0, -0.21, 0), Vector3(0.09, 0.42, 0.09), face)
				legs.append(leg)
	else:
		var feathers := Color("#f2ede2") if rng.randf() < 0.6 else Color("#a8643a")
		W.box(node, Vector3(0, 0.25, 0.02), Vector3(0.24, 0.22, 0.32), feathers)  # body
		W.box(node, Vector3(0, 0.36, 0.17), Vector3(0.16, 0.16, 0.1), feathers.darkened(0.08))  # tail
		head.position = Vector3(0, 0.42, -0.14)
		node.add_child(head)
		W.box(head, Vector3(0, 0, 0), Vector3(0.12, 0.14, 0.12), feathers)
		W.box(head, Vector3(0, 0.1, 0), Vector3(0.04, 0.06, 0.08), Color("#d23a2c"))  # comb
		W.box(head, Vector3(0, -0.01, -0.08), Vector3(0.04, 0.03, 0.05), Color("#e8a530"))  # beak
		for x in [-0.06, 0.06]:
			var leg := Node3D.new()
			leg.position = Vector3(x, 0.15, 0.02)
			node.add_child(leg)
			W.box(leg, Vector3(0, -0.075, 0), Vector3(0.025, 0.15, 0.025), Color("#e8a530"))
			legs.append(leg)
	herd.append({"node": node, "head": head, "legs": legs, "kind": kind, "target": at, "wait": rng.randf_range(0.0, 4.0),
		"speed": 0.0, "phase": rng.randf() * TAU, "hop": 0.0})


func _process(delta: float) -> void:
	spin += delta
	var player: Vector3 = ctx.player.position
	for a in herd:
		var node: Node3D = a.node
		var sheep: bool = a.kind == "sheep"
		var home := PASTURE if sheep else COOP
		var home_r := PASTURE_R if sheep else COOP_R
		var away := Vector3(node.position.x - player.x, 0, node.position.z - player.z)
		var scared := away.length() < (4.0 if sheep else 3.0)
		if scared:  # shy away from the wanderer, but not out of their own ground
			var flee := node.position + away.normalized() * 3.0
			var back := flee - home
			back.y = 0
			if back.length() > home_r:
				flee = home + back.normalized() * home_r
			a.target = flee
			a.wait = 0.0
			if not sheep and a.hop <= 0.0:
				a.hop = 0.35  # a startled flap
		var to: Vector3 = a.target - node.position
		to.y = 0
		var moving: bool = to.length() > 0.15 and a.wait <= 0.0
		var top_speed: float = (2.6 if scared else 0.6) if sheep else (2.8 if scared else 0.9)
		a.speed = move_toward(a.speed, top_speed if moving else 0.0, delta * 4.0)
		if moving:
			node.position += to.normalized() * minf(to.length(), a.speed * delta)
			var yaw := atan2(-to.x, -to.z)
			node.rotation.y = lerp_angle(node.rotation.y, yaw, minf(delta * 6.0, 1.0))
		elif a.wait > 0.0:
			a.wait -= delta
		else:  # arrived: graze / peck a while, then pick a new spot
			a.wait = randf_range(3.0, 9.0) if sheep else randf_range(1.0, 4.0)
			var r := home_r * sqrt(randf())
			var ang := randf() * TAU
			a.target = home + Vector3(cos(ang) * r, 0, sin(ang) * r)
		a.phase += delta * (a.speed * (9.0 if sheep else 16.0))
		var swing := sin(a.phase) * 0.5 * clampf(a.speed, 0.0, 1.0)
		for i in a.legs.size():
			a.legs[i].rotation.x = swing * (1 if i % 2 == 0 else -1) * (1 if i < 2 else -1)
		var head: Node3D = a.head
		if not moving and a.wait > 0.0:  # head down to graze / quick pecks
			head.rotation.x = (-0.7 + sin(spin * 2.0 + a.phase) * 0.1) if sheep else (-0.9 * absf(sin(spin * 7.0 + a.phase)))
		else:
			head.rotation.x = lerpf(head.rotation.x, 0.0, minf(delta * 8.0, 1.0))
		a.hop = maxf(a.hop - delta, 0.0)
		node.position.y = W.ground_y(node.position.x, node.position.z) + (sin(a.hop / 0.35 * PI) * 0.35 if a.hop > 0.0 else 0.0)


func seen_from(from: Vector3, _viewer: Node) -> Array:
	return ["a flock of sheep grazing in the pasture %s" % W.where(from, PASTURE),
		"chickens pecking about between the village cottages"]
