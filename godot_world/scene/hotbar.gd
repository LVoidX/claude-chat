extends Node3D
## The hotbar (bottom of the screen, keys 1-2 and 9) and the sword. Slot 1 = the sword; slot 2 = the rocket (rocket.gd).
## Pressing a slot's key takes that item in hand; pressing it again puts it away.
## Sword: left click swings it and hurts goblins (goblins.gd) in front of you. Given with [sword] or [hotbar].
## state["hotbar"] = the bar has been given, state["sword_held"] = the sword is in hand.

const SLOTS := ["Sword", "Rocket", "", "", "", "", "", "", "Todo"]  # slot 9 is the to-do book (todo.gd)
const SLOT_SIZE := 58
const REACH := 3.0  # how far the sword reaches
const ARC := 0.35  # dot product with your forward direction: anything in front of you within about 70 degrees

var ctx: Dictionary
var W
var layer: CanvasLayer
var slot_panels := []
var sword: Node3D
var sword_arm: Node3D
var upper_sleeve: MeshInstance3D
var forearm_bracer: MeshInstance3D
var wrist_cuff: MeshInstance3D
var sword_hand_root: Node3D
var sword_hand: MeshInstance3D
var swing := 0.0
var blocking := false  # right mouse with the sword out (see _process)
var guard := 0.0  # 0..1, how far the sword is raised into the block


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	ctx.state["hotbar"] = true  # the bar is always there now, no need to be given it
	ctx.state["blocks"] = []  # old builder-hammer structures are no longer part of the world
	ctx.state.erase("hammer")
	make_sword()
	sword.visible = held()
	make_bar()


func _exit_tree() -> void:
	for n in [sword, sword_arm, sword_hand_root]:
		if n and is_instance_valid(n):
			n.queue_free()


func held() -> bool:
	return ctx.state.get("sword_held", false)


func has_bar() -> bool:
	return ctx.state.get("hotbar", false)


func make_sword() -> void:
	for old in W.camera.get_children():
		if old.name in ["Sword", "SwordArm", "SwordHand"]:
			old.free()
	sword = Node3D.new()
	sword.name = "Sword"
	sword.position = Vector3(0.34, -0.42, -0.82)
	sword.scale = Vector3.ONE * 1.2
	sword.rotation_degrees = Vector3(-15, -10, -32)
	# The blade shows the weapon equipped in the RPG (rpg.gd): rusty iron, plain steel, or blue Troll-Bane.
	var weapon: String = ctx.state.get("rpg", {}).get("weapon", "iron_sword")
	var steel: Color = {"rusty_sword": Color("#a47a55"), "steel_sword": Color("#91b7e3")}.get(weapon, Color("#bac5ce"))
	var brass := Color("#c99c51") if weapon != "rusty_sword" else Color("#776044")
	var model_name: String = {"rusty_sword": "sword_rusty", "steel_sword": "sword_steel"}.get(weapon, "sword_iron")
	var model = W.prop(model_name, sword, Vector3.ZERO)  # the Blender sword (tools/blender/sword.py); the code-built one below is the fallback
	if model != null:
		var metal := StandardMaterial3D.new()
		metal.vertex_color_use_as_albedo = true
		metal.albedo_color = Color(0.8, 0.8, 0.82)  # (the hand-held light is strong: keep the blade from washing out)
		metal.metallic = 0.2 if weapon != "rusty_sword" else 0.1
		metal.roughness = 0.35 if weapon != "rusty_sword" else 0.6
		metal.cull_mode = BaseMaterial3D.CULL_DISABLED
		model.material_override = metal
		W.camera.add_child(sword)
		make_sword_arm()
		return
	var blade_material := StandardMaterial3D.new()
	blade_material.albedo_color = steel
	blade_material.metallic = 0.2 if weapon != "rusty_sword" else 0.05
	blade_material.roughness = 0.32 if weapon != "rusty_sword" else 0.5
	blade_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	blade_material.vertex_color_use_as_albedo = true
	blade_material.emission_enabled = true
	blade_material.emission = steel.darkened(0.25)
	blade_material.emission_energy_multiplier = 0.04
	if weapon == "steel_sword":
		blade_material.emission = Color("#8abfff")
		blade_material.emission_energy_multiplier = 0.1
	var blade := MeshInstance3D.new()
	blade.mesh = blade_mesh()
	blade.material_override = blade_material
	sword.add_child(blade)
	var fuller_tool := SurfaceTool.new()
	fuller_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fuller_color := steel.darkened(0.38)
	var fuller_vertices := [
		[Vector3(-0.003, 0.15, 0.026), Vector3(0.003, 0.15, 0.026), Vector3(-0.012, 0.94, 0.026)],
		[Vector3(0.003, 0.15, 0.026), Vector3(0.012, 0.94, 0.026), Vector3(-0.012, 0.94, 0.026)],
		[Vector3(-0.012, 0.94, 0.026), Vector3(0.012, 0.94, 0.026), Vector3(-0.002, 1.08, 0.018)],
		[Vector3(0.012, 0.94, 0.026), Vector3(0.002, 1.08, 0.018), Vector3(-0.002, 1.08, 0.018)]]
	for triangle in fuller_vertices:
		for vertex in triangle:
			fuller_tool.set_color(fuller_color)
			fuller_tool.add_vertex(vertex)
	fuller_tool.generate_normals()
	var fuller := MeshInstance3D.new()
	fuller.mesh = fuller_tool.commit()
	var fuller_material := metal_material(Color.WHITE, 0.02, 0.46)
	fuller_material.vertex_color_use_as_albedo = true
	fuller_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	fuller.material_override = fuller_material
	sword.add_child(fuller)
	if weapon == "rusty_sword":
		for p in [Vector3(-0.025, 0.24, -0.019), Vector3(0.018, 0.47, -0.019), Vector3(-0.008, 0.63, -0.019)]:
			var rust: MeshInstance3D = W.box(sword, p, Vector3(0.012, 0.045, 0.003), Color("#805032"))
			rust.rotation.z = 0.12
	var guard_points := [Vector3(-0.16, -0.005, 0.005), Vector3(-0.11, 0.018, 0.0),
		Vector3(-0.055, 0.043, 0.0), Vector3(0, 0.052, 0.0), Vector3(0.055, 0.043, 0.0),
		Vector3(0.11, 0.018, 0.0), Vector3(0.16, -0.005, 0.005)]
	for i in guard_points.size() - 1:
		rod(sword, guard_points[i], guard_points[i + 1], 0.018, brass)
	for side in [-1, 1]:
		sphere_piece(sword, Vector3(side * 0.158, -0.004, 0.005), Vector3.ONE * 0.038, brass)
	var ricasso := CylinderMesh.new()
	ricasso.top_radius = 0.044
	ricasso.bottom_radius = 0.052
	ricasso.height = 0.045
	ricasso.radial_segments = 8
	var ricasso_node := MeshInstance3D.new()
	ricasso_node.mesh = ricasso
	ricasso_node.material_override = metal_material(brass, 0.62, 0.32)
	ricasso_node.position.y = 0.075
	sword.add_child(ricasso_node)
	var grip := CylinderMesh.new()
	grip.top_radius = 0.027
	grip.bottom_radius = 0.03
	grip.height = 0.18
	grip.radial_segments = 10
	var grip_node := MeshInstance3D.new()
	grip_node.mesh = grip
	grip_node.material_override = leather_material(Color("#493020"))
	grip_node.position.y = -0.085
	sword.add_child(grip_node)
	for i in 5:
		var wrap := TorusMesh.new()
		wrap.inner_radius = 0.025
		wrap.outer_radius = 0.031
		wrap.rings = 4
		wrap.ring_segments = 6
		var thread := MeshInstance3D.new()
		thread.mesh = wrap
		thread.material_override = leather_material(Color("#9b7651") if i % 2 == 0 else Color("#36251b"))
		thread.position.y = -0.02 - i * 0.032
		sword.add_child(thread)
	sphere_piece(sword, Vector3(0, -0.19, 0), Vector3(0.075, 0.082, 0.075), brass)
	var pommel_cap := MeshInstance3D.new()
	var cap_mesh := SphereMesh.new()
	cap_mesh.radius = 0.018
	cap_mesh.height = 0.036
	cap_mesh.radial_segments = 8
	cap_mesh.rings = 4
	pommel_cap.mesh = cap_mesh
	pommel_cap.material_override = metal_material(steel.lightened(0.2), 0.65, 0.24)
	pommel_cap.position.y = -0.19
	sword.add_child(pommel_cap)
	W.camera.add_child(sword)
	make_sword_arm()


func blade_mesh() -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var levels := [[0.085, 0.27], [0.38, 0.245], [0.78, 0.18], [1.0, 0.12], [1.2, 0.003]]
	var rings := []
	for level in levels:
		var y: float = level[0]
		var half: float = float(level[1]) * 0.5
		rings.append(PackedVector3Array([
			Vector3(-half, y, 0.0), Vector3(-half * 0.38, y, -0.012),
			Vector3(-half * 0.18, y, -0.021), Vector3(0, y, -0.016),
			Vector3(half * 0.18, y, -0.021), Vector3(half * 0.38, y, -0.012),
			Vector3(half, y, 0.0), Vector3(half, y, 0.008),
			Vector3(0, y, 0.018), Vector3(-half, y, 0.008)]))
	for i in rings.size() - 1:
		var a: PackedVector3Array = rings[i]
		var b: PackedVector3Array = rings[i + 1]
		for k in a.size():
			var next := (k + 1) % a.size()
			var tone: Color = [Color("#c4d0d9"), Color("#e4edf2"), Color("#839aaa"), Color("#dce7ed"),
				Color("#8fa4b2"), Color("#eaf1f4"), Color("#bccbd4"), Color("#748b99"),
				Color("#b6c5cf"), Color("#d3dfe6")][k]
			tool.set_color(tone)
			tool.add_vertex(a[k])
			tool.add_vertex(b[k])
			tool.add_vertex(a[next])
			tool.set_color(tone)
			tool.add_vertex(a[next])
			tool.add_vertex(b[k])
			tool.add_vertex(b[next])
	tool.generate_normals()
	return tool.commit()


func metal_material(color: Color, metalness: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metalness
	material.roughness = roughness
	return material


func leather_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material


func rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var axis := b - a
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.85
	mesh.bottom_radius = radius
	mesh.height = axis.length()
	mesh.radial_segments = 8
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = metal_material(color, 0.68, 0.28)
	node.position = (a + b) * 0.5
	node.quaternion = Quaternion(Vector3.UP, axis.normalized())
	parent.add_child(node)
	return node


func sphere_piece(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 5
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.scale = size
	node.position = at
	node.material_override = metal_material(color, 0.58, 0.3)
	parent.add_child(node)
	return node


func make_sword_arm() -> void:
	# One tapered sleeve runs from the screen edge to the hilt, so the hold reads as one arm.
	sword_arm = Node3D.new()
	sword_arm.name = "SwordArm"
	W.camera.add_child(sword_arm)
	var sleeve_material := StandardMaterial3D.new()
	sleeve_material.albedo_color = Color("#675039")
	sleeve_material.roughness = 0.88
	sleeve_material.emission_enabled = true
	sleeve_material.emission = Color("#382819")
	sleeve_material.emission_energy_multiplier = 0.35
	upper_sleeve = arm_tube(0.043, 0.05, sleeve_material)
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color("#9a7955")
	cloth.roughness = 0.82
	wrist_cuff = arm_tube(0.037, 0.037, cloth)
	(wrist_cuff.mesh as CylinderMesh).height = 0.07
	forearm_bracer = arm_tube(0.052, 0.061, leather_material(Color("#765638")))
	sword_hand_root = Node3D.new()
	sword_hand_root.name = "SwordHand"
	sword_hand = MeshInstance3D.new()
	var palm := SphereMesh.new()
	palm.radius = 0.5
	palm.height = 1.0
	palm.radial_segments = 10
	palm.rings = 6
	sword_hand.mesh = palm
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color("#916b49")
	glove.roughness = 0.9
	# Keep the leather readable in the shaded foreground without making it glow.
	glove.emission_enabled = true
	glove.emission = Color("#382719")
	glove.emission_energy_multiplier = 0.28
	sword_hand.material_override = glove
	sword_hand.position = Vector3(-0.006, -0.014, -0.012)
	sword_hand.scale = Vector3(0.063, 0.1, 0.036)
	sword_hand_root.add_child(sword_hand)
	# Four curled fingers cross the grip, stacked along it like a real fist.
	# Each has a front segment and a short return around the far side of the handle.
	for i in 4:
		var y := 0.035 - i * 0.029
		hand_segment(sword_hand_root, Vector3(-0.035, y, 0.008), Vector3(0.025, y - 0.004, 0.004), 0.013, glove)
		hand_segment(sword_hand_root, Vector3(0.025, y - 0.004, 0.004), Vector3(0.021, y - 0.012, -0.03), 0.011, glove)
	# The thumb closes across the index finger on the visible side of the grip.
	hand_segment(sword_hand_root, Vector3(-0.058, 0.043, -0.025), Vector3(-0.024, 0.020, 0.01), 0.014, glove)
	hand_segment(sword_hand_root, Vector3(-0.024, 0.020, 0.01), Vector3(0.018, 0.013, 0.008), 0.013, glove)
	W.camera.move_child(sword_arm, sword.get_index())  # the sleeve sits behind the sword.
	sword.add_child(sword_hand_root)  # Parent the hand to the sword so its fingers cannot slip off the grip.
	update_sword_arm()


func hand_segment(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var axis := b - a
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = axis.length() + radius * 2.0
	mesh.radial_segments = 7
	mesh.rings = 4
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = (a + b) * 0.5
	node.quaternion = Quaternion(Vector3.UP, axis.normalized())
	parent.add_child(node)
	return node


func arm_tube(top: float, bottom: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = 0.5
	mesh.radial_segments = 10
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	sword_arm.add_child(node)
	return node


func update_sword_arm() -> void:
	if not sword_arm or not upper_sleeve or not wrist_cuff or not sword_hand:
		return
	sword_arm.visible = held() and W.camera.current
	sword_hand_root.visible = sword_arm.visible
	if not sword_arm.visible:
		return
	# The fist covers the upper grip below the guard; keep the pommel visible beneath it.
	var grip := sword.position + sword.basis * Vector3(0, -0.055, 0.022)
	var shoulder := Vector3(0.58, -0.76, -0.68)
	var wrist := grip + sword.basis * Vector3(0, -0.045, 0)
	var arm_axis := (wrist - shoulder).normalized()
	place_tube(upper_sleeve, shoulder, wrist)
	place_tube(forearm_bracer, wrist - arm_axis * 0.29, wrist - arm_axis * 0.075)
	wrist_cuff.position = wrist - arm_axis * 0.045
	wrist_cuff.quaternion = Quaternion(Vector3.UP, arm_axis)
	sword_hand_root.position = Vector3(0, -0.055, 0.022)
	sword_hand_root.rotation = Vector3.ZERO


func place_tube(node: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var axis := to - from
	(node.mesh as CylinderMesh).height = axis.length() + 0.025
	node.position = (from + to) * 0.5
	node.quaternion = Quaternion(Vector3.UP, axis.normalized())

func make_bar() -> void:
	layer = CanvasLayer.new()
	add_child(layer)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -14
	bar.visible = has_bar()
	bar.name = "Bar"
	layer.add_child(bar)
	slot_panels.clear()
	for i in SLOTS.size():
		if i > 1 and i < 8:  # keep unused RPG slots off the bar; the to-do book stays on 9
			continue
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		bar.add_child(panel)
		var number := Label.new()
		number.text = str(i + 1)
		number.position = Vector2(4, 1)
		number.add_theme_font_size_override("font_size", 12)
		number.modulate = Color(1, 1, 1, 0.7)
		panel.add_child(number)
		var name_label := Label.new()
		name_label.text = SLOTS[i]
		name_label.name = "Name"
		name_label.size = Vector2(SLOT_SIZE, SLOT_SIZE)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", Color("#f2e6c8"))
		name_label.add_theme_color_override("font_outline_color", Color.BLACK)
		name_label.add_theme_constant_override("outline_size", 4)
		panel.add_child(name_label)
		if SLOTS[i] in ICONS:  # a pixel-art picture instead of the word
			var pic := TextureRect.new()
			pic.name = "Pic"
			pic.texture = icon(SLOTS[i])
			pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.position = Vector2(7, 7)
			pic.size = Vector2(SLOT_SIZE - 14, SLOT_SIZE - 14)
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(pic)
			panel.move_child(pic, 0)
			name_label.visible = false
			panel.tooltip_text = SLOTS[i]
		slot_panels.append(panel)


## Hotbar pictures, 16 x 16 pixels: each letter is a colour from PALETTE ("." = clear).
const PALETTE := {"w": "#7a5230", "W": "#a8754a", "s": "#c9d1d9", "S": "#ffffff", "d": "#5b6168", "g": "#e8c25a",
	"r": "#c0392b", "o": "#ff9a3a", "y": "#ffe08a", "b": "#5a3a1c", "p": "#efe2bc", "k": "#2a1a0c", "l": "#8a96a3"}
const ICONS := {
	"Sword": ["..............S.", ".............sS.", "............sSs.", "...........sSs..", "..........sSs...",
		".........sSs....", "........sSs.....", "...g...sSs......", "....g.sSs.......", ".....gSs........",
		"....wgg.........", "...ww.g.........", "..ww...g........", ".gg.............", ".gg.............", "................"],
	"Rocket": ["................", "...........rr...", "..........rssr..", ".........rssssr.", "........ssssss..",
		".......sssssr...", "......sssssr....", ".....dsssss.....", "....ddsssr......", "...rddsss.......",
		"..rr.ddd........", ".yo...d.........", "yoo.............", "yo..............", "................", "................"],
	"Todo": ["................", "..bbbbbbbbbbbb..", "..bppppppppppb..", "..bpkkkkkkkkpb..", "..bppppppppppb..",
		"..bpkkkkkkkppb..", "..bppppppppppb..", "..bpkkkkkkkkpb..", "..bppppppppppb..", "..bpkkkkkpppb..",
		"..bppppppppppb..", "..bppppppprppb..", "..bppppppprppb..", "..bbbbbbbbbbbb..", "................", "................"],
}


func icon(name: String) -> ImageTexture:
	var rows: Array = ICONS[name]
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		var row: String = rows[y]
		for x in 16:
			var ch := row[x] if x < row.length() else "."
			img.set_pixel(x, y, Color(PALETTE[ch]) if ch in PALETTE else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


var _styles := {}  # selected? -> StyleBoxFlat, made once


func style(selected: bool) -> StyleBoxFlat:
	if not selected in _styles:
		var s := StyleBoxFlat.new()
		s.bg_color = Color("#3a2614", 0.88) if selected else Color("#21160c", 0.8)  # dark oak
		s.border_color = Color("#ffd24d") if selected else Color("#8a6a3a")  # gold when in hand, bronze otherwise
		s.set_border_width_all(3 if selected else 2)
		s.shadow_color = Color(1.0, 0.8, 0.3, 0.35) if selected else Color(0, 0, 0, 0.4)
		s.shadow_size = 6 if selected else 3
		s.set_corner_radius_all(4)
		_styles[selected] = s
	return _styles[selected]


func select(slot: int) -> void:  # 0 = sword, 1 = rocket
	var was_sword := held()
	var rocket = ctx.parts.get("rocket")
	if slot == 1 and (rocket == null or not rocket.owned()):
		return  # the empty launcher slot does not put away the sword
	var was_rocket: bool = rocket != null and rocket.held()
	ctx.state["sword_held"] = false
	if rocket and was_rocket:
		rocket.set_held(false)
	if slot == 0:
		ctx.state["sword_held"] = not was_sword
	elif slot == 1 and rocket and rocket.owned():
		rocket.set_held(not was_rocket)
	sword.visible = held()


func give(slot := 0) -> void:
	ctx.state["hotbar"] = true
	ctx.state["sword_held"] = false  # (so selecting the slot puts that item in hand rather than away)
	select(slot)
	W.show_notice("Hotbar: 1 sword, 2 rocket. Left click uses what you hold.", 6.0)


func key(event: InputEventKey) -> void:
	if not has_bar():
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_2:
		select(event.keycode - KEY_1)


func _input(event: InputEvent) -> void:
	if not held() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		attack()


## The swing, in keyed poses: rest, wind up (blade cocked back over the right shoulder), a fast diagonal cut down
## across to the left, follow-through, back to rest. t = 0..1 through the swing.
const POSES := [  # [t, rotation degrees, position]
	[0.0, Vector3(-15, -10, -32), Vector3(0.34, -0.42, -0.82)],
	[0.22, Vector3(18, -10, -38), Vector3(0.5, -0.24, -0.5)],
	[0.42, Vector3(-70, 20, 68), Vector3(-0.05, -0.4, -0.74)],
	[0.55, Vector3(-82, 28, 78), Vector3(-0.16, -0.48, -0.68)],
	[1.0, Vector3(-15, -10, -32), Vector3(0.34, -0.42, -0.82)],
]


func pose_sword(t: float) -> void:
	for i in POSES.size() - 1:
		var a: Array = POSES[i]
		var b: Array = POSES[i + 1]
		if t <= float(b[0]):
			var k := (t - float(a[0])) / (float(b[0]) - float(a[0]))
			k = ease(k, 0.4) if i == 1 else smoothstep(0.0, 1.0, k)  # the cut itself is fast, the rest eases
			sword.rotation_degrees = (a[1] as Vector3).lerp(b[1], k)
			sword.position = (a[2] as Vector3).lerp(b[2], k)
			return


## A brief pale arc where the blade cut through the air.
func slash_trail() -> void:
	var trail := Node3D.new()
	W.camera.add_child(trail)
	for i in 7:
		var k := float(i) / 6.0
		var a := lerpf(-0.9, 0.9, k)
		var bit: MeshInstance3D = W.glow(trail, Vector3(sin(a) * 0.55, cos(a) * 0.32 - 0.12 - k * 0.2, -0.8), Vector3(0.16, 0.025, 0.01), Color("#f4f0ff"), 1.2)
		bit.rotation.z = -a * 0.9 - 0.4
		bit.transparency = 0.35 + k * 0.4
	var tw := create_tween()
	tw.tween_interval(0.06)
	tw.tween_property(trail, "scale", Vector3(1.15, 0.6, 1.0), 0.12)
	tw.tween_callback(trail.queue_free)


func attack() -> void:
	if swing > 0.25:
		return
	swing = 1.0
	get_tree().create_timer(0.14).timeout.connect(slash_trail)  # (when the blade sweeps through)
	var music = ctx.parts.get("music")
	if music:
		music.play_sfx("swing")
	var forward: Vector3 = -W.player.global_transform.basis.z
	var goblins = ctx.parts.get("goblins")
	if goblins:
		goblins.hit(W.player.position, forward, REACH, ARC)
	var creatures = ctx.parts.get("creatures")  # the RPG's wolves, skeletons and troll
	if creatures:
		creatures.sword_hit(W.player.position, forward, REACH, ARC)


func _process(delta: float) -> void:
	if not sword:
		return
	swing = maxf(swing - delta * 2.6, 0.0)
	pose_sword(1.0 - swing if swing > 0.0 else 1.0)
	# right mouse held: blocking. The blade comes across in front of you, flat (rpg.gd takes 75% off each hit)
	blocking = held() and swing <= 0.0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	guard = move_toward(guard, 1.0 if blocking else 0.0, delta * 9.0)
	if guard > 0.0:
		sword.rotation_degrees = sword.rotation_degrees.lerp(Vector3(-5, 10, 78), guard)
		sword.position = sword.position.lerp(Vector3(0.3, -0.36, -0.72), guard)
	elif swing <= 0.0:
		var speed := Vector2(W.player.velocity.x, W.player.velocity.z).length()
		var stride := clampf(speed / 4.0, 0.0, 1.0)
		var phase := Time.get_ticks_msec() * 0.001
		sword.position += Vector3(sin(phase * 1.7) * 0.004 + sin(phase * 8.0) * 0.008 * stride,
			absf(cos(phase * 8.0)) * 0.006 * stride, 0)
		sword.rotation_degrees += Vector3(sin(phase * 1.3) * 0.45, 0,
			sin(phase * 1.7) * 0.35 + sin(phase * 8.0) * 0.7 * stride)
	update_sword_arm()
	if layer:
		var bar: Control = layer.get_node_or_null("Bar")
		if bar:
			bar.visible = has_bar() and W.camera.current
			var rocket = ctx.parts.get("rocket")
			var has_rocket: bool = rocket != null and rocket.owned()  # slot 2 is empty until you were given the launcher
			var pic2 = slot_panels[1].get_node_or_null("Pic")
			if pic2:
				pic2.visible = has_rocket
			else:
				slot_panels[1].get_node("Name").text = SLOTS[1] if has_rocket else ""
			slot_panels[1].tooltip_text = SLOTS[1] if has_rocket else ""
			for i in slot_panels.size():
				var on: bool = (i == 0 and held()) or (i == 1 and has_rocket and rocket.held())
				slot_panels[i].add_theme_stylebox_override("panel", style(on))


func seen_from(_from: Vector3, _viewer: Node) -> Array:
	var seen := []
	if has_bar():
		seen.append("the wanderer has a hotbar (1 sword, 2 rocket)%s" % (
			", the sword drawn" if held() else ""))
	return seen


func handle(c: Dictionary) -> bool:
	match c.get("cmd", ""):
		"sword", "hotbar":
			give()
		"unsword":
			ctx.state["sword_held"] = false
			sword.visible = false
		_:
			return false
	return true
