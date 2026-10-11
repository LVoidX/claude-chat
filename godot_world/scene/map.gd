extends Node3D
## The world map: P opens a painted map of the whole valley (heights, water, roads) with the places on it and an arrow
## where you are; P or Esc closes it. The picture is made once, a few rows per frame, from terrain.gd.
## Places you have not visited (waystones not attuned) show as "?".
## Needs: terrain.gd (height_at, road_distance, stream_distance, pond_distance, SIZE, VILLAGE, MILL, POND), travel.gd (STONES, attuned).

const PIXELS := 200  # map resolution (the land is terrain.SIZE metres across)
const SHOWN := 620.0  # size of the map on screen
const ROWS_PER_FRAME := 6

var ctx: Dictionary
var W
var layer: CanvasLayer
var panel: Control
var image: Image
var texture: ImageTexture
var next_row := 0
var open := false


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	image = Image.create(PIXELS, PIXELS, false, Image.FORMAT_RGB8)
	image.fill(Color("#5a7a48"))
	texture = ImageTexture.create_from_image(image)
	layer = CanvasLayer.new()
	layer.layer = 18
	add_child(layer)
	panel = Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	layer.add_child(panel)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(shade)
	var frame := Control.new()  # the map itself, centred
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.position = Vector2(-SHOWN / 2.0, -SHOWN / 2.0)
	frame.size = Vector2(SHOWN, SHOWN)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(frame)
	frame.draw.connect(paint.bind(frame))
	frame.set_meta("is_map", true)


func terrain():
	return ctx.parts.get("terrain")


## Paint a few more rows of the picture (called every frame until it is done).
func paint_rows() -> void:
	var tr = terrain()
	if tr == null or next_row >= PIXELS:
		return
	var size: float = tr.SIZE
	for r in ROWS_PER_FRAME:
		if next_row >= PIXELS:
			break
		var z := (float(next_row) + 0.5) / PIXELS * size - size / 2.0
		for col in PIXELS:
			var x := (float(col) + 0.5) / PIXELS * size - size / 2.0
			var h: float = tr.height_at(x, z)
			var c: Color
			if h < -0.12 and (tr.stream_distance(x, z) < 3.0 or tr.pond_distance(x, z) < 1.0):
				c = Color("#4a7fa8")  # water
			elif tr.road_distance(x, z) < tr.ROAD_WIDTH * 0.7:
				c = Color("#b89a6a")  # road
			elif h > 38.0:
				c = Color("#e8e8ec").lerp(Color("#b9b9c0"), clampf((70.0 - h) / 30.0, 0.0, 1.0))  # snow and bare rock
			elif h > 14.0:
				c = Color("#7c8a5e").lerp(Color("#8d8670"), clampf((h - 14.0) / 24.0, 0.0, 1.0))  # high grass to scree
			else:
				c = Color("#6fa04e").lerp(Color("#5b8a3e"), clampf(h / 14.0, 0.0, 1.0))  # the meadow and low hills
			# a little relief: the slope towards the north-west is lit
			var shade: float = clampf((tr.height_at(x - 2.0, z - 2.0) - h) * 0.03, -0.12, 0.12)
			image.set_pixel(col, next_row, c.lightened(shade) if shade > 0.0 else c.darkened(-shade))
		next_row += 1
	texture.update(image)


func to_map(x: float, z: float) -> Vector2:
	var size: float = terrain().SIZE if terrain() else 400.0
	return Vector2((x + size / 2.0) / size, (z + size / 2.0) / size) * SHOWN


func paint(frame: Control) -> void:
	frame.draw_rect(Rect2(-6, -6, SHOWN + 12, SHOWN + 12), Color("#2a2118"))
	frame.draw_rect(Rect2(-3, -3, SHOWN + 6, SHOWN + 6), Color("#c9a24a"))
	frame.draw_texture_rect(texture, Rect2(0, 0, SHOWN, SHOWN), false)
	var font := ThemeDB.fallback_font
	var tr = terrain()
	var travel = ctx.parts.get("travel")
	if travel:
		for s in travel.STONES:
			var p := to_map(s[1].x, s[1].y)
			var known: bool = travel.attuned(s[0])
			frame.draw_circle(p, 6.0, Color("#1b1b1b"))
			frame.draw_circle(p, 4.0, Color("#7fd6ff") if known else Color("#777777"))
			label_at(frame, font, p + (Vector2(-44, 22) if s[0] == "The Crossroads" else Vector2(9, 5)), s[0] if known else "?")
	if tr:
		frame.draw_circle(to_map(tr.VILLAGE.x, tr.VILLAGE.z), 7.0, Color("#8a5a3a"))  # the village, with its stone beside it
		label_at(frame, font, to_map(tr.POND.x, tr.POND.z) + Vector2(-16, -14), "Pond")
	var me: Vector3 = W.player.global_position
	var at := to_map(me.x, me.z)
	var yaw: float = W.player.rotation.y
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var side := fwd.orthogonal()
	frame.draw_colored_polygon(PackedVector2Array([at + fwd * 11.0, at - fwd * 7.0 + side * 6.0, at - fwd * 3.0, at - fwd * 7.0 - side * 6.0]), Color("#ff4a3a"))
	frame.draw_polyline(PackedVector2Array([at + fwd * 11.0, at - fwd * 7.0 + side * 6.0, at - fwd * 3.0, at - fwd * 7.0 - side * 6.0, at + fwd * 11.0]), Color("#ffffff"), 1.5)
	label_at(frame, font, Vector2(SHOWN / 2.0 - 4.0, 14.0), "N")
	label_at(frame, font, Vector2(8, SHOWN - 10.0), "P or Esc to close   -   red arrow: you")


func label_at(frame: Control, font: Font, pos: Vector2, text: String) -> void:
	frame.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
	frame.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#fff4d0"))


func key(event: InputEventKey) -> void:
	if event.keycode == KEY_P or (event.keycode == KEY_ESCAPE and open):
		open = not open if event.keycode == KEY_P else false
		panel.visible = open


func _process(_delta: float) -> void:
	paint_rows()
	if open:
		for child in panel.get_children():
			if child.has_meta("is_map"):
				child.queue_redraw()  # the arrow follows you
