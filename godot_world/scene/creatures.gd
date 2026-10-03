extends Node3D
## Hostile creatures for the RPG (rpg.gd): wolf packs at three dens in the woods around the meadow, skeletons
## guarding the old barrow in the north-western woods, and a troll camped in the eastern forest.
## They wander near home, charge when you come close, bite or strike when in reach (a short wind-up first, so
## you can back off), and give up if you lead them too far from home. Hit them with the sword (hotbar key 2):
## hotbar.gd calls sword_hit(). When one dies it gives xp, sometimes gold, and drops loot you walk over to
## pick up; it comes back after a while. Nothing here is saved: a reload puts everyone back home.

const KINDS := {
	"wolf": {"name": "Wolf", "hp": 12, "dmg": 3, "speed": 6.0, "aggro": 13.0, "reach": 1.7, "cooldown": 1.6,
		"xp": 14, "gold": [0, 3], "loot": [["pelt", 0.65]], "respawn": 60.0, "bar_y": 1.3},
	"skeleton": {"name": "Skeleton", "hp": 24, "dmg": 6, "speed": 3.4, "aggro": 12.0, "reach": 1.9, "cooldown": 1.7,
		"xp": 28, "gold": [2, 8], "loot": [["bone", 0.75], ["potion", 0.12]], "respawn": 75.0, "bar_y": 2.25},
	"troll": {"name": "Gorrak the Troll", "hp": 170, "dmg": 15, "speed": 3.6, "aggro": 16.0, "reach": 3.2, "cooldown": 2.4,
		"xp": 260, "gold": [60, 60], "loot": [["tusk", 1.0], ["potion", 1.0]], "respawn": 600.0, "bar_y": 4.3},
}
const DENS := [Vector3(80, 0, -32), Vector3(-24, 0, 92), Vector3(-112, 0, -20)]  # three wolves each
const BARROW := Vector3(-80, 0, -80)  # the old burial mound, six skeletons
const TROLL_CAMP := Vector3(96, 0, 12)
const LEASH := 34.0  # how far they follow you from home
const WINDUP := 0.45  # seconds between starting an attack and the hit

var ctx: Dictionary
var W
var foes := []  # each: {kind, node, parts, home, hp, state, timer, ...}
var drops := []  # [node, item, count, age]
var numbers := []  # floating damage numbers: [Label3D, age]
var t := 0.0


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	for den in DENS:
		build_den(at_ground(den))
		for i in 3:
			spawn("wolf", at_ground(den + Vector3(cos(i * 2.1) * 3.0, 0, sin(i * 2.1) * 3.0)), at_ground(den))
	build_barrow(at_ground(BARROW))
	for i in 6:
		var a := i * TAU / 6.0
		spawn("skeleton", at_ground(BARROW + Vector3(cos(a) * 9.0, 0, sin(a) * 9.0)), at_ground(BARROW))
	build_camp(at_ground(TROLL_CAMP))
	spawn("troll", at_ground(TROLL_CAMP + Vector3(0, 0, 4)), at_ground(TROLL_CAMP))


func at_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, W.ground_y(p.x, p.z), p.z)


# --- the places ------------------------------------------------------------------------------------------

func build_den(at: Vector3) -> void:
	var den := Node3D.new()
	den.position = at
	add_child(den)
	var rock := Color("#6d6a64")
	for i in 5:  # a ring of boulders round a hollow, with gnawed bones
		var a := i * TAU / 5.0 + 0.4
		var b: MeshInstance3D = W.box(den, Vector3(cos(a) * 4.2, 0.5, sin(a) * 4.2), Vector3(1.8, 1.4, 1.5), rock.darkened(i * 0.05), "sphere", true)
		b.rotation.y = a
	for i in 4:
		var bone: MeshInstance3D = W.box(den, Vector3(randf_range(-1.5, 1.5), 0.05, randf_range(-1.5, 1.5)), Vector3(0.5, 0.07, 0.07), Color("#e6dcc0"))
		bone.rotation.y = randf() * TAU


func build_barrow(at: Vector3) -> void:
	var barrow := Node3D.new()
	barrow.position = at
	add_child(barrow)
	var stone: Material = ctx.parts["kit"].mat("stone") if ctx.parts.has("kit") else W.mat(Color("#77736c"))
	var mound: MeshInstance3D = W.box(barrow, Vector3(0, 0, 0), Vector3(10, 5, 12), Color("#4f6b3a"), "sphere", true)
	mound.position.y = 0.2
	for p in [[Vector3(-1.1, 1.1, 5.4), Vector3(0.6, 2.2, 0.6)], [Vector3(1.1, 1.1, 5.4), Vector3(0.6, 2.2, 0.6)],
			[Vector3(0, 2.35, 5.4), Vector3(3.0, 0.5, 0.8)]]:  # the entrance: two stones and a lintel
		var s: MeshInstance3D = W.box(barrow, p[0], p[1], Color.WHITE, "cube", true)
		s.material_override = stone
	W.box(barrow, Vector3(0, 1.0, 5.3), Vector3(1.6, 2.0, 0.3), Color("#050505"))  # the dark doorway
	W.glow(barrow, Vector3(0, 0.9, 5.1), Vector3(0.5, 0.5, 0.1), Color("#5dff9a"), 2.0)  # something glows inside
	W.light(barrow, Vector3(0, 1.5, 6.5), Color("#5dff9a"), 1.5, 9.0)
	for i in 9:  # standing stones in a ring, some fallen
		var a := i * TAU / 9.0
		var tall := 2.6 if i % 3 != 1 else 0.7
		var s: MeshInstance3D = W.box(barrow, Vector3(cos(a) * 13.0, tall / 2.0, sin(a) * 13.0), Vector3(0.9, tall, 0.6), Color.WHITE, "cube", true)
		s.material_override = stone
		s.rotation.y = -a
	for i in 6:  # grave markers
		var p := Vector3(randf_range(-9, 9), 0.4, randf_range(-11, -6))
		var g: MeshInstance3D = W.box(barrow, p, Vector3(0.5, 0.8, 0.12), Color("#8a8680"))
		g.rotation = Vector3(randf_range(-0.2, 0.2), randf() * 0.6, randf_range(-0.2, 0.2))


func build_camp(at: Vector3) -> void:
	var camp := Node3D.new()
	camp.position = at
	add_child(camp)
	for i in 6:  # a firepit ringed with stones, logs to sit on, and an awful lot of bones
		var a := i * TAU / 6.0
		W.box(camp, Vector3(cos(a) * 1.0, 0.15, sin(a) * 1.0), Vector3(0.4, 0.3, 0.4), Color("#5a5650"), "sphere")
	W.glow(camp, Vector3(0, 0.25, 0), Vector3(0.9, 0.35, 0.9), Color("#ff6a1a"), 3.5)
	W.light(camp, Vector3(0, 1.4, 0), Color("#ff8a3a"), 2.5, 12.0)
	for p in [Vector3(3, 0.3, 0), Vector3(-2, 0.3, 2.5)]:
		var log: MeshInstance3D = W.box(camp, p, Vector3(2.4, 0.5, 0.5), Color("#5a3d24"), "cube", true)
		log.rotation.y = randf() * PI
	for i in 14:
		var bone: MeshInstance3D = W.box(camp, Vector3(randf_range(-5, 5), 0.06, randf_range(-5, 5)), Vector3(randf_range(0.3, 0.8), 0.09, 0.09), Color("#e6dcc0"))
		bone.rotation.y = randf() * TAU
	W.box(camp, Vector3(-4, 0.4, -3), Vector3(0.8, 0.8, 0.8), Color("#efe8d6"), "sphere")  # a skull the size of a pumpkin


# --- making creatures ------------------------------------------------------------------------------------

func spawn(kind: String, at: Vector3, home: Vector3) -> void:
	var node := Node3D.new()
	node.position = at
	node.rotation.y = randf() * TAU
	add_child(node)
	var parts: Dictionary = call("model_" + kind, node)
	var bar := Node3D.new()  # a health bar over the head, shown once it has been hit
	bar.position.y = KINDS[kind].bar_y
	node.add_child(bar)
	W.box(bar, Vector3.ZERO, Vector3(0.9, 0.09, 0.02), Color("#1a1010"))
	var fill: MeshInstance3D = W.glow(bar, Vector3(0, 0, 0.012), Vector3(0.86, 0.06, 0.01), Color("#e03a2a"), 1.2)
	bar.visible = false
	if kind == "troll":
		bar.scale = Vector3.ONE * 2.2
	foes.append({"kind": kind, "node": node, "parts": parts, "home": home, "start": at, "hp": int(KINDS[kind].hp),
		"state": "idle", "timer": randf_range(1.0, 4.0), "goal": at, "cool": 0.0, "wind": 0.0, "stagger": 0.0,
		"dead": 0.0, "bar": bar, "fill": fill, "phase": randf() * TAU, "hurt": 0.0})


func limb(parent: Node3D, pivot: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pivot
	parent.add_child(n)
	return n


func model_wolf(node: Node3D) -> Dictionary:
	var fur := Color("#6e6a66").lerp(Color("#4a4642"), randf())
	var body := Node3D.new()
	node.add_child(body)
	W.box(body, Vector3(0, 0.62, 0.05), Vector3(0.42, 0.42, 1.0), fur)  # body
	W.box(body, Vector3(0, 0.72, -0.35), Vector3(0.48, 0.48, 0.42), fur.lightened(0.06))  # shoulders / ruff
	var head := limb(body, Vector3(0, 0.82, -0.62))
	W.box(head, Vector3(0, 0, -0.08), Vector3(0.32, 0.3, 0.3), fur)
	W.box(head, Vector3(0, -0.06, -0.3), Vector3(0.18, 0.16, 0.24), fur.darkened(0.1))  # snout
	W.box(head, Vector3(0, -0.02, -0.43), Vector3(0.07, 0.06, 0.03), Color("#111111"))  # nose
	for side in [-1, 1]:
		W.box(head, Vector3(side * 0.09, 0.2, -0.02), Vector3(0.07, 0.14, 0.06), fur.darkened(0.15))  # ears
		W.glow(head, Vector3(side * 0.08, 0.05, -0.235), Vector3(0.05, 0.035, 0.01), Color("#ffc23a"), 2.0)  # eyes
	var tail := limb(body, Vector3(0, 0.75, 0.55))
	var tail_box: MeshInstance3D = W.box(tail, Vector3(0, -0.12, 0.2), Vector3(0.12, 0.12, 0.45), fur.darkened(0.1))
	tail_box.rotation.x = 0.6
	var legs := []
	for p in [Vector3(-0.14, 0.45, -0.38), Vector3(0.14, 0.45, -0.38), Vector3(-0.14, 0.45, 0.4), Vector3(0.14, 0.45, 0.4)]:
		var leg := limb(body, p)
		W.box(leg, Vector3(0, -0.22, 0), Vector3(0.11, 0.45, 0.11), fur.darkened(0.12))
		legs.append(leg)
	return {"body": body, "head": head, "legs": legs, "tail": tail}


func model_skeleton(node: Node3D) -> Dictionary:
	var bone := Color("#e3dccb")
	var body := Node3D.new()
	node.add_child(body)
	var legs := []
	for side in [-1, 1]:
		var leg := limb(body, Vector3(side * 0.12, 0.9, 0))
		W.box(leg, Vector3(0, -0.45, 0), Vector3(0.07, 0.88, 0.07), bone)
		W.box(leg, Vector3(0, -0.88, -0.04), Vector3(0.1, 0.05, 0.18), bone)
		legs.append(leg)
	W.box(body, Vector3(0, 0.93, 0), Vector3(0.34, 0.1, 0.16), bone)  # pelvis
	W.box(body, Vector3(0, 1.15, 0), Vector3(0.06, 0.4, 0.06), bone)  # spine
	for i in 4:  # ribs
		W.box(body, Vector3(0, 1.22 + i * 0.09, -0.02), Vector3(0.36 - i * 0.02, 0.04, 0.2), bone)
	W.box(body, Vector3(0, 1.55, 0), Vector3(0.5, 0.06, 0.1), bone)  # collarbones
	var head := limb(body, Vector3(0, 1.72, 0))
	W.box(head, Vector3(0, 0.02, 0), Vector3(0.27, 0.27, 0.27), bone)
	W.box(head, Vector3(0, -0.13, -0.03), Vector3(0.2, 0.08, 0.2), bone.darkened(0.08))  # jaw
	for side in [-1, 1]:
		W.glow(head, Vector3(side * 0.06, 0.04, -0.136), Vector3(0.06, 0.06, 0.01), Color("#5dff9a"), 2.5)  # eye sockets
	var arms := []
	for side in [-1, 1]:
		var arm := limb(body, Vector3(side * 0.27, 1.52, 0))
		W.box(arm, Vector3(0, -0.33, 0), Vector3(0.06, 0.66, 0.06), bone)
		arms.append(arm)
	var sword := limb(arms[1], Vector3(0, -0.66, -0.05))  # a rusty blade in the right hand
	W.box(sword, Vector3(0, 0, -0.42), Vector3(0.05, 0.02, 0.8), Color("#8a5a3a"))
	W.box(sword, Vector3(0, 0, -0.02), Vector3(0.2, 0.04, 0.04), Color("#5a4030"))
	var shield: MeshInstance3D = W.box(arms[0], Vector3(-0.06, -0.45, -0.1), Vector3(0.06, 0.5, 0.42), Color("#5a4a38"))
	shield.rotation.y = 0.2
	return {"body": body, "head": head, "legs": legs, "arms": arms}


func model_troll(node: Node3D) -> Dictionary:
	var skin := Color("#6f7d5a")
	var body := Node3D.new()
	node.add_child(body)
	var legs := []
	for side in [-1, 1]:
		var leg := limb(body, Vector3(side * 0.42, 1.25, 0))
		W.box(leg, Vector3(0, -0.6, 0), Vector3(0.55, 1.25, 0.6), skin.darkened(0.1))
		W.box(leg, Vector3(0, -1.2, -0.12), Vector3(0.65, 0.18, 0.8), skin.darkened(0.25))  # feet
		legs.append(leg)
	W.box(body, Vector3(0, 1.35, 0), Vector3(1.3, 0.5, 0.8), Color("#5a4632"))  # loincloth
	W.box(body, Vector3(0, 2.2, 0.05), Vector3(1.6, 1.4, 1.1), skin)  # belly
	W.box(body, Vector3(0, 2.95, 0.2), Vector3(1.9, 0.7, 1.0), skin.darkened(0.05))  # hunched shoulders
	var head := limb(body, Vector3(0, 3.3, -0.35))
	W.box(head, Vector3(0, 0, 0), Vector3(0.75, 0.62, 0.7), skin)
	W.box(head, Vector3(0, 0.05, -0.38), Vector3(0.28, 0.22, 0.12), skin.darkened(0.12))  # big nose
	W.box(head, Vector3(0, 0.2, -0.33), Vector3(0.66, 0.1, 0.1), skin.darkened(0.3))  # heavy brow
	for side in [-1, 1]:
		W.glow(head, Vector3(side * 0.17, 0.12, -0.36), Vector3(0.08, 0.06, 0.01), Color("#ff3a1a"), 2.5)
		var tusk: MeshInstance3D = W.box(head, Vector3(side * 0.18, -0.22, -0.36), Vector3(0.07, 0.24, 0.07), Color("#efe6cc"))
		tusk.rotation.z = side * 0.25
	var arms := []
	for side in [-1, 1]:
		var arm := limb(body, Vector3(side * 1.05, 3.0, 0.1))
		W.box(arm, Vector3(0, -0.8, 0), Vector3(0.45, 1.6, 0.5), skin.darkened(0.05))
		W.box(arm, Vector3(0, -1.65, 0), Vector3(0.5, 0.4, 0.55), skin.darkened(0.15))  # fist
		arms.append(arm)
	var club := limb(arms[1], Vector3(0, -1.65, -0.1))  # a tree-trunk club
	W.box(club, Vector3(0, 0, -0.9), Vector3(0.22, 0.22, 1.8), Color("#5a3d24"))
	W.box(club, Vector3(0, 0, -1.75), Vector3(0.5, 0.5, 0.6), Color("#4a3220"), "sphere")
	return {"body": body, "head": head, "legs": legs, "arms": arms}


# --- the sword (called by hotbar.gd) ---------------------------------------------------------------------

## A swing from `origin` facing `forward`: hits every living creature within `reach` in front of you.
func sword_hit(origin: Vector3, forward: Vector3, reach: float, arc: float) -> bool:
	var rpg = ctx.parts.get("rpg")
	if not rpg or not rpg.may_strike():
		return false
	var flat := Vector3(forward.x, 0, forward.z).normalized()
	var any := false
	for f in foes:
		if f.dead > 0.0:
			continue
		var to: Vector3 = f.node.position - origin
		to.y = 0.0
		var r: float = reach + (1.4 if f.kind == "troll" else 0.3)
		if to.length() > r or (to.length() > 0.6 and to.normalized().dot(flat) < arc):
			continue
		any = true
		damage(f, rpg.strike_damage(), flat)
	return any


func damage(f: Dictionary, amount: int, push: Vector3) -> void:
	f.hp -= amount
	f.hurt = 0.18
	f.bar.visible = true
	f.fill.scale.x = 0.86 * clampf(float(f.hp) / float(KINDS[f.kind].hp), 0.0, 1.0)
	f.fill.position.x = -0.43 + f.fill.scale.x / 2.0
	pop_number(f.node.position + Vector3(0, KINDS[f.kind].bar_y + 0.35, 0), str(amount), Color("#ffe08a"))
	if f.kind != "troll":
		f.stagger = 0.35
		f.node.position += push * 0.5
		f.node.position.y = W.ground_y(f.node.position.x, f.node.position.z)
	f.wind = 0.0  # a hit interrupts an attack
	f.state = "chase"
	if f.hp <= 0:
		die(f)


func die(f: Dictionary) -> void:
	var info: Dictionary = KINDS[f.kind]
	f.dead = float(info.respawn)
	f.node.visible = false
	f.bar.visible = false
	var rpg = ctx.parts.get("rpg")
	burst(f.node.position + Vector3(0, 0.8, 0), Color("#e3dccb") if f.kind == "skeleton" else Color("#8a1a1a"))
	if rpg:
		rpg.add_xp(int(info.xp))
		pop_number(f.node.position + Vector3(0, info.bar_y + 0.8, 0), "+%d xp" % info.xp, Color("#8fb4ff"))
		rpg.event("kill", f.kind)
		var gold := randi_range(int(info.gold[0]), int(info.gold[1]))
		if gold > 0:
			drop(f.node.position, "gold", gold)
	for entry in info.loot:
		if randf() < float(entry[1]):
			drop(f.node.position + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)), entry[0], 1)


func respawn(f: Dictionary) -> void:
	f.dead = 0.0
	f.hp = int(KINDS[f.kind].hp)
	f.node.position = f.start
	f.node.visible = true
	f.bar.visible = false
	f.state = "idle"
	f.fill.scale.x = 0.86
	f.fill.position.x = 0.0


## You died: everyone goes home.
func calm_down() -> void:
	for f in foes:
		if f.dead <= 0.0:
			f.state = "home"
			f.wind = 0.0


# --- loot on the ground ----------------------------------------------------------------------------------

func drop(at: Vector3, item: String, n: int) -> void:
	var node := Node3D.new()
	node.position = at_ground(at)
	add_child(node)
	var color: String = {"gold": "#ffd24d", "pelt": "#8a8580", "bone": "#efe8d6", "potion": "#e0342a", "tusk": "#fff4d6"}.get(item, "#ffffff")
	W.glow(node, Vector3(0, 0.35, 0), Vector3(0.28, 0.28, 0.28), Color(color), 1.6, "sphere" if item == "gold" else "cube")
	drops.append([node, item, n, 0.0])


func burst(at: Vector3, color: Color) -> void:
	for i in 10:
		var bit: MeshInstance3D = W.box(self, at, Vector3.ONE * 0.12, color)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.3, 1.4), randf_range(-1, 1))
		var tw := create_tween()
		tw.tween_property(bit, "position", at + dir * 1.4, 0.5).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(bit, "scale", Vector3.ONE * 0.01, 0.5)
		tw.tween_callback(bit.queue_free)


func pop_number(at: Vector3, text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.outline_size = 10
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.008
	l.position = at
	add_child(l)
	numbers.append([l, 0.0])


# --- every frame -----------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	t += delta
	var player: Vector3 = W.player.global_position
	var rpg = ctx.parts.get("rpg")
	for f in foes:
		if f.dead > 0.0:
			f.dead -= delta
			if f.dead <= 0.0:
				respawn(f)
			continue
		think(f, player, rpg, delta)
	for d in drops.duplicate():  # loot bobs and spins; walk over it to pick it up
		d[3] += delta
		var node: Node3D = d[0]
		node.rotation.y += delta * 2.0
		node.get_child(0).position.y = 0.35 + sin(d[3] * 3.0) * 0.08
		if Vector2(player.x - node.position.x, player.z - node.position.z).length() < 1.4 and absf(player.y - node.position.y) < 2.0:
			if rpg:
				rpg.give(d[1], d[2])
			node.queue_free()
			drops.erase(d)
		elif d[3] > 180.0:
			node.queue_free()
			drops.erase(d)
	for n in numbers.duplicate():
		n[1] += delta
		n[0].position.y += delta * 1.2
		n[0].modulate.a = clampf(1.5 - n[1] * 1.5, 0.0, 1.0)
		if n[1] > 1.0:
			n[0].queue_free()
			numbers.erase(n)


func think(f: Dictionary, player: Vector3, rpg, delta: float) -> void:
	var info: Dictionary = KINDS[f.kind]
	var node: Node3D = f.node
	var to_player := Vector3(player.x - node.position.x, 0, player.z - node.position.z)
	var dist := to_player.length()
	var from_home := Vector2(node.position.x - f.home.x, node.position.z - f.home.z).length()
	var dead_player: bool = rpg == null
	f.cool = maxf(f.cool - delta, 0.0)
	f.stagger = maxf(f.stagger - delta, 0.0)
	f.hurt = maxf(f.hurt - delta, 0.0)
	var speed := 0.0
	var goal: Vector3 = node.position
	match f.state:
		"idle":  # stroll about home, now and then
			f.timer -= delta
			if f.timer <= 0.0:
				f.timer = randf_range(3.0, 8.0)
				f.goal = f.home + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
			goal = f.goal
			speed = float(info.speed) * 0.25
			if dist < float(info.aggro) and not dead_player and absf(player.y - node.position.y) < 4.0:
				f.state = "chase"
				if f.kind == "troll" and rpg:
					W.show_notice("Gorrak the Troll roars!", 3.0)
		"chase":
			goal = player
			speed = float(info.speed)
			if from_home > LEASH or dist > float(info.aggro) * 2.2:
				f.state = "home"
			elif dist < float(info.reach) and f.cool <= 0.0 and f.wind <= 0.0:
				f.wind = WINDUP
			if f.wind > 0.0:  # winding up: stand still, then strike if you are still in reach
				speed = 0.0
				f.wind -= delta
				if f.wind <= 0.0:
					f.cool = float(info.cooldown)
					if dist < float(info.reach) + 0.6 and rpg:
						rpg.hurt(int(info.dmg), info.name.to_lower() if f.kind != "troll" else info.name)
		"home":  # gave up: trot back and heal
			goal = f.home
			speed = float(info.speed) * 0.7
			f.hp = mini(f.hp + 1, int(info.hp))
			if from_home < 3.0:
				f.state = "idle"
				f.bar.visible = false
	if f.stagger > 0.0:
		speed = 0.0
	var step := Vector3(goal.x - node.position.x, 0, goal.z - node.position.z)
	var keep := float(info.reach) * 0.7 if f.state == "chase" else 0.2  # stop short of you
	var moving := step.length() > keep and speed > 0.0
	if moving:
		var dir := step.normalized()
		node.position += dir * minf(speed * delta, step.length() - keep)
		node.position.y = W.ground_y(node.position.x, node.position.z)
		node.rotation.y = lerp_angle(node.rotation.y, atan2(-dir.x, -dir.z), minf(delta * 8.0, 1.0))
	elif f.state == "chase" and dist > 0.1:
		node.rotation.y = lerp_angle(node.rotation.y, atan2(-to_player.x, -to_player.z), minf(delta * 8.0, 1.0))
	animate(f, moving, speed, delta)
	if f.bar.visible:  # the health bar faces the camera
		var cam: Vector3 = W.camera.global_position
		f.bar.look_at(Vector3(cam.x, f.bar.global_position.y, cam.z), Vector3.UP)
		f.bar.rotate_object_local(Vector3.UP, PI)


func animate(f: Dictionary, moving: bool, speed: float, delta: float) -> void:
	var p: Dictionary = f.parts
	f.phase += delta * (speed * 2.2 if moving else 0.0)
	var swing := sin(f.phase) * (0.7 if moving else 0.0)
	var legs: Array = p.legs
	if f.kind == "wolf":
		legs[0].rotation.x = swing
		legs[3].rotation.x = swing
		legs[1].rotation.x = -swing
		legs[2].rotation.x = -swing
		p.tail.rotation.y = sin(t * 3.0 + f.phase) * 0.3
		var lunge: float = (1.0 - f.wind / WINDUP) if f.wind > 0.0 else 0.0
		p.body.position.z = -lunge * 0.5
		p.head.rotation.x = -0.25 * lunge + (0.0 if moving else sin(t * 0.8 + f.phase) * 0.12)
	else:
		legs[0].rotation.x = swing * 0.8
		legs[1].rotation.x = -swing * 0.8
		var arms: Array = p.arms
		arms[0].rotation.x = -swing * 0.5
		if f.wind > 0.0:  # raise the weapon high, then bring it down
			arms[1].rotation.x = lerpf(arms[1].rotation.x, -2.6, minf(delta * 10.0, 1.0))
		elif f.cool > float(KINDS[f.kind].cooldown) - 0.25:
			arms[1].rotation.x = lerpf(arms[1].rotation.x, -0.4, minf(delta * 25.0, 1.0))
		else:
			arms[1].rotation.x = lerpf(arms[1].rotation.x, swing * 0.5 - 0.2, minf(delta * 6.0, 1.0))
		p.head.rotation.y = sin(t * 0.7 + f.phase) * 0.2 if not moving else 0.0
	p.body.scale = Vector3.ONE * (1.0 + f.hurt * 0.6)  # a flinch when hit


func seen_from(from: Vector3, _viewer: Node) -> Array:
	return ["wolf dens in the woods (%s, %s and %s)" % [W.where(from, DENS[0]), W.where(from, DENS[1]), W.where(from, DENS[2])],
		"the old barrow where skeletons walk, %s" % W.where(from, BARROW),
		"the camp of Gorrak the troll, %s" % W.where(from, TROLL_CAMP)]
