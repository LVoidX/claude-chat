extends Node3D
## The land: a flat grassy meadow in the middle (everything that lives there assumes the ground is at y = 0),
## ringed by rolling wooded hills that rise into snowy mountains at the edge of the world. Dirt roads lead north
## up to the castle (castle.gd) and west to the village (village.gd), with lanterns along them. Grass sways,
## trees and boulders cover the hills, fireflies drift over the meadow.
##
## height_at(x, z) is the ground height anywhere (0 in the meadow); W.ground_y() asks it. The heavy parts
## (the ground mesh, its collision and the trees) are kept in ctx between reloads, so saving a part is quick.

const VERSION := 21  # rebuild cached terrain and grass after changing their scatter
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
## A stream rising at the south-west foot of the hills and winding east across the south of the meadow into a pond.
## Everything is derived from this one polyline: the channel cut into the ground (height_at), the water ribbon, the
## muddy banks (ground_color), the reeds, and what keeps trees off it (keep_clear). The meadow is flat at y = 0, the
## water sits at WATER_Y, a little below it.
const STREAM := [Vector2(-52, 49), Vector2(-36, 44), Vector2(-18, 49), Vector2(1, 52), Vector2(20, 47), Vector2(36, 42), Vector2(47, 34)]
const POND := Vector3(51, 0, 30)  # centre (x, z; y unused); radius POND_R
const POND_R := 6.5
const STREAM_DEPTH := 0.75
const WATER_Y := -0.16
const BANK_IN := 1.2  # within this far of the middle the channel is at full depth
const BANK_OUT := 3.7  # ...and the ground is back to normal this far out

const GROUND_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform float wetness = 0.0;
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
	vec3 col = COLOR.rgb * (0.78 + n * 0.42);
	float road = COLOR.a;  // 1 on a road (ground_color puts it there)
	vec3 up = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	float grassy = (1.0 - road) * smoothstep(0.8, 0.92, up.y) * (1.0 - smoothstep(20.0, 28.0, wpos.y));
	// grass: darker clumps and lighter sunny patches
	float clump = vnoise(wpos.xz * 2.3 + 7.0);
	col *= mix(1.0, mix(0.82, 1.12, clump), grassy);
	// wildflowers: a few tiny dots of white, yellow and violet in the grass
	vec2 cell = wpos.xz * 3.0;
	float pick = hash(floor(cell));
	vec2 inside = fract(cell) - 0.5 + (vec2(hash(floor(cell) + 3.1), hash(floor(cell) + 7.7)) - 0.5) * 0.5;
	float flower = step(0.965, pick) * (1.0 - smoothstep(0.07, 0.11, length(inside))) * grassy;
	vec3 petal = pick > 0.988 ? vec3(0.95, 0.93, 0.85) : (pick > 0.976 ? vec3(0.98, 0.82, 0.25) : vec3(0.62, 0.45, 0.85));
	col = mix(col, petal, flower);
	// roads: packed earth with pebbles and darker wheel-worn patches
	float peb = step(0.82, hash(floor(wpos.xz * 7.0))) * (1.0 - smoothstep(0.18, 0.3, length(fract(wpos.xz * 7.0) - 0.5)));
	float worn = vnoise(wpos.xz * vec2(0.6, 3.5));
	col = mix(col, col * mix(0.82, 1.05, worn) + peb * vec3(0.12, 0.11, 0.09), road);
	ALBEDO = col * mix(1.0, 0.78, wetness * (0.2 + road * 0.8));
	ROUGHNESS = mix(0.95, 0.72 - road * 0.22, wetness);
	SPECULAR = 0.2 + road * wetness * 0.32;
}
"""

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled;
varying float tip;
void vertex() {
	tip = clamp(VERTEX.y / 0.30, 0.0, 1.0);
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sway = sin(TIME * 1.7 + w.x * 0.35 + w.z * 0.27) * 0.6 + sin(TIME * 3.1 + w.x * 1.3) * 0.25;
	VERTEX.x += sway * 0.12 * tip * tip;
	VERTEX.z += sway * 0.06 * tip * tip;
}
void fragment() {
	ALBEDO = COLOR.rgb * mix(0.4, 1.0, tip);
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.15, 0.2, 0.05);
}
"""

## Painted tufts and flowers from Blender (grass.glb etc.): the colour is in the vertices (dark base, bright tip); this only
## adds the wind. `height` = how tall the model is, so the top moves most.
const TUFT_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float height = 0.45;
void vertex() {
	float tip = clamp(VERTEX.y / height, 0.0, 1.0);
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sway = sin(TIME * 1.7 + w.x * 0.35 + w.z * 0.27) * 0.6 + sin(TIME * 3.1 + w.x * 1.3) * 0.25;
	VERTEX.x += sway * 0.12 * tip * tip;
	VERTEX.z += sway * 0.06 * tip * tip;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.9;
	BACKLIGHT = vec3(0.15, 0.2, 0.05);
}
"""

var ctx: Dictionary
var W
var ground_material: ShaderMaterial
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
	ground_material = ShaderMaterial.new()
	ground_material.shader = shader
	ground.material_override = ground_material
	add_child(ground)
	add_ground_collision(cache["heights"])
	for mm in cache["trees"]:
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		add_child(node)
	add_tree_collision()
	add_grass()
	add_water()
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
	var h := base_height(x, z)
	var sd := stream_distance(x, z)
	if sd < BANK_OUT:
		h -= STREAM_DEPTH * (1.0 - smoothstep(BANK_IN, BANK_OUT, sd))
	var pd := pond_distance(x, z)
	if pd < 2.5:
		h -= (STREAM_DEPTH + 0.35) * (1.0 - smoothstep(-2.0, 2.5, pd))
	return h


## The land before the stream is cut into it.
func base_height(x: float, z: float) -> float:
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
var _stream_dense: Array = []


## The stream's polyline, with a gentle meander added and a point every ~2 m.
func stream_points() -> Array:
	if not _stream_dense.is_empty():
		return _stream_dense
	var out := []
	for i in STREAM.size() - 1:
		var a: Vector2 = STREAM[i]
		var b: Vector2 = STREAM[i + 1]
		var n := int(a.distance_to(b) / 2.0)
		for k in n:
			var t := float(k) / n
			var p := a.lerp(b, t)
			var side := (b - a).normalized().rotated(PI / 2.0)
			var s := float(out.size())
			out.append(p + side * (1.3 * sin(s * 0.33) + 0.6 * sin(s * 0.9 + 1.0)))
	out.append(STREAM[STREAM.size() - 1])
	_stream_dense = out
	return out


## How far x, z is from the stream's middle (INF when none is near: a cheap early-out by bounding box).
func stream_distance(x: float, z: float) -> float:
	if z < 24.0 or z > 62.0 or x < -64.0 or x > 62.0:
		return INF
	var pts := stream_points()
	var p := Vector2(x, z)
	var best := INF
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + (b - a) * t))
	return best


func pond_distance(x: float, z: float) -> float:
	return Vector2(x - POND.x, z - POND.z).length() - POND_R


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
	var grass := Color("#355c1e").lerp(Color("#4f7a24"), clampf(n + 0.5, 0.0, 1.0))
	if Vector2(x, z).length() > FLAT + 8.0:  # darker forest floor on the hills
		grass = grass.lerp(Color("#33502a"), smoothstep(FLAT + 8.0, FLAT + 40.0, Vector2(x, z).length()) * 0.6)
	var col := grass
	col = col.lerp(Color("#6f6a5e"), smoothstep(0.35, 0.65, slope))  # steep: bare rock
	col = col.lerp(Color("#77746d"), smoothstep(26.0, 36.0, h))  # high up: grey stone
	col = col.lerp(Color("#cdd3de"), smoothstep(46.0, 54.0, h + n * 6.0))  # peaks: snow
	var road := road_distance(x, z)
	var wet := minf(stream_distance(x, z), maxf(pond_distance(x, z) + 3.0, 0.0))  # distance to the water's edge zone
	col = col.lerp(Color("#8a7a58"), (1.0 - smoothstep(1.6, 4.4 + n * 0.8, wet)) * 0.75)  # sandy, pebbly banks
	col = col.lerp(Color("#4d4434"), (1.0 - smoothstep(0.8, 2.6, wet)) * 0.85)  # dark wet mud at the water
	var on_road := smoothstep(ROAD_WIDTH, ROAD_WIDTH * 0.55, road + n * 0.6)
	col = col.lerp(Color("#66503a"), on_road)  # dirt road
	var dc := Vector2(x - CASTLE.x, z - CASTLE.z).length()
	col = col.lerp(Color("#6e6250"), smoothstep(15.0, 12.0, dc))  # the castle's trodden courtyard
	col.a = maxf(on_road, smoothstep(15.0, 12.0, dc))  # (the shader adds pebbles where this is 1)
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
	if stream_distance(x, z) < 5.0 or pond_distance(x, z) < 3.0:
		return true
	if Vector2(x - CASTLE.x, z - CASTLE.z).length() < 42.0 or Vector2(x - VILLAGE.x, z - VILLAGE.z).length() < 22.0:
		return true
	if Vector2(x - MILL.x, z - MILL.z).length() < 10.0:
		return true
	if Vector2(x - 12.0, z - 18.0).length() < 9.0:
		return true  # Marigold's stall
	if Vector2(x + 30.0, z + 28.0).length() < 10.0 or Vector2(x + 54.0, z + 20.0).length() < 5.0 or Vector2(x + 40.0, z - 24.0).length() < 13.0:
		return true  # the wheat field, the log pile, the sheep's pasture (villagers.gd, animals.gd)
	for den in [Vector2(80, -32), Vector2(-24, 92), Vector2(-112, -20)]:  # the wolf dens (creatures.gd)
		if Vector2(x, z).distance_to(den) < 7.5:
			return true
	if Vector2(x + 80.0, z + 80.0).length() < 17.0 or Vector2(x - 96.0, z - 12.0).length() < 10.0:
		return true  # the old barrow and the troll's camp (creatures.gd)
	for chest in [Vector2(-92, -66), Vector2(18, -150), Vector2(84, 66), Vector2(-120, 30), Vector2(110, -40),
			Vector2(-30, 120), Vector2(60, 110), Vector2(-60, -118)]:  # treasure chests (gathering.gd CHESTS)
		if Vector2(x, z).distance_to(chest) < 3.5:
			return true
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
	var painted: ArrayMesh = W.load_mesh("pine")  # made in Blender (tools/blender/pine.py)
	if painted:
		painted.surface_set_material(0, painted_tree_material())
		return painted
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.24
	trunk.height = 2.0
	trunk.radial_segments = 10
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, 1.0, 0)))
	var roots := CylinderMesh.new()  # a flare of roots where it meets the ground
	roots.top_radius = 0.24
	roots.bottom_radius = 0.24 * 1.9
	roots.height = 0.45
	roots.radial_segments = 10
	st.append_from(roots, 0, Transform3D(Basis(), Vector3(0, 0.2, 0)))
	st.commit(mesh)
	mesh.surface_set_material(0, tree_material(Color("#4a3423")))
	st = SurfaceTool.new()
	for k in 7:  # broad overlapping boughs keep the crown full between its tiers
		var cone := CylinderMesh.new()
		cone.top_radius = maxf(0.08, 0.34 - k * 0.035)
		cone.bottom_radius = 2.25 - k * 0.31
		cone.height = 2.2 - k * 0.15
		cone.radial_segments = 14
		st.append_from(cone, 0, Transform3D(Basis(Vector3.UP, k * 0.38), Vector3(0, 1.9 + k * 0.72, 0)))
	st.commit(mesh)
	mesh.surface_set_material(1, foliage_material(Color("#2f5a32"), 1.2, 7.5))
	return mesh


func oak_mesh() -> ArrayMesh:
	var painted: ArrayMesh = W.load_mesh("oak")  # made in Blender (tools/blender/oak.py), colours painted into the vertices
	if painted:
		painted.surface_set_material(0, painted_tree_material())
		return painted
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.22
	trunk.bottom_radius = 0.34
	trunk.height = 2.6
	trunk.radial_segments = 10
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, 1.3, 0)))
	var roots := CylinderMesh.new()  # a flare of roots where it meets the ground
	roots.top_radius = 0.34
	roots.bottom_radius = 0.34 * 1.9
	roots.height = 0.45
	roots.radial_segments = 10
	st.append_from(roots, 0, Transform3D(Basis(), Vector3(0, 0.2, 0)))
	for side in [-1, 1]:  # visible limbs support the broad crown instead of leaving a bare pole
		var branch := CylinderMesh.new()
		branch.top_radius = 0.07
		branch.bottom_radius = 0.13
		branch.height = 1.5
		branch.radial_segments = 8
		var tilt := Basis(Vector3.FORWARD, side * 0.85) * Basis(Vector3.RIGHT, -0.55)
		st.append_from(branch, 0, Transform3D(tilt, Vector3(side * 0.62, 2.45, 0)))
		st.append_from(branch, 0, Transform3D(tilt.rotated(Vector3.UP, PI * 0.72), Vector3(side * 0.58, 2.8, 0.2)))
	st.commit(mesh)
	mesh.surface_set_material(0, tree_material(Color("#53392a")))
	st = SurfaceTool.new()
	for blob in [[Vector3(0, 3.4, 0), 1.9], [Vector3(0.9, 3.0, 0.3), 1.3], [Vector3(-0.8, 3.1, -0.4), 1.35], [Vector3(0.1, 4.2, -0.2), 1.25],
			[Vector3(-0.3, 3.7, 0.9), 1.15], [Vector3(0.7, 4.0, -0.8), 1.05], [Vector3(-1.1, 3.9, 0.3), 0.95]]:  # a fuller, lumpier crown
		var s := SphereMesh.new()
		s.radius = blob[1]
		s.height = blob[1] * 1.7
		s.radial_segments = 14
		s.rings = 9
		st.append_from(s, 0, Transform3D(Basis(), blob[0]))
	st.commit(mesh)
	mesh.surface_set_material(1, foliage_material(Color("#40722f"), 1.6, 5.4))
	return mesh


const FOLIAGE_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec3 leaf : source_color;
uniform float low = 1.0;  // the crown's bottom and top (model space): darker below, sunlit on top
uniform float high = 6.0;
varying float up;
varying vec3 wp;
void vertex() {
	up = clamp((VERTEX.y - low) / (high - low), 0.0, 1.0);
	wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float sway = sin(TIME * 1.1 + wp.x * 0.13 + wp.z * 0.11) + 0.4 * sin(TIME * 2.3 + wp.z * 0.3);
	VERTEX.x += sway * 0.07 * up * up;  // the top moves, the bottom stays put
	VERTEX.z += sway * 0.04 * up * up;
}
void fragment() {
	vec3 c = leaf * COLOR.rgb;  // (COLOR = this tree's shade)
	float tint = fract(sin(dot(wp.xz, vec2(12.9898, 78.233))) * 43758.5453);
	c = mix(c, c * vec3(1.08, 1.02, 0.78), tint * 0.5);  // some trees a little yellower
	c *= mix(0.62, 1.12, up);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	BACKLIGHT = vec3(0.12, 0.18, 0.06);
}
"""


const PAINTED_TREE_SHADER := """
shader_type spatial;
render_mode cull_back;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float up = clamp(VERTEX.y / 5.0, 0.0, 1.0);  // the top of the tree moves in the wind, the foot stays put
	float sway = sin(TIME * 1.1 + wp.x * 0.13 + wp.z * 0.11) + 0.4 * sin(TIME * 2.3 + wp.z * 0.3);
	VERTEX.x += sway * 0.07 * up * up;
	VERTEX.z += sway * 0.04 * up * up;
}
void fragment() {
	vec3 c = COLOR.rgb;  // painted in Blender, times this tree's own shade (the MultiMesh instance colour)
	float tint = fract(sin(dot(wp.xz, vec2(12.9898, 78.233))) * 43758.5453);
	c *= mix(vec3(1.0), vec3(1.1, 1.02, 0.8), tint * 0.5);  // some trees a little yellower
	ALBEDO = c;
	ROUGHNESS = 0.85;
	BACKLIGHT = vec3(0.1, 0.15, 0.05);
}
"""


func painted_tree_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = PAINTED_TREE_SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	return m


## Leaves: darker low in the crown, sunlit on top, each tree its own shade, swaying a little in the wind.
func foliage_material(color: Color, low: float, high: float) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = FOLIAGE_SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("leaf", color)
	m.set_shader_parameter("low", low)
	m.set_shader_parameter("high", high)
	return m


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
	out.append_array(boulders())
	var bush_mm := bushes()
	if bush_mm:
		out.append(bush_mm)
	return out


## Boulders: three rock shapes made in Blender (rock1..3.glb, moss on top), scattered over the land; the old
## squashed spheres if the files are missing. Returns one MultiMesh per shape.
func boulders() -> Array:
	var shapes := []
	for name in ["rock1", "rock2", "rock3"]:
		var rock: ArrayMesh = W.load_mesh(name)
		if rock:
			var m := StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			m.roughness = 1.0
			rock.surface_set_material(0, m)
			shapes.append(rock)
	var fallback := shapes.is_empty()
	if fallback:
		var sphere := SphereMesh.new()
		sphere.radial_segments = 7
		sphere.rings = 4
		var m2 := StandardMaterial3D.new()
		m2.albedo_color = Color("#7a7670")
		m2.vertex_color_use_as_albedo = true
		m2.roughness = 1.0
		sphere.material = m2
		shapes.append(sphere)
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
	var out := []
	for k in shapes.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = shapes[k]
		var mine := []
		for i in spots.size():
			if i % shapes.size() == k:
				mine.append(spots[i])
		mm.instance_count = mine.size()
		for i in mine.size():
			var s := rng.randf_range(0.5, 2.6)
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(0.9, 1.4), s * (0.75 if fallback else rng.randf_range(0.8, 1.2)), s))
			mm.set_instance_transform(i, Transform3D(basis, mine[i] - Vector3(0, s * (0.18 if fallback else 0.12), 0)))
			mm.set_instance_color(i, Color.WHITE.darkened(rng.randf_range(0.0, 0.3)))
		out.append(mm)
	return out


## Bushes (Blender: bush.glb, some with red berries) tucked along the edges of the woods and over the hills.
func bushes() -> MultiMesh:
	var bush: ArrayMesh = W.load_mesh("bush")
	if bush == null:
		return null
	bush.surface_set_material(0, painted_tree_material())
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var spots := []
	var tries := 0
	while spots.size() < 320 and tries < 6000:
		tries += 1
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf_range(0.05, 1.0)) * 185.0
		var x := cos(a) * r
		var z := sin(a) * r
		if r < 30.0 or keep_clear(x, z):
			continue
		var forest := noise.get_noise_2d(x * 0.6 + 50.0, z * 0.6)  # more of them where the woods are
		if forest < -0.15 and rng.randf() < 0.9:
			continue
		var h := height_at(x, z)
		if h > 30.0:
			continue
		spots.append(Vector3(x, h, z))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bush
	mm.instance_count = spots.size()
	for i in spots.size():
		var s := rng.randf_range(0.7, 1.5)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s)), spots[i] - Vector3(0, 0.05, 0)))
		mm.set_instance_color(i, Color.WHITE.darkened(rng.randf_range(0.0, 0.25)))
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
		var side := d.cross(Vector3.UP) * 0.018
		var lean := d * 0.07
		verts.append_array([-side, side, Vector3(0, 0.3 - k * 0.05, 0) + lean])
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
		var tuft: ArrayMesh = W.load_mesh("grass_tuft")  # made in Blender (tools/blender/grass.py)
		mm.mesh = tuft if tuft else blade_mesh()
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		var spots := []
		while spots.size() < 23000:
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * (FLAT + 14.0)
			var x := cos(a) * r
			var z := sin(a) * r
			if road_distance(x, z) < ROAD_WIDTH * 0.8 or Vector2(x - VILLAGE.x, z - VILLAGE.z).length() < 24.0:
				continue
			spots.append(Vector3(x, height_at(x, z), z))
		var extra := 0  # the castle hill and the road up to it
		while extra < 12000:
			var x := rng.randf_range(-48.0, 48.0)
			var z := rng.randf_range(-182.0, -66.0)
			var dc := Vector2(x - CASTLE.x, z - CASTLE.z).length()
			if absf(x - CASTLE.x) < 17.5 and absf(z - CASTLE.z) < 17.5:
				continue  # not inside the walls
			if dc > 46.0 and absf(x) > 22.0:
				continue  # (keep to the hill and a band along the road)
			if road_distance(x, z) < ROAD_WIDTH * 0.8:
				continue
			var h := height_at(x, z)
			if absf(height_at(x + 1.0, z) - h) > 0.8 or absf(height_at(x, z + 1.0) - h) > 0.8:
				continue  # too steep
			spots.append(Vector3(x, h, z))
			extra += 1
		extra = 0  # scatter grass over the remaining walkable hills, not just the meadow and castle road
		while extra < 36000:
			var x := rng.randf_range(-SIZE * 0.5, SIZE * 0.5)
			var z := rng.randf_range(-SIZE * 0.5, SIZE * 0.5)
			if road_distance(x, z) < ROAD_WIDTH * 0.8:
				continue
			var h := height_at(x, z)
			if h > 42.0 or absf(height_at(x + 1.0, z) - h) > 0.8 or absf(height_at(x, z + 1.0) - h) > 0.8:
				continue  # keep the exposed rock faces and snowy peaks bare
			spots.append(Vector3(x, h, z))
			extra += 1
		spots = spots.filter(func(p): return stream_distance(p.x, p.z) > BANK_OUT - 0.4 and pond_distance(p.x, p.z) > 0.5)  # (no grass underwater)
		if tuft:  # each tuft is several blades, so about half as many are needed
			var thinned := []
			for i in range(0, spots.size(), 2):
				thinned.append(spots[i])
			spots = thinned
		mm.instance_count = spots.size()
		for i in spots.size():
			if tuft:
				var sc := rng.randf_range(0.85, 1.5)
				mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc * rng.randf_range(0.8, 1.3), sc)), spots[i]))
				var tint := Color(rng.randf_range(0.8, 1.1), rng.randf_range(0.85, 1.05), rng.randf_range(0.7, 1.0))  # a patch a little yellower or bluer
				mm.set_instance_color(i, tint.darkened(rng.randf_range(0.0, 0.18)))
				continue
			var s := rng.randf_range(0.65, 1.1)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.4), s)), spots[i]))
			var g := Color("#3e6a20").lerp(Color("#5e8a2a"), rng.randf()).darkened(rng.randf_range(0.0, 0.25))
			mm.set_instance_color(i, g)
		ctx["grass_cache"] = mm
		ctx["grass_version"] = VERSION
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shader := Shader.new()
	shader.code = TUFT_SHADER if mm.mesh != null and not (mm.mesh.get_surface_count() == 1 and mm.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] == null) else GRASS_SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	node.material_override = m
	add_child(node)
	add_flowers()


## Wildflowers (white, yellow, purple, red; Blender: flower_*.glb) dotted over the meadow, the village green and the
## castle hill, thicker in clumps.
func add_flowers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var names := ["flower_white", "flower_yellow", "flower_purple", "flower_red"]
	for name in names:
		var mesh: ArrayMesh = W.load_mesh(name)
		if mesh == null:
			continue
		var shader := Shader.new()
		shader.code = TUFT_SHADER
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("height", 0.45)
		mesh.surface_set_material(0, m)
		var spots := []
		var tries := 0
		while spots.size() < 900 and tries < 10000:
			tries += 1
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * (FLAT + 18.0)
			var x := cos(a) * r
			var z := sin(a) * r
			if road_distance(x, z) < ROAD_WIDTH * 0.9 or keep_clear(x, z):
				continue
			if noise.get_noise_2d(x * 1.3 + 400.0 + names.find(name) * 50.0, z * 1.3) < 0.1:  # clumps, not an even sprinkle
				continue
			spots.append(Vector3(x, height_at(x, z), z))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = spots.size()
		for i in spots.size():
			var sc := rng.randf_range(1.4, 2.1)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), spots[i]))
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = 60.0
		add_child(node)


const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;
uniform vec3 shallow : source_color = vec3(0.30, 0.72, 0.68);
uniform vec3 deep : source_color = vec3(0.06, 0.34, 0.48);
uniform float flow_speed = 0.35;
void fragment() {
	float edge = abs(UV.y - 0.5) * 2.0;  // 0 in the middle of the stream .. 1 at the bank
	float u = UV.x - TIME * flow_speed;
	float a = sin(u * 7.0 + sin(UV.y * 9.0 + TIME * 0.8) * 1.6);
	float b = sin(u * 13.0 - UV.y * 11.0 + TIME * 0.6);
	float ripple = (a + b) * 0.25 + 0.5;
	vec3 col = mix(deep, shallow, smoothstep(0.05, 0.95, edge));
	col += vec3(0.10, 0.12, 0.10) * smoothstep(0.78, 0.98, ripple);  // little glints on the ripples
	float foam = smoothstep(0.80, 1.0, edge) * (0.55 + 0.45 * sin(UV.x * 38.0 + TIME * 2.2 + sin(UV.y * 20.0) * 2.0));
	col = mix(col, vec3(0.94, 0.97, 0.95), foam * 0.75);
	ALBEDO = col;
	ALPHA = mix(0.82, 0.92, edge) * (1.0 - smoothstep(0.96, 1.0, edge) * 0.4);
	ROUGHNESS = mix(0.03, 0.12, ripple);
	SPECULAR = 0.9;
	NORMAL_MAP = vec3(0.5 + (ripple - 0.5) * 0.14, 0.5 + (b * 0.5) * 0.06, 1.0);  // tiny ripples bend the reflections
	NORMAL_MAP_DEPTH = 1.0;
}
"""


## The water: a ribbon along the stream and a disc for the pond, flat at WATER_Y (parts of it lie under the banks and are
## hidden by the ground), with moving ripples, glints and foam at the edges (WATER_SHADER), and reeds along the banks.
func add_water() -> void:
	var pts := stream_points()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var run := 0.0
	var half := 3.1
	for i in pts.size():
		var a: Vector2 = pts[maxi(i - 1, 0)]
		var b: Vector2 = pts[mini(i + 1, pts.size() - 1)]
		var t := (b - a).normalized()
		var side := Vector2(-t.y, t.x)
		if i > 0:
			run += (pts[i] as Vector2).distance_to(pts[i - 1])
		var wide := half * (1.0 if i < pts.size() - 4 else lerpf(1.0, 1.6, float(i - (pts.size() - 4)) / 3.0))  # opens into the pond
		for s in [-1.0, 1.0]:
			var q: Vector2 = (pts[i] as Vector2) + side * wide * s
			verts.append(Vector3(q.x, WATER_Y, q.y))
			normals.append(Vector3.UP)
			uvs.append(Vector2(run / 5.0, 0.5 + 0.5 * s))
		if i > 0:
			var k := (i - 1) * 2
			indices.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var shader := Shader.new()
	shader.code = WATER_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	# the pond: a disc with the same look (UV.y runs from the middle to the rim)
	var pv := PackedVector3Array()
	var pn := PackedVector3Array()
	var pu := PackedVector2Array()
	var pi := PackedInt32Array()
	pv.append(Vector3(POND.x, WATER_Y, POND.z))
	pn.append(Vector3.UP)
	pu.append(Vector2(0.0, 0.5))
	var seg := 28
	for k in seg + 1:
		var ang := k * TAU / seg
		var rr := POND_R + 0.9 + 0.5 * sin(ang * 3.0)
		pv.append(Vector3(POND.x + cos(ang) * rr, WATER_Y, POND.z + sin(ang) * rr))
		pn.append(Vector3.UP)
		pu.append(Vector2(float(k) * 0.4, 1.0))
		if k > 0:
			pi.append_array([0, k + 1, k])
	var parrays := []
	parrays.resize(Mesh.ARRAY_MAX)
	parrays[Mesh.ARRAY_VERTEX] = pv
	parrays[Mesh.ARRAY_NORMAL] = pn
	parrays[Mesh.ARRAY_TEX_UV] = pu
	parrays[Mesh.ARRAY_INDEX] = pi
	var pmesh := ArrayMesh.new()
	pmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, parrays)
	var pnode := MeshInstance3D.new()
	pnode.mesh = pmesh
	pnode.material_override = mat
	pnode.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pnode)
	add_reeds()


## Reeds and cattails (Blender: reeds.glb, reeds_plain.glb) standing in clumps along both banks and round the pond.
func add_reeds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var pts := stream_points()
	for name in ["reeds", "reeds_plain"]:
		var mesh: ArrayMesh = W.load_mesh(name)
		if mesh == null:
			continue
		var shader := Shader.new()
		shader.code = TUFT_SHADER
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("height", 1.6)
		mesh.surface_set_material(0, m)
		var spots := []
		for i in range(2, pts.size() - 1):
			if rng.randf() < (0.55 if name == "reeds" else 0.4):
				var a: Vector2 = pts[i - 1]
				var b: Vector2 = pts[i + 1]
				var side := (b - a).normalized().rotated(PI / 2.0)
				var off := (3.0 if rng.randf() < 0.5 else -3.0) + rng.randf_range(-0.8, 1.0)
				var q: Vector2 = (pts[i] as Vector2) + side * off
				spots.append(Vector3(q.x, height_at(q.x, q.y), q.y))
		for k in 18:  # round the pond
			var ang := rng.randf() * TAU
			var rr := POND_R + rng.randf_range(-0.2, 1.8)
			var qx := POND.x + cos(ang) * rr
			var qz := POND.z + sin(ang) * rr
			spots.append(Vector3(qx, height_at(qx, qz), qz))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = spots.size()
		for i in spots.size():
			var sc := rng.randf_range(0.8, 1.4)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), spots[i] - Vector3(0, 0.12, 0)))
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = 90.0
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
