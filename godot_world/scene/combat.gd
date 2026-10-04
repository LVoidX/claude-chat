extends Node3D
## The player's side of a fight: health, blocking and parrying with the sword, and the feel of hits (screen
## shake, a short freeze, a red flash, sounds). Goblins (goblins.gd) call incoming() when their strike lands;
## the sword and gun (hotbar.gd) call hitstop(), shake() and sfx().
## Right click with the sword drawn blocks hits from the front (costs guard, the yellow bar). Pressing it just
## before a hit lands parries: the attacker is stunned and your next hit on it does triple damage. Red "!!"
## attacks can't be blocked, only parried. At 0 health you faint and wake up in the middle.

const MAX_HP := 100.0
const REGEN_DELAY := 4.0  # seconds without being hit before health comes back
const REGEN := 12.0  # health per second
const MAX_GUARD := 100.0
const BLOCK_COST := 34.0  # guard per blocked hit: three blocks in a row break it
const GUARD_REGEN := 30.0
const PARRY_WINDOW := 0.2  # seconds after pressing block in which a hit is parried
const PARRY_REARM := 0.45  # pressing block again sooner than this gives no new parry window (no spamming)
const STAGGER := 0.8  # seconds you can't act after your guard breaks

var ctx: Dictionary
var W
var hp := MAX_HP
var guard := MAX_GUARD
var since_hit := 99.0
var block_held := false
var block_age := 99.0  # seconds since block was pressed
var last_press := -99.0
var stagger := 0.0
var knock := Vector3.ZERO  # the player is shoved by hits (moved with collisions)
var trauma := 0.0  # screen shake, 0..1
var hitstop_until := 0
var flash := 0.0
var flash_color := Color(1, 0, 0)
var layer: CanvasLayer
var overlay: ColorRect
var hp_back: ColorRect
var hp_fill: ColorRect
var guard_fill: ColorRect
var callout: Label
var callout_left := 0.0
var players := []
var next_player := 0
var sounds := {}


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	hp = float(ctx.state.get("player_hp", MAX_HP))
	build_hud()
	for i in 6:  # a few players so sounds can overlap
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		players.append(p)
	for kind in ["clang", "block", "hit", "swish", "slash", "shot", "break"]:
		sounds[kind] = make_sound(kind)


func _exit_tree() -> void:
	Engine.time_scale = 1.0  # never leave the world frozen by a reload mid-hitstop
	if W and W.camera:
		W.camera.position = Vector3.ZERO


# --- sounds, made in code (no files): short decaying tones and noise ----------------------------------

func make_sound(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var length: float = {"clang": 0.45, "block": 0.16, "hit": 0.22, "swish": 0.16, "slash": 0.14, "shot": 0.2, "break": 0.4}[kind]
	var n := int(rate * length)
	var data := PackedByteArray()
	data.resize(n * 2)
	var low := 0.0  # a simple low-pass for the noise
	for i in n:
		var t := float(i) / rate
		var noise := randf_range(-1.0, 1.0)
		low += (noise - low) * 0.15
		var v := 0.0
		match kind:
			"clang":  # bright metal ring
				v = (sin(TAU * 1870.0 * t) * 0.5 + sin(TAU * 2830.0 * t) * 0.3 + sin(TAU * 4120.0 * t) * 0.15) * exp(-t * 9.0) + noise * 0.4 * exp(-t * 60.0)
			"block":  # dull metal knock
				v = (sin(TAU * 620.0 * t) * 0.6 + noise * 0.5) * exp(-t * 28.0)
			"hit":  # a thump: you got hit
				v = (sin(TAU * (140.0 - t * 200.0) * t) * 0.8 + low * 1.2) * exp(-t * 16.0)
			"swish":  # air, swelling and fading
				v = (noise - low) * 0.7 * sin(PI * t / length)
			"slash":  # the blade connecting
				v = (low * 1.5 + sin(TAU * 320.0 * t) * 0.4) * exp(-t * 30.0)
			"shot":
				v = (noise * 0.9 + sin(TAU * 90.0 * t) * 0.6) * exp(-t * 32.0)
			"break":  # guard broken: a falling crunch
				v = (low * 1.6 + sin(TAU * (500.0 - t * 900.0) * t) * 0.4) * exp(-t * 7.0)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 26000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


func sfx(kind: String, pitch := 1.0) -> void:
	if not sounds.has(kind) or players.is_empty():
		return
	var p: AudioStreamPlayer = players[next_player]
	next_player = (next_player + 1) % players.size()
	p.stream = sounds[kind]
	p.pitch_scale = pitch * randf_range(0.92, 1.08)
	p.play()


# --- feel: shake, freeze, flash -----------------------------------------------------------------------

func shake(amount: float) -> void:
	trauma = minf(trauma + amount, 1.0)


## Freeze the action for a moment so a hit lands with weight (real time, so it ends even at time scale 0.05).
func hitstop(seconds: float) -> void:
	Engine.time_scale = 0.05
	hitstop_until = maxi(hitstop_until, Time.get_ticks_msec() + int(seconds * 1000.0))


func flash_screen(color: Color, strength: float) -> void:
	flash_color = color
	flash = strength


func call_out(text: String, color: Color) -> void:
	callout.text = text
	callout.add_theme_color_override("font_color", color)
	callout_left = 0.7


# --- blocking and getting hit -------------------------------------------------------------------------

func sword_out() -> bool:
	var bar = ctx.parts.get("hotbar")
	return bar != null and bar.held()


func can_act() -> bool:
	return stagger <= 0.0


func blocking() -> bool:
	return block_held and can_act()


## Is `pos` in front of where the player looks (within about 75 degrees)?
func in_front(pos: Vector3) -> bool:
	var fwd: Vector3 = -W.camera.global_basis.z
	var to := Vector3(pos.x - ctx.player.position.x, 0, pos.z - ctx.player.position.z)
	return to.length() < 0.01 or Vector2(fwd.x, fwd.z).normalized().dot(Vector2(to.x, to.z).normalized()) > 0.25


## An attack lands on the player. Returns "parry", "block" or "hit" so the attacker can react.
func incoming(from: Vector3, damage: float, unblockable := false) -> String:
	var away := Vector3(ctx.player.position.x - from.x, 0, ctx.player.position.z - from.z).normalized()
	if blocking() and in_front(from):
		if block_age <= PARRY_WINDOW:
			sfx("clang")
			hitstop(0.12)
			shake(0.35)
			flash_screen(Color(1, 1, 1), 0.35)
			call_out("PARRY!", Color("#fff2a8"))
			guard = minf(guard + 25.0, MAX_GUARD)
			return "parry"
		if not unblockable:
			guard -= BLOCK_COST
			knock = away * 4.0
			if guard > 0.0:
				sfx("block")
				shake(0.2)
				return "block"
			guard = 0.0  # guard broken: staggered, and half the hit gets through
			stagger = STAGGER
			sfx("break")
			call_out("GUARD BROKEN", Color("#ff9a4d"))
			take(damage * 0.5, away)
			return "hit"
		call_out("UNBLOCKABLE", Color("#ff4d4d"))
	take(damage, away)
	return "hit"


func take(damage: float, away: Vector3) -> void:
	hp -= damage
	since_hit = 0.0
	knock = away * 6.0
	sfx("hit")
	shake(0.5)
	hitstop(0.06)
	flash_screen(Color(1, 0, 0), 0.45)
	if hp <= 0.0:
		faint()


func faint() -> void:
	hp = MAX_HP
	guard = MAX_GUARD
	knock = Vector3.ZERO
	stagger = 0.0
	W.recenter()
	var goblins = ctx.parts.get("goblins")
	if goblins:
		goblins.calm()
	W.show_notice("The goblins knocked you out. You wake up in the middle of the field.", 5.0)


# --- every frame --------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not callout:
		return
	if Engine.time_scale < 1.0 and Time.get_ticks_msec() >= hitstop_until:
		Engine.time_scale = 1.0
	var playing := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var want_block := playing and sword_out() and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var now := Time.get_ticks_msec() / 1000.0
	if want_block and not block_held:
		# a fresh press opens the parry window, unless it is spammed
		block_age = 0.0 if now - last_press > PARRY_REARM else 99.0
		last_press = now
	block_held = want_block
	block_age += delta
	stagger = maxf(stagger - delta, 0.0)
	since_hit += delta
	if since_hit > REGEN_DELAY:
		hp = minf(hp + REGEN * delta, MAX_HP)
	if not block_held:
		guard = minf(guard + GUARD_REGEN * delta, MAX_GUARD)
	ctx.state["player_hp"] = roundf(hp)
	# screen shake: the camera wobbles inside the head (held items are on the camera and wobble with it)
	trauma = maxf(trauma - delta * 2.5, 0.0)
	if trauma > 0.0:
		var s := trauma * trauma * 0.09
		W.camera.position = Vector3(randf_range(-s, s), randf_range(-s, s), 0)
	elif W.camera.position != Vector3.ZERO:
		W.camera.position = Vector3.ZERO
	flash = maxf(flash - delta * 2.0, 0.0)
	overlay.color = Color(flash_color, flash * 0.5)
	callout_left = maxf(callout_left - delta, 0.0)
	callout.modulate.a = clampf(callout_left / 0.3, 0.0, 1.0)
	callout.scale = Vector2.ONE * (1.0 + maxf(callout_left - 0.55, 0.0) * 2.0)
	var goblins = ctx.parts.get("goblins")
	var fighting: bool = goblins != null and goblins.angry()
	var shown: bool = W.camera.current and (fighting or hp < MAX_HP)
	hp_back.visible = shown
	hp_fill.size.x = 256.0 * clampf(hp / MAX_HP, 0.0, 1.0)
	hp_fill.color = Color("#e04848") if hp > 30.0 else Color("#ff2020").lerp(Color("#ffffff"), absf(sin(now * 8.0)) * 0.4)
	guard_fill.visible = sword_out() and (guard < MAX_GUARD or block_held)
	guard_fill.size.x = 256.0 * clampf(guard / MAX_GUARD, 0.0, 1.0)
	guard_fill.color = Color("#ff9a4d") if stagger > 0.0 else Color("#ffd24d")


func _physics_process(delta: float) -> void:
	if knock.length() > 0.05:
		ctx.player.move_and_collide(knock * delta)
		knock = knock.move_toward(Vector3.ZERO, 30.0 * delta)


# --- on-screen: health and guard bars above the hotbar, a red/white flash, PARRY! in the middle ---------

func build_hud() -> void:
	layer = CanvasLayer.new()
	add_child(layer)
	overlay = ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.color = Color(1, 0, 0, 0)
	layer.add_child(overlay)
	hp_back = ColorRect.new()  # health: a dark frame with the red fill inside, guard as a thin bar under it
	hp_back.color = Color(0, 0, 0, 0.6)
	hp_back.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	set_offsets(hp_back, -130, -104, 130, -84)  # (offsets from the bottom middle, so it stays put on resize)
	hp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hp_back)
	hp_fill = ColorRect.new()
	hp_fill.position = Vector2(2, 2)
	hp_fill.size = Vector2(256, 10)
	hp_back.add_child(hp_fill)
	guard_fill = ColorRect.new()
	guard_fill.position = Vector2(2, 14)
	guard_fill.size = Vector2(256, 4)
	hp_back.add_child(guard_fill)
	callout = Label.new()
	callout.set_anchors_preset(Control.PRESET_CENTER)
	set_offsets(callout, -200, 40, 200, 100)  # a little below the crosshair
	callout.pivot_offset = Vector2(200, 30)
	callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	callout.add_theme_font_size_override("font_size", 34)
	callout.add_theme_color_override("font_outline_color", Color.BLACK)
	callout.add_theme_constant_override("outline_size", 8)
	callout.modulate.a = 0.0
	layer.add_child(callout)


func set_offsets(c: Control, left: float, top: float, right: float, bottom: float) -> void:
	c.offset_left = left
	c.offset_top = top
	c.offset_right = right
	c.offset_bottom = bottom
