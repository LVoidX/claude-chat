extends Node3D
## The RPG layer: your level, health, gold and inventory, the quests on the village board, the smith's shop,
## and the screens for all of it. Enemies (creatures.gd) and things to gather (gathering.gd) report to it.
##
## Keys: I inventory, J quest journal, E use what you stand next to (board, smith, ore), Q drink a potion.
## Fighting: take the sword (hotbar key 2) and left click. Your damage = the equipped weapon + your level.
## Dying sends you back to the village well with full health, minus a tenth of your gold.
##
## For other parts (ctx.parts["rpg"]): give(item, n), take(item, n) -> bool, count(item), add_xp(n),
## add_gold(n), hurt(amount, source_name), strike_damage(), event(kind, what) (e.g. "kill", "wolf" or
## "gather", "herb": quest progress). A part can offer things to use with E through
## interactables() -> [{"pos": Vector3, "label": "Mine iron ore", "act": Callable, "range": 2.5}].
## Chat commands (Barnaby and Marigold can use them): [give potion 2], [give gold 20], [xp 50], [heal].
##
## state["rpg"] = {level, xp, hp, gold, inv: {item: count}, weapon, armor, quests: {id: {"st", "n"}}}.

const ITEMS := {
	"gold": {"name": "Gold", "kind": "money", "desc": "Coins.", "price": 1},
	"potion": {"name": "Healing Potion", "kind": "use", "heal": 40, "price": 12,
		"desc": "A red draught. Restores 40 health. (Q drinks one.)"},
	"mushroom": {"name": "Woodcap Mushroom", "kind": "use", "heal": 12, "price": 3,
		"desc": "A brown forest mushroom. Restores 12 health."},
	"herb": {"name": "Healing Herb", "kind": "loot", "price": 3, "desc": "Silverleaf, the healers' favourite."},
	"pelt": {"name": "Wolf Pelt", "kind": "loot", "price": 7, "desc": "Thick grey fur. The tanner wants these."},
	"bone": {"name": "Old Bone", "kind": "loot", "price": 4, "desc": "Yellowed and cold. It rattles faintly."},
	"ore": {"name": "Iron Ore", "kind": "loot", "price": 9, "desc": "A lump of rust-red rock, heavy with iron."},
	"tusk": {"name": "Troll Tusk", "kind": "loot", "price": 70, "desc": "As long as your forearm. Proof of a mighty deed."},
	"ring": {"name": "Miller's Ring", "kind": "quest", "price": 0, "desc": "A plain gold band, engraved 'H & E'."},
	"rusty_sword": {"name": "Rusty Sword", "kind": "weapon", "dmg": 3, "price": 5, "desc": "Better than a stick. Barely."},
	"iron_sword": {"name": "Iron Sword", "kind": "weapon", "dmg": 6, "price": 60, "desc": "Honest village steel."},
	"steel_sword": {"name": "Troll-Bane", "kind": "weapon", "dmg": 11, "price": 150,
		"desc": "A blue-steel blade forged from the troll's bounty."},
	"leather": {"name": "Leather Armour", "kind": "armor", "def": 2, "price": 40, "desc": "Stiff wolf leather. Blocks 2 damage a hit."},
	"chainmail": {"name": "Chainmail", "kind": "armor", "def": 5, "price": 130, "desc": "Rings of iron. Blocks 5 damage a hit."},
}

## The quest board. kind "kill" counts kills of `what`, "bring" wants `n` of an item handed in at the board,
## "find" wants the item found once. Rewards: xp, gold, items.
const QUESTS := [
	{"id": "wolves", "title": "Wolf Trouble", "level": 1, "kind": "kill", "what": "wolf", "n": 5,
		"text": "The shepherd has lost three lambs this week. Wolves prowl the woods around the meadow. Thin the packs.",
		"xp": 70, "gold": 30, "items": {"potion": 2}},
	{"id": "herbs", "title": "The Healer's Errand", "level": 1, "kind": "bring", "what": "herb", "n": 6,
		"text": "Silverleaf grows wild at the edges of the meadow, glowing faintly green. Bring six sprigs for the healer's salves.",
		"xp": 40, "gold": 15, "items": {"potion": 3}},
	{"id": "ring", "title": "The Miller's Ring", "level": 1, "kind": "find", "what": "ring", "n": 1,
		"text": "Old Hob the miller lost his wedding ring somewhere near the windmill on the eastern hill. Look for a glint in the grass.",
		"xp": 45, "gold": 35, "items": {}},
	{"id": "pelts", "title": "A Warm Winter", "level": 2, "kind": "bring", "what": "pelt", "n": 4,
		"text": "The tanner will turn four good wolf pelts into armour, and let you keep it.",
		"xp": 50, "gold": 0, "items": {"leather": 1}},
	{"id": "ore", "title": "Iron for the Anvil", "level": 2, "kind": "bring", "what": "ore", "n": 5,
		"text": "The smith's iron ran out. Rust-red ore rocks crop out on the high slopes. Press E at one to mine it.",
		"xp": 70, "gold": 20, "items": {"iron_sword": 1}},
	{"id": "barrow", "title": "The Restless Dead", "level": 3, "kind": "kill", "what": "skeleton", "n": 6,
		"text": "Something has stirred the old barrow in the north-western woods. The dead walk there. Put them back to rest.",
		"xp": 140, "gold": 60, "items": {"potion": 2}},
]

## What the smith sells (and he buys everything that has a price, for half of it).
const SHOP := ["potion", "iron_sword", "leather", "chainmail"]

const BOARD := Vector3(-30, 0, -5.5)  # the quest board, by the village road
const SMITHY := Vector3(-30, 0, 8)  # the smith's forge, across the road
const RESPAWN := Vector3(-38, 0.5, 2)  # where you wake up after dying (by the village well)
const STRIKE_EVERY := 0.42  # seconds between sword hits that land

var ctx: Dictionary
var W
var layer: CanvasLayer
var hp_bar: ProgressBar
var xp_bar: ProgressBar
var hp_text: Label
var level_text: Label
var gold_text: Label
var prompt_label: Label
var tracker: Label
var hurt_flash: ColorRect
var panel: PanelContainer  # the open screen (inventory, journal, board, shop), or null
var panel_kind := ""
var last_strike := -10.0
var regen := 0.0
var near_act: Dictionary = {}  # the interactable you are standing next to
var smith_fire: OmniLight3D
var fire_t := 0.0
var _styles := {}


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	var s: Dictionary = ctx.state.get_or_add("rpg", {})
	for key in ["level", "xp", "gold"]:
		if not s.has(key):
			s[key] = {"level": 1, "xp": 0, "gold": 10}[key]
	if not s.has("inv"):
		s["inv"] = {"potion": 2}
	if not s.has("weapon"):
		s["weapon"] = "rusty_sword"
	if not s.has("armor"):
		s["armor"] = ""
	if not s.has("quests"):
		s["quests"] = {}
	if not s.has("hp"):
		s["hp"] = max_hp()
	build_board()
	build_smithy()
	build_hud()
	refresh_hud()


func st() -> Dictionary:
	return ctx.state["rpg"]


# --- numbers ---------------------------------------------------------------------------------------------

func max_hp() -> int:
	return 50 + 12 * (int(st().level) - 1)


func xp_needed() -> int:  # xp to go from this level to the next
	return 40 + 40 * int(st().level)


func defense() -> int:
	var armor: String = st().armor
	return int(ITEMS[armor].get("def", 0)) if armor in ITEMS else 0


const TEMP_SWORD_DAMAGE := 30  # temporary, asked for by the user: every sword hit does this; set to 0 to go back to normal


func strike_damage() -> int:
	if TEMP_SWORD_DAMAGE > 0:
		return TEMP_SWORD_DAMAGE
	var weapon: String = st().weapon
	var base := int(ITEMS[weapon].get("dmg", 1)) if weapon in ITEMS else 1
	return base + int(st().level) - 1


## Called by the sword: true if this swing may land (hits are spaced out a little).
func may_strike() -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - last_strike < STRIKE_EVERY:
		return false
	last_strike = now
	return true


# --- inventory -------------------------------------------------------------------------------------------

func count(item: String) -> int:
	if item == "gold":
		return int(st().gold)
	return int(st().inv.get(item, 0))


func give(item: String, n := 1, quiet := false) -> void:
	if n <= 0 or not item in ITEMS:
		return
	if item == "gold":
		add_gold(n, quiet)
		return
	st().inv[item] = count(item) + n
	if not quiet:
		sfx("pickup")
		W.show_notice("+%d %s" % [n, ITEMS[item].name] if n > 1 else "+ " + ITEMS[item].name)
	if item == "ring":
		event("find", "ring")
	refresh_hud()
	refresh_panel()


func take(item: String, n := 1) -> bool:
	if count(item) < n:
		return false
	if item == "gold":
		st().gold = count("gold") - n
	else:
		st().inv[item] = count(item) - n
		if st().inv[item] <= 0:
			st().inv.erase(item)
			if st().weapon == item:
				st().weapon = ""
			if st().armor == item:
				st().armor = ""
	refresh_hud()
	refresh_panel()
	return true


func add_gold(n: int, quiet := false) -> void:
	st().gold = count("gold") + n
	if not quiet and n > 0:
		sfx("coin")
		W.show_notice("+%d gold" % n)
	refresh_hud()


func sfx(sound: String) -> void:  # music.gd makes the jingles ("levelup", "quest", "chapter")
	var music = ctx.parts.get("music")
	if music:
		music.play_sfx.call_deferred({"handin": "quest"}.get(sound, sound))


func add_xp(n: int) -> void:
	st().xp = int(st().xp) + n
	while int(st().xp) >= xp_needed():
		st().xp = int(st().xp) - xp_needed()
		st().level = int(st().level) + 1
		st().hp = max_hp()
		W.show_notice("LEVEL UP!  You are now level %d.  Health %d, damage +%d" % [st().level, max_hp(), int(st().level) - 1], 5.0)
		level_up_burst()
		sfx("levelup")
		W.send({"t": "notice", "text": "level %d" % st().level})
	refresh_hud()
	refresh_panel()


## Use or equip an item from the inventory.
func use(item: String) -> void:
	if count(item) <= 0 or not item in ITEMS:
		return
	var info: Dictionary = ITEMS[item]
	match info.kind:
		"use":
			if int(st().hp) >= max_hp():
				W.show_notice("You are already at full health.")
				return
			take(item, 1)
			heal(int(info.heal))
			W.show_notice("You drink the %s." % info.name.to_lower() if item == "potion" else "You eat the %s." % info.name.to_lower())
		"weapon":
			st().weapon = item
			var hotbar = ctx.parts.get("hotbar")  # the sword in your hand changes too
			if hotbar and hotbar.has_method("make_sword"):
				hotbar.make_sword()
				hotbar.sword.visible = hotbar.held()
			W.show_notice("You draw the %s (damage %d)." % [info.name, strike_damage()])
		"armor":
			st().armor = "" if st().armor == item else item
			W.show_notice("You put on the %s." % info.name if st().armor == item else "You take off the %s." % info.name)
	refresh_hud()
	refresh_panel()


func heal(n: int) -> void:
	st().hp = mini(int(st().hp) + n, max_hp())
	refresh_hud()


## An enemy hits you. Armour blocks some of it (never all).
func hurt(amount: int, source := "") -> void:
	if panel_kind == "dead":
		return
	var music = ctx.parts.get("music")
	if music:
		music.play_sfx("hurt")
	var hotbar = ctx.parts.get("hotbar")
	if hotbar and hotbar.get("blocking"):  # caught on the blade: a quarter gets through
		amount = int(ceil(amount * 0.25))
		sfx("hit")
	var taken := maxi(amount - defense(), 1)
	st().hp = int(st().hp) - taken
	hurt_flash.color.a = clampf(0.25 + taken * 0.02, 0.25, 0.55)
	if int(st().hp) <= 0:
		die(source)
	refresh_hud()


func die(source: String) -> void:
	var lost := int(count("gold") * 0.1)
	st().gold = count("gold") - lost
	st().hp = max_hp()
	W.player.position = RESPAWN
	W.player.velocity = Vector3.ZERO
	var by := (" by %s" % source) if source != "" else ""
	W.show_notice("You were struck down%s. You wake by the village well%s." % [by, (", %d gold lighter" % lost) if lost > 0 else ""], 6.0)
	var creatures = ctx.parts.get("creatures")
	if creatures and creatures.has_method("calm_down"):
		creatures.calm_down()


# --- quests ----------------------------------------------------------------------------------------------

func quest(id: String) -> Dictionary:
	for q in QUESTS:
		if q.id == id:
			return q
	return {}


func qstate(id: String) -> String:  # "" (not taken), "active", "done"
	return st().quests.get(id, {}).get("st", "")


func progress(q: Dictionary) -> int:
	match q.kind:
		"kill":
			return mini(int(st().quests.get(q.id, {}).get("n", 0)), q.n)
		_:
			return mini(count(q.what), q.n)


func ready_to_hand_in(q: Dictionary) -> bool:
	return qstate(q.id) == "active" and progress(q) >= int(q.n)


## Something happened that quests may count: ("kill", "wolf"), ("find", "ring"), ...
func event(kind: String, what: String) -> void:
	var story = ctx.parts.get("story")  # the main story's quests count too
	if story:
		story.event(kind, what)
	for q in QUESTS:
		if qstate(q.id) != "active" or q.what != what:
			continue
		if kind == "kill" and q.kind == "kill":
			var entry: Dictionary = st().quests[q.id]
			entry["n"] = int(entry.get("n", 0)) + 1
			if int(entry.n) == int(q.n):
				W.show_notice("%s: done! Return to the quest board." % q.title, 5.0)
			elif int(entry.n) < int(q.n):
				W.show_notice("%s %d/%d" % [q.title, entry.n, q.n])
		elif q.kind in ["bring", "find"] and progress(q) == int(q.n):
			W.show_notice("%s: you have what you need. Return to the quest board." % q.title, 5.0)
	refresh_hud()


func accept(id: String) -> void:
	st().quests[id] = {"st": "active", "n": 0}
	W.show_notice("New quest: " + quest(id).title, 4.0)
	refresh_hud()
	refresh_panel()


func hand_in(id: String) -> void:
	var q := quest(id)
	if not ready_to_hand_in(q):
		return
	if q.kind in ["bring", "find"]:
		take(q.what, int(q.n))
	st().quests[id] = {"st": "done", "n": q.n}
	var got := []
	if int(q.gold) > 0:
		add_gold(int(q.gold), true)
		got.append("%d gold" % q.gold)
	for item in q.items:
		give(item, int(q.items[item]), true)
		got.append(("%d %s" % [q.items[item], ITEMS[item].name]) if int(q.items[item]) > 1 else ITEMS[item].name)
	W.show_notice("Quest complete: %s!  %s" % [q.title, ", ".join(got)], 6.0)
	sfx("quest")
	add_xp(int(q.xp))
	refresh_panel()


func quest_line(q: Dictionary) -> String:
	var n := progress(q)
	var what: String = {"kill": "slain", "bring": "gathered", "find": "found"}[q.kind]
	return "%s  (%d/%d %s)%s" % [q.title, n, q.n, what, "  - return to the board" if n >= int(q.n) else ""]


# --- places: the quest board and the smithy ---------------------------------------------------------------

func at_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, W.ground_y(p.x, p.z), p.z)


func build_board() -> void:
	var board := Node3D.new()
	board.position = at_ground(BOARD)
	board.rotation.y = PI  # faces the road (south)
	add_child(board)
	var wood := Color("#5a3d24")
	W.box(board, Vector3(-1.1, 1.2, 0), Vector3(0.16, 2.4, 0.16), wood, "cube", true)
	W.box(board, Vector3(1.1, 1.2, 0), Vector3(0.16, 2.4, 0.16), wood, "cube", true)
	W.box(board, Vector3(0, 1.55, 0), Vector3(2.1, 1.3, 0.08), Color("#7a5634"))  # the board
	W.box(board, Vector3(0, 2.38, 0.05), Vector3(2.6, 0.12, 0.5), Color("#4a3220"))  # little roof
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 7:  # notices pinned to it
		var p := Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(1.1, 2.0), -0.05)
		var paper: MeshInstance3D = W.box(board, p, Vector3(rng.randf_range(0.3, 0.42), rng.randf_range(0.3, 0.45), 0.01), Color("#e8dcb8"))
		paper.rotation.z = rng.randf_range(-0.15, 0.15)
	var sign := Label3D.new()
	sign.text = "QUESTS"
	sign.font_size = 64
	sign.outline_size = 12
	sign.modulate = Color("#ffd24d")
	sign.position = Vector3(0, 2.75, 0)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign.pixel_size = 0.006
	board.add_child(sign)
	W.light(board, Vector3(0, 2.2, -0.8), Color("#ffb060"), 1.2, 6.0)


func build_smithy() -> void:
	var smithy := Node3D.new()
	smithy.position = at_ground(SMITHY)
	add_child(smithy)
	var kit = ctx.parts.get("kit")
	var stone: Material = kit.mat("stone") if kit else W.mat(Color("#77736c"))
	var timber := Color("#4a3220")
	for x in [-2.4, 2.4]:  # an open shed: four posts and a roof
		for z in [-1.6, 1.6]:
			W.box(smithy, Vector3(x, 1.4, z), Vector3(0.22, 2.8, 0.22), timber, "cube", true)
	var roof: MeshInstance3D = W.box(smithy, Vector3(0, 3.0, 0), Vector3(5.6, 0.18, 4.0), Color("#5c4a3a"))
	roof.rotation.x = -0.12
	var forge: MeshInstance3D = W.box(smithy, Vector3(-1.5, 0.6, 0.6), Vector3(1.4, 1.2, 1.4), Color.WHITE, "cube", true)
	forge.material_override = stone
	W.glow(smithy, Vector3(-1.5, 1.22, 0.6), Vector3(0.9, 0.06, 0.9), Color("#ff6a1a"), 3.0)  # embers
	smith_fire = W.light(smithy, Vector3(-1.5, 1.7, 0.6), Color("#ff7a30"), 2.0, 7.0)
	W.box(smithy, Vector3(0.9, 0.35, -0.2), Vector3(0.5, 0.7, 0.5), Color("#4a3220"), "cube", true)  # anvil block
	W.box(smithy, Vector3(0.9, 0.8, -0.2), Vector3(0.9, 0.22, 0.34), Color("#3a3d42"))  # anvil
	W.box(smithy, Vector3(1.4, 0.8, -0.2), Vector3(0.3, 0.12, 0.2), Color("#3a3d42"))  # its horn
	for i in 3:  # swords on a rack
		var blade: MeshInstance3D = W.box(smithy, Vector3(2.2, 1.3, -0.9 + i * 0.5), Vector3(0.04, 1.0, 0.1), Color("#c9d1d9"))
		blade.rotation.x = 0.1
	# the smith: a stout figure in a leather apron
	var smith := Node3D.new()
	smith.position = Vector3(0.2, 0, 0.9)
	smith.rotation.y = PI * 0.15
	smithy.add_child(smith)
	W.box(smith, Vector3(-0.16, 0.42, 0), Vector3(0.22, 0.84, 0.26), Color("#3a2d22"))
	W.box(smith, Vector3(0.16, 0.42, 0), Vector3(0.22, 0.84, 0.26), Color("#3a2d22"))
	W.box(smith, Vector3(0, 1.22, 0), Vector3(0.7, 0.8, 0.42), Color("#8a4a2a"))  # shirt
	W.box(smith, Vector3(0, 1.08, 0.22), Vector3(0.6, 0.95, 0.04), Color("#5a3a20"))  # apron
	W.box(smith, Vector3(-0.45, 1.25, 0), Vector3(0.2, 0.7, 0.22), Color("#d9a07a"))  # arms
	W.box(smith, Vector3(0.45, 1.25, 0), Vector3(0.2, 0.7, 0.22), Color("#d9a07a"))
	W.box(smith, Vector3(0, 1.85, 0), Vector3(0.42, 0.44, 0.42), Color("#d9a07a"))  # head
	W.box(smith, Vector3(0, 1.7, 0.2), Vector3(0.4, 0.22, 0.06), Color("#3b2414"))  # beard
	W.box(smith, Vector3(0, 2.08, 0), Vector3(0.44, 0.08, 0.44), Color("#2a1a10"))  # hair
	var sign := Label3D.new()
	sign.text = "SMITH"
	sign.font_size = 56
	sign.outline_size = 12
	sign.modulate = Color("#ffb070")
	sign.position = Vector3(0, 3.5, 0)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign.pixel_size = 0.006
	smithy.add_child(sign)


func interactables() -> Array:
	return [
		{"pos": at_ground(BOARD), "label": "Read the quest board", "act": open_panel.bind("board"), "range": 3.2},
		{"pos": at_ground(SMITHY), "label": "Trade with the smith", "act": open_panel.bind("shop"), "range": 3.6},
	]


# --- the HUD ---------------------------------------------------------------------------------------------

func style(bg: Color, border: Color, width := 2, radius := 4) -> StyleBoxFlat:
	var key := "%s%s%d%d" % [bg, border, width, radius]
	if not key in _styles:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = border
		s.set_border_width_all(width)
		s.set_corner_radius_all(radius)
		s.content_margin_left = 10
		s.content_margin_right = 10
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		_styles[key] = s
	return _styles[key]


func label(text: String, size := 16, color := Color("#f2e6c8")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l


func bar(fill: Color, height: int) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(260, height)
	b.add_theme_stylebox_override("background", style(Color("#1a1009", 0.75), Color("#8a6a3a"), 2, 3))  # bronze frame
	var f := StyleBoxFlat.new()
	f.bg_color = fill
	f.set_corner_radius_all(3)
	b.add_theme_stylebox_override("fill", f)
	return b


func build_hud() -> void:
	layer = CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	hurt_flash = ColorRect.new()  # the screen flashes red when you are hit
	hurt_flash.color = Color(0.8, 0, 0, 0)
	hurt_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hurt_flash)
	var box := VBoxContainer.new()  # bottom left: level, health, xp, gold
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_left = 18
	box.offset_bottom = -18
	box.add_theme_constant_override("separation", 3)
	layer.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	level_text = label("", 20, Color("#ffd24d"))
	gold_text = label("", 18, Color("#ffe08a"))
	top.add_child(level_text)
	top.add_child(gold_text)
	box.add_child(top)
	hp_bar = bar(Color("#c0392b"), 20)
	hp_text = label("", 13)
	hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_bar.add_child(hp_text)
	box.add_child(hp_bar)
	xp_bar = bar(Color("#5b8cff"), 8)
	box.add_child(xp_bar)
	box.add_child(label("I inventory   J journal   Q potion   Right-click block   K music", 12, Color(1, 1, 1, 0.55)))
	prompt_label = label("", 20, Color.WHITE)  # "[E] Read the quest board"
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.offset_bottom = -96
	layer.add_child(prompt_label)
	tracker = label("", 16, Color("#f2e6c8"))  # the active quests, right side
	tracker.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tracker.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tracker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tracker.offset_top = 70
	tracker.offset_right = -18
	layer.add_child(tracker)


func refresh_hud() -> void:
	if not hp_bar:
		return
	hp_bar.max_value = max_hp()
	hp_bar.value = int(st().hp)
	hp_text.text = "%d / %d" % [st().hp, max_hp()]
	xp_bar.max_value = xp_needed()
	xp_bar.value = int(st().xp)
	level_text.text = "Level %d" % st().level
	gold_text.text = "%d gold" % count("gold")
	var text := ""
	var story = ctx.parts.get("story")  # the main story's chapter and quests first
	if story and story.built():
		var main: Array = story.tracker_lines()
		if not main.is_empty():
			text = story.chapter_title().to_upper() + "\n" + "\n".join(main) + "\n\n"
	var lines := []
	for q in QUESTS:
		if qstate(q.id) == "active":
			lines.append(quest_line(q))
	if lines:
		text += "QUESTS\n" + "\n".join(lines)
	tracker.text = text


# --- screens (inventory, journal, board, shop) ------------------------------------------------------------

func open_panel(kind: String) -> void:
	close_panel()
	panel_kind = kind
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style(Color(0.13, 0.09, 0.06, 0.94), Color("#c9a24a"), 3, 8))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(720, 460)
	if ctx.has("ui_theme"):
		panel.theme = ctx["ui_theme"]  # the book font (style.gd)
	layer.add_child(panel)
	ctx["ui_open"] = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh_panel()


func close_panel() -> void:
	if panel:
		panel.queue_free()
	panel = null
	panel_kind = ""
	ctx["ui_open"] = false


func button(text: String, action: Callable, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_stylebox_override("normal", style(Color("#3a2a1a"), Color("#8a6a3a"), 1, 4))
	b.add_theme_stylebox_override("hover", style(Color("#5a3e22"), Color("#e0b85a"), 1, 4))
	b.add_theme_stylebox_override("pressed", style(Color("#6a4a28"), Color("#ffd24d"), 1, 4))
	b.add_theme_stylebox_override("disabled", style(Color("#2a2018"), Color("#4a3a28"), 1, 4))
	b.pressed.connect(action)
	return b


func refresh_panel() -> void:
	if not panel:
		return
	for child in panel.get_children():
		child.queue_free()
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	var head := HBoxContainer.new()
	var title := label({"inventory": "INVENTORY", "journal": "QUEST JOURNAL", "board": "THE QUEST BOARD",
		"shop": "THE SMITH"}.get(panel_kind, ""), 24, Color("#ffd24d"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(label("%d gold" % count("gold"), 18, Color("#ffe08a")))
	head.add_child(button("Close (Esc)", close_panel))
	outer.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	match panel_kind:
		"inventory":
			fill_inventory(body)
		"journal":
			fill_journal(body)
		"board":
			fill_board(body)
		"shop":
			fill_shop(body)


func row(body: Control, text: String, sub: String, buttons: Array) -> void:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(label(text, 17))
	if sub != "":
		var s := label(sub, 13, Color("#c8b890"))
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size = Vector2(440, 0)
		words.add_child(s)
	r.add_child(words)
	for b in buttons:
		r.add_child(b)
	body.add_child(r)


func fill_inventory(body: VBoxContainer) -> void:
	var weapon: String = st().weapon
	var armor: String = st().armor
	body.add_child(label("Level %d   (%d / %d xp)      Health %d / %d      Damage %d      Armour %d" % [
		st().level, st().xp, xp_needed(), st().hp, max_hp(), strike_damage(), defense()], 16, Color("#ffd24d")))
	body.add_child(label("Weapon: %s      Armour: %s" % [ITEMS[weapon].name if weapon in ITEMS else "bare hands",
		ITEMS[armor].name if armor in ITEMS else "none"], 15, Color("#e8d9b0")))
	body.add_child(HSeparator.new())
	var items: Array = st().inv.keys()
	items.sort()
	if items.is_empty():
		body.add_child(label("Your pack is empty.", 16, Color("#c8b890")))
	for item in items:
		if not item in ITEMS:
			continue
		var info: Dictionary = ITEMS[item]
		var buttons := []
		match info.kind:
			"use":
				buttons.append(button("Use", use.bind(item)))
			"weapon":
				buttons.append(button("Equipped" if weapon == item else "Equip", use.bind(item), weapon != item))
			"armor":
				buttons.append(button("Take off" if armor == item else "Wear", use.bind(item)))
		var stat := ""
		if info.has("dmg"):
			stat = "  [damage %d]" % info.dmg
		elif info.has("def"):
			stat = "  [armour %d]" % info.def
		row(body, "%s  x%d%s" % [info.name, count(item), stat], info.desc, buttons)


func fill_journal(body: VBoxContainer) -> void:
	var story = ctx.parts.get("story")
	if story and story.built():
		body.add_child(label(story.chapter_title(), 19, Color("#ffd24d")))
		var intro := label(str(story.data.get("intro", "")), 14, Color("#e8d9b0"))
		intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		intro.custom_minimum_size = Vector2(660, 0)
		body.add_child(intro)
		for q in story.quests():
			var head: String = ("[done] " + q.title) if story.is_done(q.id) else q.title + story.progress_text(q)
			row(body, head, "" if story.is_done(q.id) else str(q.get("text", "")), [])
		if story.st().get("finished", false):
			body.add_child(label("This chapter is over. The next one is being written...", 14, Color("#8fb4ff")))
		body.add_child(HSeparator.new())
	var any := false
	for q in QUESTS:
		var s := qstate(q.id)
		if s == "":
			continue
		any = true
		var head: String = ("[done] " + q.title) if s == "done" else quest_line(q)
		row(body, head, "" if s == "done" else q.text, [])
	if not any:
		body.add_child(label("No quests yet. The quest board stands by the road into the village, west of the meadow.", 15, Color("#c8b890")))


func fill_board(body: VBoxContainer) -> void:
	for q in QUESTS:
		var s := qstate(q.id)
		var reward := "Reward: %d xp" % q.xp
		if int(q.gold) > 0:
			reward += ", %d gold" % q.gold
		for item in q.items:
			reward += ", " + (("%d %s" % [q.items[item], ITEMS[item].name]) if int(q.items[item]) > 1 else ITEMS[item].name)
		var buttons := []
		var title: String = q.title
		if s == "done":
			title += "   (completed)"
		elif s == "active":
			buttons.append(button("Hand in" if ready_to_hand_in(q) else "%d/%d" % [progress(q), q.n], hand_in.bind(q.id), ready_to_hand_in(q)))
		elif int(st().level) < int(q.level):
			buttons.append(button("Needs level %d" % q.level, func(): pass, false))
		else:
			buttons.append(button("Accept", accept.bind(q.id)))
		row(body, title, ("" if s == "done" else q.text + "\n") + reward, buttons)


func fill_shop(body: VBoxContainer) -> void:
	body.add_child(label("\"Need steel? Got coin? Then we'll get on.\"", 15, Color("#c8b890")))
	for item in SHOP:
		var info: Dictionary = ITEMS[item]
		var stat := ""
		if info.has("dmg"):
			stat = "  [damage %d]" % info.dmg
		elif info.has("def"):
			stat = "  [armour %d]" % info.def
		row(body, "%s%s   -   %d gold" % [info.name, stat, info.price], info.desc,
			[button("Buy", buy.bind(item), count("gold") >= int(info.price))])
	body.add_child(HSeparator.new())
	body.add_child(label("Sell (half price):", 17, Color("#ffd24d")))
	var items: Array = st().inv.keys()
	items.sort()
	for item in items:
		if not item in ITEMS or int(ITEMS[item].price) <= 0:
			continue
		var equipped: bool = st().weapon == item or st().armor == item
		var price := maxi(int(ITEMS[item].price) / 2, 1)
		row(body, "%s  x%d   -   %d gold each" % [ITEMS[item].name, count(item), price], "",
			[button("Sell", sell.bind(item), not (equipped and count(item) <= 1))])


func buy(item: String) -> void:
	if take("gold", int(ITEMS[item].price)):
		give(item, 1, true)
		W.show_notice("Bought: " + ITEMS[item].name)
		refresh_panel()


func sell(item: String) -> void:
	if take(item, 1):
		add_gold(maxi(int(ITEMS[item].price) / 2, 1), true)
		refresh_panel()


# --- input and the frame ---------------------------------------------------------------------------------

func key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_I:
			if panel_kind == "inventory":
				close_panel()
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				open_panel("inventory")
		KEY_J:
			if panel_kind == "journal":
				close_panel()
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				open_panel("journal")
		KEY_E:
			if panel:
				close_panel()
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			elif not near_act.is_empty() and not ctx.get("ui_open", false):  # (another part's screen is open)
				near_act.act.call()
		KEY_Q:
			if count("potion") > 0:
				use("potion")
			else:
				W.show_notice("No potions left. The smith sells them.")
		KEY_ESCAPE:
			if panel:
				close_panel()  # (world.gd frees the mouse on Esc; clicking the world grabs it again)


func _process(delta: float) -> void:
	if not layer:
		return
	layer.visible = W.camera.current
	if hurt_flash.color.a > 0.0:
		hurt_flash.color.a = maxf(hurt_flash.color.a - delta * 1.2, 0.0)
	regen += delta  # slow healing when nothing is hitting you
	if regen > 2.0:
		regen = 0.0
		if int(st().hp) < max_hp() and hurt_flash.color.a == 0.0:
			heal(1)
	fire_t += delta
	if smith_fire:
		smith_fire.light_energy = 1.8 + sin(fire_t * 9.0) * 0.25 + sin(fire_t * 23.0) * 0.15
	# what can you use with E from here?
	var best := {}
	var best_d := INF
	var at: Vector3 = W.player.global_position
	for part in ctx.parts.values():
		if not part.has_method("interactables"):
			continue
		for it in part.interactables():
			var d: float = Vector2(at.x - it.pos.x, at.z - it.pos.z).length()
			if d < float(it.get("range", 2.5)) and d < best_d and absf(at.y - it.pos.y) < 3.0:
				best = it
				best_d = d
	near_act = best
	prompt_label.text = "" if best.is_empty() or panel or ctx.get("ui_open", false) else "[E]  " + best.label


func level_up_burst() -> void:
	var at: Vector3 = W.player.global_position
	for i in 16:
		var spark: MeshInstance3D = W.glow(self, at + Vector3(0, 1, 0), Vector3.ONE * 0.12, Color("#ffd24d"), 4.0)
		var dir := Vector3(cos(i * TAU / 16.0), 0.6, sin(i * TAU / 16.0))
		var tw := create_tween()
		tw.tween_property(spark, "position", at + Vector3(0, 1, 0) + dir * 2.5, 0.8)
		tw.parallel().tween_property(spark, "scale", Vector3.ONE * 0.01, 0.8)
		tw.tween_callback(spark.queue_free)


# --- what the characters know, and their commands ---------------------------------------------------------

func seen_from(from: Vector3, _viewer: Node) -> Array:
	var seen := ["the wanderer is a level %d adventurer with %d of %d health and %d gold, wielding the %s" % [
		st().level, st().hp, max_hp(), count("gold"), ITEMS[st().weapon].name if st().weapon in ITEMS else "bare fists"]]
	var active := []
	for q in QUESTS:
		if qstate(q.id) == "active":
			active.append(quest_line(q))
	if active:
		seen.append("the wanderer's quests from the village board: " + "; ".join(active))
	seen.append("the village quest board, %s, and the smith's forge, %s" % [W.where(from, BOARD), W.where(from, SMITHY)])
	return seen


func handle(c: Dictionary) -> bool:
	var args: Array = c.get("args", [])
	match c.get("cmd", ""):
		"give":  # [give potion 2] / [give gold 20]
			if args.is_empty():
				return true
			var item := str(args[0]).to_lower()
			var n := int(args[1]) if args.size() > 1 else 1
			if not item in ITEMS:
				for id in ITEMS:  # a name like "healing potion" or "potions"
					if item.begins_with(id) or ITEMS[id].name.to_lower().contains(item):
						item = id
						break
			give(item, clampi(n, 1, 500))
		"xp":
			add_xp(clampi(int(args[0]) if args.size() > 0 else 20, 1, 1000))
		"heal":
			heal(max_hp())
			W.show_notice("You feel whole again.")
		_:
			return false
	return true
