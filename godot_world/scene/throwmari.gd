extends Node3D
## [throwmari] (Barnaby throws Marigold): he walks to her, hoists her overhead, turns to the wanderer and flings
## her in an arc to land in front of you. She lies dazed a moment, then gets up. This part runs after the
## characters' own _process (high process_priority), so it overrides their pose while it is active.

var ctx: Dictionary
var W
var phase := ""  # "", "fetch", "carry", "fly", "lie"
var t := 0.0
var from := Vector3.ZERO
var to := Vector3.ZERO
var air_time := 1.0
var air_height := 3.0


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	process_priority = 100
	phase = ""


func start() -> void:
	var b = ctx.parts.get("barnaby")
	var m = ctx.parts.get("marigold")
	if phase != "" or b == null or m == null or b.body == null or m.body == null:
		return
	if b.st().get("mode") == "thrown":
		return
	b.st()["mode"] = "stay"
	phase = "fetch"
	t = 0.0
	W.show_notice("Barnaby goes to fetch Marigold...", 3.0)


func finish(b, m) -> void:
	phase = ""
	m.body.rotation.x = 0.0
	m.body.position.y = 0.0
	m.home = m.body.position
	m.target = m.body.position
	m.arms_up = false
	b.st()["mode"] = "wander"
	b.target = b.body.position


func _process(delta: float) -> void:
	if phase == "":
		return
	var b = ctx.parts.get("barnaby")
	var m = ctx.parts.get("marigold")
	if b == null or m == null or b.body == null or m.body == null:
		phase = ""
		return
	t += delta
	var player: Vector3 = ctx.player.position
	m.pause = 5.0  # she doesn't wander off while he comes for her
	match phase:
		"fetch":
			var walking: bool = b.walk_to(m.body.position, 4.5, 1.0, delta)
			W.face(b.body, m.body.position)
			var d: Vector3 = m.body.position - b.body.position
			d.y = 0
			if not walking or d.length() < 1.3 or t > 30.0:
				phase = "carry"
				t = 0.0
		"carry":
			var u := clampf(t / 0.8, 0.0, 1.0)
			W.face(b.body, player)
			# she is held just in front of him, rising overhead (offset along his facing, so nothing overlaps him)
			var fwd: Vector3 = -b.body.global_transform.basis.z
			m.body.position = Vector3(b.body.position.x + fwd.x * 0.45, u * 2.1, b.body.position.z + fwd.z * 0.45)
			m.body.rotation.y = b.body.rotation.y
			b.limbs[2][0].rotation.x = -deg_to_rad(160)
			b.limbs[3][0].rotation.x = -deg_to_rad(160)
			if u >= 1.0:
				var pf: Vector3 = -ctx.player.global_transform.basis.z
				from = m.body.position
				to = Vector3(player.x + pf.x * 2.0, 0, player.z + pf.z * 2.0)
				var dist := Vector2(to.x - from.x, to.z - from.z).length()
				air_time = clampf(dist / 11.0, 0.9, 3.0)
				air_height = 2.0 + dist * 0.12
				phase = "fly"
				t = 0.0
		"fly":
			var u := minf(t / air_time, 1.0)
			m.body.position = Vector3(lerpf(from.x, to.x, u), lerpf(from.y, 0.0, u) + 4.0 * air_height * u * (1.0 - u), lerpf(from.z, to.z, u))
			m.body.rotation.x = -u * TAU * 2.0
			if u >= 1.0:
				phase = "lie"
				t = 0.0
		"lie":
			m.body.position.y = 0.0
			m.body.rotation.x = -deg_to_rad(88)  # flat on her back
			if t > 1.6:
				finish(b, m)
	if m.body:
		ctx.state["marigold"]["x"] = m.body.position.x
		ctx.state["marigold"]["z"] = m.body.position.z


func handle(c: Dictionary) -> bool:
	if c.get("cmd", "") == "throwmari":
		start()
		return true
	return false
