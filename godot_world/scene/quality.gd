extends Node3D
## Graphics quality: four presets (Ultra / High / Medium / Low), picked for the PC the first time it runs (a
## discrete graphics card gets High, an integrated one Medium), lowered automatically if the game runs slowly, and
## changed by hand with F8. The choice is saved in state["quality"] = {"level": 0..3, "locked": bool}.
## Each preset sets: 3D anti-aliasing, SSAO, glow, volumetric light shafts, the sun's shadow splits and range, the grass density (the grass
## MultiMesh draws only a share of its blades) and the 3D render scale. base.gd / terrain.gd rebuild their environment
## and grass when saved, so part_reloaded() puts the current preset back.

const NAMES := ["Ultra", "High", "Medium", "Low"]
const PRESETS := [
	{"msaa": Viewport.MSAA_4X, "fxaa": false, "ssao": true, "glow": true, "vol": true, "splits": 4, "shadow_m": 140.0, "grass": 1.0, "scale": 1.0},
	{"msaa": Viewport.MSAA_2X, "fxaa": false, "ssao": true, "glow": true, "vol": true, "splits": 2, "shadow_m": 110.0, "grass": 1.0, "scale": 1.0},
	{"msaa": Viewport.MSAA_DISABLED, "fxaa": true, "ssao": false, "glow": true, "vol": false, "splits": 2, "shadow_m": 70.0, "grass": 0.55, "scale": 1.0},
	{"msaa": Viewport.MSAA_DISABLED, "fxaa": true, "ssao": false, "glow": false, "vol": false, "splits": 1, "shadow_m": 40.0, "grass": 0.25, "scale": 0.77},
]
const SLOW_FPS := 38.0  # below this for SLOW_SECONDS in a row, drop one level
const SLOW_SECONDS := 5

var ctx: Dictionary
var W
var slow_for := 0
var next_check := 0.0
var warmup := 6.0  # seconds after a (re)build before judging speed: loading is slow, play is not


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	var q: Dictionary = ctx.state.get_or_add("quality", {})
	if not q.has("level"):
		q["level"] = detect_level()
		q["locked"] = false
	apply()


## The first guess: discrete card -> Ultra (it is lowered by itself if the game runs slowly), integrated -> Medium,
## software rendering -> Low.
func detect_level() -> int:
	var kind := RenderingServer.get_video_adapter_type()
	var name := RenderingServer.get_video_adapter_name().to_lower()
	if kind == RenderingDevice.DEVICE_TYPE_CPU or name.contains("llvmpipe") or name.contains("software"):
		return 3
	if kind == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU or name.contains("uhd") or name.contains("iris") \
			or name.contains("vega") and not name.contains("rx"):
		return 2
	return 0


func level() -> int:
	return clampi(int(ctx.state.get("quality", {}).get("level", 1)), 0, 3)


func apply() -> void:
	var p: Dictionary = PRESETS[level()]
	var vp := get_viewport()
	vp.msaa_3d = p.msaa
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if p.fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_scale = p.scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if p.scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	var base = ctx.parts.get("base")
	if base and base.env and base.light:
		base.env.ssao_enabled = p.ssao
		base.env.glow_enabled = p.glow
		base.env.volumetric_fog_enabled = p.vol  # light shafts (the costliest effect after shadows)
		base.light.directional_shadow_mode = {1: DirectionalLight3D.SHADOW_ORTHOGONAL, 2: DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
			4: DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS}[p.splits]
		base.light.directional_shadow_max_distance = p.shadow_m
	var terrain = ctx.parts.get("terrain")
	if terrain:
		for ch in terrain.get_children():
			if ch is MultiMeshInstance3D and ch.multimesh.instance_count > 20000:  # the grass
				ch.multimesh.visible_instance_count = int(ch.multimesh.instance_count * float(p.grass))


## base.gd or terrain.gd was swapped: put the preset back on what they just built.
func part_reloaded(name: String) -> void:
	if name in ["base", "terrain"]:
		apply.call_deferred()


func key(event: InputEventKey) -> void:
	if event.keycode == KEY_F8:
		var q: Dictionary = ctx.state["quality"]
		q["level"] = (level() + 1) % PRESETS.size()
		q["locked"] = true  # the player chose: no more automatic changes
		apply()
		W.show_notice("Graphics: %s   (F8 changes it)" % NAMES[level()], 3.5)


func _process(delta: float) -> void:
	warmup -= delta
	next_check -= delta
	if warmup > 0.0 or next_check > 0.0 or not W.camera.current:
		return
	next_check = 1.0
	var q: Dictionary = ctx.state["quality"]
	if q.get("locked", false):
		return
	if Engine.get_frames_per_second() < SLOW_FPS:
		slow_for += 1
	else:
		slow_for = 0
	if slow_for >= SLOW_SECONDS and level() < PRESETS.size() - 1:
		slow_for = 0
		q["level"] = level() + 1
		apply()
		W.show_notice("Running slowly: graphics lowered to %s (F8 changes it)" % NAMES[level()], 5.0)


func seen_from(_from: Vector3, _viewer: Node) -> Array:
	return []
