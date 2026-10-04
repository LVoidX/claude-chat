extends Node3D
## Rocket launcher, slot 3 (key 3 or [rocket]): left click fires a rocket that flies straight and
## explodes on whatever it touches (or after 4 s). The blast shoves you (rocket jump!), Barnaby and
## Marigold (knockback.gd, never hurts) and leaves a fireball. state["rocket_held"] = in hand.

const SPEED := 45.0
const LIFE := 4.0
const BLAST := 7.0  # radius of the push
const ROCKET_DAMAGE := 20  # to wolves, skeletons and trolls in the inner half of the blast (half further out)
const COOLDOWN := 0.8

var ctx: Dictionary
var W
var launcher: Node3D
var rockets := []  # [node, velocity, age]
var booms := []  # [node, light, age]
var cooldown := 0.0
var recoil := 0.0


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	for old in W.camera.get_children():
		if old.name == "RocketLauncher":
			old.free()
	launcher = Node3D.new()
	launcher.name = "RocketLauncher"
	launcher.position = Vector3(0.3, -0.26, -0.55)
	var olive := Color("#4d5a3a")
	W.box(launcher, Vector3(0, 0, 0), Vector3(0.11, 0.11, 0.7), olive)  # tube
	W.box(launcher, Vector3(0, 0, -0.3575), Vector3(0.13, 0.13, 0.015), Color("#2b2f26"))  # front rim, touching the tube end
	W.box(launcher, Vector3(0, 0, 0.3575), Vector3(0.14, 0.14, 0.015), Color("#2b2f26"))  # back flare
	W.box(launcher, Vector3(0, -0.12, 0.05), Vector3(0.04, 0.13, 0.05), Color("#6b4a2f"))  # grip under the tube
	W.box(launcher, Vector3(0, 0.0675, -0.1), Vector3(0.03, 0.025, 0.08), Color("#1b1e22"))  # sight on top
	W.glow(launcher, Vector3(0, 0, -0.34), Vector3(0.07, 0.07, 0.012), Color("#ff7a2d"), 2.0)  # warhead tip showing in the muzzle
	launcher.visible = held()
	W.camera.add_child(launcher)


func _exit_tree() -> void:
	if launcher and is_instance_valid(launcher):
		launcher.queue_free()


func held() -> bool:
	return ctx.state.get("rocket_held", false)


func set_held(on: bool) -> void:
	ctx.state["rocket_held"] = on
	if on:  # one thing in hand at a time
		ctx.state["sword_held"] = false
		ctx.state["gun_held"] = false
		var hb = ctx.parts.get("hotbar")
		if hb:
			hb.sword.visible = false
			hb.gun.visible = false
		var builder = ctx.parts.get("builder")
		if builder and ctx.state.get("hammer", false):
			builder.set_held(false)
	launcher.visible = on


func key(event: InputEventKey) -> void:
	if event.keycode == KEY_3:
		set_held(not held())


func handle(c: Dictionary) -> bool:
	match c.get("cmd", ""):
		"rocket":
			set_held(true)
			W.show_notice("Rocket launcher in hand: left click fires. Fire at your feet to rocket-jump.", 6.0)
		"unrocket":
			set_held(false)
		_:
			return false
	return true


func _input(event: InputEvent) -> void:
	if not held() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		fire()


func fire() -> void:
	if cooldown > 0.0:
		return
	cooldown = COOLDOWN
	recoil = 1.0
	var dir: Vector3 = -W.camera.global_basis.z
	var node := Node3D.new()
	add_child(node)
	node.global_position = launcher.global_position + launcher.global_basis * Vector3(0, 0, -0.45)
	node.look_at(node.global_position + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	W.box(node, Vector3.ZERO, Vector3(0.1, 0.1, 0.4), Color("#c9ccd1"))  # body
	W.glow(node, Vector3(0, 0, -0.2275), Vector3(0.08, 0.08, 0.055), Color("#ff3b2d"), 2.0)  # nose
	W.glow(node, Vector3(0, 0, 0.2475), Vector3(0.12, 0.12, 0.095), Color("#ffb347"), 4.0)  # exhaust flame
	W.light(node, Vector3(0, 0, 0.4), Color("#ff9a3c"), 2.5, 6.0)
	rockets.append([node, dir * SPEED, 0.0])


func explode(pos: Vector3) -> void:
	var ball := Node3D.new()
	add_child(ball)
	ball.global_position = pos
	W.glow(ball, Vector3.ZERO, Vector3(1.0, 1.0, 1.0), Color("#ff8a2a"), 5.0, "sphere")
	var l: OmniLight3D = W.light(ball, Vector3.ZERO, Color("#ff9a3c"), 12.0, 16.0)
	booms.append([ball, l, 0.0])
	var gob = ctx.parts.get("goblins")
	if gob:
		gob.burst(pos, Color("#ffb347"), 14, 6.0)
		gob.blast(pos, BLAST)  # goblins take real damage
	var creatures = ctx.parts.get("creatures")  # so do the RPG's wolves, skeletons and trolls
	if creatures:
		creatures.blast(pos, BLAST, ROCKET_DAMAGE)
	# shove the user
	var to_player: Vector3 = W.player.global_position + Vector3(0, 0.9, 0) - pos
	var d := to_player.length()
	if d < BLAST:
		var power := (1.0 - d / BLAST) * 34.0  # was 16
		var away := to_player.normalized()
		# strong in both directions: sideways is boosted most, with a solid lift on top
		W.player.velocity += Vector3(away.x * power * 2.2, away.y * power * 1.0 + power * 0.5, away.z * power * 2.2)
	# shove the characters (never hurts)
	var kb = ctx.parts.get("knockback")
	if kb:
		for who in ["barnaby", "marigold"]:
			var b = kb.body_of(who)
			if b == null:
				continue
			var away: Vector3 = b.global_position + Vector3(0, 0.9, 0) - pos
			if away.length() < BLAST:
				var flat := Vector3(away.x, 0, away.z)
				kb.vel[who] = (flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD) * 14.0


func _process(delta: float) -> void:
	if ctx.is_empty() or not is_instance_valid(launcher):
		return  # (a reload frees the old launcher while this old part may still tick once)
	cooldown = maxf(cooldown - delta, 0.0)
	recoil = maxf(recoil - delta * 4.0, 0.0)
	if held() and (ctx.state.get("hammer", false) or ctx.state.get("sword_held", false)):
		set_held(false)  # the hammer or sword took the hand
	launcher.position = Vector3(0.3, -0.26, -0.55 + recoil * 0.1)
	launcher.rotation_degrees = Vector3(recoil * 8.0, 0, 0)
	var space: PhysicsDirectSpaceState3D = W.get_world_3d().direct_space_state
	for r in rockets.duplicate():
		var node: Node3D = r[0]
		var step: Vector3 = r[1] * delta
		var query := PhysicsRayQueryParameters3D.create(node.global_position, node.global_position + step, 0xFFFFFFFF, [W.player.get_rid()])
		var hit: Dictionary = space.intersect_ray(query)
		r[2] += delta
		if not hit.is_empty():
			explode(hit.position + hit.normal * 0.1)
		elif r[2] > LIFE:
			explode(node.global_position)
		else:
			node.global_position += step
			continue
		node.queue_free()
		rockets.erase(r)
	for b in booms.duplicate():
		b[2] += delta
		var t: float = b[2] / 0.5
		if t >= 1.0:
			b[0].queue_free()
			booms.erase(b)
			continue
		b[0].scale = Vector3.ONE * (1.0 + t * 5.0)
		b[1].light_energy = 12.0 * (1.0 - t)


func seen_from(_from: Vector3, _viewer: Node) -> Array:
	if held():
		return ["the wanderer carries a rocket launcher"]
	return []
