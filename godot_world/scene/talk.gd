extends Node3D
## Shared talking for characters (Marigold uses it; Barnaby has his own copy of this code in barnaby.gd).
## A character part makes one Talker on its body: `talker = ctx.parts["talk"].make(W, body, bubble_y, mouth_pos, mouth_size)`
## (make(W, body, bubble_y, mouth_pos, mouth_size)) and forwards the chat's commands to it: say_start(text), say_end(), say(text), set_mind("listening"/"thinking"/"").
## The Talker draws the pixel-art speech bubble over the head, opens and closes a mouth oval while the voice
## reads, and shows a "..." (listening) or "?" (thinking) symbol when the character is not talking.


func make(world, parent: Node3D, bubble_y: float, mouth_pos: Vector3, mouth_size: Vector3) -> Node3D:
	var talker := Talker.new()
	parent.add_child(talker)
	talker.setup(world, bubble_y, mouth_pos, mouth_size)
	return talker


class Talker extends Node3D:
	const BUBBLE_FONT := 16
	const BUBBLE_WRAP := 190.0
	const BUBBLE_PAD := 9
	const BUBBLE_TAIL := 8
	const INK := Color("#2b1d12")
	const PAPER := Color("#fff3d6")
	var W
	var mouth: MeshInstance3D
	var mouth_y := 0.0
	var bubble: Node3D
	var vp: SubViewport
	var canvas: Control
	var sprite: Sprite3D
	var font: SystemFont
	var text := ""
	var wrapped := []
	var shown := -1
	var bubble_size := Vector2(100, 100)
	var lines := []  # [start, end, text, (timed by the voice)]
	var cps := 14.0
	var mind_state := ""
	var mind: Label3D
	var base_y := 2.0

	func setup(world, bubble_y: float, mouth_pos: Vector3, mouth_size: Vector3) -> void:
		W = world
		base_y = bubble_y
		mouth = W.box(get_parent(), mouth_pos, mouth_size, Color("#4a1218"), "sphere")
		mouth.visible = false
		mouth_y = mouth_pos.y
		bubble = Node3D.new()
		bubble.position = Vector3(0, bubble_y, 0)
		bubble.visible = false
		add_child(bubble)
		font = SystemFont.new()
		font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
		font.font_weight = 700
		font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		font.hinting = TextServer.HINTING_NONE
		font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		vp = SubViewport.new()
		vp.transparent_bg = true
		vp.size = Vector2i(100, 100)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		bubble.add_child(vp)
		canvas = Control.new()
		canvas.draw.connect(draw_bubble)
		vp.add_child(canvas)
		sprite = Sprite3D.new()
		sprite.texture = vp.get_texture()
		sprite.pixel_size = 0.0065
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.shaded = false
		sprite.no_depth_test = true
		sprite.render_priority = 5
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		bubble.add_child(sprite)
		mind = Label3D.new()
		mind.position = Vector3(0, bubble_y - 0.05, 0)
		mind.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mind.no_depth_test = true
		mind.render_priority = 6
		mind.shaded = false
		mind.font_size = 160
		mind.pixel_size = 0.004
		mind.outline_size = 36
		mind.outline_modulate = INK
		mind.font = font
		mind.visible = false
		add_child(mind)

	func set_text(t: String) -> void:
		text = t
		shown = -1
		wrapped.clear()
		var cur := ""
		for word in t.split(" ", false):
			var test: String = word if cur == "" else cur + " " + word
			if cur != "" and font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT).x > BUBBLE_WRAP:
				wrapped.append(cur)
				cur = word
			else:
				cur = test
		wrapped.append(cur)
		var widest := 0.0
		for l in wrapped:
			widest = maxf(widest, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT).x)
		var h := font.get_height(BUBBLE_FONT) * wrapped.size()
		bubble_size = Vector2(ceilf(widest) + BUBBLE_PAD * 2, ceilf(h) + BUBBLE_PAD * 2 + BUBBLE_TAIL)
		bubble_size = Vector2(roundf(bubble_size.x / 2.0) * 2.0, bubble_size.y)
		vp.size = Vector2i(bubble_size)
		canvas.size = bubble_size
		sprite.offset = Vector2(0, bubble_size.y / 2.0)

	func px(r: Rect2, c: Color) -> void:
		canvas.draw_rect(r, c)

	func draw_bubble() -> void:
		var w := bubble_size.x
		var bh := bubble_size.y - BUBBLE_TAIL
		px(Rect2(2, 0, w - 4, bh), INK)
		px(Rect2(0, 2, w, bh - 4), INK)
		px(Rect2(4, 2, w - 8, bh - 4), PAPER)
		px(Rect2(2, 4, w - 4, bh - 8), PAPER)
		var cx := w / 2.0
		for i in 4:
			px(Rect2(cx - 7 + 2 * i, bh + 2 * i, 14 - 4 * i, 2), INK)
			if i < 3:
				px(Rect2(cx - 5 + 2 * i, bh + 2 * i, 10 - 4 * i, 2), PAPER)
		px(Rect2(cx - 5, bh - 2, 10, 2), PAPER)
		var lh := font.get_height(BUBBLE_FONT)
		var left := shown
		var y := float(BUBBLE_PAD)
		for l in wrapped:
			if left <= 0:
				break
			canvas.draw_string(font, Vector2(BUBBLE_PAD, y + font.get_ascent(BUBBLE_FONT)), l.substr(0, left),
				HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT, INK)
			left -= l.length() + 1
			y += lh

	func say_start(t: String) -> void:
		var now := Time.get_ticks_msec() / 1000.0
		lines.clear()
		lines.append([now, now + 60.0, t, true])  # the end is set by say_end (60 s = safety net)

	func say_end() -> void:
		var now := Time.get_ticks_msec() / 1000.0
		if lines.is_empty() or lines[0].size() < 4:
			return
		var elapsed: float = now - lines[0][0]
		var n: int = lines[0][2].length()
		if elapsed > 0.6 and n > 8:
			cps = lerpf(cps, clampf(n / elapsed, 6.0, 40.0), 0.5)
		lines[0][1] = now

	func say(t: String) -> void:  # an empty text means the voice was stopped
		if t.strip_edges() == "":
			lines.clear()

	func set_mind(state: String) -> void:
		mind_state = state

	func _process(_delta: float) -> void:
		if not bubble:
			return
		var now := Time.get_ticks_msec() / 1000.0
		while lines.size() > 1 and lines[1][0] <= now:
			lines.pop_front()
		if not lines.is_empty() and now > lines[0][1] + 1.5:
			lines.pop_front()
		var talking: bool = not lines.is_empty() and now >= lines[0][0]
		bubble.visible = talking
		if talking:
			var line: Array = lines[0]
			if text != line[2]:
				set_text(line[2])
			var progress := 1.0 if now >= line[1] else clampf((now - line[0]) * cps * 1.7 / maxf(text.length(), 1), 0.0, 1.0)
			var count := ceili(text.length() * progress)
			if count != shown:
				shown = count
				canvas.queue_redraw()
			var speaking: bool = now <= line[1]
			mouth.visible = speaking
			if speaking:
				var open := absf(sin(now * 13.0)) * (0.55 + 0.45 * sin(now * 4.7 + 1.0))
				mouth.scale.y = 0.02 + open * 0.035
				mouth.position.y = mouth_y - open * 0.0175
		else:
			mouth.visible = false
		if mind_state == "" or talking:
			mind.visible = false
		else:
			mind.visible = true
			if mind_state == "thinking":
				mind.text = "?"
				mind.modulate = Color("#ffd24d")
				mind.position.y = base_y - 0.05 + sin(now * 4.0) * 0.06
				mind.rotation.z = sin(now * 3.0) * 0.15
			else:
				mind.text = ".".repeat(1 + int(now * 3.0) % 3)
				mind.modulate = Color("#4dff88")
				mind.position.y = base_y - 0.05
				mind.rotation.z = 0.0
