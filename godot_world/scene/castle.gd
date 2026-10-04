extends Node3D
## The castle on the levelled hilltop north of the meadow (terrain.gd: CASTLE). Stone curtain walls with
## battlements, four round corner towers with slate roofs and banners, a gatehouse facing the meadow (south)
## with a raised portcullis and torches, and a tall keep with lit windows inside the courtyard. The walls,
## towers and keep are solid; the gate is open, so you can walk in.

const HALF := 16.0  # half the width of the square curtain wall
const WALL_H := 7.0
const WALL_T := 1.6
const GATE_W := 4.0
const BANNER := Color("#9e2230")
const SINK := 0.3  # how far the whole castle is sunk into the levelled hilltop

var ctx: Dictionary
var W
var kit
var torches := []  # [light, phase]
var banners := []  # [node, phase]
var spin := 0.0
# Chapter 4 (flag "castle"): "burnt" = raiders torched it and hold it, "ruin" = they were driven out and it stands
# charred and empty, "tolled" = they were paid and squat in the ruin under a black banner.
var state := ""
var ruined := false  # any of the three: no roof, dark windows, soot
var fires := []  # [light, phase, energy]
var smoke := []  # [node, phase, speed]


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	kit = ctx.parts["kit"]
	state = W.flag("castle")
	ruined = state in ["burnt", "ruin", "tolled"]
	var terrain = ctx.parts["terrain"]
	position = Vector3(terrain.CASTLE.x, terrain.CASTLE_TOP - SINK, terrain.CASTLE.z)  # sunk so the wall bottoms are buried, not level with the ground
	build_walls()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		tower(Vector3(corner.x * HALF, 0, corner.y * HALF), 2.8, 12.0)
	build_gatehouse()
	build_keep()
	if ruined:
		build_ruin()
	elif state == "rebuilt":
		build_rebuilt()


func s(pos: Vector3, size: Vector3, kind := "stone", collide := true) -> MeshInstance3D:
	return kit.block(W, self, pos, size, kind, collide)


## Merlons (the teeth on top of a wall) along a straight stretch from a to b, at height y.
func battlements(a: Vector3, b: Vector3, y: float, thick: float) -> void:
	var length := a.distance_to(b)
	var n := int(length / 1.6)
	var along := (b - a).normalized()
	for i in n:
		if i % 2 == 0:
			var p := a + along * (i + 0.5) * (length / n)
			var size := Vector3(length / n, 0.9, thick) if absf(along.x) > 0.5 else Vector3(thick, 0.9, length / n)
			s(Vector3(p.x, y + 0.45, p.z), size, "stone", false)


func build_walls() -> void:
	var y := WALL_H / 2.0
	s(Vector3(0, y, -HALF), Vector3(HALF * 2, WALL_H, WALL_T))  # north
	s(Vector3(-HALF, y, 0), Vector3(WALL_T, WALL_H, HALF * 2))  # west
	s(Vector3(HALF, y, 0), Vector3(WALL_T, WALL_H, HALF * 2))  # east
	var side := (HALF * 2 - GATE_W) / 2.0  # the south wall, in two pieces either side of the gate
	s(Vector3(-(GATE_W / 2.0 + side / 2.0), y, HALF), Vector3(side, WALL_H, WALL_T))
	s(Vector3(GATE_W / 2.0 + side / 2.0, y, HALF), Vector3(side, WALL_H, WALL_T))
	battlements(Vector3(-HALF, 0, -HALF), Vector3(HALF, 0, -HALF), WALL_H, WALL_T)
	battlements(Vector3(-HALF, 0, -HALF), Vector3(-HALF, 0, HALF), WALL_H, WALL_T)
	battlements(Vector3(HALF, 0, -HALF), Vector3(HALF, 0, HALF), WALL_H, WALL_T)
	battlements(Vector3(-HALF, 0, HALF), Vector3(-GATE_W / 2.0 - 2.0, 0, HALF), WALL_H, WALL_T)
	battlements(Vector3(GATE_W / 2.0 + 2.0, 0, HALF), Vector3(HALF, 0, HALF), WALL_H, WALL_T)
	s(Vector3(0, SINK + 0.05, 0), Vector3(HALF * 2 - WALL_T, 0.1, HALF * 2 - WALL_T), "dark_stone", false)  # courtyard paving, just above the ground


## A round tower with a conical slate roof and a banner on top.
func tower(at: Vector3, radius: float, height: float) -> void:
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius * 1.08
	cyl.height = height
	cyl.radial_segments = 14
	body.mesh = cyl
	body.material_override = kit.mat("stone")
	body.position = at + Vector3(0, height / 2.0, 0)
	add_child(body)
	W.add_collider(self, Transform3D(Basis(), body.position), Vector3(radius * 2, height, radius * 2))
	if not ruined:
		var roof := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = radius * 1.3
		cone.height = radius * 2.2
		cone.radial_segments = 14
		roof.mesh = cone
		roof.material_override = kit.mat("slate")
		roof.position = at + Vector3(0, height + radius * 1.1, 0)
		add_child(roof)
	else:  # the roof burned away: a few charred rafters stick up
		for k in 5:
			var rafter: MeshInstance3D = W.box(self, at + Vector3(cos(k * 1.3) * radius * 0.5, height + 1.0, sin(k * 1.3) * radius * 0.5),
				Vector3(0.18, 2.2 + k * 0.3, 0.18), Color("#17120e"))
			rafter.rotation = Vector3(0.25 * cos(k * 2.0), 0, 0.25 * sin(k * 2.0))
	for k in 8:  # a ring of slit windows, a few of them lit
		var a := k * TAU / 8.0
		var p := at + Vector3(cos(a) * radius * 1.01, height * 0.62, sin(a) * radius * 1.01)
		if k % 3 == 0 and not ruined:
			var win: MeshInstance3D = W.glow(self, p, Vector3(0.22, 0.8, 0.22), Color("#ffc46b"), 2.4)
			win.rotation.y = -a
		else:
			var dark: MeshInstance3D = W.box(self, p, Vector3(0.2, 0.8, 0.2), Color("#141210"))
			dark.rotation.y = -a
	if not ruined:
		banner(at + Vector3(0, height + radius * 2.2, 0), 1.6)
	elif state == "tolled":
		banner(at + Vector3(0, height + 1.0, 0), 1.6, Color("#161414"))


func banner(top: Vector3, length: float, color := BANNER) -> void:
	W.box(self, top + Vector3(0, 0.9, 0), Vector3(0.06, 1.8, 0.06), Color("#3b2a1e"))  # pole
	var flag := Node3D.new()
	flag.position = top + Vector3(0, 1.65, 0)
	add_child(flag)
	W.box(flag, Vector3(length / 2.0, -0.35, 0), Vector3(length, 0.7, 0.03), color)
	W.box(flag, Vector3(length / 2.0, -0.35, 0), Vector3(0.28, 0.28, 0.035), Color("#e8c25a") if color == BANNER else Color("#a82a2a"))  # a golden emblem (raiders: red)
	banners.append([flag, randf() * TAU])


func build_gatehouse() -> void:
	var z := HALF
	for side in [-1, 1]:  # two square towers either side of the gate
		var x: float = side * (GATE_W / 2.0 + 1.6)
		s(Vector3(x, 5.0, z), Vector3(3.2, 10.0, 3.6))
		battlements(Vector3(x - 1.6, 0, z + 1.8), Vector3(x + 1.6, 0, z + 1.8), 10.0, 0.5)
		torch(Vector3(x - side * 1.0, 3.2, z + 1.95))
	s(Vector3(0, 8.0, z), Vector3(GATE_W, 4.0, 3.6))  # the bridge of stone over the gateway
	s(Vector3(0, 0.02, z + 3.0), Vector3(GATE_W + 1.0, 0.04, 3.0), "dark_stone", false)  # the threshold
	for i in 5:  # the portcullis, raised: only its spiked lower edge shows below the arch
		W.box(self, Vector3(-1.6 + i * 0.8, 6.3, z + 1.3), Vector3(0.1, 0.9, 0.1), Color("#26231f"))
	W.box(self, Vector3(0, 6.6, z + 1.3), Vector3(GATE_W, 0.12, 0.12), Color("#26231f"))
	if W.flag("castle") in ["", "restored", "rebuilt", "fortified"]:  # (the story may burn or seize the castle)
		for side in [-1, 1]:  # great banners hanging down the gate towers
			hanging_banner(Vector3(side * (GATE_W / 2.0 + 1.6), 9.4, z + 1.83))


## A long cloth banner hanging from a rod: red, gold-edged, a gold emblem, a swallow-tail end.
func hanging_banner(top: Vector3) -> void:
	var gold := Color("#e8c25a")
	W.box(self, top + Vector3(0, 0.1, 0.05), Vector3(1.8, 0.1, 0.1), Color("#3b2a1e"))  # rod
	W.box(self, top + Vector3(0, -2.0, 0.04), Vector3(1.4, 4.0, 0.04), BANNER)
	for x in [-0.66, 0.66]:
		W.box(self, top + Vector3(x, -2.0, 0.065), Vector3(0.08, 4.0, 0.02), gold)  # gold edges
	for dx in [-0.36, 0.36]:  # the swallow tail
		var tail: MeshInstance3D = W.box(self, top + Vector3(dx, -4.25, 0.04), Vector3(0.66, 0.66, 0.04), BANNER)
		tail.rotation.z = PI / 4.0
	var emblem: MeshInstance3D = W.box(self, top + Vector3(0, -1.6, 0.07), Vector3(0.7, 0.7, 0.02), gold)
	emblem.rotation.z = PI / 4.0
	W.box(self, top + Vector3(0, -1.6, 0.085), Vector3(0.12, 0.6, 0.02), BANNER)  # a red sword on the gold
	W.box(self, top + Vector3(0, -1.45, 0.085), Vector3(0.4, 0.08, 0.02), BANNER)


func torch(at: Vector3) -> void:
	if state in ["burnt", "ruin"]:  # the torches went out with the guards
		return
	W.box(self, at - Vector3(0, 0.25, 0), Vector3(0.1, 0.5, 0.1), Color("#3b2a1e"))
	W.glow(self, at + Vector3(0, 0.08, 0), Vector3(0.16, 0.22, 0.16), Color("#ff9a3a"), 4.0, "sphere")
	var l: OmniLight3D = W.light(self, at + Vector3(0, 0.3, 0.4), Color("#ff9a45"), 2.2, 11.0)
	torches.append([l, randf() * TAU])


func build_keep() -> void:
	var at := Vector3(0, 0, -5.0)
	great_hall(at)  # hollow: you can walk in through the big door facing the gate
	battlements(at + Vector3(-7, 0, 5.0), at + Vector3(7, 0, 5.0), 12.0, 0.6)
	battlements(at + Vector3(-7, 0, -5.0), at + Vector3(7, 0, -5.0), 12.0, 0.6)
	if not ruined:
		var roof := MeshInstance3D.new()  # a steep slate roof over the hall (a prism)
		var prism := PrismMesh.new()
		prism.size = Vector3(10.0, 5.0, 13.0)
		roof.mesh = prism
		roof.material_override = kit.mat("slate")
		roof.position = at + Vector3(0, 14.5, 0)
		roof.rotation.y = PI / 2.0
		add_child(roof)
	else:  # the roof has fallen in: bare charred roof beams over the hall
		for k in 6:
			W.box(self, at + Vector3(-5.0 + k * 2.0, 12.9, 0), Vector3(0.3, 0.3, 10.4), Color("#17120e"))
		for k in 3:
			var rib: MeshInstance3D = W.box(self, at + Vector3(-4.0 + k * 4.0, 14.0, 0.3), Vector3(0.28, 3.0, 0.28), Color("#120e0a"))
			rib.rotation.z = 0.2 - k * 0.2
	s(at + Vector3(4.5, 11.0, -1.0), Vector3(5.0, 22.0, 5.0))  # the tall tower at one end
	battlements(at + Vector3(2.0, 0, 1.5), at + Vector3(7.0, 0, 1.5), 22.0, 0.5)
	if not ruined:
		banner(at + Vector3(4.5, 22.0, -1.0), 2.4)
	elif state == "tolled":
		banner(at + Vector3(4.5, 22.0, -1.0), 2.4, Color("#161414"))
	for row in 2:  # rows of tall windows facing the gate, most of them lit
		for k in 5:
			var p := at + Vector3(-5.0 + k * 2.5, 4.0 + row * 4.0, 5.06)
			if state == "burnt" and (k + row) % 2 == 0:  # fire raging behind the windows
				W.glow(self, p, Vector3(0.7, 1.5, 0.1), Color("#ff5a1a"), 3.5)
			elif ruined:
				W.box(self, p, Vector3(0.7, 1.5, 0.1), Color("#0a0806"))
			elif (k + row) % 4 != 3:
				W.glow(self, p, Vector3(0.7, 1.5, 0.1), Color("#ffc46b"), 2.0)
			else:
				W.box(self, p, Vector3(0.7, 1.5, 0.1), Color("#141210"))
	W.box(self, at + Vector3(0, 1.6, 5.08), Vector3(2.2, 3.2, 0.12), Color("#3b2a1e"))  # the great door
	torch(at + Vector3(-1.8, 2.6, 5.3))
	torch(at + Vector3(1.8, 2.6, 5.3))


## Chapter 4: what the raid left. Soot up the walls, rubble in the yard, and fire and smoke by how far gone it is.
func build_ruin() -> void:
	var soot := Color("#0e0b09")
	for k in 5:  # black streaks above the keep's windows
		s(Vector3(-5.0 + k * 2.5, 10.8, 0.15), Vector3(1.1, 2.6 + (k % 2) * 1.2, 0.04), "dark_stone", false)
	s(Vector3(0, 3.0, 0.2), Vector3(2.8, 3.6, 0.04), "dark_stone", false)  # the scorched great door
	for side in [-1, 1]:  # soot over the gatehouse
		s(Vector3(side * (GATE_W / 2.0 + 1.6), 6.5, HALF + 1.84), Vector3(2.6, 5.0, 0.04), "dark_stone", false)
	for x in [-10.0, 9.0]:
		s(Vector3(x, 5.0, HALF + 0.84), Vector3(5.0, 4.0, 0.04), "dark_stone", false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for spot in [Vector3(-11, 0, 4), Vector3(11, 0, 5), Vector3(-11, 0, 11), Vector3(11, 0, 11), Vector3(-12, 0, -7), Vector3(12, 0, -7), Vector3(0, 0, 8.5)]:
		for i in 6:  # a heap of fallen stone and burnt timber
			var p: Vector3 = spot + Vector3(rng.randf_range(-1.6, 1.6), 0.0, rng.randf_range(-1.2, 1.2))
			var size := Vector3(rng.randf_range(0.4, 1.3), rng.randf_range(0.3, 0.8), rng.randf_range(0.4, 1.3))
			var chunk: MeshInstance3D = W.box(self, Vector3(p.x, SINK + 0.1 + size.y / 2.0, p.z), size, soot if i % 2 == 0 else Color("#5a5650"))
			chunk.rotation.y = rng.randf() * TAU
	for k in 4:  # burnt beams lying across the yard
		var beam: MeshInstance3D = W.box(self, Vector3(-6 + k * 4.5, SINK + 0.4, 5.0 + (k % 2) * 4.0), Vector3(0.35, 0.35, 3.2), Color("#17120e"))
		beam.rotation.y = 0.7 * k - 0.5
	match state:
		"burnt":  # still burning: flames in the yard, in the windows and on the roofless towers, thick smoke
			for p in [Vector3(-8, 0.5, 6), Vector3(8, 0.5, 8), Vector3(-9, 0.5, -6), Vector3(9, 0.5, -6)]:
				fire(p, 1.3)
			fire(Vector3(HALF, 12.2, HALF), 1.0)
			fire(Vector3(-HALF, 12.2, -HALF), 1.0)
			fire(Vector3(0, 12.5, -5), 1.6)
			for p in [Vector3(0, 12, -5), Vector3(HALF, 12, HALF), Vector3(-HALF, 12, -HALF), Vector3(-8, 1, 6)]:
				smoke_column(p, 14.0)
		"ruin":  # cold and empty: a few embers and one thin thread of smoke
			fire(Vector3(-9, 0.4, -6), 0.5)
			smoke_column(Vector3(0, 12, -5), 7.0)
		"tolled":  # the raiders' cooking fires in the yard under their black banner
			for p in [Vector3(-6, 0.4, 7), Vector3(6, 0.4, 9), Vector3(0, 0.4, 4)]:
				fire(p, 0.8)
			smoke_column(Vector3(0, 0.5, 5), 9.0)


## Chapter 5 ("rebuilt"): Highmoor raised anew. Pale new stone patches, fresh timber hoardings along the south wall,
## a new iron-bound gate door, and the valley's blue pennants on the corner towers beside the old red banners.
func build_rebuilt() -> void:
	var timber := Color("#b98a52")
	for x in [-11.0, -6.0, 6.0, 11.0]:  # hoardings: timber galleries standing out over the south wall top
		W.box(self, Vector3(x, WALL_H + 1.3, HALF + 0.3), Vector3(4.2, 0.18, 1.4), timber)
		W.box(self, Vector3(x, WALL_H + 2.1, HALF + 1.0), Vector3(4.2, 1.5, 0.14), timber.darkened(0.08))
		for dx in [-1.9, 1.9]:
			W.box(self, Vector3(x + dx, WALL_H + 0.9, HALF + 0.3), Vector3(0.18, 0.9, 0.18), timber.darkened(0.2))
	for k in 4:  # new pale stone patches where the fire had bitten
		s(Vector3(-9.0 + k * 6.0, 3.0 + (k % 2) * 1.5, HALF + 0.86), Vector3(2.4, 1.8, 0.04), "plaster", false)
	W.box(self, Vector3(0, 1.8, -5.0 + 5.14), Vector3(2.6, 3.6, 0.1), timber.darkened(0.25))  # the new great door
	for y in [0.8, 2.6]:
		W.box(self, Vector3(0, y, -5.0 + 5.21), Vector3(2.6, 0.14, 0.06), Color("#26231f"))  # iron bands
	for side in [-1, 1]:  # blue pennants on the gatehouse towers
		banner(Vector3(side * (GATE_W / 2.0 + 1.6), 10.0, HALF - 0.8), 1.4, Color("#2f4f8a"))


func fire(at: Vector3, size: float) -> void:
	W.glow(self, at, Vector3(0.9, 0.5, 0.9) * size, Color("#ff6a1a"), 3.5)
	W.glow(self, at + Vector3(0, 0.45 * size, 0), Vector3(0.5, 0.7, 0.5) * size, Color("#ffb040"), 3.0)
	var l: OmniLight3D = W.light(self, at + Vector3(0, 1.2 * size, 0), Color("#ff7a30"), 2.6 * size, 14.0 * size)
	fires.append([l, randf() * TAU, 2.6 * size])


## A column of grey puffs that rise, swell and fade, then start again from the bottom.
func smoke_column(base: Vector3, height: float) -> void:
	for i in 7:
		var puff := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.9
		ball.height = 1.8
		puff.mesh = ball
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.12, 0.11, 0.1, 0.5)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		puff.material_override = m
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.position = base
		add_child(puff)
		smoke.append([puff, i / 7.0, base, height, m])


func _process(delta: float) -> void:
	spin += delta
	var night: float = ctx.get("night", 1.0)
	for f in fires:  # flames flicker, and are brighter than the daylight
		f[0].light_energy = f[2] * (0.85 + 0.15 * sin(spin * 11.0 + f[1]) + 0.1 * sin(spin * 27.0 + f[1]))
	for sm in smoke:
		var life: float = fmod(spin * 0.08 + sm[1], 1.0)
		sm[0].position = sm[2] + Vector3(life * 3.0 + sin(spin + sm[1] * 6.0) * 0.4, life * sm[3], 0.0)
		sm[0].scale = Vector3.ONE * (0.6 + life * 2.4)
		sm[4].albedo_color.a = 0.5 * (1.0 - life) * smoothstep(0.0, 0.1, life)
	for t in torches:
		t[0].light_energy = 2.2 * (0.8 + 0.12 * sin(spin * 9.0 + t[1]) + 0.08 * sin(spin * 23.0 + t[1])) * lerpf(0.2, 1.0, night)
	for b in banners:  # banners stirring in the wind
		b[0].rotation.y = sin(spin * 1.3 + b[1]) * 0.25
		b[0].rotation.x = sin(spin * 2.1 + b[1]) * 0.05


## The great hall: thick walls round a stone floor, a tall doorway facing the gate (+z), and inside a long feast
## table with benches, the lord's throne on a dais, a great hearth, banners and candle chandeliers. When the story
## has ruined the castle it is dark inside: rubble, charred beams, a toppled throne.
func great_hall(at: Vector3) -> void:
	var w := 14.0
	var d := 10.0
	var h := 12.0
	var t := 1.0
	var door_w := 3.0
	var door_h := 4.5
	s(at + Vector3(0, h / 2.0, -d / 2.0 + t / 2.0), Vector3(w, h, t))  # back wall
	for side in [-1, 1]:
		s(at + Vector3(side * (w / 2.0 - t / 2.0), h / 2.0, 0), Vector3(t, h, d))
		var piece := (w - door_w) / 2.0  # front wall either side of the door
		s(at + Vector3(side * (door_w / 2.0 + piece / 2.0), h / 2.0, d / 2.0 - t / 2.0), Vector3(piece, h, t))
	s(at + Vector3(0, door_h + (h - door_h) / 2.0, d / 2.0 - t / 2.0), Vector3(door_w, h - door_h, t))  # over the door
	s(at + Vector3(0, 0.05, 0), Vector3(w - 2.0 * t, 0.1, d - 2.0 * t), "dark_stone", false)  # the floor
	s(at + Vector3(0, h - 0.3, 0), Vector3(w, 0.6, d), "planks")  # the ceiling (the roof sits on it)
	var inner := at + Vector3(0, 0.1, 0)
	if ruined:
		for k in 9:  # rubble and fallen beams, and the throne on its side
			var r: MeshInstance3D = W.box(self, inner + Vector3(randf_range(-5, 5), 0.3, randf_range(-3, 3)), Vector3(randf_range(0.6, 1.4), randf_range(0.4, 0.8), randf_range(0.6, 1.2)), Color("#5e5a54"), "cube", true)
			r.rotation.y = randf() * PI
		for k in 3:
			var beam: MeshInstance3D = W.box(self, inner + Vector3(-3.0 + k * 3.0, 0.4, randf_range(-2, 2)), Vector3(0.35, 0.35, 5.0), Color("#17120e"))
			beam.rotation = Vector3(randf_range(-0.3, 0.3), randf() * PI, randf_range(-0.2, 0.2))
		var throne: MeshInstance3D = W.box(self, inner + Vector3(0, 0.4, -3.2), Vector3(1.2, 0.8, 1.6), Color("#3a2a1a"))
		throne.rotation.z = PI / 2.0
		return
	var red := BANNER
	var gold := Color("#e8c25a")
	s(inner + Vector3(0, 0.3, -3.4), Vector3(5.0, 0.6, 2.2), "stone")  # the dais
	W.box(self, inner + Vector3(0, 0.62, 1.0), Vector3(1.8, 0.02, 7.5), red.darkened(0.15))  # a red runner
	var throne := inner + Vector3(0, 0.6, -3.6)
	W.box(self, throne + Vector3(0, 0.45, 0), Vector3(1.1, 0.9, 0.9), Color("#5a3d24"), "cube", true)
	W.box(self, throne + Vector3(0, 1.6, -0.4), Vector3(1.2, 2.2, 0.2), Color("#5a3d24"))  # tall back
	W.box(self, throne + Vector3(0, 1.4, -0.29), Vector3(0.8, 1.4, 0.04), red)  # its cushion
	W.box(self, throne + Vector3(0, 2.75, -0.4), Vector3(0.5, 0.25, 0.22), gold)  # a gilded crest
	for z in [-1.0, 1.6]:  # the long feast table (two halves) and benches
		W.box(self, inner + Vector3(0, 0.85, z), Vector3(1.4, 0.1, 2.4), Color("#6b4a2b"), "cube", true)
		for x in [-0.55, 0.55]:
			for zz in [-1.0, 1.0]:
				W.box(self, inner + Vector3(x, 0.42, z + zz), Vector3(0.1, 0.84, 0.1), Color("#4a3220"))
		for side in [-1, 1]:
			W.box(self, inner + Vector3(side * 1.15, 0.45, z), Vector3(0.4, 0.08, 2.4), Color("#5a3d24"))
		for k in 3:  # plates, goblets and a roast
			W.box(self, inner + Vector3(-0.35 + k * 0.35, 0.92, z - 0.7 + k * 0.7), Vector3(0.25, 0.03, 0.25), Color("#c9c2b0"))
			W.box(self, inner + Vector3(0.35 - k * 0.3, 0.98, z - 0.4 + k * 0.6), Vector3(0.08, 0.16, 0.08), gold)
		W.box(self, inner + Vector3(0, 0.98, z), Vector3(0.45, 0.22, 0.3), Color("#8a4a24"), "sphere")
	var hx := -w / 2.0 + t + 0.6  # the great hearth on the west wall
	s(inner + Vector3(hx, 1.6, 0), Vector3(1.2, 3.2, 3.0), "stone")
	W.box(self, inner + Vector3(hx + 0.62, 0.8, 0), Vector3(0.04, 1.4, 1.8), Color("#120e0a"))
	W.glow(self, inner + Vector3(hx + 0.55, 0.45, 0), Vector3(0.3, 0.6, 1.2), Color("#ff7a1a"), 4.0, "sphere")
	var hearth_light: OmniLight3D = W.light(self, inner + Vector3(hx + 1.6, 1.5, 0), Color("#ffa050"), 2.5, 10.0)
	torches.append([hearth_light, randf() * TAU])
	for x in [-3.5, 0.0, 3.5]:  # banners down the back wall
		W.box(self, inner + Vector3(x, 6.0, -d / 2.0 + t + 0.03), Vector3(1.4, 4.5, 0.05), red)
		W.box(self, inner + Vector3(x, 6.6, -d / 2.0 + t + 0.06), Vector3(0.6, 0.6, 0.02), gold)
	for z in [-1.5, 2.0]:  # chandeliers: an iron ring of candles on a chain
		var c := inner + Vector3(0, 7.0, z)
		W.box(self, c + Vector3(0, 2.2, 0), Vector3(0.05, 4.4, 0.05), Color("#2a2622"))
		W.box(self, c, Vector3(1.6, 0.08, 1.6), Color("#2a2622"))
		for k in 6:
			var a := k * TAU / 6.0
			W.glow(self, c + Vector3(cos(a) * 0.7, 0.2, sin(a) * 0.7), Vector3(0.06, 0.14, 0.06), Color("#ffcf6a"), 3.0)
		W.light(self, c - Vector3(0, 0.5, 0), Color("#ffcf8a"), 1.6, 12.0)

