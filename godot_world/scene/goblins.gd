extends Node3D
## A goblin army, called up on request ([goblins] / [goblins 20] / [goblins away]). They appear in a ring far
## around the wanderer, march in and surround them, shuffling about and glaring. They are harmless until you
## attack one: then the army fights back (state["goblins_angry"]), a few at a time.
## Each attack is telegraphed: the goblin winds up (arms raised, eyes burn red, a "!" over its head), then
## lunges. Block it (right click with the sword) or parry it (block just before it lands; see combat.gd).
## Kinds: grunts (3 hits), spear goblins (longer reach, slower wind-up) and big brutes (8 hits, hits don't
## stop their wind-up, and some of their attacks, marked with a red "!!", can only be parried).
## The count is kept in state["goblins"] so they survive reloads.

const DEFAULT_COUNT := 12
const MAX_COUNT := 40
const SPAWN_RADIUS := 18.0
const RING_RADIUS := 4.5  # how close they stop to you while they just glare
const FIGHT_RADIUS := 5.0  # where they circle while they fight
const MARCH_SPEED := 3.2
# per kind: health, reach of the attack, wind-up seconds, damage, speed factor, chance of an unblockable attack
const KINDS := {
	"grunt": {"hp": 3, "reach": 1.6, "windup": 0.65, "damage": 8.0, "speed": 1.0, "red": 0.0},
	"spear": {"hp": 3, "reach": 2.5, "windup": 0.85, "damage": 12.0, "speed": 0.95, "red": 0.2},
	"brute": {"hp": 8, "reach": 2.0, "windup": 1.05, "damage": 24.0, "speed": 0.75, "red": 0.5},
}

var ctx: Dictionary
var W
var army := []  # one dictionary per goblin (see add_goblin)
var dying := []  # [node, seconds, direction knocked, size] goblins that were just beaten
var bits := []  # little flying cubes from hits: {node, vel, age, size}
var next_attack := 1.0  # seconds until another goblin may start an attack


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	for i in int(ctx.state.get("goblins", 0)):
		add_goblin(i, int(ctx.state["goblins"]))


func angry() -> bool:
	return ctx.state.get("goblins_angry", false) and not army.is_empty()


## The player fainted: the army stops fighting and goes back to glaring.
func calm() -> void:
	ctx.state["goblins_angry"] = false
	for g in army:
		end_attack(g)


func kind_for(i: int) -> String:
	if i % 5 == 4:
		return "brute"
	return "spear" if i % 3 == 0 else "grunt"


func add_goblin(i: int, total: int) -> void:
	var kind := kind_for(i)
	var node := Node3D.new()
	var angle := TAU * i / maxf(total, 1) + randf_range(-0.1, 0.1)
	var from: Vector3 = ctx.player.position
	node.position = Vector3(from.x + cos(angle) * SPAWN_RADIUS * randf_range(0.9, 1.3), 0, from.z + sin(angle) * SPAWN_RADIUS * randf_range(0.9, 1.3))
	add_child(node)
	var skin := Color.from_hsv(randf_range(0.24, 0.31), randf_range(0.5, 0.65), randf_range(0.5, 0.65))
	var cloth := Color.from_hsv(randf_range(0.05, 0.11), 0.5, randf_range(0.25, 0.4))
	var s := randf_range(0.85, 1.15)  # each a bit different in size
	if kind == "brute":  # big, darker and armoured
		s = randf_range(1.4, 1.55)
		skin = skin.darkened(0.3)
		cloth = Color("#3a3f47")
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
	if kind == "brute":  # shoulder plates, standing proud of the tunic
		for side in [-1, 1]:
			W.box(node, Vector3(side * 0.2, 1.06, 0), Vector3(0.2, 0.06, 0.3), Color("#6a707a"))
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
	var eyes := []
	for side in [-1, 1]:  # glowing eyes (they turn red while it winds up an attack)
		eyes.append(W.box(head, Vector3(side * 0.09, 0.04, -0.175), Vector3(0.07, 0.05, 0.02), Color("#ffe14d")))
	W.box(head, Vector3(0, -0.13, -0.175), Vector3(0.18, 0.03, 0.02), Color("#2a0a0a"))  # grumpy mouth
	for side in [-1, 1]:  # long pointy ears
		var ear: MeshInstance3D = W.box(head, Vector3(side * 0.29, 0.06, 0), Vector3(0.24, 0.07, 0.05), skin)
		ear.rotation_degrees.z = side * -18
	if kind == "spear":
		var spear := Node3D.new()
		spear.position = Vector3(0, -0.4, -0.08)
		arms[1][0].add_child(spear)
		# shaft ends exactly where the head starts (y 1.15); head is thicker than the shaft so no faces overlap
		W.box(spear, Vector3(0, 0.425, 0), Vector3(0.03, 1.45, 0.03), Color("#7a5a38"))
		W.box(spear, Vector3(0, 1.25, 0), Vector3(0.07, 0.2, 0.045), Color("#aab0b8"))
	elif kind == "brute":  # a club: a handle with a heavy head on top
		var club := Node3D.new()
		club.position = Vector3(0, -0.45, -0.06)
		arms[1][0].add_child(club)
		W.box(club, Vector3(0, 0.2, 0), Vector3(0.05, 0.5, 0.05), Color("#5a3d24"))
		W.box(club, Vector3(0, 0.55, 0), Vector3(0.13, 0.2, 0.13), Color("#6b4a2f"))
	var mark := Label3D.new()  # "!" over its head while it winds up
	mark.position = Vector3(0, 1.75, 0)
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.font_size = 96
	mark.pixel_size = 0.004
	mark.outline_size = 24
	mark.visible = false
	node.add_child(mark)
	var bar := Label3D.new()  # health left, shown once it has been hurt
	bar.position = Vector3(0, 1.58, 0)
	bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bar.font_size = 48
	bar.pixel_size = 0.003
	bar.outline_size = 12
	bar.modulate = Color("#ff6a5a")
	bar.visible = false
	node.add_child(bar)
	var k: Dictionary = KINDS[kind]
	army.append({"node": node, "legs": legs, "arms": arms, "eyes": eyes, "mark": mark, "bar": bar, "kind": kind,
		"slot": TAU * i / maxf(total, 1), "phase": randf() * TAU, "speed": MARCH_SPEED * randf_range(0.85, 1.15) * k.speed,
		"hp": k.hp, "stun": 0.0, "vel": Vector3.ZERO, "squash": 0.0, "base": s,
		"state": "ring", "t": 0.0, "red": false, "riposte": false, "orbit": 1.0 if randf() < 0.5 else -1.0})


## A little burst of coloured cubes flying out from `pos` (hit sparks, goblin dust); they fall, then shrink away.
func burst(pos: Vector3, color: Color, count: int, speed: float) -> void:
	for i in count:
		var size := randf_range(0.05, 0.11)
		var bit: MeshInstance3D = W.box(self, pos, Vector3.ONE * size, color.lightened(randf_range(-0.15, 0.2)))
		var dir := Vector3(randf_range(-1, 1), randf_range(0.3, 1.2), randf_range(-1, 1)).normalized()
		bits.append({"node": bit, "vel": dir * speed * randf_range(0.5, 1.0), "age": 0.0, "size": size})


## A sword swing from `from` toward `forward`: every goblin within `reach` and in front is hurt and knocked back.
## `heavy` (the last hit of a combo) knocks harder and breaks even a brute's wind-up. Returns how many it hit.
func hit(from: Vector3, forward: Vector3, reach: float, arc: float, damage := 1, heavy := false) -> int:
	var fwd := Vector3(forward.x, 0, forward.z).normalized()
	var hits := 0
	var killed := 0
	for g in army.duplicate():
		var node: Node3D = g.node
		var d := Vector3(node.position.x - from.x, 0, node.position.z - from.z)
		if d.length() > reach + 0.2 * g.base or d.length() > 0.01 and d.normalized().dot(fwd) < arc:
			continue
		var away := d.normalized() if d.length() > 0.01 else fwd
		hits += 1
		if hurt(g, from, away, damage, heavy):
			killed += 1
	if killed > 0:
		report_kills()
	return hits


## One goblin takes `damage`: shoved away, squashed, sparks; if its health is gone it is beaten. True if beaten.
## A goblin you just parried takes triple damage. Hits stop a wind-up, except a brute's (unless `heavy`).
func hurt(g: Dictionary, from: Vector3, away: Vector3, damage: int, heavy := false) -> bool:
	var node: Node3D = g.node
	var combat = ctx.parts.get("combat")
	if g.riposte:
		damage *= 3
		g.riposte = false
		if combat:
			combat.call_out("CRITICAL!", Color("#ff7aff"))
	g.hp -= damage
	ctx.state["goblins_angry"] = true  # you started it
	var brute: bool = g.kind == "brute"
	if not brute or heavy or g.stun > 0.0:
		g.stun = maxf(g.stun, 0.45 if heavy else 0.3)
		g.vel = away * (8.0 if heavy else 5.0) / (2.0 if brute else 1.0)
		if g.state in ["approach", "windup", "strike"]:
			end_attack(g)  # interrupted
	else:
		g.vel = away * 1.5  # a brute shrugs off light hits mid-swing
	g.squash = 1.0
	W.face(node, from)  # turns to face you as it is hit
	burst(node.position + Vector3(0, 0.9 * g.base, 0), Color("#d8f06a"), 6 + damage * 2, 3.0)
	if combat:
		combat.sfx("slash", 0.8 if brute else 1.0)
		combat.hitstop(0.05 + 0.02 * damage)
		combat.shake(0.12 + 0.05 * damage)
	if g.hp > 0:
		var full: int = KINDS[g.kind].hp
		g.bar.text = "%d/%d" % [g.hp, full]
		g.bar.visible = true
		return false
	army.erase(g)
	g.mark.visible = false
	g.bar.visible = false
	dying.append([node, 0.0, away, g.base])
	burst(node.position + Vector3(0, 0.7 * g.base, 0), Color("#7bd45a"), 20 if brute else 14, 4.5)
	return true


func report_kills() -> void:
	ctx.state["goblins"] = army.size()
	if army.is_empty():
		ctx.state["goblins_angry"] = false
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
	ctx.state["goblins_angry"] = false


# --- fighting: one goblin at a time (a few in a big army) steps in, winds up and strikes -----------------

func attackers() -> int:
	var n := 0
	for g in army:
		if g.state in ["approach", "windup", "strike"]:
			n += 1
	return n


## Pick a goblin to attack next; mostly one you can see, so attacks from behind are the exception.
func pick_attacker() -> void:
	var player: Vector3 = ctx.player.position
	var fwd: Vector3 = -W.camera.global_basis.z
	var seen := []
	var others := []
	for g in army:
		if g.state != "ring" or g.stun > 0.0:
			continue
		var d: Vector3 = g.node.position - player
		var ahead := Vector2(fwd.x, fwd.z).normalized().dot(Vector2(d.x, d.z).normalized()) > 0.3
		(seen if ahead else others).append(g)
	var pool: Array = seen if not seen.is_empty() and (others.is_empty() or randf() < 0.8) else others
	if pool.is_empty():
		return
	var g: Dictionary = pool.pick_random()
	g.state = "approach"
	g.t = 0.0
	g.red = randf() < KINDS[g.kind].red


func end_attack(g: Dictionary) -> void:
	g.state = "ring"
	g.t = 0.0
	g.mark.visible = false
	g.red = false
	for e in g.eyes:
		e.material_override = W.mat(Color("#ffe14d"))
	var p: Vector3 = ctx.player.position
	g.slot = atan2(g.node.position.z - p.z, g.node.position.x - p.x)  # back to the ring where it stands


## The strike lands (or misses): the player's combat part decides block / parry / hit.
func strike(g: Dictionary) -> void:
	var k: Dictionary = KINDS[g.kind]
	var p: Vector3 = ctx.player.position
	var node: Node3D = g.node
	var d := Vector2(p.x - node.position.x, p.z - node.position.z).length()
	var combat = ctx.parts.get("combat")
	g.state = "recover"
	g.t = 0.0
	g.mark.visible = false
	if combat == null or d > k.reach * g.base + 0.4 or absf(p.y - node.position.y) > 1.6:
		return  # missed: you stepped away (or jumped)
	match combat.incoming(node.position, k.damage, g.red):
		"parry":  # thrown off balance: stunned, and open to a critical hit
			g.stun = 1.5
			g.riposte = true
			g.vel = Vector3(node.position.x - p.x, 0, node.position.z - p.z).normalized() * 5.0
			burst(node.position + Vector3(0, 1.0 * g.base, 0), Color("#fff2a8"), 10, 4.0)
		"block":
			g.t = -0.3  # bounced off your guard: a longer recovery
			g.vel = Vector3(node.position.x - p.x, 0, node.position.z - p.z).normalized() * 2.5
			burst(node.position.lerp(p, 0.6) + Vector3(0, 1.1, 0), Color("#ffd24d"), 5, 2.5)


func update_attack(g: Dictionary, delta: float, player: Vector3) -> bool:
	var node: Node3D = g.node
	var k: Dictionary = KINDS[g.kind]
	var d := Vector3(player.x - node.position.x, 0, player.z - node.position.z)
	g.t += delta
	match g.state:
		"approach":  # step in until the player is just within reach
			if d.length() > k.reach * g.base * 0.8:
				node.position += d.normalized() * minf(d.length(), g.speed * 1.5 * delta)
				W.face(node, player)
				if g.t > 3.5:
					end_attack(g)
				return true
			g.state = "windup"
			g.t = 0.0
			g.mark.text = "!!" if g.red else "!"
			g.mark.modulate = Color("#ff3b3b") if g.red else Color("#fff2a8")
			g.mark.outline_modulate = Color("#3a0000") if g.red else Color("#2b1d12")
			g.mark.visible = true
			for e in g.eyes:
				e.material_override = W.mat(Color("#ff2a1a"))
		"windup":  # arms back, leaning, tracking you: the cue to block or parry
			W.face(node, player)
			var u := clampf(g.t / k.windup, 0.0, 1.0)
			var raise := deg_to_rad(-55.0 if g.kind == "spear" else -150.0) * ease(u, 0.4)
			g.arms[1][0].rotation.x = raise
			if g.kind != "spear":
				g.arms[0][0].rotation.x = raise
			node.rotation.x = 0.15 * u
			g.mark.scale = Vector3.ONE * (1.0 + 0.25 * sin(g.t * 18.0))
			if g.t >= k.windup:
				g.state = "strike"
				g.t = 0.0
		"strike":  # a quick lunge; the hit is decided at the end of it
			var u := clampf(g.t / 0.1, 0.0, 1.0)
			var swing := deg_to_rad(70.0 if g.kind == "spear" else 20.0)
			g.arms[1][0].rotation.x = swing
			if g.kind != "spear":
				g.arms[0][0].rotation.x = swing
			node.rotation.x = -0.25
			if d.length() > 0.9:
				node.position += d.normalized() * 6.0 * delta
			if u >= 1.0:
				strike(g)
		"recover":  # arms come down, then back to the ring
			var u := clampf(g.t / 0.6, 0.0, 1.0)
			for pair in g.arms:
				pair[0].rotation.x = lerpf(pair[0].rotation.x, 0.0, minf(delta * 6.0, 1.0))
			node.rotation.x = lerpf(-0.25, 0.0, u)
			if g.t >= 0.6:
				end_attack(g)
		_:
			return false
	return true


func _process(delta: float) -> void:
	if ctx.is_empty():
		return
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
	var fighting: bool = angry() and ctx.parts.has("combat")
	if fighting:  # the attack director: a few attackers at a time, with short gaps
		next_attack -= delta
		if next_attack <= 0.0 and attackers() < clampi(1 + army.size() / 8, 1, 2):
			pick_attacker()
			next_attack = randf_range(0.8, 1.8)
	for g in army:
		var node: Node3D = g.node
		node.position += g.vel * delta  # knockback, slowing down
		g.vel = g.vel.move_toward(Vector3.ZERO, 18.0 * delta)
		g.squash = maxf(g.squash - delta * 5.0, 0.0)
		node.scale = Vector3(1 + 0.18 * g.squash, 1 - 0.25 * g.squash, 1 + 0.18 * g.squash) * g.base
		if g.stun > 0.0:  # just got hit: dazed for a moment (wobbling when parried)
			g.stun -= delta
			node.rotation.z = sin(g.stun * 20.0) * 0.12 if g.riposte else 0.0
			continue
		node.rotation.z = 0.0
		if g.riposte:
			g.riposte = false  # the opening has passed
		if fighting and update_attack(g, delta, player):
			continue
		if g.state != "ring":
			end_attack(g)
		node.rotation.x = 0.0
		var radius := RING_RADIUS
		if fighting:  # circle slowly around you, waiting for a turn
			radius = FIGHT_RADIUS
			g.slot += g.orbit * 0.25 * delta
		var slot: float = g.slot
		var goal := Vector3(player.x + cos(slot) * radius, 0, player.z + sin(slot) * radius)
		var d := Vector3(goal.x - node.position.x, 0, goal.z - node.position.z)
		var moving := d.length() > 0.3
		if moving:
			node.position += d.normalized() * minf(d.length(), g.speed * delta)
			W.face(node, goal if not fighting else player)
		else:
			W.face(node, player)  # glare at you
		g.phase += delta * (11.0 if moving else 2.0)
		var swing := sin(g.phase) * deg_to_rad(35 if moving else 4)
		for pair in g.legs:
			pair[0].rotation.x = swing * pair[1]
		for pair in g.arms:
			pair[0].rotation.x = swing * pair[1]
		node.position.y = absf(sin(g.phase)) * 0.05 if moving else 0.0


func describe_goblins(from: Vector3) -> Array:
	if army.is_empty():
		return []
	if angry():
		return ["an army of %d little green goblins (some with spears, some big armoured brutes with clubs) fighting the wanderer %s; the wanderer started it" % [
			army.size(), W.where(from, ctx.player.position)]]
	return ["an army of %d little green goblins the wanderer called up, harmless but glaring, standing in a ring %s (they fight back if attacked)" % [
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
	W.show_notice("A goblin army marches in! (%d) Attack one and they fight back." % n, 4.0)
	return true
