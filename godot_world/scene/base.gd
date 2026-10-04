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

const SHOW_PLACED := false  # objects placed on request (spawn) are hidden for now; they stay saved

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
uniform vec3 moon_dir = vec3(-0.38, 0.64, 0.66);  // where the red moon hangs (the night light comes from there)
const float MOON_SIZE = 0.075;  // its radius, in radians (about 4.3 degrees)

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));  // each octave turned, so the noise grid doesn't show
	for (int i = 0; i < 5; i++) { v += a * vnoise(p); p = turn * p * 2.03 + 17.0; a *= 0.5; }
	return v;
}
// The red moon, drawn here (not in the picture) so it is round and sharp at any size: dark seas, craters,
// a darker rim, and a soft red halo around it.
vec3 moon(vec3 d) {
	vec3 m = normalize(moon_dir);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), m));
	vec3 up = cross(m, right);
	float facing = dot(d, m);
	vec2 p = vec2(dot(d, right), dot(d, up)) / MOON_SIZE;  // -1..1 across the disc
	float r = length(p);
	float halo = exp(-max(acos(clamp(facing, -1.0, 1.0)) - MOON_SIZE, 0.0) * 9.0) * 0.35
		+ exp(-max(acos(clamp(facing, -1.0, 1.0)) - MOON_SIZE, 0.0) * 40.0) * 0.5;
	vec3 glow_col = vec3(0.7, 0.12, 0.08) * halo * step(0.0, facing);
	if (r >= 1.0 || facing < 0.0) return glow_col;
	float z = sqrt(1.0 - r * r);  // a sphere: the light falls off toward the rim
	vec2 q = p / (1.0 + z) * 2.0;  // surface coordinates that wrap round the ball instead of stretching
	float seas = smoothstep(0.45, 0.7, fbm(q * 2.2 + 3.0));
	float detail = fbm(q * 9.0);
	float craters = 0.0;
	for (int i = 0; i < 9; i++) {
		vec2 c = vec2(hash(vec2(float(i), 1.3)), hash(vec2(float(i), 7.9))) * 1.6 - 0.8;
		float cr = 0.06 + 0.12 * hash(vec2(float(i), 4.2));
		float dd = length(q - c) / cr;
		craters += smoothstep(1.0, 0.75, dd) * 0.35 - smoothstep(1.15, 1.0, dd) * smoothstep(0.9, 1.0, dd) * 0.25;
	}
	vec3 base = mix(vec3(1.0, 0.27, 0.15), vec3(0.55, 0.07, 0.05), seas);
	base *= 0.8 + 0.35 * detail;
	base *= 1.0 - craters;
	base *= pow(z, 0.35);  // limb darkening
	float edge = smoothstep(1.0, 0.985, r);  // a crisp but not jagged edge
	return mix(glow_col, base * 0.62, edge);  // kept under the bloom threshold so it stays red
}

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
	vec3 c = mix(night + moon(d), day_sky, day) + sun * day;
	COLOR = mix(c, tint.rgb, tint.a);
}
"""

var ctx: Dictionary
var W  # world.gd
var env: Environment
var sky_material: ShaderMaterial
var light: DirectionalLight3D  # the sun by day, the moon by night
var placed_nodes := {}  # index in state.placed -> node
var sky_from := 0.0
var sky_to := 0.0
var sky_transition := 0.0
var sky_transition_time := 0.0


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	build_environment()  # (the ground itself is scene/terrain.gd)
	if not ctx.state.has("time") or not ctx.state.get("night_set", false):
		ctx.state["time"] = 0.0  # it starts in the middle of the red-moon night
		ctx.state["night_set"] = true  # (one-time: the user asked for night; later changes stick)
	apply_time(0.0)
	for spec in ctx.state.get("placed", []):  # things placed on request survive reloads
		if SHOW_PLACED or spec.get("shape", "") == "tree":
			make_placed(spec)


const MOON_ANGLES := Vector3(-40, -30, 0)  # the night light's direction; the sky draws the moon where it comes from


func build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	var shader := Shader.new()
	shader.code = SKY_SHADER
	sky_material = ShaderMaterial.new()
	sky_material.shader = shader
	sky_material.set_shader_parameter("night_tex", W.tex("sky_night.png"))  # dark sky with stars, red horizon
	env.sky.sky_material = sky_material
	sky_material.set_shader_parameter("moon_dir", Basis.from_euler(MOON_ANGLES * PI / 180.0).z)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR  # an even fill light, so colours still read
	env.tonemap_mode = Environment.TONE_MAPPER_ACES  # richer colour than filmic, which washed everything pastel
	env.tonemap_exposure = 0.72
	env.adjustment_enabled = true  # a touch of grading: livelier colour, a bit more contrast
	env.adjustment_saturation = 1.25
	env.adjustment_contrast = 1.07
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
		light.rotation_degrees = MOON_ANGLES
	light.light_color = Color("#ffc7b8").lerp(Color("#fff1dc"), day).lerp(Color("#ffb070"), clampf(glow, 0.0, 1.0) * day)
	light.light_energy = lerpf(1.0, 1.55, day)  # a strong sun and a weaker fill: real shadows, shapes read
	env.ambient_light_color = Color("#6f78a0").lerp(Color("#a8b6cc"), day).lerp(Color("#c09080"), clampf(glow, 0.0, 1.0) * day * 0.5)
	env.ambient_light_energy = lerpf(0.5, 0.3, day)
	env.fog_light_color = Color("#1e1a2c").lerp(Color("#7f93ab"), day).lerp(Color("#c27a55"), clampf(glow, 0.0, 1.0) * 0.6)
	env.fog_density = lerpf(0.005, 0.0013, day)


## A time of day by name ("day", "sunset", "night", ...), or a plain colour for the whole sky.
func set_sky(name: String) -> void:
	if name in SKY_PRESETS:
		sky_from = hour()
		sky_to = float(SKY_PRESETS[name])
		sky_transition = 3.0
		sky_transition_time = 0.0
		ctx.state.erase("sky_tint")
	elif Color.html_is_valid(name) or Color.from_string(name, Color(0, 0, 0, 0)).a > 0.0:
		ctx.state["sky_tint"] = name
	apply_time(0.0)
	var tint := Color.from_string(str(ctx.state.get("sky_tint", "")), Color(0, 0, 0, 0))
	sky_material.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, 0.85 if tint.a > 0.0 else 0.0))


func _process(delta: float) -> void:
	if sky_material:
		if sky_transition > 0.0:
			sky_transition_time = minf(sky_transition_time + delta, sky_transition)
			var a := sky_from * TAU / 24.0
			var b := sky_to * TAU / 24.0
			var hour_angle := lerp_angle(a, b, smoothstep(0.0, 1.0, sky_transition_time / sky_transition))
			ctx.state["time"] = fposmod(hour_angle * 24.0 / TAU, 24.0)
			apply_time(0.0)
			if sky_transition_time >= sky_transition:
				sky_transition = 0.0
		else:
			apply_time(delta)


## A simple solid box, sphere or pillar placed on request.
func make_placed(spec: Dictionary) -> void:
	var color := Color.from_string(spec.get("color", "white"), Color.WHITE)
	var shape: String = spec.get("shape", "box")
	var node := Node3D.new()
	node.position = Vector3(spec.x, W.ground_y(spec.x, spec.z), spec.z)
	add_child(node)
	if shape == "tree":  # a trunk with a few overlapping leaf blobs, like the oaks in the woods
		var leaf := Color("#3e6b2e")
		W.box(node, Vector3(0, 1.3, 0), Vector3(0.5, 2.6, 0.5), Color("#53392a"), "cube", true)
		W.box(node, Vector3(0, 3.4, 0), Vector3(3.6, 3.2, 3.6), leaf, "sphere")
		W.box(node, Vector3(0.9, 3.0, 0.3), Vector3(2.5, 2.2, 2.5), leaf.darkened(0.12), "sphere")
		W.box(node, Vector3(-0.8, 3.1, -0.4), Vector3(2.6, 2.3, 2.6), leaf.lightened(0.08), "sphere")
		W.box(node, Vector3(0.1, 4.3, -0.2), Vector3(2.4, 2.0, 2.4), leaf.darkened(0.05), "sphere")
	elif shape in ["sphere", "ball"]:
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
	for spec in (ctx.state.get("placed", []) if SHOW_PLACED else []):
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
			if SHOW_PLACED or spec.shape == "tree":
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
