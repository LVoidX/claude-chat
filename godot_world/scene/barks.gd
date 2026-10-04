extends Node3D
## Villagers talk as you pass: a short line over their head about what is going on, and it follows the story,
## so the world visibly remembers what you did (the troll slain, the bandits gone, the barrow stirring...), plus
## your level, the weather and the time of day. One line at a time, each person at most every 40 s.
## New story flags: add lines to FLAG_LINES ("flag=value": [...]); the storyteller may add them too.

const RANGE := 5.5
const FLAG_LINES := {
	"troll=slain": ["They say you put Gorrak's head on a pike. Good riddance!", "No more troll on the east road, thanks to you.",
		"Sheep are safe again. Bless you, traveller."],
	"troll=appeased": ["Gorrak guards the road now. Strangest bargain I ever heard of.", "Paid a troll in pelts... well, it worked."],
	"camp=bandits": ["Bandits in Gorrak's old camp! A red flag over the east road.", "The miller won't leave his mill. Can you blame him?", "First a troll, now thieves. The east road is cursed."],
	"camp=cleared": ["You drove those bandits off! The road is ours again.", "The watch fire burns at the old camp now."],
	"camp=tolled": ["A coin at the toll post, every time... still better than robbery.", "Bandits taking tolls. What a world."],
	"bandits=routed": ["The bandit camp is ash. Well done.", "Merchants are coming back up the east road."],
	"bandits=bribed": ["Those bandits wave at me now. I don't like it.", "Paid off, are they? For how long..."],
	"barrow=stirring": ["Green lights at the old barrow at night... stay away from there.", "My grandmother said the dead kings would wake. She was right.",
		"Those paid bandits looted the barrow, they say. The dead want their gold back."],
	"barrow=laid": ["The barrow is quiet again. Candles and flowers. You did that.", "I slept well last night, first time in weeks."],
	"barrow=sealed": ["They walled up the barrow. Good. Leave it shut.", "Blue wards on the barrow door. Gives me shivers."],
	"barrow=bargain": ["A bargain with the dead? You're braver than me. Or madder."],
	"castle=burnt": ["Highmoor is burning! Did you see the smoke?", "Raiders in the castle... where will the guards sleep now?", "The Ashen Host. May they choke on their own smoke."],
	"castle=ruin": ["Highmoor is a black shell, but it's ours to rebuild.", "The raiders are gone. The castle is not coming back by itself.", "I can still smell the smoke on the north wind."],
	"host=camped": ["Varga's men bar the north road now. Toll for everything, even a loaf.", "A captain with horns on his helm sits in our castle. Wonderful.", "We paid them once. Now they want it again."],
	"host=broken": ["Varga's down. The Host scattered like crows.", "North road's open again. First honest traveller in weeks."],
	"host=gone": ["Varga took his iron and marched off. Good riddance, but who'll he rob next?", "Smoke-black men gone from the road. Feels strange."],
	"castle=rebuilt": ["Highmoor stands again! Red banners and blue, look at that.", "The guards are back on the wall. I sleep better.", "Fresh timber on the walls. Smells of sawdust and hope."],
	"castle=tolled": ["Raiders under a black banner on the hill. We paid for that.", "The Host keeps to the castle, as promised. I still lock my door."],
}
const ANY_LINES := ["Fine day for it.", "Mind the wolves in the woods, traveller.", "Folk round here always need a hand. Look for the ones with a gold mark over their heads.",
	"The smith's prices are robbery, but his steel is good.", "Marigold's bread is the best in the valley.",
	"Old Barnaby still talks about the sea. There's no sea here, Barnaby.", "Highmoor's guards don't let just anyone in."]
const NIGHT_LINES := ["Late to be out, friend.", "Keep to the lantern light.", "The red moon again... bad omen."]
const RAIN_LINES := ["Rain again! My boots will never dry.", "Good for the wheat, I suppose.", "Get under a roof, you'll catch your death."]

var ctx: Dictionary
var W
var bubble: Label3D
var speaker: Node3D
var until := 0.0
var last := {}  # node -> when they last spoke
var t := 0.0


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	bubble = Label3D.new()
	bubble.font_size = 34
	bubble.outline_size = 10
	bubble.pixel_size = 0.0009
	bubble.fixed_size = true
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.modulate = Color("#fff4d6")
	bubble.width = 900.0
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.visible = false
	add_child(bubble)


func lines_for() -> Array:
	var out := []
	var flags: Dictionary = ctx.state.get("story", {}).get("flags", {})
	for key in flags:
		var k := "%s=%s" % [key, flags[key]]
		if k in FLAG_LINES:
			out += FLAG_LINES[k]
			out += FLAG_LINES[k]  # (what you did comes up more often than small talk)
	if float(ctx.get("rain", 0.0)) > 0.5:
		out += RAIN_LINES
	elif float(ctx.get("night", 0.0)) > 0.5:
		out += NIGHT_LINES
	else:
		out += ANY_LINES
	var level := int(ctx.state.get("rpg", {}).get("level", 1))
	if level >= 5:
		out += ["Level %d? You've grown into quite the hero." % level, "Children play at being you now, you know."]
	elif level <= 2:
		out += ["New around here? Try the quest board, it pays."]
	return out


func _process(delta: float) -> void:
	t += delta
	if bubble.visible:
		if t > until or not is_instance_valid(speaker):
			bubble.visible = false
		else:
			bubble.global_position = speaker.global_position + Vector3(0, 2.75, 0)
		return
	var v = ctx.parts.get("villagers")
	if not v or not "folk" in v:
		return
	var me: Vector3 = W.player.global_position
	for f in v.folk:
		var node: Node3D = f.node
		if node.global_position.distance_to(me) < RANGE and t - float(last.get(node, -99.0)) > 40.0:
			last[node] = t
			speaker = node
			bubble.text = lines_for().pick_random()
			bubble.visible = true
			until = t + 4.5
			bubble.global_position = node.global_position + Vector3(0, 2.75, 0)
			return
