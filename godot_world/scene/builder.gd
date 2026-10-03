extends Node3D
## The builder's hammer. Press H (or ask Barnaby for the hammer) to hold it: left click puts a 1 m block on the
## grid where you aim, right click knocks the aimed block away, C or the mouse wheel changes the block colour.
## Blocks are solid (you can jump up on them) and are saved in state["blocks"] as [x, y, z, colour index].

const COLORS := ["#c0392b", "#2e86de", "#27ae60", "#f1c40f", "#8e5a2b", "#bdc3c7", "#8e44ad", "#ecf0f1"]
const COLOR_NAMES := ["red", "blue", "green", "yellow", "brown", "grey", "purple", "white"]
const REACH := 8.0

var ctx: Dictionary
var W
var blocks := {}  # "x,y,z" -> StaticBody3D
var hammer: Node3D
var swing := 0.0


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	if not ctx.state.get("blocks_cleared", false):  # one-time: the user asked to remove all placed blocks
		ctx.state["blocks"] = []
		ctx.state["blocks_cleared"] = true
	for spec in ctx.state.get_or_add("blocks", []):
		make_block(int(spec[0]), int(spec[1]), int(spec[2]), int(spec[3]))
	make_hammer()
	hammer.visible = ctx.state.get("hammer", false)


## What the characters see of the built blocks: touching blocks form one structure, described by size, colours
## and place. Also whether the wanderer holds the hammer.
func seen_from(from: Vector3, _viewer: Node) -> Array:
	var cells := {}  # "x,y,z" -> [x, y, z, colour]
	for s in ctx.state.get("blocks", []):
		cells["%d,%d,%d" % [int(s[0]), int(s[1]), int(s[2])]] = [int(s[0]), int(s[1]), int(s[2]), int(s[3])]
	var found := []
	var done := {}
	for key in cells:
		if done.has(key):
			continue
		var group := []
		var todo := [key]
		done[key] = true
		while not todo.is_empty():
			var c: Array = cells[todo.pop_back()]
			group.append(c)
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						var k := "%d,%d,%d" % [c[0] + dx, c[1] + dy, c[2] + dz]
						if cells.has(k) and not done.has(k):
							done[k] = true
							todo.append(k)
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var counts := {}
		for c in group:
			lo = lo.min(Vector3(c[0], c[1], c[2]))
			hi = hi.max(Vector3(c[0], c[1], c[2]))
			counts[c[3]] = counts.get(c[3], 0) + 1
		var names := []
		for ci in counts:
			names.append(COLOR_NAMES[ci % COLOR_NAMES.size()])
		var mid := (lo + hi) / 2.0 + Vector3(0.5, 0, 0.5)
		var size := hi - lo + Vector3.ONE
		found.append([Vector2(mid.x - from.x, mid.z - from.z).length(),
			"a %s structure of %d block%s the wanderer built (%d wide, %d deep, %d high), %s" % [
				" and ".join(names), group.size(), "" if group.size() == 1 else "s", int(size.x), int(size.z), int(size.y),
				W.where(from, Vector3(mid.x, 0, mid.z))]])
	found.sort_custom(func(a, b): return a[0] < b[0])
	var out := []
	for i in mini(found.size(), 6):
		out.append(found[i][1])
	if found.size() > 6:
		out.append("and %d more built structures farther away" % (found.size() - 6))
	if held():
		out.append("the wanderer is holding a builder's hammer")
	return out


func _exit_tree() -> void:
	if hammer and is_instance_valid(hammer):
		hammer.queue_free()


func held() -> bool:
	return ctx.state.get("hammer", false)


func make_hammer() -> void:
	for old in W.camera.get_children():
		if old.name == "Hammer":
			old.free()
	hammer = Node3D.new()
	hammer.name = "Hammer"
	hammer.position = Vector3(0.34, -0.36, -0.65)
	hammer.rotation_degrees = Vector3(-20, 0, -12)
	var steel := Color("#7c828a")
	W.box(hammer, Vector3(0, 0, 0), Vector3(0.036, 0.4, 0.036), Color("#a0693a"))  # wooden handle
	W.box(hammer, Vector3(0, -0.1, 0), Vector3(0.046, 0.17, 0.046), Color("#3b2a20"))  # leather grip
	W.box(hammer, Vector3(0, -0.2, 0), Vector3(0.05, 0.02, 0.05), Color("#3b2a20"))  # butt end
	W.box(hammer, Vector3(0, 0.18, 0), Vector3(0.05, 0.05, 0.05), steel.darkened(0.2))  # collar
	W.box(hammer, Vector3(0, 0.22, -0.02), Vector3(0.055, 0.06, 0.13), steel)  # head
	W.box(hammer, Vector3(0, 0.22, -0.095), Vector3(0.07, 0.075, 0.03), steel.lightened(0.25))  # striking face
	for side in [-1, 1]:  # the two prongs of the claw, curving down
		var claw: MeshInstance3D = W.box(hammer, Vector3(side * 0.014, 0.205, 0.095), Vector3(0.02, 0.045, 0.1), steel)
		claw.rotation_degrees.x = 18
	W.camera.add_child(hammer)


func make_block(x: int, y: int, z: int, ci: int) -> void:
	var key := "%d,%d,%d" % [x, y, z]
	if blocks.has(key):
		return
	var body := StaticBody3D.new()
	body.position = Vector3(x + 0.5, y + 0.5, z + 0.5)
	body.set_meta("block", [x, y, z])
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3.ONE
	shape.shape = b
	body.add_child(shape)
	W.box(body, Vector3.ZERO, Vector3.ONE, Color(COLORS[ci % COLORS.size()]))
	add_child(body)
	blocks[key] = body


func aim() -> Dictionary:
	var from: Vector3 = W.camera.global_position
	var to: Vector3 = from - W.camera.global_basis.z * REACH
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [W.player.get_rid()])
	return W.get_world_3d().direct_space_state.intersect_ray(query)


func place() -> void:
	var hit := aim()
	if hit.is_empty():
		return
	var p: Vector3 = hit.position + hit.normal * 0.5
	var x := int(floorf(p.x))
	var y := int(floorf(p.y))
	var z := int(floorf(p.z))
	if y < 0 or blocks.has("%d,%d,%d" % [x, y, z]):
		return
	var pp: Vector3 = W.player.position  # don't build inside yourself
	if absf(pp.x - (x + 0.5)) < 0.9 and absf(pp.z - (z + 0.5)) < 0.9 and pp.y < y + 1.0 and pp.y + 1.9 > y:
		return
	var ci: int = ctx.state.get("block_color", 0)
	ctx.state["blocks"].append([x, y, z, ci])
	make_block(x, y, z, ci)
	swing = 1.0


func remove() -> void:
	var hit := aim()
	if hit.is_empty() or not hit.collider.has_meta("block"):
		return
	var cell: Array = hit.collider.get_meta("block")
	var key := "%d,%d,%d" % cell
	blocks.erase(key)
	hit.collider.queue_free()
	var list: Array = ctx.state["blocks"]
	for i in list.size():
		if list[i][0] == cell[0] and list[i][1] == cell[1] and list[i][2] == cell[2]:
			list.remove_at(i)
			break
	swing = 1.0


func cycle_color(step: int) -> void:
	var ci: int = (int(ctx.state.get("block_color", 0)) + step + COLORS.size()) % COLORS.size()
	ctx.state["block_color"] = ci
	W.show_notice("Hammer: %s blocks" % COLOR_NAMES[ci])


func set_held(on: bool) -> void:
	ctx.state["hammer"] = on
	hammer.visible = on
	if on:
		W.show_notice("Hammer: click builds, right click removes, C / wheel = colour (%s)" % COLOR_NAMES[ctx.state.get("block_color", 0)], 6.0)


func key(event: InputEventKey) -> void:
	if event.keycode == KEY_H:
		set_held(not held())
	elif event.keycode == KEY_C and held():
		cycle_color(1)


func _input(event: InputEvent) -> void:
	if not held() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				place()
			MOUSE_BUTTON_RIGHT:
				remove()
			MOUSE_BUTTON_WHEEL_UP:
				cycle_color(1)
			MOUSE_BUTTON_WHEEL_DOWN:
				cycle_color(-1)


func _process(delta: float) -> void:
	if hammer:
		swing = maxf(swing - delta * 5.0, 0.0)
		hammer.rotation_degrees.x = -20 - sin(swing * PI) * 50


func handle(c: Dictionary) -> bool:
	match c.get("cmd", ""):
		"hammer":
			set_held(true)
		"unhammer":
			set_held(false)
		_:
			return false
	return true
