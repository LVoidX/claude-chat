extends Node3D
## Wildlife that makes the valley feel lived in. Models are made in Blender (tools/blender/wildlife.py):
## - birds: three small flocks circling high over the valley by day, wings flapping (a vertex shader lifts the wing
##   tips), banking a little in the turns. They go to roost at dusk and stay in when it rains.
## - butterflies: about thirty, drifting over the meadow and the village green by day, each its own colour.
## - ducks: four mallards paddling about on the pond, bobbing a little, always there.
## Nothing here is saved: a reload puts everyone back (they just start flying again).

const BIRD_FLOCKS := 3
const BIRDS_PER_FLOCK := 5
const BUTTERFLIES := 30
const DUCKS := 4
const TINTS := [Color("#ffb347"), Color("#ffe566"), Color("#9ec9ff"), Color("#ffffff"), Color("#ff8fb1"), Color("#c9a0ff")]

const WING_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float flap_speed = 12.0;
uniform float flap_amount = 0.7;
instance uniform float phase = 0.0;
instance uniform vec3 tint : source_color = vec3(1.0);
void vertex() {
	VERTEX.y += abs(VERTEX.x) * sin(TIME * flap_speed + phase) * flap_amount;  // the tips lift and fall, the middle stays
}
void fragment() {
	ALBEDO = COLOR.rgb * tint;
	ROUGHNESS = 0.9;
}
"""

var ctx: Dictionary
var W
var birds := []  # {node, flock centre/radius/speed/height, angle, offset}
var butterflies := []  # {node, goal, speed, hover, phase}
var ducks := []  # {node, angle, radius, speed}
var t := 0.0


func make_material(speed: float, amount: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = WING_SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("flap_speed", speed)
	m.set_shader_parameter("flap_amount", amount)
	return m


func spawn(mesh_name: String, material: Material, scale := 1.0) -> MeshInstance3D:
	var mesh: ArrayMesh = W.load_mesh(mesh_name)
	if mesh == null:
		return null
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.scale = Vector3.ONE * scale
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var bird_mat := make_material(11.0, 0.55)
	for f in BIRD_FLOCKS:
		var centre := Vector2(rng.randf_range(-70, 70), rng.randf_range(-70, 70))
		var flock := {"centre": centre, "radius": rng.randf_range(35.0, 70.0), "speed": rng.randf_range(0.07, 0.12) * (1.0 if f % 2 == 0 else -1.0),
			"height": rng.randf_range(24.0, 42.0)}
		for i in BIRDS_PER_FLOCK:
			var node := spawn("bird", bird_mat, 1.5)
			if node == null:
				return
			node.set_instance_shader_parameter("phase", rng.randf() * TAU)
			birds.append({"node": node, "flock": flock, "angle": rng.randf() * TAU, "off": Vector3(rng.randf_range(-4, 4), rng.randf_range(-2, 2), rng.randf_range(-4, 4)),
				"wobble": rng.randf() * TAU})
	var wing_mat := make_material(15.0, 1.4)
	for i in BUTTERFLIES:
		var node := spawn("butterfly", wing_mat, 1.4)
		if node == null:
			break
		node.set_instance_shader_parameter("phase", rng.randf() * TAU)
		node.set_instance_shader_parameter("tint", TINTS[rng.randi() % TINTS.size()])
		var home := Vector2(rng.randf_range(-48, 52), rng.randf_range(-30, 40))
		node.position = Vector3(home.x, 1.0, home.y)
		butterflies.append({"node": node, "home": home, "goal": node.position, "speed": rng.randf_range(0.8, 1.6), "hover": rng.randf_range(0.5, 1.6), "seed": rng.randf() * 100.0})
	var duck_mat := make_material(0.0, 0.0)
	var terrain = ctx.parts.get("terrain")
	for i in DUCKS:
		var node := spawn("duck", duck_mat, 1.25)
		if node == null:
			break
		ducks.append({"node": node, "angle": rng.randf() * TAU, "radius": rng.randf_range(1.0, 4.2), "speed": rng.randf_range(0.04, 0.09) * (1.0 if i % 2 == 0 else -1.0)})


func _process(delta: float) -> void:
	t += delta
	var day := 1.0 - float(ctx.get("night", 0.0))
	var dry := 1.0 - clampf(float(ctx.get("rain", 0.0)) * 1.5, 0.0, 1.0)
	var out := day > 0.55 and dry > 0.5  # birds and butterflies are out on dry days
	for b in birds:
		var node: MeshInstance3D = b.node
		node.visible = out
		if not out:
			continue
		var f: Dictionary = b.flock
		b.angle += delta * float(f.speed)
		var a: float = b.angle
		var centre: Vector2 = f.centre
		var wob: float = b.wobble
		var off: Vector3 = b.off
		var p: Vector3 = Vector3(centre.x + cos(a) * float(f.radius), float(f.height) + sin(t * 0.4 + wob) * 1.5, centre.y + sin(a) * float(f.radius)) + off
		var dir := Vector3(-sin(a), 0, cos(a)) * signf(f.speed)  # the way it is going: along the circle
		node.position = p
		node.rotation = Vector3(0, atan2(-dir.x, -dir.z), -0.25 * signf(f.speed))  # banked into the turn
	for bf in butterflies:
		var node: MeshInstance3D = bf.node
		node.visible = out
		if not out:
			continue
		var pos: Vector3 = node.position
		var to: Vector3 = Vector3(bf.goal.x - pos.x, 0, bf.goal.z - pos.z)
		if to.length() < 0.6:  # arrived: pick a new flower to flutter to, near where it lives
			var home: Vector2 = bf.home
			var gx := home.x + randf_range(-9.0, 9.0)
			var gz := home.y + randf_range(-9.0, 9.0)
			bf.goal = Vector3(gx, 0, gz)
		else:
			var dir := to.normalized()
			pos += dir * float(bf.speed) * delta
			node.rotation.y = lerp_angle(node.rotation.y, atan2(-dir.x, -dir.z), minf(delta * 3.0, 1.0))
		var ground: float = W.ground_y(pos.x, pos.z)
		pos.y = maxf(ground, 0.0) + float(bf.hover) + sin(t * 2.6 + bf.seed) * 0.28 + sin(t * 1.1 + bf.seed * 2.0) * 0.15  # bobbing as they go
		node.position = pos
	var pond: Vector3 = ctx.parts["terrain"].POND if ctx.parts.has("terrain") else Vector3.ZERO
	for d in ducks:
		var node: MeshInstance3D = d.node
		d.angle += delta * float(d.speed)
		var a: float = d.angle
		var p := Vector3(pond.x + cos(a) * float(d.radius), -0.12 + sin(t * 1.5 + a * 3.0) * 0.012, pond.z + sin(a * 1.3) * float(d.radius) * 0.8)
		var ahead := Vector3(pond.x + cos(a + 0.05 * signf(d.speed)) * float(d.radius), 0, pond.z + sin((a + 0.05 * signf(d.speed)) * 1.3) * float(d.radius) * 0.8)
		node.position = p
		node.rotation = Vector3(sin(t * 1.5 + a) * 0.02, atan2(-(ahead.x - p.x), -(ahead.z - p.z)), 0)


func seen_from(_from: Vector3, _viewer: Node) -> Array:
	return ["birds circling high over the valley by day, butterflies over the meadow, and ducks on the pond at the south of the meadow"]
