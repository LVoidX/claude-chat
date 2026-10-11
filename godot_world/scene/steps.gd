extends Node3D
## Footsteps: a soft tap every stride while you walk, and its sound follows the ground under your feet: grass, the
## packed dirt of the roads, the planks of the footbridge, shallow water. Quiet on purpose (music.gd makes the sounds).
## Needs: music.gd (play_sfx), terrain.gd (road_distance, bridge_spot, stream_distance, pond_distance).

const STRIDE := 1.9  # metres of walking per step
const RUN_STRIDE := 2.5

var ctx: Dictionary
var W
var travelled := 0.0
var last := Vector3.ZERO


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	last = W.player.global_position


func surface(p: Vector3) -> String:
	var tr = ctx.parts.get("terrain")
	if tr == null:
		return "step_grass"
	var spot: Array = tr.bridge_spot()
	var b: Vector2 = spot[0]
	if Vector2(p.x - b.x, p.z - b.y).length() < 3.6 and p.y > 0.0:
		return "step_wood"
	if tr.pond_distance(p.x, p.z) < 0.3 or tr.stream_distance(p.x, p.z) < 1.6:
		return "step_water"
	if tr.road_distance(p.x, p.z) < tr.ROAD_WIDTH * 0.5:
		return "step_road"
	return "step_grass"


func _process(_delta: float) -> void:
	var me: Vector3 = W.player.global_position
	var moved := Vector2(me.x - last.x, me.z - last.z).length()
	last = me
	if moved > 3.0 or ctx.get("seated", false) or ctx.state.get("flying", false) or not W.player.is_on_floor():
		return  # teleported, sitting, flying or in the air: no steps
	travelled += moved
	var stride := RUN_STRIDE if Vector2(W.player.velocity.x, W.player.velocity.z).length() > 6.0 else STRIDE
	if travelled >= stride:
		travelled = 0.0
		var music = ctx.parts.get("music")
		if music:
			music.play_sfx(surface(me))
