extends Node3D
## The hotbar (bottom of the screen, keys 1-9) and the sword. Slot 1 = the builder's hammer (builder.gd),
## slot 2 = the sword. Pressing a slot's key takes that item in hand; pressing it again puts it away.
## Sword: left click swings it and hurts goblins (goblins.gd) in front of you; clicking again as a swing ends
## chains a 3-hit combo (slash, backhand, a heavy overhead chop). Right click blocks / parries (combat.gd).
## Gun: 6 shots, then it reloads by itself. Given with [sword] / [hotbar] and [gun].
## state["hotbar"] = the bar has been given, state["sword_held"] = the sword is in hand.

const SLOTS := ["Hammer", "Sword", "Gun", "", "", "", "", "", ""]
const GUN_RANGE := 80.0
const GUN_DAMAGE := 2  # a goblin takes 3 hit points: two shots
const SLOT_SIZE := 58
const REACH := 3.0  # how far the sword reaches
const ARC := 0.35  # dot product with your forward direction: anything in front of you within about 70 degrees
# the combo: per hit its length (s), damage, reach and arc; the third is a slow, heavy chop
const COMBO := [[0.3, 1, 3.0, 0.35], [0.3, 1, 3.0, 0.35], [0.5, 2, 3.4, 0.15]]
const COMBO_GAP := 0.45  # seconds after a swing ends in which a click continues the combo
const MAGAZINE := 6
const RELOAD := 1.4

var ctx: Dictionary
var W
var layer: CanvasLayer
var slot_panels := []
var sword: Node3D
var swing_t := -1.0  # seconds into the current swing (-1 = not swinging)
var step := 0  # which hit of the combo the current swing is
var since_swing := 99.0
var queued := false  # a click during a swing: the next combo hit follows as soon as it can
var landed := false  # the current swing's hit has been dealt
var guard_pose := 0.0  # 0 = sword ready .. 1 = held across, blocking
var ammo := MAGAZINE
var reload_left := 0.0
var ammo_label: Label
var last_hammer := false
var gun: Node3D
var muzzle_flash: MeshInstance3D
var crosshair: ColorRect
var recoil := 0.0
var flash := 0.0
var tracers := []  # [node, age] bullet trails that fade after a moment


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
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
	var steel := Color("#c9d1d9")
	W.box(sword, Vector3(0, 0.34, 0), Vector3(0.055, 0.62, 0.014), steel)  # blade
	W.box(sword, Vector3(0, 0.34, 0), Vector3(0.02, 0.6, 0.02), steel.darkened(0.25))  # blade ridge
	W.box(sword, Vector3(0, 0.68, 0), Vector3(0.04, 0.05, 0.012), steel)  # tip
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
	ammo_label = Label.new()  # shots left, just below and right of the crosshair
	ammo_label.set_anchors_preset(Control.PRESET_CENTER)
	ammo_label.offset_left = 14
	ammo_label.offset_top = 10
	ammo_label.add_theme_font_size_override("font_size", 15)
	ammo_label.add_theme_color_override("font_outline_color", Color.BLACK)
	ammo_label.add_theme_constant_override("outline_size", 4)
	ammo_label.visible = false
	layer.add_child(ammo_label)
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
		name_label.add_theme_font_size_override("font_size", 13)
		panel.add_child(name_label)
		slot_panels.append(panel)


func style(selected: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.1, 0.1, 0.12, 0.75)
	s.border_color = Color("#ffd24d") if selected else Color(1, 1, 1, 0.35)
	s.set_border_width_all(3 if selected else 1)
	s.set_corner_radius_all(4)
	return s


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
	W.show_notice("Hotbar: 1 hammer, 2 sword, 3 gun. Left click uses what you hold; right click blocks with the sword (just in time = parry).", 6.0)


func key(event: InputEventKey) -> void:
	if not has_bar():
		return
	if event.keycode >= KEY_1 and event.keycode <= KEY_3:
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
	if recoil > 0.55 or reload_left > 0.0:
		return
	ammo -= 1
	if ammo <= 0:
		reload_left = RELOAD
	recoil = 1.0
	var combat = ctx.parts.get("combat")
	if combat:
		combat.sfx("shot")
		combat.shake(0.08)
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


## Left click with the sword: start a swing, or queue the next hit of the combo if one is under way.
func attack() -> void:
	var combat = ctx.parts.get("combat")
	if combat and (combat.blocking() or not combat.can_act()):
		return
	if swing_t >= 0.0:
		queued = true
		return
	step = (step + 1) % COMBO.size() if since_swing < COMBO_GAP else 0
	swing_t = 0.0
	landed = false
	queued = false
	if combat:
		combat.sfx("swish", 1.15 - step * 0.15)


## The blade connects about a third of the way into the swing.
func land_hit() -> void:
	landed = true
	var goblins = ctx.parts.get("goblins")
	if goblins:
		var c: Array = COMBO[step]
		var forward: Vector3 = -W.player.global_transform.basis.z
		goblins.hit(W.player.position, forward, c[2], c[3], c[1], step == COMBO.size() - 1)


func update_sword(delta: float) -> void:
	var combat = ctx.parts.get("combat")
	var blocking: bool = combat != null and combat.blocking()
	guard_pose = move_toward(guard_pose, 1.0 if blocking and swing_t < 0.0 else 0.0, delta * 9.0)
	var arc := 0.0
	if swing_t >= 0.0:
		swing_t += delta
		var length: float = COMBO[step][0]
		var u := clampf(swing_t / length, 0.0, 1.0)
		arc = sin(u * PI)
		if not landed and u >= 0.35:
			land_hit()
		if u >= 1.0:
			swing_t = -1.0
			since_swing = 0.0
			if queued:
				attack()
	else:
		since_swing += delta
	var rest := Vector3(-10, 0, -18)
	var rot := rest
	var pos := Vector3(0.36, -0.38, -0.62)
	match step if swing_t >= 0.0 else -1:
		0:  # slash from right to left
			rot = Vector3(-10 - arc * 70, arc * 25, -18 + arc * 55)
			pos += Vector3(-arc * 0.2, arc * 0.08, -arc * 0.12)
		1:  # backhand, left to right
			rot = Vector3(-10 - arc * 65, -arc * 30, -18 - arc * 60)
			pos += Vector3(-0.2 + arc * 0.15, arc * 0.1, -arc * 0.12)
		2:  # overhead chop
			rot = Vector3(30 - arc * 120, 0, -5)
			pos += Vector3(-arc * 0.12, 0.12 - arc * 0.05, -arc * 0.18)
	# blocking: the blade held across the view
	sword.rotation_degrees = rot.lerp(Vector3(0, 10, 75), guard_pose)
	sword.position = pos.lerp(Vector3(0.12, -0.24, -0.55), guard_pose)


func _process(delta: float) -> void:
	if not sword or not gun:
		return
	if hammer_held() and (held() or gun_held()):  # H (builder) took the hammer in hand: the rest go away
		ctx.state["sword_held"] = false
		ctx.state["gun_held"] = false
		sword.visible = false
		gun.visible = false
	recoil = maxf(recoil - delta * 5.0, 0.0)  # gun kick
	if reload_left > 0.0:  # reloading: the gun dips and turns away
		reload_left -= delta
		if reload_left <= 0.0:
			ammo = MAGAZINE
	var dip := sin(clampf(1.0 - reload_left / RELOAD, 0.0, 1.0) * PI) if reload_left > 0.0 else 0.0
	gun.position = Vector3(0.27, -0.25 - dip * 0.15, -0.5 + recoil * 0.06)
	gun.rotation_degrees = Vector3(recoil * 9.0 - dip * 30.0, 0, dip * 40.0)
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
		ammo_label.visible = crosshair.visible
		ammo_label.text = "reloading..." if reload_left > 0.0 else "%d / %d" % [ammo, MAGAZINE]
	last_hammer = hammer_held()
	update_sword(delta)
	if layer:
		var bar: Control = layer.get_node_or_null("Bar")
		if bar:
			bar.visible = has_bar() and W.camera.current
			for i in slot_panels.size():
				var on: bool = (i == 0 and hammer_held()) or (i == 1 and held()) or (i == 2 and gun_held())
				slot_panels[i].add_theme_stylebox_override("panel", style(on))


func describe_hotbar() -> Array:
	var seen := []
	if has_bar():
		seen.append("the wanderer has a hotbar (1 hammer, 2 sword, 3 gun)%s" % (
			", the sword drawn" if held() else ", holding a pistol" if gun_held() else ""))
	return seen


func handle(c: Dictionary) -> bool:
	match c.get("cmd", ""):
		"sword", "hotbar":
			give()
		"gun":
			give(2)
		"unsword", "ungun":
			ctx.state["sword_held"] = false
			ctx.state["gun_held"] = false
			sword.visible = false
			gun.visible = false
		_:
			return false
	return true
