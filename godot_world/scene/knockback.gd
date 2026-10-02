extends Node3D
## Shooting Barnaby or Marigold with the gun (hotbar.gd calls shoot()) shoves them back along the bullet.
## It never hurts them. They carry on afterwards.

const RADIUS := 0.5
const HEIGHT := 1.9
const PUSH := 9.0
const DRAG := 4.0

var ctx: Dictionary
var W
var vel := {}  # part name -> Vector3 velocity


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]


func body_of(who: String) -> Node3D:
	var p = ctx.parts.get(who)
	if p == null or p.body == null:
		return null
	if who == "barnaby" and p.st().get("mode") in ["thrown", "atop", "climb", "heli"]:
		return null
	return p.body


## Distance along the ray from..from+dir*far to the character's upright cylinder, or -1.
func ray_hit(b: Node3D, from: Vector3, dir: Vector3, far: float) -> float:
	var flat := Vector2(dir.x, dir.z)
	if flat.length() < 0.001:
		return -1.0
	var rel := Vector2(b.global_position.x - from.x, b.global_position.z - from.z)
	var along := rel.dot(flat) / flat.length_squared()  # ray parameter (dir is unit length)
	if along < 0.0 or along > far:
		return -1.0
	var miss := (rel - flat * along).length()
	if miss > RADIUS:
		return -1.0
	var y := from.y + dir.y * along
	if y < b.global_position.y or y > b.global_position.y + HEIGHT:
		return -1.0
	return along


## Returns the (possibly shortened) bullet length.
func shoot(from: Vector3, dir: Vector3, far: float) -> float:
	var best := far
	var who_hit := ""
	for who in ["barnaby", "marigold"]:
		var b := body_of(who)
		if b == null:
			continue
		var d := ray_hit(b, from, dir, best)
		if d >= 0.0:
			best = d
			who_hit = who
	if who_hit != "":
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		vel[who_hit] = flat * PUSH
	return best


func _process(delta: float) -> void:
	for who in vel.keys():
		var b := body_of(who)
		if b == null:
			vel.erase(who)
			continue
		var v: Vector3 = vel[who]
		b.position += v * delta
		vel[who] = v.move_toward(Vector3.ZERO, DRAG * delta * v.length() * 0.5 + DRAG * delta)
		if vel[who].length() < 0.15:
			vel.erase(who)
		if who == "marigold":  # keep her saved position in step
			ctx.state["marigold"]["x"] = b.position.x
			ctx.state["marigold"]["z"] = b.position.z
