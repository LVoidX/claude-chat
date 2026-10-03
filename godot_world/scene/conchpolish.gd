extends Node3D
## Quest "conch_polish": hold G for about 4 seconds to polish the conch shell. Works next to the conch on its rock
## (sea.gd), while you carry it, or next to Barnaby once he holds it. When it is done the shell gleams
## (a white shine on the rock conch), state["conch_polished"] = true and the quest is reported done.

const NEED := 4.0  # seconds of holding G
const REACH := 6.0
const QUEST_ID := "conch_polish"

var ctx: Dictionary
var W
var progress := 0.0
var last_quarter := 0
var gleam: MeshInstance3D
var spin := 0.0
var hinted := false
var warned := false  # the "too far" hint was shown for this key press


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	process_priority = 100  # after sea.gd, whose _process sets the conch light
	progress = NEED if polished() else 0.0
	last_quarter = 0
	gleam = null


func polished() -> bool:
	return ctx.state.get("conch_polished", false)


func can_polish() -> bool:
	var sea = ctx.parts.get("sea")
	if sea == null:
		return false
	var p: Vector3 = ctx.player.position
	match sea.conch_where():
		"rock":
			return Vector2(p.x - sea.CONCH_AT.x, p.z - sea.CONCH_AT.z).length() < REACH
		"carried":
			return true
		"given":
			var b = ctx.parts.get("barnaby")
			return b != null and b.body != null and Vector2(p.x - b.body.position.x, p.z - b.body.position.z).length() < REACH
	return false


func ensure_gleam() -> void:
	var sea = ctx.parts.get("sea")
	if sea == null or sea.conch == null:
		return
	var shell: Node3D = sea.conch.get_node_or_null("Shell")
	if shell == null:
		return
	if gleam and is_instance_valid(gleam) and gleam.get_parent() == shell:
		return
	gleam = MeshInstance3D.new()
	gleam.name = "Gleam"
	var s := SphereMesh.new()
	s.radius = 0.5
	s.height = 1.0
	gleam.mesh = s
	gleam.scale = Vector3(0.62, 0.52, 0.78)  # a shine hugging the shell, slightly bigger than it
	gleam.position = Vector3(0, 0.07, 0.04)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1, 1, 1, 0.0)
	gleam.material_override = m
	gleam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.add_child(gleam)


func _process(delta: float) -> void:
	if ctx.is_empty():
		return
	spin += delta
	ensure_gleam()
	if not polished() and not hinted and QUEST_ID in ctx.get("quest_ids", []) and can_polish():
		hinted = true
		W.show_notice("Hold G to polish the conch.", 5.0)
	if polished() and QUEST_ID in ctx.get("quest_ids", []):  # polished before the quest was (re)given: finish it now
		W.quest_done(QUEST_ID)
	if not polished():
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_key_pressed(KEY_G) and can_polish():
			progress += delta
			var q := int(progress / NEED * 4.0)
			if q > last_quarter and q < 4:
				last_quarter = q
				W.show_notice("Polishing... %d%%" % (q * 25), 1.5)
			if progress >= NEED:
				ctx.state["conch_polished"] = true
				W.show_notice("The conch gleams like new.", 4.0)
				W.quest_done(QUEST_ID)
		else:
			if Input.is_key_pressed(KEY_G) and QUEST_ID in ctx.get("quest_ids", []) and not can_polish() and not warned:
				warned = true
				W.show_notice("Too far: stand within %d m of the conch (or Barnaby, while he holds it) and hold G." % int(REACH), 3.0)
			if not Input.is_key_pressed(KEY_G):
				warned = false
			progress = maxf(progress - delta * 0.25, 0.0)
			last_quarter = int(progress / NEED * 4.0)
	var sea = ctx.parts.get("sea")
	if gleam and is_instance_valid(gleam):
		var a := clampf(progress / NEED, 0.0, 1.0) * 0.22
		if polished():
			a = 0.16 + sin(spin * 2.0) * 0.06
		(gleam.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, a)
	if sea and sea.conch and sea.conch.visible and sea.light and is_instance_valid(sea.light) and polished():
		sea.light.light_energy += 1.5  # brighter than the ordinary hum


func seen_from(_from: Vector3, _viewer: Node) -> Array:
	if polished():
		return ["the conch shell is polished and gleams brightly now"]
	if QUEST_ID in ctx.get("quest_ids", []):
		return ["the conch can be polished: the wanderer holds G next to it for a few seconds (%d%% done)" % int(progress / NEED * 100.0)]
	return []
