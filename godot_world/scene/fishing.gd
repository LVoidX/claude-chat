extends Node3D
## Fishing at the pond (and the stream): stand at the water's edge and press E to cast where you are looking; the bobber
## floats on the water, and after a few seconds it dips with a splash: press E again within a moment to hook the fish.
## Catches: trout, carp (food and trade goods), now and then an old boot, rarely a golden carp (worth a lot). E at the
## campfire grills a trout (a better meal). Nothing here is saved except what lands in your pack (rpg.gd).
## Needs: terrain.gd (POND, stream_distance, WATER_Y), rpg.gd (give/take/count/ITEMS), music.gd (splash sounds).

const CAST_RANGE := 7.5  # how far out you can throw
const WAIT := Vector2(3.0, 9.0)  # seconds until a bite
const BITE_WINDOW := 1.3  # seconds you have to react
const FISH := [["trout", 0.52], ["carp", 0.30], ["boot", 0.12], ["golden_carp", 0.06]]

var ctx: Dictionary
var W
var state := "idle"  # idle, waiting, bite
var timer := 0.0
var target := Vector3.ZERO
var bobber: MeshInstance3D
var line: MeshInstance3D
var splash: GPUParticles3D
var t := 0.0
var shoal: Array = []  # [node, radius, speed, phase, lift]: dark fish shapes drifting under the pond's surface


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	var m := SphereMesh.new()
	m.radius = 0.07
	m.height = 0.14
	m.radial_segments = 8
	m.rings = 4
	bobber = MeshInstance3D.new()
	bobber.mesh = m
	var top := StandardMaterial3D.new()
	top.albedo_color = Color("#e0392b")
	bobber.material_override = top
	bobber.visible = false
	add_child(bobber)
	W.box(bobber, Vector3(0, -0.07, 0), Vector3(0.1, 0.06, 0.1), Color("#f2efe6"), "sphere")  # a white underside
	line = MeshInstance3D.new()
	line.mesh = BoxMesh.new()
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.95, 0.95, 0.9, 0.8)
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.material_override = lm
	line.visible = false
	add_child(line)
	splash = GPUParticles3D.new()
	splash.amount = 16
	splash.lifetime = 0.7
	splash.one_shot = true
	splash.explosiveness = 1.0
	splash.emitting = false
	splash.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 4, 6))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 45.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, -9.8, 0)
	splash.process_material = pm
	var drop := SphereMesh.new()
	drop.radius = 0.03
	drop.height = 0.06
	drop.radial_segments = 4
	drop.rings = 2
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.85, 0.95, 1.0)
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = dm
	splash.draw_pass_1 = drop
	add_child(splash)
	make_shoal()


## A few fish seen as dim shapes under the water: they show where the pond is worth a cast.
func make_shoal() -> void:
	var tr = terrain()
	if tr == null:
		return
	var body := SphereMesh.new()
	body.radius = 0.5
	body.height = 1.0
	body.radial_segments = 8
	body.rings = 4
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.1, 0.16, 0.12, 0.55)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	body.material = dm
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 6:
		var f := MeshInstance3D.new()
		f.mesh = body
		f.scale = Vector3(0.55, 0.1, 0.16) * rng.randf_range(0.8, 1.3)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.visibility_range_end = 45.0
		add_child(f)
		shoal.append([f, rng.randf_range(1.2, 4.8), rng.randf_range(0.25, 0.6) * (1.0 if i % 2 == 0 else -1.0), rng.randf() * TAU, rng.randf_range(0.22, 0.4)])


func terrain():
	return ctx.parts.get("terrain")


## Is this spot over water (the pond, or the stream's ribbon)?
func over_water(x: float, z: float) -> bool:
	var tr = terrain()
	if tr == null:
		return false
	return tr.pond_distance(x, z) < 0.6 or tr.stream_distance(x, z) < 2.4


func near_water() -> bool:
	var me: Vector3 = W.player.global_position
	for d in [Vector2(0, 0), Vector2(2.5, 0), Vector2(-2.5, 0), Vector2(0, 2.5), Vector2(0, -2.5)]:
		if over_water(me.x + d.x, me.z + d.y):
			return true
	return false


func interactables() -> Array:
	var out := []
	var me: Vector3 = W.player.global_position
	if state == "idle" and near_water() and not ctx.get("seated", false):
		out.append({"pos": me, "label": "Cast a line", "act": cast, "range": 3.0})
	elif state == "waiting":
		out.append({"pos": me, "label": "Reel in", "act": reel, "range": 3.0})
	elif state == "bite":
		out.append({"pos": me, "label": "HOOK IT!", "act": reel, "range": 3.0})
	var travel = ctx.parts.get("travel")
	var rpg = ctx.parts.get("rpg")
	if travel and rpg and rpg.count("trout") > 0:
		var fire: Vector3 = travel.ground(travel.FIRE)
		if Vector2(me.x - fire.x, me.z - fire.z).length() < 3.2:
			out.append({"pos": me, "label": "Grill a trout", "act": grill, "range": 3.0})
	if travel and rpg and rpg.count("trout") == 0 and rpg.count("carp") > 0:
		var fire2: Vector3 = travel.ground(travel.FIRE)
		if Vector2(me.x - fire2.x, me.z - fire2.z).length() < 3.2:
			out.append({"pos": me, "label": "Grill a carp", "act": grill_carp, "range": 3.0})
	return out


## Throw the line along where you look, as far as the water goes.
func cast() -> void:
	var from: Vector3 = W.camera.global_position
	var dir: Vector3 = -W.camera.global_basis.z
	var found := false
	for k in range(10, int(CAST_RANGE * 10) + 1, 4):  # march out along the view, look for the first water
		var d: float = k / 10.0
		var p: Vector3 = from + dir * d
		p.y = WATER_Y_SAFE()
		if over_water(p.x, p.z) and from.y + dir.y * d < 1.6:
			target = Vector3(p.x, WATER_Y_SAFE(), p.z)
			found = true
			break
	if not found:  # not looking at the water: try straight out in front of the feet
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		for k in range(10, int(CAST_RANGE * 10) + 1, 4):
			var p: Vector3 = W.player.global_position + flat * (k / 10.0)
			if over_water(p.x, p.z):
				target = Vector3(p.x, WATER_Y_SAFE(), p.z)
				found = true
				break
	if not found:
		W.show_notice("Aim at the water to cast.", 2.0)
		return
	state = "waiting"
	timer = randf_range(WAIT.x, WAIT.y)
	if float(ctx.get("rain", 0.0)) > 0.3:  # the fish rise when it rains
		timer *= 0.6
	bobber.visible = true
	line.visible = true
	bobber.global_position = target + Vector3(0, 0.03, 0)
	play("splash")
	W.show_notice("You cast your line... (E reels it in)", 3.0)


func WATER_Y_SAFE() -> float:
	var tr = terrain()
	return tr.WATER_Y if tr else -0.16


func reel() -> void:
	if state == "bite":
		catch_fish()
	elif state == "waiting":
		W.show_notice("You reel in the empty line.", 2.0)
	end_cast()


func end_cast() -> void:
	state = "idle"
	bobber.visible = false
	line.visible = false


func catch_fish() -> void:
	var rpg = ctx.parts.get("rpg")
	if rpg == null:
		return
	var roll := randf()
	var item := "trout"
	var acc := 0.0
	for f in FISH:
		acc += float(f[1])
		if roll <= acc:
			item = f[0]
			break
	rpg.give(item, 1, true)
	var names := {"trout": "a fat trout", "carp": "a carp", "boot": "an old boot... the pond keeps its secrets", "golden_carp": "A GOLDEN CARP! Worth a small fortune"}
	W.show_notice("You caught " + names[item] + "!", 4.0)
	rpg.sfx("pickup")
	rpg.add_xp(3 if item != "boot" else 1)
	rpg.event("catch", item)
	splash.global_position = target
	splash.restart()
	play("splash")


func grill() -> void:
	var rpg = ctx.parts.get("rpg")
	if rpg and rpg.take("trout", 1):
		rpg.give("grilled_trout", 1, true)
		W.show_notice("You grill a trout over the fire. It smells wonderful.", 3.0)
		play("pickup")


func grill_carp() -> void:
	var rpg = ctx.parts.get("rpg")
	if rpg and rpg.take("carp", 1):
		rpg.give("grilled_carp", 1, true)
		W.show_notice("You grill the carp until the skin blisters. Hearty.", 3.0)
		play("pickup")


func play(name: String) -> void:
	var music = ctx.parts.get("music")
	if music:
		music.play_sfx(name)


func _process(delta: float) -> void:
	t += delta
	var tr = terrain()
	if tr != null:
		for f in shoal:
			var a: float = f[3] + t * f[2] + sin(t * 0.7 + f[1]) * 0.3
			var c: Vector3 = tr.POND
			f[0].position = Vector3(c.x + cos(a) * f[1], tr.WATER_Y - f[4], c.z + sin(a) * f[1])
			f[0].rotation.y = -a + (PI / 2.0 if f[2] > 0.0 else -PI / 2.0)
	if state == "idle":
		return
	var me: Vector3 = W.player.global_position
	if Vector2(me.x - target.x, me.z - target.z).length() > CAST_RANGE + 3.0:  # you walked away: the line comes in
		W.show_notice("You walked off, and the line came in.", 2.5)
		end_cast()
		return
	timer -= delta
	var bob := sin(t * 2.2) * 0.012
	if state == "waiting":
		bobber.global_position = target + Vector3(0, 0.03 + bob, 0)
		if timer <= 0.0:
			state = "bite"
			timer = BITE_WINDOW
			splash.global_position = target
			splash.restart()
			play("splash")
			W.show_notice("A bite! Press E!", 1.4)
	elif state == "bite":
		bobber.global_position = target + Vector3(0, -0.04 + sin(t * 30.0) * 0.03, 0)  # it bobs under, hard
		if timer <= 0.0:
			W.show_notice("It got away...", 2.0)
			end_cast()
	# the line: from your hand (lower right of the view) to the bobber
	var hand: Vector3 = W.camera.global_position + W.camera.global_basis * Vector3(0.28, -0.3, -0.5)
	var to: Vector3 = bobber.global_position
	var mid := (hand + to) / 2.0
	var len := hand.distance_to(to)
	line.global_position = mid
	line.scale = Vector3(0.004, 0.004, maxf(len, 0.01))
	if len > 0.05:
		line.look_at(to, Vector3.UP if absf((to - hand).normalized().y) < 0.99 else Vector3.RIGHT)


func seen_from(from: Vector3, _viewer: Node) -> Array:
	var tr = terrain()
	if tr == null:
		return []
	return ["the wanderer can fish in the pond (E at the water's edge) and grill a trout at the campfire; the pond is %s" % W.where(from, Vector3(tr.POND.x, 0, tr.POND.z))]
