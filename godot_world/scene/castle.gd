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

var ctx: Dictionary
var W
var kit
var torches := []  # [light, phase]
var banners := []  # [node, phase]
var spin := 0.0


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	kit = ctx.parts["kit"]
	var terrain = ctx.parts["terrain"]
	position = Vector3(terrain.CASTLE.x, terrain.CASTLE_TOP, terrain.CASTLE.z)
	build_walls()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		tower(Vector3(corner.x * HALF, 0, corner.y * HALF), 2.8, 12.0)
	build_gatehouse()
	build_keep()


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
	s(Vector3(0, 0.05, 0), Vector3(HALF * 2 - WALL_T, 0.1, HALF * 2 - WALL_T), "dark_stone", false)  # courtyard paving


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
	for k in 8:  # a ring of slit windows, a few of them lit
		var a := k * TAU / 8.0
		var p := at + Vector3(cos(a) * radius * 1.01, height * 0.62, sin(a) * radius * 1.01)
		if k % 3 == 0:
			var win: MeshInstance3D = W.glow(self, p, Vector3(0.22, 0.8, 0.22), Color("#ffc46b"), 2.4)
			win.rotation.y = -a
		else:
			var dark: MeshInstance3D = W.box(self, p, Vector3(0.2, 0.8, 0.2), Color("#141210"))
			dark.rotation.y = -a
	banner(at + Vector3(0, height + radius * 2.2, 0), 1.6)


func banner(top: Vector3, length: float) -> void:
	W.box(self, top + Vector3(0, 0.9, 0), Vector3(0.06, 1.8, 0.06), Color("#3b2a1e"))  # pole
	var flag := Node3D.new()
	flag.position = top + Vector3(0, 1.65, 0)
	add_child(flag)
	W.box(flag, Vector3(length / 2.0, -0.35, 0), Vector3(length, 0.7, 0.03), BANNER)
	W.box(flag, Vector3(length / 2.0, -0.35, 0), Vector3(0.28, 0.28, 0.035), Color("#e8c25a"))  # a golden emblem
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


func torch(at: Vector3) -> void:
	W.box(self, at - Vector3(0, 0.25, 0), Vector3(0.1, 0.5, 0.1), Color("#3b2a1e"))
	W.glow(self, at + Vector3(0, 0.08, 0), Vector3(0.16, 0.22, 0.16), Color("#ff9a3a"), 4.0, "sphere")
	var l: OmniLight3D = W.light(self, at + Vector3(0, 0.3, 0.4), Color("#ff9a45"), 2.2, 11.0)
	torches.append([l, randf() * TAU])


func build_keep() -> void:
	var at := Vector3(0, 0, -5.0)
	s(at + Vector3(0, 6.0, 0), Vector3(14.0, 12.0, 10.0))  # the great hall
	battlements(at + Vector3(-7, 0, 5.0), at + Vector3(7, 0, 5.0), 12.0, 0.6)
	battlements(at + Vector3(-7, 0, -5.0), at + Vector3(7, 0, -5.0), 12.0, 0.6)
	var roof := MeshInstance3D.new()  # a steep slate roof over the hall (a prism)
	var prism := PrismMesh.new()
	prism.size = Vector3(10.0, 5.0, 13.0)
	roof.mesh = prism
	roof.material_override = kit.mat("slate")
	roof.position = at + Vector3(0, 14.5, 0)
	roof.rotation.y = PI / 2.0
	add_child(roof)
	s(at + Vector3(4.5, 11.0, -1.0), Vector3(5.0, 22.0, 5.0))  # the tall tower at one end
	battlements(at + Vector3(2.0, 0, 1.5), at + Vector3(7.0, 0, 1.5), 22.0, 0.5)
	banner(at + Vector3(4.5, 22.0, -1.0), 2.4)
	for row in 2:  # rows of tall windows facing the gate, most of them lit
		for k in 5:
			var p := at + Vector3(-5.0 + k * 2.5, 4.0 + row * 4.0, 5.06)
			if (k + row) % 4 != 3:
				W.glow(self, p, Vector3(0.7, 1.5, 0.1), Color("#ffc46b"), 2.0)
			else:
				W.box(self, p, Vector3(0.7, 1.5, 0.1), Color("#141210"))
	W.box(self, at + Vector3(0, 1.6, 5.08), Vector3(2.2, 3.2, 0.12), Color("#3b2a1e"))  # the great door
	torch(at + Vector3(-1.8, 2.6, 5.3))
	torch(at + Vector3(1.8, 2.6, 5.3))


func _process(delta: float) -> void:
	spin += delta
	var night: float = ctx.get("night", 1.0)
	for t in torches:
		t[0].light_energy = 2.2 * (0.8 + 0.12 * sin(spin * 9.0 + t[1]) + 0.08 * sin(spin * 23.0 + t[1])) * lerpf(0.2, 1.0, night)
	for b in banners:  # banners stirring in the wind
		b[0].rotation.y = sin(spin * 1.3 + b[1]) * 0.25
		b[0].rotation.x = sin(spin * 2.1 + b[1]) * 0.05
