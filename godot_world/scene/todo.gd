extends Node3D
## The to-do book (hotbar slot 9, key 9). Press 9 to open it and write what you want done, one line per
## task; start a line with "[x] " to tick it off. Esc closes it. The list lives in todo.txt next to
## chat.pyw, so the assistant can read it and change it (edits to the file show up in the book within a
## second), and the characters can change it with [todo add ...], [todo done N], [todo remove N], [todo clear].

const FILE := "todo.txt"
const MAX_LINES := 200

var ctx: Dictionary
var W
var layer: CanvasLayer
var panel: PanelContainer
var edit: TextEdit
var file_time := 0  # modified time of todo.txt when we last read or wrote it
var poll := 0.0


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	ctx["typing"] = null
	layer = CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	make_panel()
	panel.visible = false
	var text := read_file()
	if text == "" and ctx.state.has("todo"):
		text = str(ctx.state["todo"])  # the file was lost: take the copy from the saved state
	edit.text = text
	save()
	if ctx.get("todo_open", false):  # the world was rebuilt while you were writing: carry on where you were
		open_book.call_deferred(true)


func _exit_tree() -> void:
	if edit and is_instance_valid(edit):
		ctx["todo_caret"] = [edit.get_caret_line(), edit.get_caret_column()]
		save()  # (whatever was typed since the last change)


func path() -> String:
	return W.project_file(FILE)


func read_file() -> String:
	if not FileAccess.file_exists(path()):
		return ""
	return FileAccess.get_file_as_string(path())


func save() -> void:
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f:
		f.store_string(edit.text)
		f.close()
		file_time = FileAccess.get_modified_time(path())
	ctx.state["todo"] = edit.text  # (a copy in the saved state, in case the file is lost)


func make_panel() -> void:
	panel = PanelContainer.new()
	if ctx.has("ui_theme"):
		panel.theme = ctx["ui_theme"]
	var s := StyleBoxFlat.new()  # a leather-bound book with a parchment page
	s.bg_color = Color("#e8d9b0")
	s.border_color = Color("#5a3a1c")
	s.set_border_width_all(6)
	s.set_corner_radius_all(6)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 10
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 14
	s.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", s)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(520, 460)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := Label.new()
	title.text = "To do"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("#4a2a10"))
	box.add_child(title)
	edit = TextEdit.new()
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.placeholder_text = "One task per line.\nStart a line with [x] when it is done."
	edit.add_theme_font_size_override("font_size", 19)
	edit.add_theme_color_override("font_color", Color("#2a1a0a"))
	edit.add_theme_color_override("font_placeholder_color", Color("#8a7450"))
	edit.add_theme_color_override("caret_color", Color("#2a1a0a"))
	edit.add_theme_color_override("selection_color", Color("#c9a85c"))
	var clear := StyleBoxEmpty.new()  # write straight on the page
	for state_name in ["normal", "focus", "read_only"]:
		edit.add_theme_stylebox_override(state_name, clear)
	edit.text_changed.connect(save)
	box.add_child(edit)
	var hint := Label.new()
	hint.text = "Esc closes the book"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color("#7a6240"))
	box.add_child(hint)


func is_open() -> bool:
	return panel != null and panel.visible


func open_book(again := false) -> void:
	for other in ["rpg", "travel"]:  # another screen (inventory, waystone, ...) is really open
		var part = ctx.parts.get(other)
		if part and part.panel and is_instance_valid(part.panel):
			return
	# (a leftover ui_open flag from a rebuilt world must not block the book)
	panel.visible = true
	ctx["ui_open"] = true
	ctx["todo_open"] = true
	ctx["typing"] = self  # world.gd then sends keys only to this part, so typing doesn't walk, recentre or switch window
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	edit.grab_focus()
	var caret: Array = ctx.get("todo_caret", []) if again else []
	var line := mini(int(caret[0]), edit.get_line_count() - 1) if caret.size() == 2 else edit.get_line_count() - 1
	edit.set_caret_line(line)
	edit.set_caret_column(mini(int(caret[1]), edit.get_line(line).length()) if caret.size() == 2 else edit.get_line(line).length())


func close_book() -> void:
	ctx["todo_open"] = false
	panel.visible = false
	edit.release_focus()
	ctx["ui_open"] = false
	ctx["typing"] = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	save()


func key(event: InputEventKey) -> void:
	if is_open():
		if event.keycode == KEY_ESCAPE:
			close_book()
			get_viewport().set_input_as_handled()
		return  # (9 is just a character while you write)
	if event.keycode == KEY_9:
		open_book()
		get_viewport().set_input_as_handled()  # (so the 9 isn't typed into the book)


func _process(delta: float) -> void:
	poll += delta
	if poll < 0.7:
		return
	poll = 0.0
	# the assistant (or you in an editor) changed todo.txt: show the new text
	if FileAccess.file_exists(path()) and FileAccess.get_modified_time(path()) != file_time:
		var text := read_file()
		file_time = FileAccess.get_modified_time(path())
		if text != edit.text:
			var line := edit.get_caret_line()
			edit.text = text
			edit.set_caret_line(mini(line, edit.get_line_count() - 1))
			ctx.state["todo"] = text
			W.show_notice("The to-do book changed.", 3.0)


## The non-empty lines of the list.
func lines() -> Array:
	var out := []
	for l in edit.text.split("\n"):
		if l.strip_edges() != "":
			out.append(l.strip_edges())
	return out


func set_lines(list: Array) -> void:
	edit.text = "\n".join(list.slice(0, MAX_LINES))
	save()


func handle(c: Dictionary) -> bool:
	if c.get("cmd", "") != "todo":
		return false
	var args: Array = c.get("args", [])
	var what := str(args[0]).to_lower() if args.size() > 0 else ""
	var list := lines()
	match what:
		"add":  # [todo add buy bread]
			var text := " ".join(args.slice(1)).strip_edges()
			if text != "":
				list.append(text)
				set_lines(list)
				W.show_notice("Added to your to-do book: " + text, 4.0)
		"done", "undone", "remove":  # [todo done 2]
			var i := (int(args[1]) - 1) if args.size() > 1 else -1
			if i >= 0 and i < list.size():
				var line: String = list[i]
				var plain := line.trim_prefix("[x] ").trim_prefix("[X] ")
				if what == "remove":
					list.remove_at(i)
				else:
					list[i] = ("[x] " + plain) if what == "done" else plain
				set_lines(list)
		"clear":  # takes out the finished ones
			set_lines(list.filter(func(l): return not l.to_lower().begins_with("[x]")))
	return true


func seen_from(_from: Vector3, _viewer: Node) -> Array:
	var open_tasks := lines().filter(func(l): return not l.to_lower().begins_with("[x]"))
	if open_tasks.is_empty():
		return []
	return ["the wanderer's to-do book lists: " + "; ".join(open_tasks.slice(0, 5))]
