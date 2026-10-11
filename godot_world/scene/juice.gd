extends Node3D
## "Game feel": a camera shake that fades away, and a very short freeze (hit-stop) when a blow lands, so fights have
## weight. Other parts call juice.shake(amount) and juice.hit_stop(seconds): creatures.gd when you hit something or kill
## it, rpg.gd when you are hurt. Everything here is brief and gentle: the shake is a few centimetres, the freeze 0.05 s.

var ctx: Dictionary
var W
var amount := 0.0  # current shake strength (metres of camera offset)
var frozen := false


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	Engine.time_scale = 1.0


func _exit_tree() -> void:
	Engine.time_scale = 1.0  # (never leave the game frozen if this part is swapped mid-freeze)
	if W and W.camera:
		W.camera.h_offset = 0.0
		W.camera.v_offset = 0.0


func shake(strength: float) -> void:
	amount = clampf(maxf(amount, strength), 0.0, 0.12)


## Freeze the game for `seconds` of REAL time (the timer ignores the slowdown it causes).
func hit_stop(seconds: float) -> void:
	if frozen:
		return
	frozen = true
	Engine.time_scale = 0.06
	get_tree().create_timer(seconds, true, false, true).timeout.connect(_thaw)


func _thaw() -> void:
	Engine.time_scale = 1.0
	frozen = false


func _process(delta: float) -> void:
	# running widens the view a little (80 -> 86 degrees), walking and standing settle it back
	var run_speed := Vector2(W.player.velocity.x, W.player.velocity.z).length()
	var want_fov := 80.0 + clampf((run_speed - 5.0) * 2.0, 0.0, 6.0)
	W.camera.fov = lerpf(W.camera.fov, want_fov, minf(delta * 4.0, 1.0))
	if amount > 0.0005:
		W.camera.h_offset = randf_range(-1.0, 1.0) * amount
		W.camera.v_offset = randf_range(-1.0, 1.0) * amount
		amount = move_toward(amount, 0.0, delta / maxf(Engine.time_scale, 0.2) * 0.22)
	elif W.camera.h_offset != 0.0:
		W.camera.h_offset = 0.0
		W.camera.v_offset = 0.0
