extends Node3D
## Marigold's moonbread in your hand. [bread] (she gives you a loaf) puts a glowing loaf in your right hand;
## press F to eat it and you glow warmly for 30 seconds. state["bread_held"] = the loaf is in hand.

const GLOW_TIME := 30.0

var ctx: Dictionary
var W
var loaf: Node3D
var aura: OmniLight3D
var glow_left := 0.0
var spin := 0.0


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	for old in W.camera.get_children():
		if old.name == "Moonbread":
			old.free()
	loaf = Node3D.new()
	loaf.name = "Moonbread"
	loaf.position = Vector3(0.3, -0.26, -0.5)
	loaf.rotation_degrees = Vector3(-8, 20, 0)
	# a stepped, golden-crusted loaf (three tiers, each touching the last) with a glowing crescent moon on top
	W.box(loaf, Vector3(0, 0, 0), Vector3(0.28, 0.06, 0.15), Color("#b87a3d"))  # dark base crust
	W.box(loaf, Vector3(0, 0.055, 0), Vector3(0.25, 0.05, 0.13), Color("#d49a52"))  # middle
	W.box(loaf, Vector3(0, 0.0975, 0), Vector3(0.19, 0.035, 0.10), Color("#e8b872"))  # pale golden top
	W.box(loaf, Vector3(-0.01, 0.12, 0), Vector3(0.07, 0.01, 0.07), Color("#d8f2ff"))  # moon disc
	W.box(loaf, Vector3(0.015, 0.13, 0), Vector3(0.06, 0.01, 0.06), Color("#e8b872"))  # bite out of it: a crescent
	loaf.visible = ctx.state.get("bread_held", false)
	W.camera.add_child(loaf)
	aura = OmniLight3D.new()
	aura.light_color = Color("#bfe8ff")
	aura.omni_range = 7.0
	aura.light_energy = 0.0
	ctx.player.add_child(aura)
	aura.position = Vector3(0, 1.2, 0)


func _exit_tree() -> void:
	for n in [loaf, aura]:
		if n and is_instance_valid(n):
			n.queue_free()


func give() -> void:
	ctx.state["bread_held"] = true
	loaf.visible = true
	W.show_notice("Marigold gave you a loaf of moonbread. Press F to eat it.", 5.0)
	var m = ctx.parts.get("marigold")
	if m:
		ctx.state["moonbread"] = maxi(int(ctx.state.get("moonbread", 0)) - 1, 0)
		m.show_loaves()


func key(event: InputEventKey) -> void:
	if event.keycode == KEY_F and ctx.state.get("bread_held", false):
		ctx.state["bread_held"] = false
		loaf.visible = false
		glow_left = GLOW_TIME
		W.show_notice("Warm and sweet. You glow.", 4.0)


func _process(delta: float) -> void:
	if not aura:
		return
	spin += delta
	glow_left = maxf(glow_left - delta, 0.0)
	aura.light_energy = (1.2 + sin(spin * 3.0) * 0.25) * minf(glow_left, 2.0) / 2.0


func describe() -> String:
	return "the wanderer is holding a loaf of moonbread" if ctx.state.get("bread_held", false) else ""


func handle(c: Dictionary) -> bool:
	if c.get("cmd", "") == "bread":
		give()
		return true
	return false
