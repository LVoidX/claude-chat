extends Node3D
## The hotbar (bottom of the screen, keys 1-3) and the sword. Slot 1 = the builder's hammer (builder.gd),
## slot 2 = the sword. Pressing a slot's key takes that item in hand; pressing it again puts it away.
## Sword: left click swings it and hurts goblins (goblins.gd) in front of you. Given with [sword] or [hotbar].
## state["hotbar"] = the bar has been given, state["sword_held"] = the sword is in hand.

const SLOTS := ["Hammer", "Sword", "Rocket", "","", "", "", "", "Todo"]  # slot 9 is the to-do book (todo.gd)
const GUN_RANGE := 80.0
const GUN_DAMAGE := 2  # a goblin takes 3 hit points: two shots
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
var gun: Node3D
var muzzle_flash: MeshInstance3D
var crosshair: ColorRect
var recoil := 0.0
var flash := 0.0
var blocking := false  # right mouse with the sword out (see _process)
var guard := 0.0  # 0..1, how far the sword is raised into the block
var tracers := []  # [node, age] bullet trails that fade after a moment


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	ctx.state["gun_held"] = false  # no gun any more
	ctx.state["hotbar"] = true  # the bar is always there now, no need to be given it
	make_sword()
	sword.visible = held()
	make_gun()
	gun.visible = gun_held()
	make_bar()
	last_hammer = hammer_held()


func _exit_tree() -> void:
	for n in [sword, gun]:
		if n and is_instance_valid(n):
			n.queue_free()


func gun_held() -> bool:
	return ctx.state.get("gun_held", false)


## A little pistol in the right hand. Its boxes only touch (never overlap or share a plane).
func make_gun() -> void:
	for old in W.camera.get_children():
		if old.name == "Gun":
			old.free()
	gun = Node3D.new()
	gun.name = "Gun"
	gun.position = Vector3(0.27, -0.25, -0.5)
	var dark := Color("#2d3238")
	W.box(gun, Vector3(0, 0, 0), Vector3(0.05, 0.07, 0.26), dark)  # slide and frame
	W.box(gun, Vector3(0, 0.005, -0.17), Vector3(0.026, 0.026, 0.08), Color("#1b1e22"))  # barrel (z -0.13 to -0.21)
	W.box(gun, Vector3(0, -0.095, 0.075), Vector3(0.04, 0.12, 0.05), Color("#6b4a2f"))  # grip, hangs under the frame
	W.box(gun, Vector3(0, -0.0475, -0.02), Vector3(0.012, 0.025, 0.07), dark.lightened(0.1))  # trigger guard, just under the frame
	W.box(gun, Vector3(0, 0.0425, -0.11), Vector3(0.012, 0.015, 0.012), Color("#ff7a2d"))  # front sight
	W.box(gun, Vector3(0, 0.0425, 0.11), Vector3(0.03, 0.015, 0.012), dark.lightened(0.15))  # rear sight
	muzzle_flash = W.box(gun, Vector3(0, 0.005, -0.235), Vector3(0.05, 0.05, 0.03), Color("#ffe58a"))
	muzzle_flash.visible = false
	W.camera.add_child(gun)


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
	var steel: Color = {"rusty_sword": Color("#9a6a48"), "steel_sword": Color("#9cc4ff")}.get(weapon, Color("#c9d1d9"))
	W.box(sword, Vector3(0, 0.34, 0), Vector3(0.055, 0.62, 0.014), steel)  # blade
	W.box(sword, Vector3(0, 0.34, 0), Vector3(0.02, 0.6, 0.02), steel.darkened(0.25))  # blade ridge
	W.box(sword, Vector3(0, 0.68, 0), Vector3(0.04, 0.05, 0.012), steel)  # tip
	if weapon == "rusty_sword":  # patches of rust and a notch
		for p in [Vector3(0.012, 0.2, 0), Vector3(-0.014, 0.45, 0), Vector3(0.01, 0.58, 0)]:
			W.box(sword, p, Vector3(0.03, 0.06, 0.016), Color("#6a3a20"))
	elif weapon == "steel_sword":  # Troll-Bane's edge glows faintly
		W.glow(sword, Vector3(0, 0.34, 0), Vector3(0.062, 0.6, 0.008), Color("#6aa8ff"), 1.4)
	W.box(sword, Vector3(0, 0.02, 0), Vector3(0.24, 0.035, 0.05), Color("#d4a72c"))  # cross guard
	W.box(sword, Vector3(0, -0.07, 0), Vector3(0.034, 0.16, 0.034), Color("#4a3322"))  # grip
	W.box(sword, Vector3(0, -0.16, 0), Vector3(0.06, 0.05, 0.06), Color("#d4a72c"), "sphere")  # pommel
	W.camera.add_child(sword)


func make_bar() -> void:
	layer = CanvasLayer.new()
	add_child(layer)
	crosshair = ColorRect.new()  # a small dot in the middle of the screen while the gun is out
	crosshair.color = Color(1, 1, 1, 0.85)
	crosshair.custom_minimum_size = Vector2(5, 5)
	crosshair.size = Vector2(5, 5)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(2.5, 2.5)
	crosshair.visible = false
	layer.add_child(crosshair)
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
		name_label.size = Vector2(SLOT_SIZE, SLOT_SIZE)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", Color("#f2e6c8"))
		name_label.add_theme_color_override("font_outline_color", Color.BLACK)
		name_label.add_theme_constant_override("outline_size", 4)
		panel.add_child(name_label)
		slot_panels.append(panel)


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


func select(slot: int) -> void:  # 0 = hammer, 1 = sword, 2 = gun
	var builder = ctx.parts.get("builder")
	var was_hammer := hammer_held()
	var was_sword := held()
	var was_gun := gun_held()
	ctx.state["sword_held"] = false
	ctx.state["gun_held"] = false
	if slot == 0:
		if builder:
			builder.set_held(not was_hammer)
	else:
		if builder and was_hammer:
			builder.set_held(false)
		if slot == 1:
			ctx.state["sword_held"] = not was_sword
		elif slot == 2:
			ctx.state["gun_held"] = not was_gun
	sword.visible = held()
	gun.visible = gun_held()
	last_hammer = hammer_held()


func give(slot := 1) -> void:
	ctx.state["hotbar"] = true
	ctx.state["sword_held"] = false  # (so selecting the slot puts that item in hand rather than away)
	ctx.state["gun_held"] = false
	select(slot)
	W.show_notice("Hotbar: 1 hammer, 2 sword. Left click uses what you hold.", 6.0)


func key(event: InputEventKey) -> void:
	if not has_bar():
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_2:  # (slot 3, the gun, is taken away)
		select(event.keycode - KEY_1)


func _input(event: InputEvent) -> void:
	if not (held() or gun_held()) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if gun_held():
			shoot()
		else:
			attack()


## Gun: an instant shot along where you aim. Stops at the first wall/block, hurts the goblin it passes through.
func shoot() -> void:
	if recoil > 0.55:
		return
	recoil = 1.0
	var from: Vector3 = W.camera.global_position
	var dir: Vector3 = -W.camera.global_basis.z
	var far := GUN_RANGE
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * GUN_RANGE, 0xFFFFFFFF, [W.player.get_rid()])
	var hit: Dictionary = W.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		far = from.distance_to(hit.position)
	var goblins = ctx.parts.get("goblins")
	if goblins:
		far = goblins.shoot(from, dir, far, GUN_DAMAGE)
	var kb = ctx.parts.get("knockback")
	if kb:
		far = kb.shoot(from, dir, far)  # Barnaby and Marigold get shoved back, never hurt
	var end := from + dir * far
	if not hit.is_empty() and far >= from.distance_to(hit.position) - 0.01 and goblins:
		goblins.burst(end, Color("#ffd24d"), 4, 2.5)  # sparks where it hit the ground or a block
	var muzzle: Vector3 = gun.global_position + gun.global_basis * Vector3(0, 0.01, -0.23)
	tracer(muzzle, end)
	flash = 0.06
	muzzle_flash.visible = true


func tracer(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.1:
		return
	var node := Node3D.new()
	add_child(node)
	node.global_position = (a + b) / 2.0
	node.look_at(b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
	W.box(node, Vector3.ZERO, Vector3(0.02, 0.02, length), Color("#fff2a8"))
	tracers.append([node, 0.0])


func attack() -> void:
	if swing > 0.35:
		return
	swing = 1.0
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
	if not sword or not gun:
		return
	if hammer_held() and (held() or gun_held()):  # H (builder) took the hammer in hand: the rest go away
		ctx.state["sword_held"] = false
		ctx.state["gun_held"] = false
		sword.visible = false
		gun.visible = false
	recoil = maxf(recoil - delta * 5.0, 0.0)  # gun kick
	gun.position = Vector3(0.27, -0.25, -0.5 + recoil * 0.06)
	gun.rotation_degrees = Vector3(recoil * 9.0, 0, 0)
	if flash > 0.0:
		flash -= delta
		if flash <= 0.0:
			muzzle_flash.visible = false
	for tr in tracers.duplicate():
		tr[1] += delta
		if tr[1] > 0.08:
			tr[0].queue_free()
			tracers.erase(tr)
	if crosshair:
		crosshair.visible = gun_held() and W.camera.current
	last_hammer = hammer_held()
	swing = maxf(swing - delta * 3.5, 0.0)
	var t := 1.0 - swing  # 0 at the start of a swing, 1 at the end
	var arc := sin(t * PI) if swing > 0.0 else 0.0
	sword.rotation_degrees = Vector3(-10 - arc * 70, arc * 25, -18 + arc * 55)
	sword.position = Vector3(0.36 - arc * 0.2, -0.38 + arc * 0.08, -0.62 - arc * 0.12)
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
			for i in slot_panels.size():
				var on: bool = (i == 0 and hammer_held()) or (i == 1 and held()) or (i == 2 and gun_held())
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
		"gun":
			pass  # the gun is taken away
		"unsword", "ungun":
			ctx.state["sword_held"] = false
			ctx.state["gun_held"] = false
			sword.visible = false
			gun.visible = false
		_:
			return false
	return true
