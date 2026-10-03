extends Node3D
## Weather: now and then a rain shower rolls in. The sky greys, the light dims, the far hills fade into mist and
## rain falls round you with a soft hiss; after a few minutes it clears. state["rain"] = 0..1 (how wet it is now),
## state["rain_until"] / ["dry_until"] = when it changes (in-game seconds played). [rain] / [rain stop] force it.

const SHOWER := Vector2(120.0, 260.0)  # seconds a shower lasts
const DRY := Vector2(300.0, 700.0)  # seconds between showers
const HISS_DB := -24.0

var ctx: Dictionary
var W
var rain: GPUParticles3D
var hiss: AudioStreamPlayer
var clock := 0.0
var want := 0.0  # 1 = raining, 0 = dry (the wetness eases toward it)


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	clock = float(ctx.state.get("weather_clock", 0.0))
	if not ctx.state.has("dry_until"):
		ctx.state["dry_until"] = clock + randf_range(DRY.x, DRY.y)
	want = 1.0 if clock < float(ctx.state.get("rain_until", -1.0)) else 0.0
	make_rain()
	hiss = AudioStreamPlayer.new()
	hiss.stream = hiss_loop()
	hiss.volume_db = -80.0
	add_child(hiss)
	hiss.play()


func make_rain() -> void:
	rain = GPUParticles3D.new()
	rain.amount = 4000
	rain.lifetime = 1.1
	rain.visibility_aabb = AABB(Vector3(-25, -25, -25), Vector3(50, 50, 50))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 0.5, 22)
	pm.direction = Vector3(0.12, -1, 0.05)
	pm.spread = 2.0
	pm.initial_velocity_min = 18.0
	pm.initial_velocity_max = 22.0
	pm.gravity = Vector3(0, -9.8, 0)
	rain.process_material = pm
	var drop := BoxMesh.new()  # a thin streak
	drop.size = Vector3(0.015, 0.45, 0.015)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.82, 0.95, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = m
	rain.draw_pass_1 = drop
	rain.emitting = false
	add_child(rain)


## Two seconds of soft brown noise, looped: the hiss of rain on grass.
func hiss_loop() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 2
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var v := 0.0
	for i in n:
		v = clampf(v * 0.97 + randf_range(-1.0, 1.0) * 0.12, -1.0, 1.0)
		var edge := minf(minf(float(i), float(n - i)) / 400.0, 1.0)  # (no click at the loop point)
		bytes.encode_s16(i * 2, int(v * edge * 26000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = n
	return wav


func _process(delta: float) -> void:
	clock += delta
	ctx.state["weather_clock"] = clock
	if want > 0.5 and clock > float(ctx.state.get("rain_until", 0.0)):
		set_rain(false)
	elif want < 0.5 and clock > float(ctx.state.get("dry_until", INF)):
		set_rain(true)
	var wet := move_toward(float(ctx.state.get("rain", 0.0)), want, delta / 20.0)  # clouds take ~20 s to roll in
	ctx.state["rain"] = wet
	ctx["rain"] = wet
	rain.emitting = wet > 0.35
	rain.global_position = W.player.global_position + Vector3(0, 16, 0)
	hiss.volume_db = lerpf(-60.0, HISS_DB, clampf(wet * 1.5, 0.0, 1.0)) if wet > 0.02 else -80.0
	var base = ctx.parts.get("base")  # (base.gd sets the light each frame before us: we dim what it set)
	if base and base.light and wet > 0.0:
		base.light.light_energy *= lerpf(1.0, 0.35, wet)
		base.env.fog_density += 0.008 * wet
		base.env.fog_light_color = base.env.fog_light_color.lerp(Color("#5a6270"), wet * 0.8)
		base.env.adjustment_saturation = lerpf(1.25, 0.85, wet)
		if not ctx.state.has("sky_tint"):
			base.sky_material.set_shader_parameter("tint", Color(0.42, 0.45, 0.5, 0.75 * wet * (1.0 - float(ctx.get("night", 0.0)) * 0.7)))


func set_rain(on: bool) -> void:
	want = 1.0 if on else 0.0
	if on:
		ctx.state["rain_until"] = clock + randf_range(SHOWER.x, SHOWER.y)
	else:
		ctx.state["dry_until"] = clock + randf_range(DRY.x, DRY.y)


func seen_from(_from: Vector3, _viewer: Node) -> Array:
	var wet := float(ctx.state.get("rain", 0.0))
	if wet > 0.5:
		return ["it is raining, grey clouds hang low over the valley"]
	if wet > 0.05:
		return ["the sky is clouding over (rain coming, or just passing)" if want > 0.5 else "the rain is easing off"]
	return []


func handle(c: Dictionary) -> bool:
	if c.get("cmd", "") != "rain":
		return false
	var args: Array = c.get("args", [])
	set_rain(args.is_empty() or not str(args[0]).to_lower() in ["stop", "off", "away"])
	return true
