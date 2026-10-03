extends Node3D
## The sky, the light and the time of day, plus simple objects placed on request (spawn / remove / sky).
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

## Time of day: state["time"] is the hour (0..24). A whole day takes DAY_MINUTES real minutes. Night (the red
## moon) is 20:00 to 5:00, day 7:00 to 18:00, with sunrise and sunset glowing in between. ctx["night"] is 1 at
## night and 0 by day, for other parts (lanterns, windows, fireflies dim by day).
const DAY_MINUTES := 40.0
const SKY_PRESETS := {"night": 0.0, "midnight": 0.0, "dawn": 6.0, "sunrise": 6.3, "morning": 9.0, "day": 12.0,
	"noon": 12.0, "afternoon": 15.5, "evening": 18.5, "sunset": 18.8, "dusk": 19.3}

const SKY_SHADER := """
shader_type sky;
uniform sampler2D night_tex : source_color, filter_linear, repeat_enable;
uniform float day = 0.0;  // 0 = night sky (the panorama), 1 = day sky
uniform float glow = 0.0;  // sunrise / sunset colours near the horizon
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);  // a plain colour asked for with the sky command (alpha = how much)
void sky() {
	vec3 d = EYEDIR;
	vec2 uv = vec2(atan(d.x, -d.z) / (2.0 * PI) + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
	vec3 night = texture(night_tex, uv).rgb;
	float h = clamp(d.y, 0.0, 1.0);
	vec3 day_sky = mix(vec3(0.72, 0.82, 0.92), vec3(0.24, 0.46, 0.82), pow(h, 0.55));
	float toward_sun = max(dot(normalize(vec2(d.x, d.z) + 0.0001), normalize(vec2(sun_dir.x, sun_dir.z) + 0.0001)), 0.0);
	vec3 warm = mix(vec3(0.95, 0.45, 0.25), vec3(1.0, 0.75, 0.4), h);
	day_sky = mix(day_sky, warm, glow * pow(1.0 - h, 1.6) * (0.35 + 0.65 * toward_sun));
	day_sky = mix(day_sky, day_sky * vec3(0.75, 0.6, 0.8), glow * h);  // the sky overhead dims to violet at dusk
	float s = max(dot(d, normalize(sun_dir)), 0.0);
	vec3 sun = vec3(1.0, 0.9, 0.7) * (pow(s, 900.0) * 30.0 + pow(s, 30.0) * 0.6) * step(-0.05, sun_dir.y);
	vec3 c = mix(night, day_sky, day) + sun * day;
	COLOR = mix(c, tint.rgb, tint.a);
}
"""

var ctx: Dictionary
var W  # world.gd
var env: Environment
var sky_material: ShaderMaterial
var light: DirectionalLight3D  # the sun by day, the moon by night
var placed_nodes := {}  # index in state.placed -> node


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	build_environment()  # (the ground itself is scene/terrain.gd)
	if not ctx.state.has("time"):
		ctx.state["time"] = 0.0  # it starts in the middle of the red-moon night
	apply_time(0.0)
	for spec in ctx.state.get("placed", []):  # things placed on request survive reloads
		make_placed(spec)


func build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	var shader := Shader.new()
	shader.code = SKY_SHADER
	sky_material = ShaderMaterial.new()
	sky_material.shader = shader
	sky_material.set_shader_parameter("night_tex", W.tex("sky_night.png"))  # dark sky, red horizon, red moon
	env.sky.sky_material = sky_material
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR  # an even fill light, so colours still read
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true  # lanterns, windows and fireflies bloom softly
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.ssao_enabled = true  # soft shadows in corners: walls on the ground, roofs on walls
	env.ssao_intensity = 1.6
	env.fog_enabled = true  # a haze that swallows the far hills
	env.fog_density = 0.005
	env.fog_sky_affect = 0.1
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	light = DirectionalLight3D.new()
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 140.0
	add_child(light)


func hour() -> float:
	return float(ctx.state.get("time", 0.0))


## Advance the clock by `delta` seconds and set the sky, the light, the fog and ctx["night"] to match.
func apply_time(delta: float) -> void:
	var t := fposmod(hour() + delta * 24.0 / (DAY_MINUTES * 60.0), 24.0)
	ctx.state["time"] = t
	var day := smoothstep(5.0, 7.0, t) * (1.0 - smoothstep(18.0, 20.0, t))  # 0 night .. 1 day
	var glow := maxf(1.0 - absf(t - 6.3) / 1.4, 0.0) + maxf(1.0 - absf(t - 18.8) / 1.4, 0.0)  # sunrise, sunset
	ctx["night"] = 1.0 - day
	# the sun rises in the east (+x), is high in the south at noon, and sets in the west
	var a := (t - 6.0) / 12.0 * PI
	var sun := Vector3(cos(a), sin(a) * 0.85, sin(a) * 0.5).normalized()
	sky_material.set_shader_parameter("day", day)
	sky_material.set_shader_parameter("glow", clampf(glow, 0.0, 1.0))
	sky_material.set_shader_parameter("sun_dir", sun)
	if day > 0.5 and sun.y > 0.05:  # by day the light follows the sun
		light.look_at_from_position(Vector3.ZERO, -sun, Vector3.UP if absf(sun.y) < 0.99 else Vector3.FORWARD)
	else:  # by night it comes from the red moon, high in the south-west
		light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_color = Color("#ffc7b8").lerp(Color("#fff1dc"), day).lerp(Color("#ffb070"), clampf(glow, 0.0, 1.0) * day)
	light.light_energy = lerpf(1.0, 1.5, day)
	env.ambient_light_color = Color("#6f78a0").lerp(Color("#a8b6cc"), day).lerp(Color("#c09080"), clampf(glow, 0.0, 1.0) * day * 0.5)
	env.ambient_light_energy = lerpf(0.5, 0.6, day)
	env.fog_light_color = Color("#1e1a2c").lerp(Color("#7f93ab"), day).lerp(Color("#c27a55"), clampf(glow, 0.0, 1.0) * 0.6)
	env.fog_density = lerpf(0.005, 0.0022, day)


## A time of day by name ("day", "sunset", "night", ...), or a plain colour for the whole sky.
func set_sky(name: String) -> void:
	if name in SKY_PRESETS:
		ctx.state["time"] = SKY_PRESETS[name]
		ctx.state.erase("sky_tint")
	elif Color.html_is_valid(name) or Color.from_string(name, Color(0, 0, 0, 0)).a > 0.0:
		ctx.state["sky_tint"] = name
	apply_time(0.0)
	var tint := Color.from_string(str(ctx.state.get("sky_tint", "")), Color(0, 0, 0, 0))
	sky_material.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, 0.85 if tint.a > 0.0 else 0.0))


func _process(delta: float) -> void:
	if sky_material:
		apply_time(delta)


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


## The time of day, in words.
func time_words() -> String:
	var t := hour()
	if t < 4.5 or t >= 20.5:
		return "it is night, and the red moon hangs in the dark sky"
	if t < 7.0:
		return "dawn is breaking over the hills"
	if t < 11.0:
		return "it is morning, the sun is climbing"
	if t < 15.0:
		return "it is the middle of the day, under a clear blue sky"
	if t < 18.0:
		return "it is afternoon"
	return "the sun is setting, and dusk is falling over the valley"


func seen_from(from: Vector3, _viewer: Node) -> Array:
	var seen := [time_words()]
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
