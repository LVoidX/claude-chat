extends Node3D
## Flight for the user: [fly] switches it on, [land] off. world.gd's physics reads state["flying"]
## (Space up, Ctrl down, WASD along the ground, Shift faster).

var ctx: Dictionary


func build(c: Dictionary) -> void:
	ctx = c


func handle(c: Dictionary) -> bool:
	match c.get("cmd", ""):
		"fly":
			ctx.state["flying"] = true
			ctx.world.show_notice("Flight: W goes where you look, Space up, Ctrl down, Shift faster")
		"land":
			ctx.state["flying"] = false
		_:
			return false
	return true


func seen_from(_from: Vector3, _viewer: Node) -> Array:
	return []
