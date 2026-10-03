extends Node3D
## The sea. Somewhere out in the field a glowing conch shell hums (a pale beam of light shows where). Walk up to it
## and press E to blow it: the sea slowly rises over the whole field, knee-deep, with waves and the red moon on it.
## Blow it again and the sea drains away. state["sea"] is true while the sea is up. Barnaby is told about it.

const CONCH_AT := Vector3(-16, 0, -22)
const REACH := 6.0
const LOW := -0.7  # water level when the sea is away (hidden under the ground)
const HIGH := 0.45  # water level when the sea is up
const RISE_SPEED := 0.09  # m/s: the sea takes about 13 s to rise

const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always;
uniform vec3 shallow_color : source_color = vec3(0.06, 0.28, 0.32);
uniform vec3 deep_color : source_color = vec3(0.02, 0.06, 0.12);
varying vec3 wpos;
float height(vec2 p, float t) {
	return sin(p.x * 0.55 + t * 1.3) * 0.06 + sin(p.y * 0.42 + t * 1.0) * 0.06 + sin((p.x + p.y) * 1.2 + t * 2.1) * 0.02;
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += height(wpos.xz, TIME);
}
void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;
	float gx = cos(p.x * 0.55 + t * 1.3) * 0.033 + cos((p.x + p.y) * 1.2 + t * 2.1) * 0.024 + cos(p.x * 3.1 - t * 1.7) * 0.02;
	float gz = cos(p.y * 0.42 + t * 1.0) * 0.025 + cos((p.x + p.y) * 1.2 + t * 2.1) * 0.024 + cos(p.y * 2.7 + t * 1.5) * 0.02;
	vec3 n = normalize(vec3(-gx, 1.0, -gz));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(shallow_color, deep_color, 0.35 + fres * 0.5);
	ROUGHNESS = 0.06;
	SPECULAR = 0.9;
	ALPHA = mix(0.62, 0.92, fres);
}
"""

var ctx: Dictionary
var W
var water: MeshInstance3D
var conch: Node3D
var light: OmniLight3D
var level := LOW
var hinted := false
var spin := 0.0
var held: Node3D  # the conch in your hands (on the camera) while you carry it
var armed := false  # the carried conch may be handed to Barnaby (not right after he gave it to you)


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	level = HIGH if risen() else LOW
	build_water()
	build_conch()
	conch.visible = conch_where() == "rock"
	build_held()
	apply_level()


func build_held() -> void:
	for old in W.camera.get_children():
		if old.name == "HeldConch":
			old.free()
	held = Node3D.new()
	held.name = "HeldConch"
	held.position = Vector3(0.22, -0.3, -0.55)
	held.rotation_degrees = Vector3(-10, 25, 0)
	held.visible = false
	var shell := Color("#f3dcc2")
	var s := 0.55  # the shell, scaled down for the hand
	W.box(held, Vector3(0, 0, 0), Vector3(0.36, 0.3, 0.5) * s, shell, "sphere")
	W.box(held, Vector3(0, 0.05, -0.28) * s, Vector3(0.22, 0.2, 0.26) * s, Color("#f0b9a0"), "sphere")
	W.box(held, Vector3(0, 0.17, 0.2) * s, Vector3(0.26, 0.22, 0.26) * s, shell.darkened(0.06), "sphere")
	W.box(held, Vector3(0, 0.27, 0.3) * s, Vector3(0.17, 0.16, 0.17) * s, shell.darkened(0.1), "sphere")
	W.box(held, Vector3(0, 0.34, 0.36) * s, Vector3(0.1, 0.1, 0.1) * s, shell.darkened(0.14), "sphere")
	var glow := OmniLight3D.new()
	glow.light_color = Color("#8ff0ff")
	glow.light_energy = 1.2
	glow.omni_range = 4.0
	held.add_child(glow)
	W.camera.add_child(held)


func _exit_tree() -> void:
	if held and is_instance_valid(held):
		held.queue_free()


## Where the conch is: "rock" (where it hums), "carried" (the wanderer picked it up, F) or "given" (Barnaby holds it).
func conch_where() -> String:
	return ctx.state.get("conch", "rock")


func risen() -> bool:
	return ctx.state.get("sea", false)


func build_water() -> void:
	water = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	plane.subdivide_width = 300
	plane.subdivide_depth = 300
	water.mesh = plane
	var shader := Shader.new()
	shader.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	water.material_override = m
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func build_conch() -> void:
	conch = Node3D.new()
	conch.position = CONCH_AT
	add_child(conch)
	var shell := Color("#f3dcc2")
	W.box(conch, Vector3(0, 0.15, 0), Vector3(0.9, 0.3, 0.9), Color("#4a4a52"), "sphere", true)  # a rock to sit on
	var body: Node3D = Node3D.new()
	body.name = "Shell"
	body.position = Vector3(0, 0.62, 0)
	conch.add_child(body)
	W.box(body, Vector3(0, 0, 0), Vector3(0.36, 0.3, 0.5), shell, "sphere")
	W.box(body, Vector3(0, 0.05, -0.28), Vector3(0.22, 0.2, 0.26), Color("#f0b9a0"), "sphere")  # the pink mouth
	W.box(body, Vector3(0, 0.17, 0.2), Vector3(0.26, 0.22, 0.26), shell.darkened(0.06), "sphere")
	W.box(body, Vector3(0, 0.27, 0.3), Vector3(0.17, 0.16, 0.17), shell.darkened(0.1), "sphere")
	W.box(body, Vector3(0, 0.34, 0.36), Vector3(0.1, 0.1, 0.1), shell.darkened(0.14), "sphere")
	light = OmniLight3D.new()
	light.light_color = Color("#8ff0ff")
	light.light_energy = 2.5
	light.omni_range = 9.0
	light.position = Vector3(0, 0.9, 0)
	conch.add_child(light)
	var beam := MeshInstance3D.new()  # a pale column of light, so you can find the shell from afar
	beam.mesh = CylinderMesh.new()
	(beam.mesh as CylinderMesh).top_radius = 0.12
	(beam.mesh as CylinderMesh).bottom_radius = 0.35
	(beam.mesh as CylinderMesh).height = 40.0
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(0.55, 0.95, 1.0, 0.16)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = bm
	beam.position = Vector3(0, 20, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	conch.add_child(beam)


func apply_level() -> void:
	water.position.y = level
	water.visible = level > LOW + 0.02


func near_conch() -> bool:
	var p: Vector3 = ctx.player.position
	return Vector2(p.x - CONCH_AT.x, p.z - CONCH_AT.z).length() < REACH


func key(event: InputEventKey) -> void:
	var where := conch_where()
	if event.keycode == KEY_F and where == "rock" and near_conch():
		ctx.state["conch"] = "carried"
		conch.visible = false
		W.show_notice("You pick up the glowing conch. Bring it to Barnaby.", 5.0)
		return
	if event.keycode == KEY_E and where == "rock" and not near_conch() and near_conch_soon():
		W.show_notice("Get closer to the conch to blow it.", 2.5)
	if event.keycode == KEY_E and (where == "carried" or (where == "rock" and near_conch())):
		print("[sea] conch blown, sea was up: ", risen())
		ctx.state["sea"] = not risen()
		if risen():
			W.show_notice("You blow the conch. A deep note rolls over the field... and the sea begins to rise.", 5.0)
		else:
			W.show_notice("You blow the conch. The sea sighs and slips away.", 4.0)


func handle(c: Dictionary) -> bool:
	if c.get("cmd", "") == "conch":  # [conch]: the conch goes into the wanderer's hands (E blows it, G polishes it)
		ctx.state["conch"] = "carried"
		armed = false
		conch.visible = false
		W.show_notice("Barnaby gives you the glowing conch. E blows it, G polishes it.", 5.0)
		return true
	if c.get("cmd", "") != "sea":
		return false
	var away: bool = "away" in c.get("args", []) or "off" in c.get("args", [])
	ctx.state["sea"] = not away
	W.show_notice("The sea slips away." if away else "The sea begins to rise...", 4.0)
	return true


func seen_from(from: Vector3, viewer: Node) -> Array:
	var seen := []
	var to_barnaby: bool = "npc_id" in viewer and viewer.npc_id == "barnaby"  # the conch and the sea are his story
	match conch_where():
		"carried":
			seen.append("the wanderer is carrying the glowing conch shell (the \"Kong\" you asked for); they just need to bring it to you"
				if to_barnaby else "the wanderer is carrying a glowing conch shell for Barnaby")
		"given":
			seen.append("you are holding the glowing conch the wanderer fetched for you" if to_barnaby
				else "Barnaby is holding a glowing conch shell the wanderer brought him")
	if risen():
		seen.append("THE SEA HAS COME: the wanderer blew the glowing conch and dark water now covers the whole field, knee-deep, "
			+ "with waves under the red moon" + (" (this is what you have been looking for all your life)" if to_barnaby
			else " (the sea Barnaby has been looking for)"))
	elif conch_where() == "rock":
		seen.append("a glowing conch shell on a rock %s hums softly; blowing it (E) is said to call the sea, and F picks it up" % W.where(from, CONCH_AT))
	return seen


func _process(delta: float) -> void:
	if not water:
		return
	if held and is_instance_valid(held):
		held.visible = conch_where() == "carried"
	if held and is_instance_valid(held) and held.visible:
		held.rotation.y = sin(spin * 1.2) * 0.15
		held.position.y = -0.3 + sin(spin * 1.6) * 0.008
	if conch_where() == "given" and "kong" in ctx.get("quest_ids", []):  # Barnaby already holds the conch
		W.quest_done("kong")
	if conch_where() == "given" and "conch_polish" in ctx.get("quest_ids", []):  # he has the conch: polishing is done
		ctx.state["conch_polished"] = true
		W.quest_done("conch_polish")
	if conch_where() == "carried":  # hand it over once the wanderer stands next to Barnaby
		var barnaby = ctx.parts.get("barnaby")
		if barnaby and barnaby.body:
			var d: Vector3 = ctx.player.position - barnaby.body.position
			var dist := Vector2(d.x, d.z).length()
			if dist > 6.0:
				armed = true  # only once you have walked away from him (he may just have given it to you)
			elif dist < 3.5 and armed:
				ctx.state["conch"] = "given"
				armed = false
				W.quest_done("conch")
				W.quest_done("kong")  # "the Kong" is how the conch got heard
				if "conch_polish" in ctx.get("quest_ids", []):  # handing it back counts as polishing it
					ctx.state["conch_polished"] = true
					W.quest_done("conch_polish")
				W.show_notice("You hand Barnaby the glowing conch.", 4.0)
	var goal := HIGH if risen() else LOW
	if absf(level - goal) > 0.001:
		level = move_toward(level, goal, RISE_SPEED * delta)
		apply_level()
	spin += delta
	if not conch.visible:
		return
	var shell := conch.get_node_or_null("Shell")
	if shell:
		shell.position.y = 0.62 + sin(spin * 1.6) * 0.04  # the shell bobs gently
		shell.rotation.y = spin * 0.5
	light.light_energy = 2.2 + sin(spin * 2.3) * 0.5
	if not hinted and near_conch_soon():
		hinted = true
		W.show_notice("A conch shell hums on the rock. E blows it, F picks it up.", 5.0)


func near_conch_soon() -> bool:
	var p: Vector3 = ctx.player.position
	return Vector2(p.x - CONCH_AT.x, p.z - CONCH_AT.z).length() < 9.0
