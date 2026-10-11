extends Node3D
## One-time tips that appear the first time they matter (a new player learns the game without a tutorial screen):
## welcome, talking by voice, work from villagers (the gold !), the sword, fishing, healing, resting at night.
## Each tip shows once (state["hints"] lists the ones already seen), at most one every 25 seconds, and none at all
## for someone who is already well into the game (level 3 or more).

const TIPS := {
	"welcome": "Welcome to Thornvale.  WASD walk, Shift run, mouse look.  E talks to or uses whatever you stand next to.",
	"talk": "You can simply SPEAK: stand beside someone and talk, they hear you and answer out loud.",
	"quest": "A gold ! over someone means they have work for you. Press E beside them to see it.",
	"sword": "Left click strikes, right click guards. Fight wolves from the front, with room to step back.",
	"fish": "Fishing: press E at the water's edge to cast, and E again the moment the float dips.",
	"hurt": "Hurt? Press Q to drink a potion, or rest by the campfire at the crossroads.",
	"night": "Night falls. The campfire at the crossroads is a safe place to sit (E) until morning (T).",
}
const GAP := 25.0  # seconds between tips

var ctx: Dictionary
var W
var since := 0.0
var next_check := 3.0


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	var seen: Array = ctx.state.get_or_add("hints", [])
	var rpg = ctx.parts.get("rpg")
	if seen.is_empty() and rpg and ctx.state.has("rpg") and int(ctx.state.rpg.get("level", 1)) >= 3:
		for k in TIPS:  # an old save: no tips
			seen.append(k)
	since = GAP - 6.0  # the welcome comes a few seconds after the game starts


func give_tip(id: String) -> void:
	var seen: Array = ctx.state["hints"]
	if id in seen:
		return
	seen.append(id)
	since = 0.0
	W.show_notice(TIPS[id], 8.0)


func _process(delta: float) -> void:
	since += delta
	next_check -= delta
	if next_check > 0.0 or since < GAP or not W.camera.current or ctx.get("ui_open", false):
		return
	next_check = 1.0
	var seen: Array = ctx.state["hints"]
	var rpg = ctx.parts.get("rpg")
	if not "welcome" in seen:
		give_tip("welcome")
	elif not "talk" in seen and str(W.near_who) != "":
		give_tip("talk")
	elif not "quest" in seen and rpg and not rpg.near_act.is_empty() and str(rpg.near_act.get("label", "")).begins_with("Quests from"):
		give_tip("quest")
	elif not "sword" in seen and ctx.state.get("sword_held", false):
		give_tip("sword")
	elif not "fish" in seen and ctx.parts.has("fishing") and ctx.parts.fishing.near_water():
		give_tip("fish")
	elif not "hurt" in seen and rpg and ctx.state.has("rpg") and float(rpg.st().hp) < 0.45 * float(rpg.max_hp()):
		give_tip("hurt")
	elif not "night" in seen and float(ctx.get("night", 0.0)) > 0.8:
		give_tip("night")
