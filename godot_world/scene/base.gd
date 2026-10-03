extends Node3D
## The ground, the sky and the light, plus simple objects placed on request (spawn / remove / sky commands).
##
## Every file in scene/ is one part of the world. world.gd rebuilds all parts live when any of them is saved.
## A part can have: build(ctx) (called once per (re)build), handle(c) -> bool (a chat command; return true
## if this part dealt with it), key(event), seen_from(from, viewer) -> Array (what the characters notice of
## this part: short phrases with W.where()), quest_progress(id) -> " (2/3)", describe() + is_near() + npc_id
## (for characters), and the usual _process(delta). ctx["world"] is world.gd with helpers: box(), glow(),
## light(), build_model(), mat(), tex(), where(), face(), seen_around(), send(), quest_done(), show_notice().
## ctx["state"] survives reloads and restarts (saved to world_state.json):
## keep only plain values in it (numbers, strings, arrays, dictionaries). ctx["parts"]["<file name>"] is
## another part. North is -z.

# Settings world.gd reads live
const WALK_SPEED := 5.0
const RUN_SPEED := 10.0
const JUMP_SPEED := 6.6  # about 1.2 m high
const LOOK_SENSITIVITY := 0.08  # degrees per pixel of mouse movement

const SKY_PRESETS := {"sunset": "#ff7a50", "dawn": "#f2b8a2", "day": "#87b5e8"}

var ctx: Dictionary
var W  # world.gd
var env: Environment
var sky_material: PanoramaSkyMaterial
var placed_nodes := {}  # index in state.placed -> node


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	build_environment()  # (the ground itself is scene/terrain.gd)
	set_sky(ctx.state.get("sky", "night"))
	for spec in ctx.state.get("placed", []):  # things placed on request survive reloads
		make_placed(spec)


func build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	sky_material = PanoramaSkyMaterial.new()
	env.sky.sky_material = sky_material
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR  # a cool moonlit fill, so colours still read
	env.ambient_light_color = Color("#6f78a0")
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true  # lanterns, windows and fireflies bloom softly
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.ssao_enabled = true  # soft shadows in corners: walls on the ground, roofs on walls
	env.ssao_intensity = 1.6
	env.fog_enabled = true  # a night haze that swallows the far hills
	env.fog_light_color = Color("#1e1a2c")
	env.fog_density = 0.005
	env.fog_sky_affect = 0.1
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var moon := DirectionalLight3D.new()  # red-tinted moonlight, with shadows
	moon.light_color = Color("#ffc7b8")
	moon.light_energy = 1.0
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 140.0
	moon.rotation_degrees = Vector3(-40, -30, 0)
	add_child(moon)


func set_sky(name: String) -> void:
	ctx.state["sky"] = name
	if name == "night" or not (name in SKY_PRESETS or name.begins_with("#")):
		sky_material.panorama = W.tex("sky_night.png")  # dark sky, red horizon, red moon
		env.background_mode = Environment.BG_SKY
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color.from_string(SKY_PRESETS.get(name, name), Color("#0b1026"))


## A simple solid box, sphere or pillar placed on request.
func make_placed(spec: Dictionary) -> void:
	var color := Color.from_string(spec.get("color", "white"), Color.WHITE)
	var shape: String = spec.get("shape", "box")
	var node := Node3D.new()
	node.position = Vector3(spec.x, W.ground_y(spec.x, spec.z), spec.z)
	add_child(node)
	if shape in ["sphere", "ball"]:
		W.box(node, Vector3(0, 0.6, 0), Vector3.ONE * 1.2, color, "sphere", true)
	elif shape == "pillar":
		W.box(node, Vector3(0, 2, 0), Vector3(1, 4, 1), color, "cube", true)
	else:
		W.box(node, Vector3(0, 0.5, 0), Vector3.ONE, color, "cube", true)
	placed_nodes[spec] = node


func seen_from(from: Vector3, _viewer: Node) -> Array:
	var seen := []
	for spec in ctx.state.get("placed", []):
		seen.append("a %s %s the wanderer made, %s" % [spec.get("color", ""), spec.get("shape", "box"),
			W.where(from, Vector3(spec.x, 0, spec.z))])
	return seen


func handle(c: Dictionary) -> bool:
	match c.get("cmd", ""):
		"sky":
			set_sky(str(c.get("color", "night")).to_lower())
		"spawn":  # 3 m in front of the player
			var p: CharacterBody3D = ctx.player
			var spot: Vector3 = p.position - p.transform.basis.z * 3
			var spec := {"shape": c.get("shape", "box"), "color": c.get("color", "white"), "x": spot.x, "z": spot.z}
			ctx.state.get_or_add("placed", []).append(spec)
			make_placed(spec)
		"remove":  # the placed object nearest the player
			var placed: Array = ctx.state.get("placed", [])
			if placed.is_empty():
				return true
			var p: Vector3 = ctx.player.position
			var nearest = placed[0]
			for spec in placed:
				if Vector2(spec.x - p.x, spec.z - p.z).length() < Vector2(nearest.x - p.x, nearest.z - p.z).length():
					nearest = spec
			placed.erase(nearest)
			if placed_nodes.has(nearest):
				placed_nodes[nearest].queue_free()
				placed_nodes.erase(nearest)
		_:
			return false
	return true
