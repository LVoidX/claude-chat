extends Node3D
## Marigold Thorne, the herbalist and baker, and her market stall (east of the middle, facing the middle).
## She wants moonblooms: glowing blue flowers scattered over the field. With five she can bake moonbread, her
## grandmother's recipe, which only works with flowers that glow under a red moon. Walk into a flower to pick it
## up, then walk up to her (the quest "moonbloom" must be active, she gives it when asked) and she takes five.
## She is built from boxes here in code (no model file), talks through the shared Talker in talk.gd, and
## the chat window treats her like Barnaby (npc_id "marigold", describe(), is_near(), commands say_start/say_end).

var npc_id := "marigold"
const STALL := Vector3(12, 0, 18)
const NEAR := 4.0
const WANDER := 2.4  # how far she strolls from her spot in front of the stall
const SPEED := 1.1
const QUEST_ID := "moonbloom"
const BLOOMS_NEEDED := 5
const BLOOM_COUNT := 12

var ctx: Dictionary
var W
var body: Node3D
var stall: Node3D
var talker: Node3D
var limbs := []  # [node, direction]
var braid: Node3D
var home := Vector3.ZERO  # her spot, in front of the stall
var target := Vector3.ZERO
var pause := 0.0
var phase := 0.0
const ERRAND_SPEED := 4.5  # how fast she hurries to fetch Barnaby
var errand_active := false  # set by Barnaby's [throw]
var errand_goal = null  # Vector3 she walks to while on that errand
var arms_up := false
var spin := 0.0
var oven_light: OmniLight3D
var oven_glow: MeshInstance3D
var flowers := []  # [node, index]
var loaves := []  # glowing moonbread on the counter
var bread_slots: Node3D


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	stall = Node3D.new()
	stall.position = STALL
	add_child(stall)
	W.face(stall, Vector3.ZERO)
	build_stall()
	home = STALL + (Vector3.ZERO - STALL).normalized() * 4.6
	body = Node3D.new()
	add_child(body)
	build_marigold()
	talker = ctx.parts["talk"].make(W, body, 2.15, Vector3(0, 1.56, -0.128), Vector3(0.05, 0.02, 0.012))
	var s: Dictionary = ctx.state.get_or_add("marigold", {"x": home.x, "z": home.z})
	body.position = Vector3(s.x, 0, s.z)
	target = body.position
	W.face(body, Vector3.ZERO)
	build_flowers()
	show_loaves()


# --- little helpers ------------------------------------------------------------------------------------------

func bx(parent: Node3D, pos: Vector3, size: Vector3, color: String, kind := "cube") -> MeshInstance3D:
	return W.box(parent, pos, size, Color(color), kind)


func solid(parent: Node3D, pos: Vector3, size: Vector3, color: String) -> MeshInstance3D:
	return W.box(parent, pos, size, Color(color), "cube", true)


func tilt(node: Node3D, x := 0.0, y := 0.0, z := 0.0) -> Node3D:
	node.rotation_degrees = Vector3(x, y, z)
	return node


func glow(parent: Node3D, pos: Vector3, size: Vector3, color: String, energy := 1.5, kind := "cube") -> MeshInstance3D:
	return W.glow(parent, pos, size, Color(color), energy, kind)


func light(parent: Node3D, pos: Vector3, color: String, energy: float, reach: float) -> OmniLight3D:
	return W.light(parent, pos, Color(color), energy, reach)


# --- the stall (local: front is -z, the counter is toward the front) -------------------------------------------

func build_stall() -> void:
	var wood := "#6b4a2b"
	var dark := "#4a321c"
	var plank := "#8a6238"
	# a rug in front, striped
	for i in 7:
		bx(stall, Vector3(-0.9 + i * 0.3, 0.012, -2.2), Vector3(0.3, 0.024, 1.5), "#8a2f3a" if i % 2 == 0 else "#e8d9b8")
	# posts, back wall, floor boards
	for px in [-1.9, 1.9]:
		for pz in [-1.1, 1.1]:
			solid(stall, Vector3(px, 1.3, pz), Vector3(0.14, 2.6, 0.14), wood)
	bx(stall, Vector3(0, 0.03, 0), Vector3(4.0, 0.06, 2.4), plank)
	solid(stall, Vector3(0, 1.15, 1.1), Vector3(3.8, 2.3, 0.1), dark)
	for i in 9:  # planks on the back wall
		bx(stall, Vector3(-1.7 + i * 0.425, 1.15, 1.04), Vector3(0.012, 2.2, 0.02), "#35230f")
	# counter with a lighter top and plank lines
	solid(stall, Vector3(0, 0.45, -0.9), Vector3(3.8, 0.9, 0.6), wood)
	bx(stall, Vector3(0, 0.94, -0.92), Vector3(4.0, 0.08, 0.78), plank)
	for i in 8:
		bx(stall, Vector3(-1.75 + i * 0.5, 0.45, -1.205), Vector3(0.015, 0.8, 0.012), dark)
	# awning: a tilted roof of red and cream stripes, with a scalloped front edge
	var awning := Node3D.new()
	awning.position = Vector3(0, 2.62, -0.1)
	awning.rotation_degrees = Vector3(-9, 0, 0)
	stall.add_child(awning)
	for i in 10:
		bx(awning, Vector3(-2.07 + i * 0.46, 0, 0), Vector3(0.46, 0.07, 3.0), "#b3323d" if i % 2 == 0 else "#f1e6d0")
		bx(awning, Vector3(-2.07 + i * 0.46, -0.16, -1.5), Vector3(0.46, 0.26, 0.04), "#b3323d" if i % 2 == 0 else "#f1e6d0")
		bx(awning, Vector3(-2.07 + i * 0.46, -0.32, -1.5), Vector3(0.3, 0.12, 0.04), "#b3323d" if i % 2 == 0 else "#f1e6d0", "sphere")
	# a wooden sign hung under the awning, text on both faces
	solid(stall, Vector3(0, 2.2, -1.25), Vector3(2.5, 0.46, 0.06), plank)
	bx(stall, Vector3(-1.15, 2.4, -1.25), Vector3(0.025, 0.2, 0.025), dark)
	bx(stall, Vector3(1.15, 2.4, -1.25), Vector3(0.025, 0.2, 0.025), dark)
	var sign := Label3D.new()
	sign.text = "MARIGOLD'S"
	sign.font_size = 92
	sign.pixel_size = 0.0036
	sign.modulate = Color("#2b1a0a")
	sign.outline_size = 0
	sign.position = Vector3(0, 2.26, -1.285)
	sign.rotation_degrees = Vector3(0, 180, 0)
	stall.add_child(sign)
	var sub := Label3D.new()
	sub.text = "bread  herbs  remedies"
	sub.font_size = 54
	sub.pixel_size = 0.0034
	sub.modulate = Color("#4a2f16")
	sub.outline_size = 0
	sub.position = Vector3(0, 2.1, -1.285)
	sub.rotation_degrees = Vector3(0, 180, 0)
	stall.add_child(sub)
	# shelves with jars on the back wall
	for row in 2:
		var y := 1.0 + row * 0.6
		bx(stall, Vector3(0, y, 0.88), Vector3(3.5, 0.05, 0.36), plank)
		for k in 8:
			var jx := -1.5 + k * 0.43
			var colors := ["#7ac77a", "#d9a441", "#a477c9", "#c9533d", "#e8d9b8", "#5aa5b8"]
			var col: String = colors[(k + row * 3) % colors.size()]
			bx(stall, Vector3(jx, y + 0.13, 0.88), Vector3(0.17, 0.22, 0.17), col)
			bx(stall, Vector3(jx, y + 0.26, 0.88), Vector3(0.12, 0.05, 0.12), "#8a6238")  # cork
			bx(stall, Vector3(jx, y + 0.13, 0.795), Vector3(0.11, 0.08, 0.012), "#f1e6d0")  # label
	# herbs hanging from the awning beam
	for i in 9:
		var hx := -1.6 + i * 0.4
		var hang := Node3D.new()
		hang.position = Vector3(hx, 2.5, 0.35)
		stall.add_child(hang)
		bx(hang, Vector3(0, -0.12, 0), Vector3(0.012, 0.24, 0.012), "#8a6238")
		var tuft: String = ["#4f8f4a", "#a477c9", "#d98a40", "#7ac77a"][i % 4]
		bx(hang, Vector3(0, -0.34, 0), Vector3(0.1, 0.2, 0.1), tuft, "sphere")
		bx(hang, Vector3(0.03, -0.46, 0.01), Vector3(0.06, 0.12, 0.06), tuft, "sphere")
		bx(hang, Vector3(0, -0.22, 0), Vector3(0.05, 0.03, 0.05), "#d9a441")  # twine
	# goods on the counter: loaves, baguettes, buns, a pie, a kettle
	bx(stall, Vector3(-1.4, 1.0, -0.9), Vector3(0.8, 0.03, 0.4), "#a5733c")  # board
	for i in 3:
		bx(stall, Vector3(-1.65 + i * 0.3, 1.1, -0.9), Vector3(0.26, 0.15, 0.2), "#b87a3a", "sphere")
		bx(stall, Vector3(-1.65 + i * 0.3, 1.16, -0.9), Vector3(0.2, 0.03, 0.02), "#e0b574")  # score marks
	for i in 3:
		var bag := bx(stall, Vector3(-0.7, 1.05 + i * 0.075, -0.85 - i * 0.04), Vector3(0.09, 0.07, 0.62), "#c98a45")
		tilt(bag, 0, 12 - i * 10, 0)
	bx(stall, Vector3(0.1, 1.0, -0.95), Vector3(0.55, 0.04, 0.5), "#d8d8d4")  # a basket tray
	for i in 6:
		bx(stall, Vector3(-0.05 + (i % 3) * 0.14, 1.07, -1.0 + int(i / 3) * 0.14), Vector3(0.12, 0.11, 0.12), "#d9a059", "sphere")
	bx(stall, Vector3(1.0, 1.0, -0.9), Vector3(0.42, 0.07, 0.42), "#8a5a2b")  # pie dish
	bx(stall, Vector3(1.0, 1.065, -0.9), Vector3(0.38, 0.06, 0.38), "#d9a441")
	for i in 3:
		var lat := bx(stall, Vector3(1.0, 1.1, -0.9), Vector3(0.38, 0.015, 0.03), "#b8782f")
		tilt(lat, 0, 30 + i * 40, 0)
	bx(stall, Vector3(1.6, 1.12, -0.9), Vector3(0.22, 0.2, 0.22), "#9aa0a8", "sphere")  # kettle
	bx(stall, Vector3(1.6, 1.26, -0.9), Vector3(0.07, 0.05, 0.07), "#6a6f78", "sphere")
	var spout := bx(stall, Vector3(1.6, 1.16, -1.03), Vector3(0.03, 0.03, 0.12), "#9aa0a8")
	tilt(spout, -20, 0, 0)
	# a jar of moonblooms that glows (and the loaves of moonbread she bakes later sit next to it)
	bx(stall, Vector3(0.6, 1.1, -0.9), Vector3(0.18, 0.28, 0.18), "#cfeaf5")
	var jar_glow := glow(stall, Vector3(0.6, 1.1, -0.9), Vector3(0.12, 0.22, 0.12), "#7fd6ff", 2.0, "sphere")
	jar_glow.name = "JarGlow"
	light(stall, Vector3(0.6, 1.3, -0.9), "#7fd6ff", 0.7, 3.0)
	bread_slots = Node3D.new()
	bread_slots.position = Vector3(0.35, 1.0, -0.82)
	stall.add_child(bread_slots)
	# lantern on a post
	bx(stall, Vector3(-1.9, 2.3, -1.2), Vector3(0.02, 0.28, 0.02), dark)
	bx(stall, Vector3(-1.9, 2.1, -1.2), Vector3(0.18, 0.22, 0.18), "#3a2a1a")
	glow(stall, Vector3(-1.9, 2.1, -1.2), Vector3(0.13, 0.17, 0.13), "#ffb04d", 2.2)
	light(stall, Vector3(-1.9, 2.1, -1.2), "#ffb04d", 1.8, 9.0)
	# brick oven on the left side
	solid(stall, Vector3(-3.2, 0.55, 0.3), Vector3(1.3, 1.1, 1.2), "#7a7168")
	for r in 5:  # brick lines
		bx(stall, Vector3(-3.2, 0.2 + r * 0.22, -0.305), Vector3(1.3, 0.012, 0.012), "#4f4a44")
	solid(stall, Vector3(-3.2, 1.3, 0.3), Vector3(1.0, 0.5, 1.0), "#6b625a")
	bx(stall, Vector3(-3.2, 1.9, 0.3), Vector3(0.4, 0.8, 0.4), "#5a524b")  # chimney
	bx(stall, Vector3(-3.2, 2.35, 0.3), Vector3(0.5, 0.1, 0.5), "#4a443e")
	bx(stall, Vector3(-3.2, 0.55, -0.31), Vector3(0.6, 0.45, 0.02), "#1a1210")  # mouth of the oven
	oven_glow = glow(stall, Vector3(-3.2, 0.5, -0.32), Vector3(0.5, 0.3, 0.02), "#ff7a1a", 2.4)
	oven_light = light(stall, Vector3(-3.2, 0.6, -1.0), "#ff8a3a", 1.6, 7.0)
	# barrel, crates, a flour sack, a planter with herbs on the other side
	solid(stall, Vector3(2.9, 0.45, 0.6), Vector3(0.7, 0.9, 0.7), "#7a5530")
	for y in [0.18, 0.72]:
		bx(stall, Vector3(2.9, y, 0.6), Vector3(0.74, 0.05, 0.74), "#3a3a3e")
	solid(stall, Vector3(3.0, 0.2, -0.4), Vector3(0.6, 0.4, 0.6), plank)
	solid(stall, Vector3(3.05, 0.58, -0.38), Vector3(0.5, 0.36, 0.5), "#9a6e3e")
	bx(stall, Vector3(2.4, 0.2, 1.0), Vector3(0.5, 0.4, 0.34), "#e8dcc4", "sphere")  # flour sack
	bx(stall, Vector3(2.4, 0.42, 1.0), Vector3(0.18, 0.1, 0.16), "#d6c9ad", "sphere")
	solid(stall, Vector3(2.2, 0.17, -2.2), Vector3(1.8, 0.34, 0.6), wood)
	bx(stall, Vector3(2.2, 0.33, -2.2), Vector3(1.7, 0.04, 0.5), "#3a2616")  # soil
	for i in 7:
		var herb: Array = [["#4f8f4a", 0.22], ["#a477c9", 0.3], ["#7ac77a", 0.18], ["#d98a40", 0.2]][i % 4]
		bx(stall, Vector3(1.55 + i * 0.25, 0.35 + float(herb[1]) / 2.0, -2.2), Vector3(0.14, float(herb[1]), 0.14), herb[0], "sphere")


# --- Marigold herself (front is -z, about 1.7 m tall) --------------------------------------------------------------

func face_texture() -> Texture2D:
	var w := 48
	var h := 52
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var skin := Color("#f0c5a3")
	img.fill(skin)
	var put := func(x: int, y: int, c: Color, bw := 1, bh := 1):
		for dx in bw:
			for dy in bh:
				if x + dx >= 0 and x + dx < w and y + dy >= 0 and y + dy < h:
					img.set_pixel(x + dx, y + dy, c)
	for side in [-1, 1]:
		var cx: int = 24 + side * 10
		put.call(cx - 5, 21, Color("#fbf6ee"), 10, 7)  # eye white
		put.call(cx - 3, 21, Color("#3c8a58"), 6, 7)  # iris
		put.call(cx - 2, 22, Color("#2a6a42"), 4, 5)
		put.call(cx - 1, 23, Color("#14221a"), 2, 3)  # pupil
		put.call(cx + (1 if side > 0 else -2), 22, Color.WHITE, 1, 1)  # sparkle
		put.call(cx - 6, 20, Color("#3a1f12"), 12, 1)  # upper lid line
		put.call(cx - 6, 19, Color("#3a1f12"), 2, 1)  # lashes at the outer corner
		put.call(cx + 4, 19, Color("#3a1f12"), 2, 1)
		put.call(cx - 5, 28, Color("#e3a58a"), 10, 1)  # lower lid
		put.call(cx - 5 + (0 if side < 0 else 2), 14 + (1 if side < 0 else 0), Color("#8a3f1e"), 8, 2)  # brow
		put.call(cx - 7 + (0 if side < 0 else 6), 13 + 2, Color("#8a3f1e"), 2, 1)
		put.call(cx - 8 if side < 0 else cx + 3, 31, Color("#f0a090"), 5, 3)  # blush
	put.call(23, 29, Color("#d9976f"), 2, 4)  # nose
	put.call(22, 33, Color("#c98263"), 4, 1)
	var freckles := [[14, 30], [17, 32], [12, 33], [31, 30], [34, 32], [36, 33], [21, 27], [27, 27], [24, 28]]
	for f in freckles:
		put.call(f[0], f[1], Color("#c58a62"))
	put.call(10, 28, Color("#fbf6ee"), 3, 1)  # a smudge of flour on one cheek
	put.call(11, 27, Color("#f4ece0"), 2, 1)
	put.call(19, 38, Color("#b5584f"), 10, 1)  # a small closed smile
	put.call(18, 37, Color("#b5584f"), 1, 1)
	put.call(29, 37, Color("#b5584f"), 1, 1)
	put.call(21, 39, Color("#d9786c"), 6, 1)
	return ImageTexture.create_from_image(img)


func build_marigold() -> void:
	var skin := "#f0c5a3"
	var hair := "#9b4a26"
	var hair_light := "#b8602f"
	var hair_dark := "#7a381c"
	var green := "#3f6b4a"
	var green_dark := "#2f523a"
	var cream := "#f1e6d0"
	var maroon := "#8a2f3a"
	var leather := "#6b3a2a"
	# legs: striped stockings, boots with cuffs and buckles
	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.position = Vector3(0.09 * side, 0.8, 0)
		leg.name = "leg_l" if side < 0 else "leg_r"
		body.add_child(leg)
		limbs.append([leg, 1 if side < 0 else -1])
		for i in 5:
			bx(leg, Vector3(0, -0.335 - i * 0.063, 0), Vector3(0.11, 0.063, 0.11), cream if i % 2 == 0 else maroon)
		# stacked pieces touch but never overlap (equal positions/faces make textures flicker through each other)
		bx(leg, Vector3(0, -0.66, 0), Vector3(0.15, 0.04, 0.15), "#4a2a1a")  # boot cuff (-0.68 .. -0.64)
		bx(leg, Vector3(0, -0.715, -0.02), Vector3(0.13, 0.07, 0.17), leather)  # boot shaft (-0.75 .. -0.68)
		bx(leg, Vector3(0, -0.765, -0.05), Vector3(0.135, 0.03, 0.22), "#5a2f1f")  # foot (-0.78 .. -0.75)
		bx(leg, Vector3(0, -0.7925, -0.05), Vector3(0.14, 0.025, 0.24), "#2a1a12")  # sole (-0.805 .. -0.78)
		bx(leg, Vector3(0, -0.715, -0.112), Vector3(0.05, 0.04, 0.014), "#d9a441")  # buckle, in front of the boot
	# skirt, petticoat, folds, apron
	bx(body, Vector3(0, 0.52, 0), Vector3(0.6, 0.03, 0.54), cream)
	bx(body, Vector3(0, 0.56, 0), Vector3(0.58, 0.07, 0.52), green_dark)
	bx(body, Vector3(0, 0.63, 0), Vector3(0.53, 0.1, 0.47), green)
	bx(body, Vector3(0, 0.73, 0), Vector3(0.49, 0.1, 0.43), green)
	bx(body, Vector3(0, 0.83, 0), Vector3(0.45, 0.1, 0.4), green)
	for layer in [[0.63, 0.1, 0.47], [0.73, 0.1, 0.43], [0.83, 0.1, 0.4]]:  # folds sit on each layer's front and back
		for i in 6:
			bx(body, Vector3(-0.22 + i * 0.088, layer[0], -layer[2] / 2), Vector3(0.012, layer[1] - 0.02, 0.012), green_dark)
			bx(body, Vector3(-0.22 + i * 0.088, layer[0], layer[2] / 2), Vector3(0.012, layer[1] - 0.02, 0.012), green_dark)
	# apron: in front of the skirt layers it covers (front z -0.2375, y 0.60 .. 0.86), above the hem layers
	bx(body, Vector3(0, 0.73, -0.2475), Vector3(0.32, 0.26, 0.02), cream)
	bx(body, Vector3(-0.16, 0.73, -0.262), Vector3(0.012, 0.26, 0.01), maroon)  # trims start at the apron's front face
	bx(body, Vector3(0.16, 0.73, -0.262), Vector3(0.012, 0.26, 0.01), maroon)
	bx(body, Vector3(0, 0.606, -0.262), Vector3(0.308, 0.012, 0.01), maroon)
	bx(body, Vector3(0, 0.69, -0.2635), Vector3(0.17, 0.11, 0.012), "#e3d4b6")  # pocket (0.635 .. 0.745)
	bx(body, Vector3(0, 0.745, -0.2715), Vector3(0.17, 0.012, 0.008), maroon)
	bx(body, Vector3(0.04, 0.76, -0.275), Vector3(0.05, 0.07, 0.012), "#7ac77a")  # a sprig in the pocket
	bx(body, Vector3(0.085, 0.77, -0.275), Vector3(0.025, 0.05, 0.012), "#a477c9")  # (x apart from the green, so they never overlap)
	# waist, bodice, blouse, shawl
	bx(body, Vector3(0, 0.9, 0), Vector3(0.38, 0.06, 0.26), maroon)  # belt
	bx(body, Vector3(0, 0.9, -0.132), Vector3(0.07, 0.05, 0.012), "#d9a441")  # buckle
	bx(body, Vector3(0.2, 0.84, -0.06), Vector3(0.07, 0.1, 0.06), "#a5733c")  # pouch
	bx(body, Vector3(0.2, 0.89, -0.06), Vector3(0.08, 0.03, 0.07), "#8a5a2b")
	bx(body, Vector3(-0.2, 0.8, 0.03), Vector3(0.05, 0.16, 0.05), "#4f8f4a", "sphere")  # herbs
	bx(body, Vector3(-0.2, 0.7, 0.03), Vector3(0.03, 0.08, 0.03), "#a477c9", "sphere")
	bx(body, Vector3(0, 1.06, 0), Vector3(0.35, 0.26, 0.2), leather)  # bodice
	for i in 4:  # lacing
		bx(body, Vector3(0, 0.98 + i * 0.065, -0.104), Vector3(0.1, 0.012, 0.008), cream)
	bx(body, Vector3(-0.025, 1.06, -0.106), Vector3(0.01, 0.26, 0.008), cream)
	bx(body, Vector3(0.025, 1.06, -0.106), Vector3(0.01, 0.26, 0.008), cream)
	bx(body, Vector3(0, 1.27, 0), Vector3(0.37, 0.24, 0.21), "#f6eedf")  # blouse
	bx(body, Vector3(0, 1.4, -0.02), Vector3(0.3, 0.05, 0.2), "#fffaf0")  # ruffled collar
	for i in 7:
		bx(body, Vector3(-0.13 + i * 0.043, 1.41, -0.118), Vector3(0.04, 0.045, 0.02), "#fffaf0", "sphere")
	var shawl := Node3D.new()
	shawl.position = Vector3(0, 1.34, 0)
	body.add_child(shawl)
	bx(shawl, Vector3(0, 0.02, 0.0), Vector3(0.44, 0.1, 0.27), "#d9a441")
	bx(shawl, Vector3(-0.1, -0.08, -0.12), Vector3(0.16, 0.18, 0.04), "#d9a441")
	bx(shawl, Vector3(0.1, -0.08, -0.12), Vector3(0.16, 0.18, 0.04), "#d9a441")
	for i in 9:  # fringe
		bx(shawl, Vector3(-0.2 + i * 0.05, -0.16, 0.0), Vector3(0.012, 0.06, 0.012), "#f1e6d0")
	for i in 5:
		bx(shawl, Vector3(-0.17 + i * 0.085, 0.08, 0.0), Vector3(0.04, 0.014, 0.28), "#b5842f")  # woven stripes
	bx(body, Vector3(0, 1.45, 0), Vector3(0.075, 0.08, 0.075), skin)  # neck
	# arms: puffed sleeves with rolled cuffs; the left carries a basket
	for side in [-1, 1]:
		var arm := Node3D.new()
		arm.position = Vector3(0.23 * side, 1.37, 0)
		arm.name = "arm_l" if side < 0 else "arm_r"
		body.add_child(arm)
		limbs.append([arm, -1 if side < 0 else 1])
		bx(arm, Vector3(0, -0.02, 0), Vector3(0.14, 0.14, 0.14), "#f6eedf", "sphere")  # puffed shoulder
		bx(arm, Vector3(0, -0.16, 0), Vector3(0.09, 0.2, 0.09), "#f6eedf")
		bx(arm, Vector3(0, -0.29, 0), Vector3(0.105, 0.04, 0.105), maroon)  # cuff
		bx(arm, Vector3(0, -0.4, 0), Vector3(0.07, 0.2, 0.07), skin)
		bx(arm, Vector3(0, -0.52, -0.005), Vector3(0.08, 0.08, 0.06), skin)  # hand
		bx(arm, Vector3(0.0, -0.57, -0.01), Vector3(0.06, 0.03, 0.04), skin)  # fingers
		bx(arm, Vector3(-0.045 * side, -0.35, 0), Vector3(0.012, 0.012, 0.075), "#d9a441")  # a bangle
		if side < 0:
			var basket := Node3D.new()
			basket.position = Vector3(-0.02, -0.74, -0.03)
			arm.add_child(basket)
			bx(basket, Vector3(0, 0, 0), Vector3(0.28, 0.17, 0.2), "#a5733c")
			for i in 5:
				bx(basket, Vector3(0, -0.07 + i * 0.035, -0.101), Vector3(0.28, 0.012, 0.006), "#7a5530")
			for i in 6:
				bx(basket, Vector3(-0.115 + i * 0.046, 0, -0.103), Vector3(0.008, 0.17, 0.006), "#8a6238")
			bx(basket, Vector3(0, 0.09, 0), Vector3(0.3, 0.03, 0.22), "#8a6238")  # rim
			bx(basket, Vector3(-0.1, 0.12, -0.02), Vector3(0.11, 0.1, 0.1), "#b87a3a", "sphere")  # a loaf
			bx(basket, Vector3(0.02, 0.11, 0.02), Vector3(0.1, 0.08, 0.1), "#c98a45", "sphere")
			bx(basket, Vector3(0.1, 0.13, -0.03), Vector3(0.06, 0.1, 0.06), "#4f8f4a", "sphere")  # herbs
			bx(basket, Vector3(0.13, 0.14, 0.02), Vector3(0.04, 0.12, 0.04), "#a477c9", "sphere")
			bx(basket, Vector3(-0.02, 0.15, 0.05), Vector3(0.1, 0.02, 0.1), "#b3323d")  # a checked cloth corner
			bx(basket, Vector3(0, 0.26, 0), Vector3(0.015, 0.2, 0.015), "#7a5530")  # handle
			bx(basket, Vector3(0, 0.17, 0), Vector3(0.015, 0.015, 0.2), "#7a5530")
			bx(basket, Vector3(0, 0.34, 0), Vector3(0.015, 0.015, 0.2), "#7a5530")
	# head: skin, a painted face, ears with hoops, nose
	bx(body, Vector3(0, 1.62, 0), Vector3(0.24, 0.26, 0.24), skin)
	var face := MeshInstance3D.new()
	face.mesh = QuadMesh.new()
	var fm := StandardMaterial3D.new()
	fm.albedo_texture = face_texture()
	fm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	fm.roughness = 1.0
	face.material_override = fm
	face.scale = Vector3(0.24, 0.26, 1)
	face.position = Vector3(0, 1.62, -0.1205)
	face.rotation = Vector3(0, PI, 0)
	body.add_child(face)
	for side in [-1, 1]:
		bx(body, Vector3(0.128 * side, 1.6, 0), Vector3(0.03, 0.06, 0.05), "#e8b595")  # ear
		bx(body, Vector3(0.137 * side, 1.555, -0.005), Vector3(0.012, 0.045, 0.012), "#d9a441")  # hoop earring
	bx(body, Vector3(0, 1.595, -0.132), Vector3(0.032, 0.04, 0.03), "#e8b595")  # nose
	# hair: cap, back, side locks, fringe, bun with a stick, a long braid and a ribbon
	bx(body, Vector3(0, 1.755, 0.005), Vector3(0.27, 0.1, 0.27), hair)
	# the back pieces overlap each other and the cap, so each has its own width / back plane (no shared faces)
	bx(body, Vector3(0, 1.62, 0.115), Vector3(0.258, 0.3, 0.07), hair_dark)
	bx(body, Vector3(0, 1.7, 0.1), Vector3(0.266, 0.16, 0.09), hair)
	for side in [-1, 1]:
		bx(body, Vector3(0.138 * side, 1.65, -0.01), Vector3(0.035, 0.22, 0.2), hair)
		bx(body, Vector3(0.12 * side, 1.51, -0.085), Vector3(0.05, 0.05, 0.05), hair_light, "sphere")  # curls by the face
		bx(body, Vector3(0.135 * side, 1.545, -0.05), Vector3(0.04, 0.1, 0.05), hair)
	for i in 6:  # fringe: sits just in front of the cap (no overlap with it); every other lock a few mm further out so no faces share a plane
		var f := bx(body, Vector3(-0.1 + i * 0.04, 1.745, -0.1465 - (i % 2) * 0.006), Vector3(0.05, 0.065, 0.03), hair_light if i % 2 == 0 else hair)
		f.rotation_degrees.z = (i - 2.5) * 5
	bx(body, Vector3(0, 1.88, 0.06), Vector3(0.17, 0.15, 0.17), hair, "sphere")  # bun
	bx(body, Vector3(0, 1.93, 0.05), Vector3(0.09, 0.07, 0.09), hair_light, "sphere")
	bx(body, Vector3(0, 1.83, 0.06), Vector3(0.18, 0.025, 0.18), maroon)  # band
	var stick := bx(body, Vector3(0.05, 1.9, 0.07), Vector3(0.012, 0.012, 0.3), "#d9b57a")
	stick.rotation_degrees = Vector3(0, 20, 18)
	braid = Node3D.new()
	braid.position = Vector3(0, 1.5, 0.14)
	body.add_child(braid)
	for i in 8:
		var s := 0.085 - i * 0.004
		bx(braid, Vector3(0, -i * 0.065, 0.01 + i * 0.004), Vector3(s, 0.075, s), hair if i % 2 == 0 else hair_light, "sphere")
	bx(braid, Vector3(0, -0.53, 0.04), Vector3(0.1, 0.03, 0.04), maroon)  # ribbon
	bx(braid, Vector3(-0.045, -0.56, 0.04), Vector3(0.05, 0.07, 0.02), maroon)
	bx(braid, Vector3(0.045, -0.56, 0.04), Vector3(0.05, 0.07, 0.02), maroon)
	bx(braid, Vector3(0, -0.6, 0.04), Vector3(0.05, 0.08, 0.05), hair_dark, "sphere")
	# a crown of little flowers, two of them glowing moonblooms
	for i in 12:
		var a := TAU * i / 12.0
		var fx := cos(a) * 0.145
		var fz := sin(a) * 0.145
		var base := Vector3(fx, 1.80, fz)
		bx(body, base, Vector3(0.05, 0.03, 0.05), "#4f8f4a")  # leaf
		var color: String = ["#f2a0b8", "#fff2c0", "#c9a0f2", "#f7d060"][i % 4]
		if i == 3 or i == 9:
			glow(body, base + Vector3(0, 0.03, 0), Vector3(0.06, 0.05, 0.06), "#7fd6ff", 2.2, "sphere")
		else:
			bx(body, base + Vector3(0, 0.03, 0), Vector3(0.05, 0.045, 0.05), color, "sphere")
			bx(body, base + Vector3(0, 0.05, 0), Vector3(0.02, 0.02, 0.02), "#f7d060", "sphere")
	# a necklace with a small pendant
	for i in 7:
		var t := float(i) / 6.0
		bx(body, Vector3(-0.07 + 0.14 * t, 1.37 - 0.03 * sin(t * PI), -0.115), Vector3(0.014, 0.014, 0.014), "#d9a441")
	glow(body, Vector3(0, 1.32, -0.12), Vector3(0.03, 0.04, 0.012), "#7fd6ff", 1.5, "sphere")


# --- moonblooms: glowing flowers over the field (walk into one to pick it) ---------------------------------------

func bloom_spots() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var spots := []
	var tries := 0
	while spots.size() < BLOOM_COUNT and tries < 400:
		tries += 1
		var a := rng.randf() * TAU
		var d := rng.randf_range(9.0, 34.0)
		var p := Vector2(cos(a) * d, sin(a) * d)
		if p.distance_to(Vector2(40, 5)) < 18.0 or p.distance_to(Vector2(STALL.x, STALL.z)) < 7.0:
			continue  # not on the parkour tower or in the stall
		if p.distance_to(Vector2(-16, -22)) < 5.0 or p.distance_to(Vector2(-19, 12)) < 6.0:
			continue  # nor on the conch rock or the built structures
		var ok := true
		for q in spots:
			if p.distance_to(q) < 7.0:
				ok = false
		if ok:
			spots.append(p)
	return spots


func build_flowers() -> void:
	var taken: Array = ctx.state.get_or_add("bloom_taken", [])
	var spots := bloom_spots()
	for i in spots.size():
		if taken.has(i):
			continue
		var f := Node3D.new()
		f.position = Vector3(spots[i].x, 0, spots[i].y)
		add_child(f)
		bx(f, Vector3(0, 0.2, 0), Vector3(0.03, 0.4, 0.03), "#3f7a4a")  # stem
		var leaf_a := bx(f, Vector3(0.07, 0.12, 0), Vector3(0.14, 0.02, 0.06), "#4f8f4a")
		leaf_a.rotation_degrees.z = 25
		var leaf_b := bx(f, Vector3(-0.07, 0.17, 0), Vector3(0.14, 0.02, 0.06), "#4f8f4a")
		leaf_b.rotation_degrees.z = -25
		var head := Node3D.new()
		head.position = Vector3(0, 0.42, 0)
		head.name = "Head"
		f.add_child(head)
		glow(head, Vector3.ZERO, Vector3(0.1, 0.1, 0.1), "#e8fbff", 2.6, "sphere")
		for k in 6:
			var pet := Node3D.new()
			pet.rotation_degrees.y = k * 60
			head.add_child(pet)
			var p := glow(pet, Vector3(0, 0.02, -0.1), Vector3(0.08, 0.02, 0.15), "#7fd6ff", 2.0)
			p.rotation_degrees.x = -22
		light(f, Vector3(0, 0.5, 0), "#7fd6ff", 0.9, 3.5)
		flowers.append([f, i])


func collect_flowers(delta: float) -> void:
	var p: Vector3 = ctx.player.position
	for entry in flowers.duplicate():
		var f: Node3D = entry[0]
		f.get_node("Head").rotate_y(delta * 0.8)
		f.get_node("Head").position.y = 0.42 + sin(spin * 2.0 + entry[1]) * 0.02
		if Vector2(p.x - f.position.x, p.z - f.position.z).length() < 1.1:
			flowers.erase(entry)
			f.queue_free()
			ctx.state.get_or_add("bloom_taken", []).append(entry[1])
			ctx.state["blooms"] = int(ctx.state.get("blooms", 0)) + 1
			W.show_notice("You picked a moonbloom! (%d)" % int(ctx.state["blooms"]), 3.0)
			W.send({"t": "need_quests"})  # redraw the quest list with the new count


func blooms() -> int:
	return int(ctx.state.get("blooms", 0))


func quest_progress(id: String) -> String:
	return " (%d/%d)" % [mini(blooms(), BLOOMS_NEEDED), BLOOMS_NEEDED] if id == QUEST_ID else ""


func show_loaves() -> void:
	for l in loaves:
		l.queue_free()
	loaves.clear()
	for i in mini(int(ctx.state.get("moonbread", 0)), 4):
		var loaf: MeshInstance3D = glow(bread_slots, Vector3(i * 0.2, 0.07, 0), Vector3(0.17, 0.12, 0.13), "#bfe8ff", 1.4, "sphere")
		loaves.append(loaf)


var hand_cooldown := 0.0


func hand_over() -> void:
	hand_cooldown = 20.0
	ctx.state["blooms"] = blooms() - BLOOMS_NEEDED
	ctx.state["moonbread"] = int(ctx.state.get("moonbread", 0)) + 1
	show_loaves()
	W.show_notice("You gave Marigold %d moonblooms." % BLOOMS_NEEDED, 3.0)
	W.send({"t": "need_quests"})
	if QUEST_ID in ctx.get("quest_ids", []):
		W.send({"t": "quest_done", "id": QUEST_ID})
	W.send({"t": "event", "who": "marigold", "label": "moonbloom delivered",
		"text": "The wanderer just handed you five glowing moonblooms. At last you can bake your grandmother's moonbread. React with joy in your own words and say what you are going to do with them."})


# --- what she sees, and how she moves ---------------------------------------------------------------------------------

func is_near() -> bool:
	var p: Vector3 = ctx.player.position
	return Vector2(p.x - body.position.x, p.z - body.position.z).length() < NEAR


func describe() -> String:
	var here := body.position
	var seen := ["your own market stall right behind you, with your oven, your herbs and your moonbread loaves on the counter (%d baked so far)" % int(ctx.state.get("moonbread", 0)),
		"a dark field with a faint green grid under a red moon, where glowing blue moonblooms grow here and there (you need five to bake moonbread, your grandmother's recipe)"]
	seen.append_array(W.seen_around(here, self))  # everything the other parts report (see world.gd)
	if blooms() > 0:
		seen.append("the wanderer is carrying %d moonbloom%s" % [blooms(), "" if blooms() == 1 else "s"])
	seen.append("the wanderer is %s" % W.where(here, ctx.player.position))
	return "; ".join(seen)


## What the other characters see of her (her own describe() covers the stall from her side).
func seen_from(from: Vector3, viewer: Node) -> Array:
	if viewer == self or not body:
		return []
	return ["Marigold, the herbalist and baker, %s" % W.where(from, body.position),
		"Marigold's market stall with a striped awning and a glowing oven, %s" % W.where(from, STALL)]


func walk_to(goal: Vector3, speed: float, delta: float) -> bool:
	var d := Vector3(goal.x - body.position.x, 0, goal.z - body.position.z)
	var dist := d.length()
	if dist <= 0.1:
		return false
	body.position += d / dist * minf(dist, speed * delta)
	W.face(body, goal)
	return true


func _process(delta: float) -> void:
	if not body:
		return
	spin += delta
	var player: Vector3 = ctx.player.position
	var moving := false
	if errand_active:  # Barnaby's [throw]: she hurries to him (errand_goal), then stands and lifts him
		var barnaby = ctx.parts.get("barnaby")
		if not barnaby or barnaby.st().get("mode") != "thrown":  # the throw was cut short: back to normal
			errand_active = false
			arms_up = false
			errand_goal = null
		elif errand_goal != null:
			moving = walk_to(errand_goal, ERRAND_SPEED, delta)
	if errand_active:
		pass
	elif is_near():
		W.face(body, player)
	elif pause > 0.0:
		pause -= delta
	else:
		moving = walk_to(target, SPEED, delta)
		if not moving:  # pick somewhere new to stroll to, after a little pause
			pause = randf_range(2.0, 6.0)
			var a := randf() * TAU
			target = home + Vector3(cos(a), 0, sin(a)) * randf_range(0.0, WANDER)
	phase += delta * 7.0 if moving else 0.0
	var swing := sin(phase) * deg_to_rad(26) if moving else 0.0
	for pair in limbs:
		pair[0].rotation.x = swing * pair[1]
	if arms_up and limbs.size() >= 4:  # both arms overhead while she holds Barnaby up
		limbs[2][0].rotation.x = -deg_to_rad(160)
		limbs[3][0].rotation.x = -deg_to_rad(160)
	if braid:
		braid.rotation.x = deg_to_rad(8) * sin(phase * 0.5 + 1.0) if moving else sin(spin * 1.3) * deg_to_rad(2.5)
	body.position.y = (absf(sin(phase)) * 0.025 if moving else sin(spin * 1.6) * 0.004) + 0.0
	if oven_light:
		oven_light.light_energy = 1.4 + sin(spin * 9.0) * 0.25 + sin(spin * 4.1) * 0.2
	collect_flowers(delta)
	hand_cooldown = maxf(hand_cooldown - delta, 0.0)
	if blooms() >= BLOOMS_NEEDED and is_near() and hand_cooldown <= 0.0:  # also for repeat requests, quest or not
		hand_over()
	ctx.state["marigold"]["x"] = body.position.x
	ctx.state["marigold"]["z"] = body.position.z


func handle(c: Dictionary) -> bool:
	if c.get("who", "marigold") != "marigold":
		return false
	match c.get("cmd", ""):
		"say_start":
			talker.say_start(str(c.get("text", "")))
		"say_end":
			talker.say_end()
		"say":
			talker.say(str(c.get("text", "")))
		"npc_state":
			talker.set_mind(str(c.get("state", "")))
		_:
			return false
	return true
