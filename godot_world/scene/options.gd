extends Node3D
## Options (F1): master volume, ambient sounds (footsteps, birds, owls) on/off, graphics preset, fullscreen.
## state["volume"] 0..1 (master), state["ambient_off"]. The panel borrows rpg.gd's button/label looks.

var ctx: Dictionary
var W
var layer: CanvasLayer
var panel: PanelContainer
var open := false


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	apply_volume()
	layer = CanvasLayer.new()
	layer.layer = 19
	add_child(layer)


func volume() -> float:
	return clampf(float(ctx.state.get("volume", 1.0)), 0.0, 1.0)


func apply_volume() -> void:
	var v := volume()
	AudioServer.set_bus_volume_db(0, -80.0 if v <= 0.001 else linear_to_db(v))


func _exit_tree() -> void:
	AudioServer.set_bus_volume_db(0, 0.0)


func toggle() -> void:
	if open:
		close()
		return
	var rpg = ctx.parts.get("rpg")
	if rpg == null:
		return
	open = true
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(420, 0)
	panel.position = Vector2(-210, -150)
	panel.add_theme_stylebox_override("panel", rpg.style(Color(0.1, 0.07, 0.04, 0.96), Color("#c9a24a"), 2, 8))
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(rpg.label("OPTIONS", 20, Color("#ffd24d")))
	var vol_row := HBoxContainer.new()
	vol_row.add_child(rpg.label("Volume  ", 15))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = volume()
	slider.custom_minimum_size = Vector2(240, 24)
	slider.value_changed.connect(func(v: float):
		ctx.state["volume"] = v
		apply_volume())
	vol_row.add_child(slider)
	box.add_child(vol_row)
	var ambient: Button = rpg.button("", func(): pass)
	ambient.text = "Ambient sounds: " + ("off" if ctx.state.get("ambient_off", false) else "on")
	ambient.pressed.connect(func():
		ctx.state["ambient_off"] = not ctx.state.get("ambient_off", false)
		ambient.text = "Ambient sounds: " + ("off" if ctx.state["ambient_off"] else "on"))
	box.add_child(ambient)
	var quality = ctx.parts.get("quality")
	if quality:
		var gfx: Button = rpg.button("", func(): pass)
		gfx.text = "Graphics: " + quality.NAMES[quality.level()]
		gfx.pressed.connect(func():
			var q: Dictionary = ctx.state["quality"]
			q["level"] = (quality.level() + 1) % quality.PRESETS.size()
			q["locked"] = true
			quality.apply()
			gfx.text = "Graphics: " + quality.NAMES[quality.level()])
		box.add_child(gfx)
	box.add_child(rpg.button("Toggle fullscreen (F11)", func(): W.set_fullscreen(DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN)))
	box.add_child(rpg.button("Close (F1 or Esc)", close))
	ctx["ui_open"] = true  # (so a click does not grab the mouse back, world.gd)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	open = false
	if panel:
		panel.queue_free()
		panel = null
	W.save_state.call_deferred()
	ctx["ui_open"] = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func key(event: InputEventKey) -> void:
	if event.keycode == KEY_F1 or (event.keycode == KEY_ESCAPE and open):
		toggle() if event.keycode == KEY_F1 else close()
