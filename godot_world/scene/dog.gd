extends Node3D
## A farm dog who lives by the crossroads campfire. Walk up to it and it joins you, trotting along at your heel (stopping
## when you stop, a little wag of body when it waits); go far from the fire, or stay away long, and it wanders back by itself.
## E beside it calls it to you or sends it home (state["dog_joined"] remembers it is with you).
## Needs: travel.gd (FIRE), the Blender model dog.glb (tools/blender/dog.py).

const FOLLOW_RANGE := 4.5  # come this close and it joins you
const KEEP_BEHIND := 2.2  # it stays about this far from you
const HOME_AFTER := 140.0  # metres from the fire where it gives up and goes home

var ctx: Dictionary
var W
var dog_node: MeshInstance3D
var following := false
var t := 0.0
var speed := 0.0
var home := Vector3.ZERO


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	var travel = ctx.parts.get("travel")
	var fire: Vector2 = travel.FIRE if travel else Vector2(9, 6)
	home = Vector3(fire.x + 1.6, 0, fire.y + 3.4)
	dog_node = W.prop("dog", self, Vector3(home.x, W.ground_y(home.x, home.z), home.z), 0.8, 1.0)
	if dog_node == null:
		set_process(false)


func interactables() -> Array:
	if dog_node == null:
		return []
	var me: Vector3 = W.player.global_position
	if me.distance_to(dog_node.position) > 2.5:
		return []
	if following:
		return [{"pos": dog_node.position, "label": "Send the dog home", "act": send_home, "range": 2.5}]
	return [{"pos": dog_node.position, "label": "Call the dog", "act": call_dog, "range": 2.5}]


func call_dog() -> void:
	following = true
	W.show_notice("The dog's tail whips about. It will follow you.", 3.0)


func send_home() -> void:
	following = false
	ctx.state["dog_joined"] = false
	W.show_notice("The dog trots back towards the fire.", 3.0)


func _process(delta: float) -> void:
	t += delta
	var me: Vector3 = W.player.global_position
	var pos: Vector3 = dog_node.position
	var near := Vector2(me.x - pos.x, me.z - pos.z)
	if not following and near.length() < FOLLOW_RANGE and ctx.state.get("dog_joined", false):
		following = true  # (it has joined you before: it comes straight away)
	var goal := home
	if following:
		ctx.state["dog_joined"] = true
		var back := Vector2(pos.x - me.x, pos.z - me.z)
		goal = me + (Vector3(back.x, 0, back.y).normalized() * KEEP_BEHIND if back.length() > 0.1 else Vector3.ZERO)
		if Vector2(me.x - home.x, me.z - home.z).length() > HOME_AFTER:
			following = false
	var to := Vector3(goal.x - pos.x, 0, goal.z - pos.z)
	var dist := to.length()
	var want := 0.0
	if dist > (KEEP_BEHIND + 0.8 if following else 0.5):
		want = clampf(dist * 1.2, 1.4, 6.5 if following else 3.0)
	speed = move_toward(speed, want, delta * 6.0)
	if speed > 0.05 and dist > 0.05:
		var dir := to.normalized()
		pos += dir * speed * delta
		dog_node.rotation.y = lerp_angle(dog_node.rotation.y, atan2(-dir.x, -dir.z), minf(delta * 8.0, 1.0))
	dog_node.position.x = pos.x
	dog_node.position.z = pos.z
	var bob := absf(sin(t * 12.0)) * 0.04 * clampf(speed / 3.0, 0.0, 1.0)
	dog_node.position.y = W.ground_y(pos.x, pos.z) + bob
	dog_node.rotation.z = sin(t * 12.0) * 0.05 * clampf(speed / 3.0, 0.0, 1.0)
	if speed < 0.05 and not following:  # lying by the fire: a slow breath
		dog_node.scale = Vector3(1.0, 1.0 + sin(t * 1.6) * 0.015, 1.0)
	else:
		dog_node.scale = Vector3.ONE


func seen_from(from: Vector3, _viewer: Node) -> Array:
	if dog_node == null:
		return []
	return ["a shaggy brown farm dog %s" % W.where(from, dog_node.position) + (" that follows the wanderer" if following else " lying by the campfire")]
