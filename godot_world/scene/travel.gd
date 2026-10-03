extends Node3D
## Getting around and resting.
## Waystones: tall standing stones with a glowing rune at Thornvale, Highmoor, the Old Mill, the Barrow and the
## crossroads. Touch one to attune to it (its rune lights up); E at any attuned stone opens the list and takes you
## to any other attuned one. state["waystones"] = names attuned.
## The campfire at the crossroads: E to rest. Heals you fully; at night you sleep until morning.

const STONES := [  # name, position (x, z)
	["The Crossroads", Vector2(7, -7)],
	["Thornvale", Vector2(-36, -10)],
	["Highmoor Castle", Vector2(7, -116)],
	["The Old Mill", Vector2(64, 48)],
	["The Barrow", Vector2(-68, -66)],
]
const FIRE := Vector2(9, 6)

var ctx: Dictionary
var W
var stones := []  # {name, pos, rune: MeshInstance3D}
var layer: CanvasLayer
var panel: PanelContainer
var fade: ColorRect
var fire_light: OmniLight3D
var t := 0.0
var opened_at := 0  # (the E that opened the list must not also close it)


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	ctx.state.get_or_add("waystones", ["The Crossroads"])
	for s in STONES:
		add_stone(s[0], ground(s[1]))
	build_fire(ground(FIRE))
	layer = CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	fade = ColorRect.new()  # for sleeping and travelling
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)


func ground(p: Vector2) -> Vector3:
	return Vector3(p.x, W.ground_y(p.x, p.y), p.y)


func attuned(name: String) -> bool:
	return name in ctx.state.get("waystones", [])


func add_stone(name: String, at: Vector3) -> void:
	var node := Node3D.new()
	node.position = at
	add_child(node)
	var stone: Material = ctx.parts["kit"].mat("dark_stone") if ctx.parts.has("kit") else W.mat(Color("#55524c"))
	for p in [[Vector3(0, 0.15, 0), Vector3(1.6, 0.3, 1.6)], [Vector3(0, 1.6, 0), Vector3(0.8, 2.8, 0.5)],
			[Vector3(0, 3.15, 0), Vector3(0.6, 0.3, 0.42)]]:
		var b: MeshInstance3D = W.box(node, p[0], p[1], Color.WHITE, "cube", true)
		b.material_override = stone
	var rune: MeshInstance3D = W.glow(node, Vector3(0, 2.0, 0.26), Vector3(0.28, 0.5, 0.02), Color("#6ad0ff"), 2.5)
	W.glow(node, Vector3(0, 2.0, -0.26), Vector3(0.28, 0.5, 0.02), Color("#6ad0ff"), 2.5)
	var l := Label3D.new()
	l.text = name
	l.font_size = 34
	l.outline_size = 8
	l.pixel_size = 0.0009
	l.fixed_size = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = Color("#bfe8ff")
	l.position.y = 3.7
	node.add_child(l)
	stones.append({"name": name, "pos": at, "rune": rune, "node": node, "label": l})


func build_fire(at: Vector3) -> void:
	var fire := Node3D.new()
	fire.position = at
	add_child(fire)
	for i in 7:  # a ring of stones
		var a := i * TAU / 7.0
		W.box(fire, Vector3(cos(a) * 0.75, 0.12, sin(a) * 0.75), Vector3(0.3, 0.24, 0.3), Color("#6a665e"), "sphere")
	for i in 3:  # crossed logs
		var log: MeshInstance3D = W.box(fire, Vector3(0, 0.15, 0), Vector3(1.0, 0.16, 0.16), Color("#4a3220"))
		log.rotation.y = i * PI / 3.0
	W.glow(fire, Vector3(0, 0.4, 0), Vector3(0.45, 0.6, 0.45), Color("#ff7a1a"), 4.0, "sphere")
	W.glow(fire, Vector3(0, 0.75, 0), Vector3(0.2, 0.4, 0.2), Color("#ffd24d"), 4.0, "sphere")
	fire_light = W.light(fire, Vector3(0, 1.2, 0), Color("#ff8a3a"), 2.0, 10.0)
	for p in [Vector3(-2.2, 0.22, 0.4), Vector3(2.0, 0.22, -0.8)]:  # logs to sit on
		var seat: MeshInstance3D = W.box(fire, p, Vector3(1.6, 0.44, 0.44), Color("#5a3d24"), "cube", true)
		seat.rotation.y = 1.2 if p.x < 0 else -0.4


func interactables() -> Array:
	var out := [{"pos": ground(FIRE), "label": "Rest by the fire", "act": rest, "range": 2.8}]
	for s in stones:
		if attuned(s.name):
			out.append({"pos": s.pos, "label": "Travel by waystone", "act": open_travel.bind(s.name), "range": 2.6})
	return out


# --- resting -----------------------------------------------------------------------------------------------

func rest() -> void:
	var base = ctx.parts.get("base")
	var night: bool = float(ctx.get("night", 0.0)) > 0.5
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.8)
	tw.tween_callback(func():
		var rpg = ctx.parts.get("rpg")
		if rpg:
			rpg.heal(rpg.max_hp())
		if night and base:
			ctx.state["time"] = 7.0
			base.apply_time(0.0)
		W.show_notice("You rest by the fire until morning, and wake refreshed." if night else "You rest a while by the fire. Fully healed.", 5.0))
	tw.tween_interval(0.8 if night else 0.3)
	tw.tween_property(fade, "color:a", 0.0, 1.0)


# --- waystones ---------------------------------------------------------------------------------------------

func open_travel(from: String) -> void:
	close_travel()
	var rpg = ctx.parts.get("rpg")
	panel = PanelContainer.new()
	if ctx.has("ui_theme"):
		panel.theme = ctx["ui_theme"]
	if rpg:
		panel.add_theme_stylebox_override("panel", rpg.style(Color(0.08, 0.1, 0.14, 0.94), Color("#6ad0ff"), 3, 8))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(380, 0)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "THE WAYSTONE HUMS"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#bfe8ff"))
	box.add_child(title)
	for s in stones:
		var ok: bool = attuned(s.name) and s.name != from
		var label: String = s.name if attuned(s.name) else "(not yet found)"
		var b: Button = rpg.button(label if s.name != from else s.name + "  (you are here)", travel.bind(s.name), ok) if rpg else Button.new()
		box.add_child(b)
	if rpg:
		box.add_child(rpg.button("Close (E)", close_travel))
	ctx["ui_open"] = true
	opened_at = Time.get_ticks_msec()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_travel() -> void:
	if panel:
		panel.queue_free()
		panel = null
		ctx["ui_open"] = false


func travel(to: String) -> void:
	close_travel()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var target := Vector3.ZERO
	for s in stones:
		if s.name == to:
			target = s.pos + Vector3(0, 0.5, 2.2)
	var tw := create_tween()
	tw.tween_property(fade, "color", Color(0.4, 0.75, 1.0, 1.0), 0.5)
	tw.tween_callback(func():
		W.player.position = target
		W.player.velocity = Vector3.ZERO
		W.show_notice("The waystone carries you to " + to + ".", 3.5))
	tw.tween_property(fade, "color", Color(0.4, 0.75, 1.0, 0.0), 0.8)


func key(event: InputEventKey) -> void:
	if panel and event.keycode in [KEY_E, KEY_ESCAPE] and Time.get_ticks_msec() - opened_at > 150:
		close_travel()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	t += delta
	if fire_light:
		fire_light.light_energy = 1.9 + sin(t * 8.0) * 0.3 + sin(t * 21.0) * 0.15
	var me: Vector3 = W.player.global_position
	for s in stones:
		var on := attuned(s.name)
		s.rune.visible = on or fmod(t, 2.0) < 1.0  # an unattuned rune flickers
		s.label.visible = me.distance_to(s.pos) < 25.0
		if not on and Vector2(me.x - s.pos.x, me.z - s.pos.z).length() < 3.0:
			ctx.state.waystones.append(s.name)
			W.show_notice("Waystone attuned: " + s.name + ". Press E at any waystone to travel here.", 5.0)
			var rpg = ctx.parts.get("rpg")
			if rpg:
				rpg.sfx("chapter")


func seen_from(from: Vector3, _viewer: Node) -> Array:
	return ["glowing waystones for travel (at the crossroads, Thornvale, Highmoor, the Old Mill and the Barrow), and a campfire to rest at by the crossroads, %s" % W.where(from, ground(FIRE))]
