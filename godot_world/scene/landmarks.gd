extends Node3D
## RPG touches that tie the world together: nameplates over people (fade in as you come close), a signpost at the
## crossroads naming the places, and place names announced as you enter an area ("Thornvale Village").
## Names live here, so the storyteller and the characters can use them: Thornvale (the village), Highmoor (the castle),
## the Old Mill, the Barrow, the Wolfwood.

const PLATE_RANGE := 14.0
const PLACES := [  # name, centre (x, z), radius
	["Thornvale Village", Vector2(-44, 0), 22.0],
	["Highmoor Castle", Vector2(0, -140), 30.0],
	["The Old Mill", Vector2(74, 58), 14.0],
	["The Barrow of the Old Kings", Vector2(-80, -80), 20.0],
	["The Meadow Crossroads", Vector2(0, 0), 10.0],
	["Gorrak's Camp", Vector2(96, 12), 14.0],
	["Wolfwood Den", Vector2(80, -32), 12.0],
	["Wolfwood Den", Vector2(-24, 92), 12.0],
	["Wolfwood Den", Vector2(-112, -20), 12.0],
]
const TITLES := {"the farmer": "Farmer", "the woodcutter": "Woodcutter", "the water carrier": "Water Carrier",
	"the shepherd": "Shepherd", "a guard": "Castle Guard", "a guard on the wall": "Castle Guard"}

var ctx: Dictionary
var W
var plates := []  # [Label3D, Node3D to follow, height]
var here := ""  # the place the player is in now
var compass: Control  # the strip at the top of the screen: N / E / S / W and gold markers for story quests
var compass_items := []  # [Control, bearing source: float (fixed angle) or "quest"]
var markers := []  # gold diamonds, reused for the story quest targets
const COMPASS_W := 520.0


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	here = ctx.get("place_here", "")
	build_signpost(Vector3(-5.5, 0, -5.5))
	build_compass()
	make_plates.call_deferred()  # (after every part is built: Marigold and the villagers come after this one)


## Another part was swapped (world.gd reload_part): if it was someone with a nameplate, make the plates again.
func part_reloaded(name: String) -> void:
	if name in ["barnaby", "marigold", "villagers", "rpg"]:
		for p in plates:
			p[0].queue_free()
		plates.clear()
		make_plates()


func make_plates() -> void:
	for part in ctx.parts.values():
		if "npc_id" in part and "body" in part and part.body:
			var who := {"barnaby": "Barnaby Finch\n[i]old lighthouse keeper[/i]", "marigold": "Marigold Thorne\n[i]herbalist & baker[/i]"}
			plate(part.body, who.get(part.npc_id, str(part.npc_id).capitalize()), 2.45)
	var v = ctx.parts.get("villagers")
	if v and "folk" in v:
		for f in v.folk:
			plate(f.node, TITLES.get(f.name, str(f.name).capitalize()), 2.25)
	var rpg = ctx.parts.get("rpg")
	if rpg:
		var spot := Node3D.new()
		spot.position = rpg.at_ground(rpg.SMITHY) + Vector3(0.2, 0, 0.9)
		add_child(spot)
		plate(spot, "Hob Ironside\n[i]smith[/i]", 2.4)


func plate(target: Node3D, text: String, height: float) -> void:
	var l := Label3D.new()
	var lines := text.split("\n")
	l.text = lines[0] + ("\n" + lines[1].replace("[i]", "").replace("[/i]", "") if lines.size() > 1 else "")
	l.font_size = 40
	l.outline_size = 10
	l.modulate = Color("#f2e6c8")
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.0009
	l.fixed_size = true  # the same size on screen near or far
	add_child(l)
	plates.append([l, target, height])


func build_signpost(at: Vector3) -> void:
	var post := Node3D.new()
	post.position = Vector3(at.x, W.ground_y(at.x, at.z), at.z)
	add_child(post)
	var wood := Color("#5a3d24")
	W.box(post, Vector3(0, 1.4, 0), Vector3(0.18, 2.8, 0.18), wood, "cube", true)
	W.box(post, Vector3(0, 2.86, 0), Vector3(0.26, 0.12, 0.26), wood.darkened(0.2))
	# arrows: direction (x, z), height, name
	for arm in [[Vector2(-1, 0), 2.5, "Thornvale"], [Vector2(0, -1), 2.15, "Highmoor Castle"], [Vector2(1, 0.75), 1.8, "The Old Mill"]]:
		var dir: Vector2 = arm[0].normalized()
		var board := Node3D.new()
		board.position = Vector3(0, arm[1], 0)
		board.rotation.y = atan2(-dir.x, -dir.y) + PI / 2.0  # the board's +x points down the road
		post.add_child(board)
		W.box(board, Vector3(0.75, 0, 0), Vector3(1.3, 0.26, 0.06), Color("#8a6440"))
		var tip: MeshInstance3D = W.box(board, Vector3(1.45, 0, 0), Vector3(0.2, 0.2, 0.06), Color("#8a6440"))
		tip.rotation.z = PI / 4.0
		for side in [-1, 1]:  # painted names on both faces
			var l := Label3D.new()
			l.text = arm[2]
			l.font_size = 40
			l.pixel_size = 0.0032
			l.modulate = Color("#2a1a0c")
			l.outline_size = 0
			l.position = Vector3(0.75, 0, side * 0.035)
			l.rotation.y = 0.0 if side > 0 else PI
			board.add_child(l)


func build_compass() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	compass = Control.new()
	compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	compass.offset_left = -COMPASS_W / 2.0
	compass.offset_right = COMPASS_W / 2.0
	compass.offset_top = 6
	compass.offset_bottom = 34
	compass.clip_contents = true
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(compass)
	var back := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1a1009", 0.55)
	sb.border_color = Color("#8a6a3a")
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	back.add_theme_stylebox_override("panel", sb)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass.add_child(back)
	var tick := ColorRect.new()  # where you are looking
	tick.color = Color("#ffd24d")
	tick.size = Vector2(2, 8)
	tick.position = Vector2(COMPASS_W / 2.0 - 1, 20)
	compass.add_child(tick)
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	for i in 8:
		var l := Label.new()
		l.text = names[i]
		l.add_theme_font_size_override("font_size", 17 if i % 2 == 0 else 12)
		l.add_theme_color_override("font_color", Color("#f2e6c8") if i % 2 == 0 else Color("#c8b890"))
		l.size = Vector2(40, 28)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		compass.add_child(l)
		compass_items.append([l, i * PI / 4.0])
	apply_theme.call_deferred()  # (style.gd, which makes the book font, is built after this part)
	if W.status_label:  # (listening / thinking moves below the compass)
		W.status_label.offset_top = 40


func apply_theme() -> void:
	if compass and ctx.has("ui_theme"):
		compass.theme = ctx["ui_theme"]


func quest_targets() -> Array:
	var out := []
	var story = ctx.parts.get("story")
	if story and story.built():
		for q in story.open_quests():
			if q.has("pos"):
				out.append(story.quest_pos(q))
	return out


func update_compass() -> void:
	if not compass:
		return
	compass.visible = W.camera.current
	var f: Vector3 = -W.camera.global_basis.z
	var heading := atan2(f.x, -f.z)  # 0 = north (-z), clockwise
	for item in compass_items:
		place_on_compass(item[0], float(item[1]) - heading)
	var targets := quest_targets()
	while markers.size() < targets.size():
		var d := ColorRect.new()
		d.color = Color("#ffd24d")
		d.size = Vector2(9, 9)
		d.pivot_offset = Vector2(4.5, 4.5)
		d.rotation = PI / 4.0
		compass.add_child(d)
		markers.append(d)
	var me: Vector3 = W.camera.global_position
	for i in markers.size():
		markers[i].visible = i < targets.size()
		if i < targets.size():
			var to: Vector3 = targets[i] - me
			var x := place_on_compass(markers[i], atan2(to.x, -to.z) - heading, false)
			markers[i].position = Vector2(x - 4.5, 2)


## Put a compass item at its spot (half a turn either way fills the strip); returns its x centre.
func place_on_compass(c: Control, delta: float, centre_label := true) -> float:
	delta = wrapf(delta, -PI, PI)
	var x := COMPASS_W / 2.0 + delta / (PI / 2.0) * (COMPASS_W / 2.0)
	c.visible = absf(delta) < PI / 2.0 + 0.1
	if centre_label:
		c.position = Vector2(x - c.size.x / 2.0, 0)
	return x


func _process(_delta: float) -> void:
	update_compass()
	var cam: Vector3 = W.camera.global_position
	for p in plates:
		var l: Label3D = p[0]
		var target: Node3D = p[1]
		if not is_instance_valid(target):
			l.visible = false
			continue
		var at := target.global_position + Vector3(0, p[2], 0)
		l.global_position = at
		var d := cam.distance_to(at)
		l.visible = d < PLATE_RANGE and target.is_visible_in_tree()
		l.modulate.a = clampf((PLATE_RANGE - d) / 4.0, 0.0, 1.0)
	# which place are we in? announce it once on the way in
	var me := Vector2(cam.x, cam.z)
	var now := ""
	for place in PLACES:
		if me.distance_to(place[1]) < float(place[2]):
			now = place[0]
			break
	if now != here:
		here = now
		ctx["place_here"] = now
		if now != "":
			W.show_notice("~  %s  ~" % now, 3.5)


func seen_from(from: Vector3, _viewer: Node) -> Array:
	return ["the places of the valley are called: Thornvale (the village), Highmoor Castle, the Old Mill, the Barrow of the Old Kings, the Wolfwood; a signpost stands at the meadow crossroads"]
