extends Node3D
## The hotbar (bottom of the screen, keys 1-3) and the sword. Slot 1 = the builder's hammer (builder.gd),
## slot 2 = the sword (slot 3 is the rocket, rocket.gd). Pressing a slot's key takes that item in hand; pressing it again puts it away.
## Sword: left click swings it and hurts goblins (goblins.gd) in front of you. Given with [sword] or [hotbar].
## state["hotbar"] = the bar has been given, state["sword_held"] = the sword is in hand.

const SLOTS := ["Hammer", "Sword", "Rocket", "","", "", "", "", "Todo"]  # slot 9 is the to-do book (todo.gd)
const SLOT_SIZE := 58
const REACH := 3.0  # how far the sword reaches
const ARC := 0.35  # dot product with your forward direction: anything in front of you within about 70 degrees

var ctx: Dictionary
var W
var layer: CanvasLayer
var slot_panels := []
var sword: Node3D
var swing := 0.0
var last_hammer := false
var blocking := false  # right mouse with the sword out (see _process)
var guard := 0.0  # 0..1, how far the sword is raised into the block


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	ctx.state["hotbar"] = true  # the bar is always there now, no need to be given it
	make_sword()
	sword.visible = held()
	make_bar()
	last_hammer = hammer_held()


func _exit_tree() -> void:
	for n in [sword]:
		if n and is_instance_valid(n):
			n.queue_free()


func held() -> bool:
	return ctx.state.get("sword_held", false)


func hammer_held() -> bool:
	return ctx.state.get("hammer", false)


func has_bar() -> bool:
	return ctx.state.get("hotbar", false)


func make_sword() -> void:
	for old in W.camera.get_children():
		if old.name == "Sword":
			old.free()
	sword = Node3D.new()
	sword.name = "Sword"
	sword.position = Vector3(0.36, -0.38, -0.62)
	sword.rotation_degrees = Vector3(-10, 0, -18)
	# the blade shows the weapon equipped in the RPG (rpg.gd): rusty, plain iron, or the blue Troll-Bane
	var weapon: String = ctx.state.get("rpg", {}).get("weapon", "iron_sword")
	var steel: Color = {"rusty_sword": Color("#8a8078"), "steel_sword": Color("#9cc4ff")}.get(weapon, Color("#c9d1d9"))
	var gold := Color("#c9a24a") if weapon != "rusty_sword" else Color("#6a5a48")
	# a tapered blade: three sections narrowing to a point, a darker fuller (groove) down the middle
	for k in 3:
		var w := 0.06 - k * 0.011
		W.box(sword, Vector3(0, 0.14 + k * 0.2, 0), Vector3(w, 0.2, 0.012), steel.lightened(0.04 * k))
	var tip := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.038, 0.1, 0.012)
	tip.mesh = prism
	tip.material_override = W.mat(steel.lightened(0.1))
	tip.position = Vector3(0, 0.79, 0)
	sword.add_child(tip)
	W.box(sword, Vector3(0, 0.33, 0), Vector3(0.012, 0.5, 0.016), steel.darkened(0.3))  # the fuller
	# crossguard with down-turned ends, a leather-wrapped grip with bands, a round pommel
	W.box(sword, Vector3(0, 0.03, 0), Vector3(0.2, 0.035, 0.045), gold)
	for side in [-1, 1]:
		var end: MeshInstance3D = W.box(sword, Vector3(side * 0.115, 0.01, 0), Vector3(0.05, 0.03, 0.04), gold)
		end.rotation.z = side * 0.6
	W.box(sword, Vector3(0, 0.03, 0), Vector3(0.05, 0.06, 0.05), gold.darkened(0.15))  # the guard's centre block
	W.box(sword, Vector3(0, -0.07, 0), Vector3(0.034, 0.15, 0.034), Color("#3e2a1a"))  # grip
	for k in 3:
		W.box(sword, Vector3(0, -0.02 - k * 0.045, 0), Vector3(0.038, 0.012, 0.038), Color("#2a1c12"))
	W.box(sword, Vector3(0, -0.165, 0), Vector3(0.06, 0.06, 0.06), gold, "sphere")  # pommel
	if weapon == "rusty_sword":  # patches of rust and a notch
		for p in [Vector3(0.012, 0.2, 0), Vector3(-0.014, 0.45, 0), Vector3(0.01, 0.58, 0)]:
			W.box(sword, p, Vector3(0.03, 0.06, 0.016), Color("#6a3a20"))
	elif weapon == "steel_sword":  # Troll-Bane's edge glows faintly
		W.glow(sword, Vector3(0, 0.38, 0), Vector3(0.066, 0.62, 0.006), Color("#6aa8ff"), 1.4)
	W.camera.add_child(sword)

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
	"Hammer": ["................", "...ddddddd......", "..dllllllld.....", "..dllllllld.....", "...ddddddd......",
		"......ww........", "......wW........", "......wW........", "......wW........", "......wW........",
		"......wW........", "......wW........", "......wW........", "......bb........", "................", "................"],
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


func select(slot: int) -> void:  # 0 = hammer, 1 = sword (3 = the rocket: rocket.gd)
	var builder = ctx.parts.get("builder")
	var was_hammer := hammer_held()
	var was_sword := held()
	ctx.state["sword_held"] = false
	if slot == 0:
		if builder:
			builder.set_held(not was_hammer)
	else:
		if builder and was_hammer:
			builder.set_held(false)
		if slot == 1:
			ctx.state["sword_held"] = not was_sword
	sword.visible = held()
	last_hammer = hammer_held()


func give(slot := 1) -> void:
	ctx.state["hotbar"] = true
	ctx.state["sword_held"] = false  # (so selecting the slot puts that item in hand rather than away)
	select(slot)
	W.show_notice("Hotbar: 1 hammer, 2 sword. Left click uses what you hold.", 6.0)


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
	[0.0, Vector3(-32, 8, -24), Vector3(0.34, -0.42, -0.6)],
	[0.22, Vector3(18, -10, -42), Vector3(0.46, -0.24, -0.5)],
	[0.42, Vector3(-70, 20, 68), Vector3(-0.05, -0.4, -0.74)],
	[0.55, Vector3(-82, 28, 78), Vector3(-0.16, -0.48, -0.68)],
	[1.0, Vector3(-32, 8, -24), Vector3(0.34, -0.42, -0.6)],
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
	if hammer_held() and held():  # H (builder) took the hammer in hand: the sword goes away
		ctx.state["sword_held"] = false
		sword.visible = false
	last_hammer = hammer_held()
	swing = maxf(swing - delta * 2.6, 0.0)
	pose_sword(1.0 - swing if swing > 0.0 else 1.0)
	# right mouse held: blocking. The blade comes across in front of you, flat (rpg.gd takes 75% off each hit)
	blocking = held() and swing <= 0.0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	guard = move_toward(guard, 1.0 if blocking else 0.0, delta * 9.0)
	if guard > 0.0:
		sword.rotation_degrees = sword.rotation_degrees.lerp(Vector3(-5, 10, 78), guard)
		sword.position = sword.position.lerp(Vector3(0.18, -0.2, -0.5), guard)
	if layer:
		var bar: Control = layer.get_node_or_null("Bar")
		if bar:
			bar.visible = has_bar() and W.camera.current
			var rocket = ctx.parts.get("rocket")
			var has_rocket: bool = rocket != null and rocket.owned()  # slot 3 is empty until you were given the launcher
			var pic3 = slot_panels[2].get_node_or_null("Pic")
			if pic3:
				pic3.visible = has_rocket
			else:
				slot_panels[2].get_node("Name").text = SLOTS[2] if has_rocket else ""
			slot_panels[2].tooltip_text = SLOTS[2] if has_rocket else ""
			for i in slot_panels.size():
				var on: bool = (i == 0 and hammer_held()) or (i == 1 and held()) or (i == 2 and has_rocket and rocket.held())
				slot_panels[i].add_theme_stylebox_override("panel", style(on))


func seen_from(_from: Vector3, _viewer: Node) -> Array:
	var seen := []
	if has_bar():
		seen.append("the wanderer has a hotbar (1 hammer, 2 sword)%s" % (
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
