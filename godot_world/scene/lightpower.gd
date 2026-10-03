extends Node3D
## The power of light: [light] makes a warm golden light follow the user (with a glowing orb that floats
## beside them), [unlight] puts it out. state["light_power"] keeps it across reloads.

var ctx: Dictionary
var lamp: OmniLight3D
var orb: Node3D
var t := 0.0


func build(c: Dictionary) -> void:
	ctx = c
	var W = ctx.world
	lamp = W.light(self, Vector3.ZERO, Color(1.0, 0.85, 0.5), 6.0, 28.0)
	lamp.shadow_enabled = true
	orb = Node3D.new()
	add_child(orb)
	W.glow(orb, Vector3.ZERO, Vector3(0.22, 0.22, 0.22), Color(1.0, 0.9, 0.55), 4.0, "sphere")
	visible = ctx.state.get("light_power", false)


func handle(c: Dictionary) -> bool:
	match c.get("cmd", ""):
		"light":
			ctx.state["light_power"] = true
			visible = true
		"unlight":
			ctx.state["light_power"] = false
			visible = false
		_:
			return false
	return true


func _process(delta: float) -> void:
	if ctx.is_empty() or not visible:
		return
	t += delta
	var p: Vector3 = ctx.player.global_position
	orb.global_position = p + Vector3(0.6, 2.0 + sin(t * 2.0) * 0.1, 0.0)
	lamp.global_position = orb.global_position
	lamp.light_energy = 6.0 + sin(t * 3.0) * 0.4


func seen_from(from: Vector3, _viewer: Node) -> Array:
	if visible:
		return ["a golden orb of light floating beside the wanderer"]
	return []
