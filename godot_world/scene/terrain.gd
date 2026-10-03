extends Node3D
## The land: a flat grassy meadow in the middle (everything that lives there assumes the ground is at y = 0),
## ringed by rolling wooded hills that rise into snowy mountains at the edge of the world. Dirt roads lead north
## up to the castle (castle.gd) and west to the village (village.gd), with lanterns along them. Grass sways,
## trees and boulders cover the hills, fireflies drift over the meadow.
##
## height_at(x, z) is the ground height anywhere (0 in the meadow); W.ground_y() asks it. The heavy parts
## (the ground mesh, its collision and the trees) are kept in ctx between reloads, so saving a part is quick.

const VERSION := 7  # bump to rebuild the cached ground after changing the shape below
const FLAT := 58.0  # radius of the flat meadow
const SIZE := 400.0  # the land is SIZE x SIZE metres, centred on the middle
const CELL := 2.0  # ground mesh resolution (m)
const CASTLE := Vector3(0, 0, -140)  # castle.gd stands here, on a levelled hilltop
const CASTLE_TOP := 17.0
const VILLAGE := Vector3(-46, 0, 0)  # village.gd
const MILL := Vector3(74, 0, 58)  # the windmill on the eastern hills
## Roads as polylines (x, z). The north road climbs to the castle gate, the west road leads to the village.
const ROADS := [
	[Vector2(0, -4), Vector2(2, -40), Vector2(-3, -75), Vector2(4, -100), Vector2(0, -119)],
	[Vector2(-4, 0), Vector2(-20, -3), Vector2(-36, 1), Vector2(-46, 0)],
	[Vector2(4, 1), Vector2(22, -4), Vector2(48, 20), Vector2(66, 48), Vector2(72, 55)],
]
const ROAD_WIDTH := 3.2

const GROUND_SHADER := """
shader_type spatial;
render_mode cull_back;
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// the painted colour (grass, road, rock, snow) with small-scale mottling, so it never looks flat
	float n = vnoise(wpos.xz * 0.35) * 0.55 + vnoise(wpos.xz * 1.7) * 0.3 + vnoise(wpos.xz * 6.0) * 0.15;
	ALBEDO = COLOR.rgb * (0.78 + n * 0.42);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
"""

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled;
varying float tip;
void vertex() {
	tip = clamp(VERTEX.y / 0.38, 0.0, 1.0);
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sway = sin(TIME * 1.7 + w.x * 0.35 + w.z * 0.27) * 0.6 + sin(TIME * 3.1 + w.x * 1.3) * 0.25;
	VERTEX.x += sway * 0.12 * tip * tip;
	VERTEX.z += sway * 0.06 * tip * tip;
}
void fragment() {
	ALBEDO = COLOR.rgb * mix(0.45, 1.15, tip);
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.15, 0.2, 0.05);
}
"""

var ctx: Dictionary
var W
var noise: FastNoiseLite
var lanterns := []  # [light, base energy, phase]
var fireflies: GPUParticles3D
var spin := 0.0


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	var cache: Dictionary = ctx.get("terrain_cache", {})
	if cache.get("version", -1) != VERSION:  # (re)make the ground and the trees, then keep them in ctx
		cache = {"version": VERSION, "mesh": ground_mesh(), "heights": height_grid(), "trees": tree_meshes()}
		ctx["terrain_cache"] = cache
	var ground := MeshInstance3D.new()
	ground.mesh = cache["mesh"]
	var shader := Shader.new()
	shader.code = GROUND_SHADER
	var gm := ShaderMaterial.new()
	gm.shader = shader
	ground.material_override = gm
	add_child(ground)
	add_ground_collision(cache["heights"])
	for mm in cache["trees"]:
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		add_child(node)
	add_tree_collision()
	add_grass()
	add_lanterns()
	add_fireflies()


# --- the shape of the land ----------------------------------------------------------------------------------

func setup_noise() -> void:
	noise = FastNoiseLite.new()
	noise.seed = 1234
	noise.frequency = 0.011
	noise.fractal_octaves = 4


## The ground height at x, z (0 everywhere in the meadow).
func height_at(x: float, z: float) -> float:
	if noise == null:
		setup_noise()
	var r := Vector2(x, z).length()
	if r <= FLAT:
		return 0.0
	var n := noise.get_noise_2d(x, z)  # about -0.6 .. 0.6
	var hills := smoothstep(FLAT, FLAT + 45.0, r) * (8.0 + 10.0 * n)
	var mountains := smoothstep(125.0, 200.0, r) * (32.0 + 30.0 * noise.get_noise_2d(x * 1.7 + 300.0, z * 1.7))
	var h := hills + mountains
	var dc := Vector2(x - CASTLE.x, z - CASTLE.z).length()  # the castle's hilltop is levelled
	h = lerpf(h, CASTLE_TOP, smoothstep(40.0, 26.0, dc))
	var road := road_distance(x, z)  # roads are cut a little into the slope, smoothing their bumps
	if road < ROAD_WIDTH * 2.0:
		h = lerpf(h, smoothed_height(x, z), smoothstep(ROAD_WIDTH * 2.0, ROAD_WIDTH * 0.5, road))
	return maxf(h, 0.0)


func smoothed_height(x: float, z: float) -> float:  # the hills without their small bumps (for the roads)
	var r := Vector2(x, z).length()
	var dc := Vector2(x - CASTLE.x, z - CASTLE.z).length()
	var h := smoothstep(FLAT, FLAT + 45.0, r) * 8.0 + smoothstep(125.0, 200.0, r) * 32.0
	return lerpf(h, CASTLE_TOP, smoothstep(40.0, 26.0, dc))


## How far x, z is from the nearest road's centre line.
func road_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := INF
	for road in ROADS:
		for i in road.size() - 1:
			var a: Vector2 = road[i]
			var b: Vector2 = road[i + 1]
			var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
			best = minf(best, p.distance_to(a + (b - a) * t))
	return best


## Ground colour: grass with patches, dirt roads, rocky slopes, snowy peaks.
func ground_color(x: float, z: float, h: float, slope: float) -> Color:
	var n := noise.get_noise_2d(x * 3.0, z * 3.0)
	var grass := Color("#3f6a24").lerp(Color("#5d8a2c"), clampf(n + 0.5, 0.0, 1.0))
	if Vector2(x, z).length() > FLAT + 8.0:  # darker forest floor on the hills
		grass = grass.lerp(Color("#33502a"), smoothstep(FLAT + 8.0, FLAT + 40.0, Vector2(x, z).length()) * 0.6)
	var col := grass
	col = col.lerp(Color("#6f6a5e"), smoothstep(0.35, 0.65, slope))  # steep: bare rock
	col = col.lerp(Color("#77746d"), smoothstep(26.0, 36.0, h))  # high up: grey stone
	col = col.lerp(Color("#cdd3de"), smoothstep(46.0, 54.0, h + n * 6.0))  # peaks: snow
	var road := road_distance(x, z)
	col = col.lerp(Color("#66503a"), smoothstep(ROAD_WIDTH, ROAD_WIDTH * 0.55, road + n * 0.6))  # dirt road
	var dc := Vector2(x - CASTLE.x, z - CASTLE.z).length()
	col = col.lerp(Color("#6e6250"), smoothstep(15.0, 12.0, dc))  # the castle's trodden courtyard
	return col


func ground_mesh() -> ArrayMesh:
	var n := int(SIZE / CELL)
	var half := SIZE / 2.0
	var heights := []
	for i in n + 1:
		var row := PackedFloat32Array()
		for j in n + 1:
			row.append(height_at(-half + j * CELL, -half + i * CELL))
		heights.append(row)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for i in n + 1:
		for j in n + 1:
			var x := -half + j * CELL
			var z := -half + i * CELL
			var h: float = heights[i][j]
			var hl: float = heights[i][maxi(j - 1, 0)]
			var hr: float = heights[i][mini(j + 1, n)]
			var hd: float = heights[maxi(i - 1, 0)][j]
			var hu: float = heights[mini(i + 1, n)][j]
			var normal := Vector3(hl - hr, 2.0 * CELL, hd - hu).normalized()
			verts.append(Vector3(x, h, z))
			normals.append(normal)
			colors.append(ground_color(x, z, h, 1.0 - normal.y))
	var indices := PackedInt32Array()
	for i in n:
		for j in n:
			var a := i * (n + 1) + j
			indices.append_array([a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Heights at 1 m spacing for the collision shape (HeightMapShape3D is always 1 m per sample).
func height_grid() -> PackedFloat32Array:
	var n := int(SIZE)
	var half := SIZE / 2.0
	var data := PackedFloat32Array()
	data.resize((n + 1) * (n + 1))
	for i in n + 1:
		for j in n + 1:
			data[i * (n + 1) + j] = height_at(-half + j, -half + i)
	return data


func add_ground_collision(heights: PackedFloat32Array) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = int(SIZE) + 1
	hm.map_depth = int(SIZE) + 1
	hm.map_data = heights
	shape.shape = hm
	body.add_child(shape)
	add_child(body)


# --- trees, boulders -----------------------------------------------------------------------------------------

var tree_spots := []  # [position, kind, scale] of every tree, also used for their collision


## Places where no tree or boulder may stand.
func keep_clear(x: float, z: float) -> bool:
	if road_distance(x, z) < ROAD_WIDTH + 2.5:
		return true
	if Vector2(x - CASTLE.x, z - CASTLE.z).length() < 42.0 or Vector2(x - VILLAGE.x, z - VILLAGE.z).length() < 22.0:
		return true
	if Vector2(x - MILL.x, z - MILL.z).length() < 10.0:
		return true
	if Vector2(x - 40.0, z - 5.0).length() < 18.0 or Vector2(x - 12.0, z - 18.0).length() < 9.0:
		return true  # the parkour tower, Marigold's stall
	if Vector2(x + 30.0, z + 28.0).length() < 10.0 or Vector2(x + 54.0, z + 20.0).length() < 5.0 or Vector2(x + 40.0, z - 24.0).length() < 13.0:
		return true  # the wheat field, the log pile, the sheep's pasture (villagers.gd, animals.gd)
	return false


func plan_trees() -> void:
	tree_spots.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var tries := 0
	while tree_spots.size() < 900 and tries < 9000:
		tries += 1
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf_range(0.04, 1.0)) * 190.0
		var x := cos(a) * r
		var z := sin(a) * r
		if r < 44.0 or keep_clear(x, z):
			continue
		var forest := noise.get_noise_2d(x * 0.6 + 50.0, z * 0.6)  # woods in patches, a few lone trees in between
		if r < FLAT and forest < 0.25:
			continue
		if forest < -0.1 and rng.randf() < 0.85:
			continue
		var h := height_at(x, z)
		if h > 38.0:  # not up on the bare peaks
			continue
		var kind := 0 if (h > 12.0 or rng.randf() < 0.55) else 1  # pines higher up, oaks lower down
		tree_spots.append([Vector3(x, h, z), kind, rng.randf_range(0.8, 1.35), rng.randf() * TAU])


func pine_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.24
	trunk.height = 2.0
	trunk.radial_segments = 6
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, 1.0, 0)))
	st.commit(mesh)
	mesh.surface_set_material(0, tree_material(Color("#4a3423")))
	st = SurfaceTool.new()
	for k in 4:  # stacked cones, each smaller
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 2.1 - k * 0.42
		cone.height = 2.3 - k * 0.25
		cone.radial_segments = 7
		st.append_from(cone, 0, Transform3D(Basis(), Vector3(0, 2.4 + k * 1.15, 0)))
	st.commit(mesh)
	mesh.surface_set_material(1, tree_material(Color("#2f5230")))
	return mesh


func oak_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.22
	trunk.bottom_radius = 0.34
	trunk.height = 2.6
	trunk.radial_segments = 6
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, 1.3, 0)))
	st.commit(mesh)
	mesh.surface_set_material(0, tree_material(Color("#53392a")))
	st = SurfaceTool.new()
	for blob in [[Vector3(0, 3.4, 0), 1.9], [Vector3(0.9, 3.0, 0.3), 1.3], [Vector3(-0.8, 3.1, -0.4), 1.35], [Vector3(0.1, 4.2, -0.2), 1.25]]:
		var s := SphereMesh.new()
		s.radius = blob[1]
		s.height = blob[1] * 1.7
		s.radial_segments = 8
		s.rings = 5
		st.append_from(s, 0, Transform3D(Basis(), blob[0]))
	st.commit(mesh)
	mesh.surface_set_material(1, tree_material(Color("#3e6b2e")))
	return mesh


func tree_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true  # each tree gets its own shade (the instance colour)
	m.roughness = 0.9
	return m


func tree_meshes() -> Array:
	plan_trees()
	var out := []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for kind in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = pine_mesh() if kind == 0 else oak_mesh()
		var mine := tree_spots.filter(func(t): return t[1] == kind)
		mm.instance_count = mine.size()
		for i in mine.size():
			var t: Array = mine[i]
			var s: float = t[2]
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, t[3]).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s)), t[0] - Vector3(0, 0.15, 0)))
			mm.set_instance_color(i, Color.WHITE.darkened(rng.randf_range(0.0, 0.3)))
		out.append(mm)
	out.append(boulders())
	return out


func boulders() -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var rock := SphereMesh.new()
	rock.radial_segments = 7
	rock.rings = 4
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#7a7670")
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	rock.material = m
	mm.mesh = rock
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var spots := []
	while spots.size() < 220:
		var a := rng.randf() * TAU
		var r := rng.randf_range(30.0, 185.0)
		var x := cos(a) * r
		var z := sin(a) * r
		if keep_clear(x, z) or (r < FLAT and rng.randf() < 0.7):
			continue
		spots.append(Vector3(x, height_at(x, z), z))
	mm.instance_count = spots.size()
	for i in spots.size():
		var s := rng.randf_range(0.5, 2.6)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(1.0, 1.6), s * 0.75, s))
		mm.set_instance_transform(i, Transform3D(basis, spots[i] - Vector3(0, s * 0.18, 0)))
		mm.set_instance_color(i, Color.WHITE.darkened(rng.randf_range(0.0, 0.35)))
	return mm


func add_tree_collision() -> void:
	if tree_spots.is_empty():
		if noise == null:
			setup_noise()
		plan_trees()
	var body := StaticBody3D.new()
	for t in tree_spots:
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.35 * t[2]
		cyl.height = 4.0
		shape.shape = cyl
		shape.position = t[0] + Vector3(0, 2.0, 0)
		body.add_child(shape)
	add_child(body)


# --- grass, lanterns, fireflies --------------------------------------------------------------------------------

func blade_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	for k in 3:  # three thin blades leaning out a little in different directions
		var a := k * TAU / 3.0 + 0.4
		var d := Vector3(cos(a), 0, sin(a))
		var side := d.cross(Vector3.UP) * 0.022
		var lean := d * 0.09
		verts.append_array([-side, side, Vector3(0, 0.38 - k * 0.07, 0) + lean])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func add_grass() -> void:
	var mm: MultiMesh = ctx.get("grass_cache")
	if mm == null or ctx.get("grass_version", -1) != VERSION:
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = blade_mesh()
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		var spots := []
		while spots.size() < 55000:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * (FLAT + 14.0)
			var x := cos(a) * r
			var z := sin(a) * r
			if road_distance(x, z) < ROAD_WIDTH * 0.8 or Vector2(x - 12.0, z - 18.0).length() < 4.5:
				continue
			spots.append(Vector3(x, height_at(x, z), z))
		mm.instance_count = spots.size()
		for i in spots.size():
			var s := rng.randf_range(0.55, 1.2)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.4), s)), spots[i]))
			var g := Color("#4a7a26").lerp(Color("#6f9a32"), rng.randf()).darkened(rng.randf_range(0.0, 0.25))
			mm.set_instance_color(i, g)
		ctx["grass_cache"] = mm
		ctx["grass_version"] = VERSION
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = GRASS_SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	node.material_override = m
	add_child(node)


## Wooden posts with a hanging lantern every ~18 m along the roads, flickering warmly.
func add_lanterns() -> void:
	lanterns.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for road in ROADS:
		var left := 1.0
		for i in road.size() - 1:
			var a: Vector2 = road[i]
			var b: Vector2 = road[i + 1]
			var length := a.distance_to(b)
			var d := 9.0
			while d < length:
				var p := a + (b - a) * (d / length)
				var side := (b - a).normalized().orthogonal() * (ROAD_WIDTH * 0.5 + 0.8) * left
				left = -left
				var at := p + side
				if Vector2(at.x, at.y).length() > 8.0:
					lantern_post(Vector3(at.x, height_at(at.x, at.y), at.y), rng.randf() * TAU)
				d += 18.0


func lantern_post(at: Vector3, phase: float) -> void:
	var post := Node3D.new()
	post.position = at
	add_child(post)
	var wood := Color("#4a3423")
	W.box(post, Vector3(0, 1.3, 0), Vector3(0.14, 2.6, 0.14), wood, "cube", true)
	W.box(post, Vector3(0.28, 2.5, 0), Vector3(0.62, 0.09, 0.09), wood)  # the arm
	W.box(post, Vector3(0.52, 2.33, 0), Vector3(0.02, 0.25, 0.02), Color("#222222"))  # chain
	W.box(post, Vector3(0.52, 2.1, 0), Vector3(0.24, 0.05, 0.24), Color("#2b2620"))  # lantern lid
	W.box(post, Vector3(0.52, 1.82, 0), Vector3(0.22, 0.04, 0.22), Color("#2b2620"))  # and base
	W.glow(post, Vector3(0.52, 1.96, 0), Vector3(0.15, 0.24, 0.15), Color("#ffb54d"), 3.0)  # the flame behind glass
	var l: OmniLight3D = W.light(post, Vector3(0.52, 1.9, 0), Color("#ffae55"), 1.6, 9.0)
	l.shadow_enabled = false
	lanterns.append([l, 1.6, phase])


func add_fireflies() -> void:
	var p := GPUParticles3D.new()
	p.amount = 160
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.visibility_aabb = AABB(Vector3(-60, -2, -60), Vector3(120, 10, 120))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(50, 1.2, 50)
	pm.gravity = Vector3.ZERO
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.35
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	pm.turbulence_noise_scale = 3.0
	var fade := Gradient.new()  # each one glows up and fades away again
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.3, Color(1, 1, 1, 1))
	fade.add_point(0.7, Color(1, 1, 1, 1))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	p.process_material = pm
	var dot := SphereMesh.new()
	dot.radius = 0.035
	dot.height = 0.07
	dot.radial_segments = 4
	dot.rings = 2
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_color = Color("#d8ff7a")
	dm.vertex_color_use_as_albedo = true
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.emission_enabled = true
	dm.emission = Color("#c8ff5a")
	dm.emission_energy_multiplier = 4.0
	dot.material = dm
	p.draw_pass_1 = dot
	p.position = Vector3(0, 1.4, 0)
	add_child(p)
	fireflies = p


func _process(delta: float) -> void:
	spin += delta
	var night: float = ctx.get("night", 1.0)  # (base.gd: 1 at night, 0 by day)
	for l in lanterns:  # a warm, uneven flicker; dimmer by day
		var light: OmniLight3D = l[0]
		light.light_energy = l[1] * (0.85 + 0.1 * sin(spin * 7.0 + l[2]) + 0.06 * sin(spin * 17.3 + l[2] * 2.0)) * lerpf(0.15, 1.0, night)
	if fireflies:
		fireflies.emitting = night > 0.4  # they come out after dark


## What the characters see of the land.
func seen_from(from: Vector3, _viewer: Node) -> Array:
	return ["wooded hills all around the meadow, rising to snowy mountains, with dirt roads and lanterns along them",
		"a castle on the hill to the north, %s, with a road leading up to it" % W.where(from, CASTLE),
		"a little village of thatched cottages %s" % W.where(from, VILLAGE),
		"a windmill on the eastern hills %s" % W.where(from, MILL)]
