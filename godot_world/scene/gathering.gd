extends Node3D
## Things to gather for the RPG (rpg.gd): silverleaf herbs glowing faintly green round the edge of the meadow,
## brown woodcap mushrooms under the trees (walk over either to pick it), rust-red iron ore rocks on the high
## slopes (press E next to one to mine it), and the miller's lost ring, which glints in the grass near the
## windmill while the quest "The Miller's Ring" is active. Picked things grow back after a while.

const HERBS := 16
const MUSHROOMS := 14
const ORE_ROCKS := 9
const REGROW := 120.0  # seconds before a herb, mushroom or ore rock comes back

var ctx: Dictionary
var W
var spots := []  # {kind, node, pos, gone}
var ring_node: Node3D
var ring_pos := Vector3.ZERO
var t := 0.0


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	var terrain = ctx.parts["terrain"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var placed := 0
	while placed < HERBS:  # at the edge of the meadow and just into the woods
		var a := rng.randf() * TAU
		var p := Vector3(cos(a), 0, sin(a)) * rng.randf_range(44.0, 70.0)
		if terrain.keep_clear(p.x, p.z):
			continue
		add_spot("herb", p)
		placed += 1
	placed = 0
	while placed < MUSHROOMS:  # deeper in the woods
		var a := rng.randf() * TAU
		var p := Vector3(cos(a), 0, sin(a)) * rng.randf_range(66.0, 105.0)
		if terrain.keep_clear(p.x, p.z):
			continue
		add_spot("mushroom", p)
		placed += 1
	placed = 0
	while placed < ORE_ROCKS:  # high slopes, north and east, where the hills turn to mountain
		var a := rng.randf_range(-PI * 0.95, PI * 0.2)  # from west-north-west round to south-east
		var p := Vector3(cos(a), 0, sin(a)) * rng.randf_range(95.0, 125.0)
		if terrain.keep_clear(p.x, p.z):
			continue
		add_spot("ore", p)
		placed += 1
	var mill: Vector3 = terrain.MILL
	ring_pos = mill + Vector3(rng.randf_range(-8, -4), 0, rng.randf_range(-7, 7))
	ring_pos.y = W.ground_y(ring_pos.x, ring_pos.z)
	ring_node = Node3D.new()
	ring_node.position = ring_pos
	add_child(ring_node)
	W.glow(ring_node, Vector3(0, 0.08, 0), Vector3(0.14, 0.04, 0.14), Color("#ffd24d"), 3.0, "sphere")
	W.light(ring_node, Vector3(0, 0.4, 0), Color("#ffe08a"), 0.6, 3.0)
	ring_node.visible = false  # (shown from _process once the quest is taken; rpg.gd is built after this part)


func add_spot(kind: String, p: Vector3) -> void:
	p.y = W.ground_y(p.x, p.z)
	var node := Node3D.new()
	node.position = p
	node.rotation.y = randf() * TAU
	add_child(node)
	match kind:
		"herb":  # a tuft of silver-green leaves with a faint glow
			for i in 5:
				var leaf: MeshInstance3D = W.box(node, Vector3(cos(i * 1.3) * 0.1, 0.16, sin(i * 1.3) * 0.1), Vector3(0.07, 0.32, 0.03), Color("#9fd8a0"))
				leaf.rotation = Vector3(cos(i * 1.3) * 0.5, i * 1.3, sin(i * 1.3) * 0.5)
			W.glow(node, Vector3(0, 0.34, 0), Vector3(0.08, 0.08, 0.08), Color("#8dffb0"), 2.0, "sphere")
		"mushroom":
			for i in 3:
				var o := Vector3(cos(i * 2.1) * 0.18, 0, sin(i * 2.1) * 0.18)
				var h := 0.12 + i * 0.04
				W.box(node, o + Vector3(0, h / 2.0, 0), Vector3(0.05, h, 0.05), Color("#efe6d0"))
				W.box(node, o + Vector3(0, h, 0), Vector3(0.2 - i * 0.03, 0.08, 0.2 - i * 0.03), Color("#7a4a2a"), "sphere")
		"ore":  # a grey boulder with rust-red veins
			var rock: MeshInstance3D = W.box(node, Vector3(0, 0.45, 0), Vector3(1.6, 1.1, 1.3), Color("#6e6862"), "sphere", true)
			rock.rotation.y = 0.4
			for i in 5:
				var vein: MeshInstance3D = W.box(node, Vector3(cos(i * 1.3) * 0.62, 0.35 + i * 0.09, sin(i * 1.3) * 0.5), Vector3(0.22, 0.12, 0.22), Color("#b5502a"))
				vein.rotation = Vector3(i, i * 2.0, 0)
	spots.append({"kind": kind, "node": node, "pos": p, "gone": 0.0})


func update_ring() -> void:
	var rpg = ctx.parts.get("rpg")
	var wanted: bool = rpg != null and ctx.state.has("rpg") and rpg.qstate("ring") == "active" and rpg.count("ring") == 0
	ring_node.visible = wanted


func interactables() -> Array:
	var out := []
	for s in spots:
		if s.kind == "ore" and s.gone <= 0.0:
			out.append({"pos": s.pos, "label": "Mine the iron ore", "act": mine.bind(s), "range": 2.6})
	return out


func mine(s: Dictionary) -> void:
	var rpg = ctx.parts.get("rpg")
	if not rpg or s.gone > 0.0:
		return
	rpg.give("ore", 1)
	take(s)


func take(s: Dictionary) -> void:
	s.gone = REGROW
	s.node.visible = false


func _process(delta: float) -> void:
	t += delta
	var rpg = ctx.parts.get("rpg")
	if not rpg:
		return
	var player: Vector3 = W.player.global_position
	for s in spots:
		if s.gone > 0.0:
			s.gone -= delta
			if s.gone <= 0.0:
				s.node.visible = true
			continue
		if s.kind == "ore":
			continue
		if Vector2(player.x - s.pos.x, player.z - s.pos.z).length() < 1.3 and absf(player.y - s.pos.y) < 2.0:
			rpg.give(s.kind, 1)
			take(s)
	update_ring()
	if ring_node.visible:
		ring_node.rotation.y += delta * 2.0
		ring_node.get_child(0).scale = Vector3(0.14, 0.04, 0.14) * (1.0 + sin(t * 6.0) * 0.25)  # it glints
		if Vector2(player.x - ring_pos.x, player.z - ring_pos.z).length() < 1.3:
			rpg.give("ring", 1)
			W.show_notice("You found the miller's ring in the grass!", 4.0)


func seen_from(from: Vector3, _viewer: Node) -> Array:
	var seen := ["glowing silverleaf herbs round the edge of the meadow, mushrooms in the woods, and iron ore rocks high on the slopes"]
	if ring_node and ring_node.visible:
		seen.append("something glinting in the grass near the windmill, %s" % W.where(from, ring_pos))
	return seen
