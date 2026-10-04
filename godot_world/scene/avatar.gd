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
var arms := []  # [shoulder pivot, elbow pivot]
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
	W.box(body, Vector3(0, 1.22, 0.07), Vector3(0.48, 0.62, 0.28), tunic)  # torso (a little behind the camera)
	W.box(body, Vector3(0, 1.48, 0.07), Vector3(0.46, 0.12, 0.29), tunic.lightened(0.08))  # shoulder yoke
	W.box(body, Vector3(0, 1.45, -0.078), Vector3(0.24, 0.035, 0.018), Color("#c5a66f"))  # collar piping
	W.box(body, Vector3(0, 0.95, 0.06), Vector3(0.46, 0.08, 0.26), Color("#3b2a1e"))  # belt
	W.box(body, Vector3(0, 0.95, -0.075), Vector3(0.08, 0.07, 0.02), Color("#c9a24a"))  # buckle
	W.box(body, Vector3(0.18, 0.88, -0.05), Vector3(0.1, 0.13, 0.08), Color("#5a3d24"))  # a pouch
	W.box(body, Vector3(-0.16, 1.16, -0.078), Vector3(0.035, 0.38, 0.018), Color("#c5a66f"))  # stitched tunic seam
	W.box(body, Vector3(0, 0.8, 0.02), Vector3(0.44, 0.22, 0.26), tunic.darkened(0.1))  # the tunic's skirt
	for side in [-1, 1]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(side * 0.28, 1.43, 0.015)
		body.add_child(shoulder)
		capsule(shoulder, Vector3(0, -0.16, 0), 0.12, 0.34, tunic.darkened(0.03))  # sleeves
		var elbow := Node3D.new()
		elbow.position = Vector3(0, -0.31, -0.015)
		shoulder.add_child(elbow)
		capsule(elbow, Vector3(0, -0.14, -0.015), 0.095, 0.29, Color("#bd8968"))  # forearm
		W.box(elbow, Vector3(0, -0.27, -0.015), Vector3(0.2, 0.07, 0.19), Color("#c4a26c"))  # sleeve cuff
		capsule(elbow, Vector3(0, -0.36, -0.035), 0.085, 0.17, Color("#795032"))  # leather glove
		arms.append([shoulder, elbow])
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


func capsule(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 3
	part.mesh = mesh
	part.material_override = W.mat(color)
	part.position = pos
	parent.add_child(part)
	return part


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
	for i in arms.size():
		var side := -1.0 if i == 0 else 1.0
		var shoulder: Node3D = arms[i][0]
		var elbow: Node3D = arms[i][1]
		var held_sword: bool = ctx.state.get("sword_held", false) and i == 1
		shoulder.rotation.x = lerpf(swing * side * 0.38, -0.45 if held_sword else 0.0, 0.65 if held_sword else 0.0)
		shoulder.rotation.z = side * 0.08
		elbow.rotation.x = 0.82 if held_sword else 0.05
	body.visible = W.camera.current
