extends Node3D
## A little village west of the meadow (terrain.gd: VILLAGE), where the west road ends: half-timbered cottages
## with thatched roofs, lit windows and smoking chimneys around a well, with fences, hay bales, barrels and a
## cart. Also the windmill on the eastern hills (terrain.gd: MILL), its sails turning slowly. Walls are solid.

const HOUSES := [  # offset from the village centre, size (width, depth), facing the well
	[Vector3(-6, 0, -11), Vector2(5.0, 7.0)],
	[Vector3(8, 0, -9), Vector2(4.5, 6.0)],
	[Vector3(-12, 0, 4), Vector2(5.5, 8.0)],
	[Vector3(6, 0, 10), Vector2(4.5, 6.5)],
	[Vector3(-4, 0, 13), Vector2(4.0, 5.5)],
]

var ctx: Dictionary
var W
var kit
var sails: Node3D
var windows := []  # [light, phase]
var spin := 0.0


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	kit = ctx.parts["kit"]
	var terrain = ctx.parts["terrain"]
	position = terrain.VILLAGE
	well()
	for i in HOUSES.size():
		cottage(HOUSES[i][0], HOUSES[i][1], i)
	fence(Vector3(-16, 0, -4), Vector3(-16, 0, -14))
	fence(Vector3(-16, 0, -14), Vector3(-9, 0, -17))
	fence(Vector3(11, 0, -3), Vector3(14, 0, 6))
	for p in [Vector3(-14, 0, -8), Vector3(-13, 0, -11), Vector3(12, 0, 1)]:
		hay(p)
	for p in [Vector3(-3.5, 0, -7.5), Vector3(-2.9, 0, -7.9), Vector3(4.5, 0, 6.8)]:
		barrel(p)
	cart(Vector3(3.5, 0, -3.5))
	windmill(terrain.MILL - terrain.VILLAGE, terrain)


func at_ground(local: Vector3) -> Vector3:
	var t = ctx.parts["terrain"]
	return Vector3(local.x, t.height_at(position.x + local.x, position.z + local.z), local.z)


func well() -> void:
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.1
	cyl.bottom_radius = 1.15
	cyl.height = 0.9
	cyl.radial_segments = 12
	ring.mesh = cyl
	ring.material_override = kit.mat("stone")
	ring.position = Vector3(0, 0.45, 0)
	add_child(ring)
	W.add_collider(self, Transform3D(Basis(), ring.position), Vector3(2.2, 0.9, 2.2), "sphere")
	W.box(self, Vector3(0, 0.88, 0), Vector3(1.6, 0.04, 1.6), Color("#0d1a22"), "sphere")  # dark water
	for side in [-1, 1]:
		kit.block(W, self, Vector3(side * 1.0, 1.4, 0), Vector3(0.16, 2.0, 0.16), "timber", false)
	kit.block(W, self, Vector3(0, 2.25, 0), Vector3(2.3, 0.12, 0.12), "timber", false)  # the winch beam
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(2.8, 0.9, 1.8)
	roof.mesh = prism
	roof.material_override = kit.mat("thatch")
	roof.position = Vector3(0, 2.75, 0)
	roof.rotation.y = PI / 2.0
	add_child(roof)
	W.box(self, Vector3(0.3, 1.6, 0), Vector3(0.3, 0.32, 0.3), Color("#6b4a2b"))  # the bucket


func cottage(offset: Vector3, size: Vector2, index: int) -> void:
	var house := Node3D.new()
	house.position = at_ground(offset)
	add_child(house)
	W.face(house, global_position)  # the door faces the well
	var w := size.x
	var d := size.y
	var h := 3.0
	kit.block(W, house, Vector3(0, 0.2, 0), Vector3(w + 0.2, 0.4, d + 0.2), "dark_stone")  # stone footing
	kit.block(W, house, Vector3(0, 0.4 + h / 2.0, 0), Vector3(w, h, d), "plaster")
	var beams := []  # the dark timber frame, standing just proud of the plaster
	for x in [-w / 2.0, w / 2.0]:
		for z in [-d / 2.0, d / 2.0]:
			beams.append([Vector3(x, 0.4 + h / 2.0, z), Vector3(0.22, h, 0.22)])
	for y in [0.45, 1.9, 3.35]:
		beams.append([Vector3(0, y, -d / 2.0 - 0.02), Vector3(w, 0.16, 0.06)])
		beams.append([Vector3(0, y, d / 2.0 + 0.02), Vector3(w, 0.16, 0.06)])
		beams.append([Vector3(-w / 2.0 - 0.02, y, 0), Vector3(0.06, 0.16, d)])
		beams.append([Vector3(w / 2.0 + 0.02, y, 0), Vector3(0.06, 0.16, d)])
	for b in beams:
		kit.block(W, house, b[0], b[1], "timber", false)
	for side in [-1, 1]:  # diagonal braces on the long walls
		var brace: MeshInstance3D = kit.block(W, house, Vector3(side * (w / 2.0 + 0.03), 1.2, -d / 4.0),
			Vector3(0.06, 0.14, d / 2.2), "timber", false)
		brace.rotation.x = 0.5
	# roof: a steep thatched prism over the length of the house, overhanging a little
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(w + 1.0, 2.6, d + 0.9)
	roof.mesh = prism
	roof.material_override = kit.mat("thatch")
	roof.position = Vector3(0, 0.4 + h + 1.3, 0)
	house.add_child(roof)
	var chimney_x := w / 2.0 - 0.7
	kit.block(W, house, Vector3(chimney_x, 0.4 + h + 1.4, d / 4.0), Vector3(0.6, 2.8, 0.6), "stone", false)
	if index % 2 == 0:
		smoke(house, Vector3(chimney_x, 0.4 + h + 2.9, d / 4.0))
	# door (front is -z: facing the well) and windows with shutters, lit from inside
	kit.block(W, house, Vector3(-w / 5.0, 1.4, -d / 2.0 - 0.04), Vector3(1.0, 2.0, 0.08), "planks", false)
	W.box(house, Vector3(-w / 5.0 + 0.35, 1.35, -d / 2.0 - 0.09), Vector3(0.08, 0.08, 0.04), Color("#2a2622"))
	for wx in [w / 4.0]:
		window(house, Vector3(wx, 2.0, -d / 2.0 - 0.03), false)
	for wz in [-d / 4.0, d / 4.0]:
		window(house, Vector3(w / 2.0 + 0.03, 2.0, wz), true)
		window(house, Vector3(-w / 2.0 - 0.03, 2.0, wz), true)


func window(house: Node3D, at: Vector3, side_wall: bool) -> void:
	var size := Vector3(0.06, 0.75, 0.7) if side_wall else Vector3(0.7, 0.75, 0.06)
	W.glow(house, at, size, Color("#ffbf66"), 2.2)
	var shutter := Vector3(0.05, 0.8, 0.3) if side_wall else Vector3(0.3, 0.8, 0.05)
	for k in [-1, 1]:
		var off := Vector3(0, 0, k * 0.52) if side_wall else Vector3(k * 0.52, 0, 0)
		kit.block(W, house, at + off, shutter, "planks", false, Color("#6d8a6a"))
	if windows.size() < 6:  # a few of the windows really light the ground outside
		var out := Vector3(signf(at.x) * 0.8, 0, 0) if side_wall else Vector3(0, 0, -0.8)
		var l: OmniLight3D = W.light(house, at + out, Color("#ffb86a"), 0.9, 6.0)
		windows.append([l, randf() * TAU])


func smoke(parent: Node3D, at: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 24
	p.lifetime = 5.0
	p.preprocess = 5.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.2, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0.15, 0.05, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, 1.6))
	var gt := CurveTexture.new()
	gt.curve = grow
	pm.scale_curve = gt
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.5))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	p.process_material = pm
	var puff := SphereMesh.new()
	puff.radius = 0.35
	puff.height = 0.7
	puff.radial_segments = 6
	puff.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#8d8a86")
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = m
	p.draw_pass_1 = puff
	p.position = at
	parent.add_child(p)


func fence(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	var n := int(length / 2.0) + 1
	for i in n + 1:
		var p := at_ground(a.lerp(b, float(i) / n))
		kit.block(W, self, p + Vector3(0, 0.6, 0), Vector3(0.14, 1.2, 0.14), "timber")
	for y in [0.5, 0.95]:  # two rails
		var mid := at_ground((a + b) / 2.0)
		var rail: MeshInstance3D = kit.block(W, self, mid + Vector3(0, y, 0), Vector3(length, 0.09, 0.07), "timber", false)
		rail.rotation.y = -atan2(b.z - a.z, b.x - a.x)


func hay(at: Vector3) -> void:
	var bale: MeshInstance3D = kit.block(W, self, at_ground(at) + Vector3(0, 0.45, 0), Vector3(1.3, 0.9, 0.9), "thatch")
	bale.rotation.y = randf() * PI


func barrel(at: Vector3) -> void:
	var b := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.32
	cyl.bottom_radius = 0.32
	cyl.height = 0.9
	cyl.radial_segments = 10
	b.mesh = cyl
	b.material_override = kit.mat("planks", Color("#a07a52"))
	b.position = at_ground(at) + Vector3(0, 0.45, 0)
	add_child(b)
	for y in [0.18, 0.72]:
		var hoop := MeshInstance3D.new()
		var hc := CylinderMesh.new()
		hc.top_radius = 0.335
		hc.bottom_radius = 0.335
		hc.height = 0.05
		hc.radial_segments = 10
		hoop.mesh = hc
		hoop.material_override = W.mat(Color("#34302c"))
		hoop.position = at_ground(at) + Vector3(0, y, 0)
		add_child(hoop)
	W.add_collider(self, Transform3D(Basis(), b.position), Vector3(0.64, 0.9, 0.64), "sphere")


func cart(at: Vector3) -> void:
	var cart_node := Node3D.new()
	cart_node.position = at_ground(at)
	cart_node.rotation.y = 0.6
	add_child(cart_node)
	kit.block(W, cart_node, Vector3(0, 0.75, 0), Vector3(1.4, 0.12, 2.2), "planks")
	for side in [-1, 1]:
		kit.block(W, cart_node, Vector3(side * 0.66, 1.0, 0), Vector3(0.08, 0.45, 2.2), "planks", false)
		var wheel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.48
		cyl.bottom_radius = 0.48
		cyl.height = 0.1
		cyl.radial_segments = 12
		wheel.mesh = cyl
		wheel.material_override = kit.mat("timber")
		wheel.position = Vector3(side * 0.78, 0.48, 0.2)
		wheel.rotation.z = PI / 2.0
		cart_node.add_child(wheel)
	kit.block(W, cart_node, Vector3(0, 0.6, -1.8), Vector3(0.08, 0.08, 1.6), "timber", false)  # the shaft
	hay(at + Vector3(0, 0.0, 0))  # (a bale stands beside it)


## A stone windmill on the hill, with a wooden cap and four lattice sails turning in the wind.
func windmill(offset: Vector3, terrain) -> void:
	var mill := Node3D.new()
	mill.position = Vector3(offset.x, terrain.height_at(terrain.MILL.x, terrain.MILL.z) - 0.3, offset.z)
	add_child(mill)
	W.face(mill, Vector3.ZERO)  # the sails face the meadow
	var tower := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.3
	cyl.bottom_radius = 3.2
	cyl.height = 11.0
	cyl.radial_segments = 12
	tower.mesh = cyl
	tower.material_override = kit.mat("stone", Color("#d8d0c4"))
	tower.position = Vector3(0, 5.5, 0)
	mill.add_child(tower)
	W.add_collider(mill, Transform3D(Basis(), tower.position), Vector3(5.6, 11.0, 5.6))
	var cap := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.2
	cone.bottom_radius = 2.8
	cone.height = 3.2
	cone.radial_segments = 12
	cap.mesh = cone
	cap.material_override = kit.mat("timber")
	cap.position = Vector3(0, 12.6, 0)
	mill.add_child(cap)
	kit.block(W, mill, Vector3(0, 1.2, -3.0), Vector3(1.2, 2.2, 0.2), "planks", false)  # the door
	W.glow(mill, Vector3(0, 7.5, -2.62), Vector3(0.6, 0.8, 0.1), Color("#ffbf66"), 2.0)  # a lit window
	sails = Node3D.new()
	sails.position = Vector3(0, 10.8, -3.0)
	mill.add_child(sails)
	kit.block(W, sails, Vector3.ZERO, Vector3(0.6, 0.6, 0.8), "timber", false)  # the hub
	for k in 4:
		var arm := Node3D.new()
		arm.rotation.z = k * PI / 2.0
		sails.add_child(arm)
		kit.block(W, arm, Vector3(0, 4.6, -0.2), Vector3(0.22, 9.0, 0.16), "timber", false)
		kit.block(W, arm, Vector3(0.75, 5.2, -0.25), Vector3(1.3, 7.2, 0.04), "plaster", false, Color("#cfc2a8"))  # the sailcloth
		for j in 6:  # lattice bars across the cloth
			kit.block(W, arm, Vector3(0.75, 2.2 + j * 1.2, -0.29), Vector3(1.4, 0.07, 0.05), "timber", false)


func _process(delta: float) -> void:
	spin += delta
	if sails:
		sails.rotation.z -= delta * 0.45
	for wl in windows:  # firelight inside, flickering a little
		wl[0].light_energy = 0.9 * (0.85 + 0.12 * sin(spin * 5.0 + wl[1]) + 0.05 * sin(spin * 13.0 + wl[1]))
