extends Node3D
## Your own body, so looking down you see yourself: tunic, belt, legs and boots. It hangs on the player, walks when
## you walk (thighs swing, knees bend), and sits properly on a log by the campfire (travel.gd: ctx["seated"]).
## No head or arms: the camera is your head, and the sword or tool in your hand is drawn by the hotbar.

const HIP := 0.9  # hips above the feet (travel.gd uses the same, to put you on the log)
const THIGH := 0.46
const SHIN := 0.44

var ctx: Dictionary
var W
var body: Node3D
var legs := []  # [hip pivot, knee pivot]
var phase := 0.0
var sit := 0.0  # 0..1 easing into sitting


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	for old in W.player.get_children():  # (a rebuild: the old body goes)
		if old.name == "Avatar":
			old.free()
	body = Node3D.new()
	body.name = "Avatar"
	W.player.add_child(body)
	var tunic := Color("#3f5a34")
	var trousers := Color("#4a3a2a")
	var boot := Color("#2e2016")
	W.box(body, Vector3(0, 1.22, 0.07), Vector3(0.44, 0.6, 0.24), tunic)  # torso (a little behind the camera)
	W.box(body, Vector3(0, 0.95, 0.06), Vector3(0.46, 0.08, 0.26), Color("#3b2a1e"))  # belt
	W.box(body, Vector3(0, 0.95, -0.075), Vector3(0.08, 0.07, 0.02), Color("#c9a24a"))  # buckle
	W.box(body, Vector3(0.18, 0.88, -0.05), Vector3(0.1, 0.13, 0.08), Color("#5a3d24"))  # a pouch
	W.box(body, Vector3(0, 0.8, 0.02), Vector3(0.44, 0.22, 0.26), tunic.darkened(0.1))  # the tunic's skirt
	for side in [-1, 1]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.11, HIP, 0.04)
		body.add_child(hip)
		W.box(hip, Vector3(0, -THIGH / 2.0, 0), Vector3(0.15, THIGH, 0.16), trousers)
		var knee := Node3D.new()
		knee.position = Vector3(0, -THIGH, 0)
		hip.add_child(knee)
		W.box(knee, Vector3(0, -SHIN / 2.0 + 0.05, 0), Vector3(0.14, SHIN - 0.1, 0.15), trousers.darkened(0.05))
		W.box(knee, Vector3(0, -SHIN + 0.08, -0.02), Vector3(0.16, 0.16, 0.17), boot)  # boot shaft
		W.box(knee, Vector3(0, -SHIN + 0.02, -0.08), Vector3(0.16, 0.06, 0.28), boot.darkened(0.1))  # foot
		legs.append([hip, knee])


func _exit_tree() -> void:
	if body and is_instance_valid(body):
		body.queue_free()


func _process(delta: float) -> void:
	if not body:
		return
	var v: Vector3 = W.player.velocity
	var speed := Vector2(v.x, v.z).length()
	var seated: bool = ctx.get("seated", false)
	sit = move_toward(sit, 1.0 if seated else 0.0, delta * 4.0)
	phase += delta * clampf(speed, 0.0, 10.0) * 1.9
	var swing := sin(phase) * clampf(speed / 5.0, 0.0, 1.0) * 0.6
	for i in legs.size():
		var s := swing * (1.0 if i == 0 else -1.0)
		var hip: Node3D = legs[i][0]
		var knee: Node3D = legs[i][1]
		var walk_hip := s
		var walk_knee := -maxf(0.0, -s) * 1.1  # the knee bends as the leg swings back
		hip.rotation.x = lerpf(walk_hip, PI / 2.0, sit)  # sitting: thighs forward along the log...
		knee.rotation.x = lerpf(walk_knee, -PI / 2.0, sit)  # ...shins straight down
	body.visible = W.camera.current
