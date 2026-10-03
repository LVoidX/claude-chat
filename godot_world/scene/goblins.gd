extends Node3D
## A goblin army, called up on request ([goblins] / [goblins 20] / [goblins away]). They appear in a ring far
## around the wanderer, march in and surround them at a respectful distance, shuffling about and glaring.
## They are harmless. The count is kept in state["goblins"] so they survive reloads.

const DEFAULT_COUNT := 12
const MAX_COUNT := 40
const SPAWN_RADIUS := 18.0
const RING_RADIUS := 4.5  # how close they stop to you
const MARCH_SPEED := 3.2

var ctx: Dictionary
var W
const HEALTH := 3  # sword hits a goblin takes
var army := []  # [{node, legs, arms, slot (angle), phase, speed, hp, stun}]
var dying := []  # [node, seconds, direction knocked, size] goblins that were just beaten
var bits := []  # little flying cubes from hits: {node, vel, age, size}


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	for i in int(ctx.state.get("goblins", 0)):
		add_goblin(i, int(ctx.state["goblins"]))


func add_goblin(i: int, total: int) -> void:
	var node := Node3D.new()
	var angle := TAU * i / maxf(total, 1) + randf_range(-0.1, 0.1)
	var from: Vector3 = ctx.player.position
	node.position = Vector3(from.x + cos(angle) * SPAWN_RADIUS * randf_range(0.9, 1.3), 0, from.z + sin(angle) * SPAWN_RADIUS * randf_range(0.9, 1.3))
	add_child(node)
	var skin := Color.from_hsv(randf_range(0.24, 0.31), randf_range(0.5, 0.65), randf_range(0.5, 0.65))
	var cloth := Color.from_hsv(randf_range(0.05, 0.11), 0.5, randf_range(0.25, 0.4))
	var s := randf_range(0.85, 1.15)  # each a bit different in size
	node.scale = Vector3.ONE * s
	var legs := []
	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.13, 0.5, 0)
		node.add_child(leg)
		W.box(leg, Vector3(0, -0.22, 0), Vector3(0.14, 0.5, 0.16), skin.darkened(0.15))
		W.box(leg, Vector3(0, -0.47, -0.03), Vector3(0.17, 0.08, 0.24), Color("#2b1d14"))
		legs.append([leg, side])
	W.box(node, Vector3(0, 0.78, 0), Vector3(0.42, 0.5, 0.26), cloth)  # tunic
	W.box(node, Vector3(0, 0.55, 0), Vector3(0.45, 0.06, 0.29), Color("#4a3322"))  # belt
	var arms := []
	for side in [-1, 1]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.28, 0.98, 0)
		node.add_child(arm)
		W.box(arm, Vector3(0, -0.22, 0), Vector3(0.11, 0.5, 0.11), skin)
		arms.append([arm, -side])
	var head := Node3D.new()
	head.position = Vector3(0, 1.2, 0)
	node.add_child(head)
	W.box(head, Vector3(0, 0, 0), Vector3(0.36, 0.32, 0.34), skin)
	W.box(head, Vector3(0, -0.06, -0.19), Vector3(0.1, 0.14, 0.1), skin.darkened(0.1))  # big nose
	W.box(head, Vector3(-0.09, 0.04, -0.175), Vector3(0.07, 0.05, 0.02), Color("#ffe14d"))  # glowing eyes
	W.box(head, Vector3(0.09, 0.04, -0.175), Vector3(0.07, 0.05, 0.02), Color("#ffe14d"))
	W.box(head, Vector3(0, -0.13, -0.175), Vector3(0.18, 0.03, 0.02), Color("#2a0a0a"))  # grumpy mouth
	for side in [-1, 1]:  # long pointy ears
		var ear: MeshInstance3D = W.box(head, Vector3(side * 0.29, 0.06, 0), Vector3(0.24, 0.07, 0.05), skin)
		ear.rotation_degrees.z = side * -18
	if i % 3 == 0:  # some carry a little spear
		var spear := Node3D.new()
		spear.position = Vector3(0, -0.4, -0.08)
		arms[1][0].add_child(spear)
		# shaft ends exactly where the head starts (y 1.15); head is thicker than the shaft so no faces overlap
		W.box(spear, Vector3(0, 0.425, 0), Vector3(0.03, 1.45, 0.03), Color("#7a5a38"))
		W.box(spear, Vector3(0, 1.25, 0), Vector3(0.07, 0.2, 0.045), Color("#aab0b8"))
	army.append({"node": node, "legs": legs, "arms": arms, "slot": TAU * i / maxf(total, 1), "phase": randf() * TAU,
		"speed": MARCH_SPEED * randf_range(0.85, 1.15), "hp": HEALTH, "stun": 0.0,
		"vel": Vector3.ZERO, "squash": 0.0, "base": s})


## A little burst of coloured cubes flying out from `pos` (hit sparks, goblin dust); they fall, then shrink away.
func burst(pos: Vector3, color: Color, count: int, speed: float) -> void:
	for i in count:
		var size := randf_range(0.05, 0.11)
		var bit: MeshInstance3D = W.box(self, pos, Vector3.ONE * size, color.lightened(randf_range(-0.15, 0.2)))
		var dir := Vector3(randf_range(-1, 1), randf_range(0.3, 1.2), randf_range(-1, 1)).normalized()
		bits.append({"node": bit, "vel": dir * speed * randf_range(0.5, 1.0), "age": 0.0, "size": size})


## A sword swing from `from` toward `forward`: every goblin within `reach` and in front is hurt and knocked back.
func hit(from: Vector3, forward: Vector3, reach: float, arc: float) -> void:
	var fwd := Vector3(forward.x, 0, forward.z).normalized()
	var killed := 0
	for g in army.duplicate():
		var node: Node3D = g.node
		var d := Vector3(node.position.x - from.x, 0, node.position.z - from.z)
		if d.length() > reach or d.length() > 0.01 and d.normalized().dot(fwd) < arc:
			continue
		var away := d.normalized() if d.length() > 0.01 else fwd
		if hurt(g, from, away, 1):
			killed += 1
	if killed > 0:
		report_kills()


## One goblin takes `damage`: shoved away, squashed, sparks; if its health is gone it is beaten. True if beaten.
func hurt(g: Dictionary, from: Vector3, away: Vector3, damage: int) -> bool:
	var node: Node3D = g.node
	g.hp -= damage
	g.stun = 0.35
	g.vel = away * 6.0  # shoved back, slowing down
	g.squash = 1.0  # squashes flat for a moment
	W.face(node, from)  # turns to face you as it is hit
	burst(node.position + Vector3(0, 0.9 * g.base, 0), Color("#d8f06a"), 6, 3.0)
	if g.hp > 0:
		return false
	army.erase(g)
	dying.append([node, 0.0, away, g.base])
	burst(node.position + Vector3(0, 0.7 * g.base, 0), Color("#7bd45a"), 14, 4.5)
	return true


func report_kills() -> void:
	ctx.state["goblins"] = army.size()
	if army.is_empty():
		W.show_notice("You beat the whole goblin army!", 5.0)
	else:
		W.show_notice("Goblins left: %d" % army.size(), 3.0)


## A shot from `origin` along `dir` (unit), at most `max_dist` far (already cut short by walls). The nearest goblin
## the line passes through is hurt. Returns how far the shot actually travelled.
func shoot(origin: Vector3, dir: Vector3, max_dist: float, damage: int) -> float:
	var best = null
	var best_t := max_dist
	for g in army:
		var node: Node3D = g.node
		var centre: Vector3 = node.position + Vector3(0, 0.75 * g.base, 0)  # about the middle of its body
		var along := (centre - origin).dot(dir)
		if along < 0.0 or along > best_t:
			continue
		if (origin + dir * along).distance_to(centre) < 0.4 * g.base + 0.1:
			best = g
			best_t = along
	if best == null:
		return max_dist
	var away := Vector3(dir.x, 0, dir.z).normalized()
	if hurt(best, origin, away, damage):
		report_kills()
	return best_t


func clear_army() -> void:
	for g in army:
		g.node.queue_free()
	army.clear()
	for dead in dying:
		dead[0].queue_free()
	dying.clear()
	for bit in bits:
		bit.node.queue_free()
	bits.clear()
	ctx.state["goblins"] = 0


func _process(delta: float) -> void:
	var player: Vector3 = ctx.player.position
	for bit in bits.duplicate():  # sparks: fly, fall, bounce a little, then shrink away
		bit.age += delta
		bit.vel.y -= 14.0 * delta
		var n: Node3D = bit.node
		n.position += bit.vel * delta
		if n.position.y < bit.size / 2:
			n.position.y = bit.size / 2
			bit.vel = Vector3(bit.vel.x * 0.4, absf(bit.vel.y) * 0.3, bit.vel.z * 0.4)
		n.rotation += Vector3(bit.vel.z, bit.vel.x, 0) * delta * 3.0
		n.scale = Vector3.ONE * bit.size * clampf(1.0 - (bit.age - 0.6) / 0.4, 0.0, 1.0)
		if bit.age > 1.0:
			n.queue_free()
			bits.erase(bit)
	for dead in dying.duplicate():  # beaten goblins fly back, fall on their backs, lie there, then shrink away
		dead[1] += delta
		var t: float = dead[1]
		var node: Node3D = dead[0]
		node.rotation.x = deg_to_rad(90) * ease(minf(t / 0.35, 1.0), 2.0)
		node.position += dead[2] * maxf(5.0 - t * 14.0, 0.0) * delta  # slides back, slowing down
		node.position.y = sin(minf(t / 0.35, 1.0) * PI) * 0.4 + 0.12 * minf(t / 0.35, 1.0)  # a little hop, then lies flat
		node.scale = Vector3.ONE * dead[3] * clampf((1.9 - t) / 0.5, 0.0, 1.0)
		if t > 1.9:
			node.queue_free()
			dying.erase(dead)
	for g in army:
		var node: Node3D = g.node
		node.position += g.vel * delta  # knockback, slowing down
		g.vel = g.vel.move_toward(Vector3.ZERO, 18.0 * delta)
		g.squash = maxf(g.squash - delta * 5.0, 0.0)
		node.scale = Vector3(1 + 0.18 * g.squash, 1 - 0.25 * g.squash, 1 + 0.18 * g.squash) * g.base
		if g.stun > 0.0:  # just got hit: dazed for a moment
			g.stun -= delta
			continue
		var slot: float = g.slot
		var goal := Vector3(player.x + cos(slot) * RING_RADIUS, 0, player.z + sin(slot) * RING_RADIUS)
		var d := Vector3(goal.x - node.position.x, 0, goal.z - node.position.z)
		var moving := d.length() > 0.3
		if moving:
			node.position += d.normalized() * minf(d.length(), g.speed * delta)
			W.face(node, goal)
		else:
			W.face(node, player)  # glare at you
		g.phase += delta * (11.0 if moving else 2.0)
		var swing := sin(g.phase) * deg_to_rad(35 if moving else 4)
		for pair in g.legs:
			pair[0].rotation.x = swing * pair[1]
		for pair in g.arms:
			pair[0].rotation.x = swing * pair[1]
		node.position.y = absf(sin(g.phase)) * 0.05 if moving else 0.0


func seen_from(from: Vector3, _viewer: Node) -> Array:
	if army.is_empty():
		return []
	return ["an army of %d little green goblins the wanderer called up, harmless but glaring, standing in a ring %s" % [
		army.size(), W.where(from, ctx.player.position)]]


func handle(c: Dictionary) -> bool:
	if c.get("cmd", "") != "goblins":
		return false
	var args: Array = c.get("args", [])
	if "away" in args or "off" in args or "stop" in args:
		clear_army()
		W.show_notice("The goblins scurry off into the dark.", 3.0)
		return true
	var n := DEFAULT_COUNT
	for a in args:
		if str(a).is_valid_int():
			n = clampi(int(a), 1, MAX_COUNT)
	clear_army()
	ctx.state["goblins"] = n
	for i in n:
		add_goblin(i, n)
	W.show_notice("A goblin army marches in! (%d)" % n, 4.0)
	return true
