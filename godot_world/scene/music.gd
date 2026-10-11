extends Node3D
## Background music and the RPG's jingles.
## Music: three public-domain (CC0) medieval tracks by RandomMind from opengameart.org, in godot_world/music/.
## By day it plays Market Day and The Bard's Tale, at night The Old Tower Inn, softly, with a quiet pause between
## tracks. K turns the music on and off (state["music_off"]); [music off] / [music on] do the same by voice.
## The player lives on the world node (not on this part), so rebuilding the parts doesn't restart the song.
## Jingles and sounds are made here in code (no files): play_sfx("levelup" | "quest" | "chapter" | "swing" | "hit" |
## "hurt" | "pickup" | "coin").

const DAY_TRACKS := ["Market_Day.mp3", "The_Bards_Tale.mp3"]
const NIGHT_TRACKS := ["The_Old_Tower_Inn.mp3"]
const VOLUME_DB := -33.0  # was -15, then -22, then -28: too loud. A constant in the file, so it stays after a restart
const TRACK_TRIM_DB := {"The_Old_Tower_Inn.mp3": -3.0}  # per-track correction for songs mastered louder than the rest
const PAUSE := Vector2(15.0, 40.0)  # seconds of quiet between tracks (random in this range)
const RATE := 22050
const SFX_DB := {"swing": -10.0, "hit": -3.0, "pickup": -4.0}  # the sword whoosh stays quiet and consistent

var ctx: Dictionary
var W
var player: AudioStreamPlayer
var sfx: AudioStreamPlayer
var wait := 3.0  # until the next track starts
var extra := []  # more sound players, for sounds that overlap


func build(c: Dictionary) -> void:
	ctx = c
	W = ctx["world"]
	var existing = ctx.get("music_player")
	if is_instance_valid(existing):  # (a reload keeps the one already playing)
		player = existing
		player.volume_db = VOLUME_DB + float(TRACK_TRIM_DB.get(ctx.get("music_last", ""), 0.0))  # the song already playing gets the new level at once
	else:
		player = AudioStreamPlayer.new()
		player.name = "Music"
		player.volume_db = VOLUME_DB
		W.add_child(player)
		ctx["music_player"] = player
	sfx = AudioStreamPlayer.new()
	sfx.volume_db = -6.0
	add_child(sfx)
	if not ctx.has("jingles") or ctx.get("jingles_v", 0) != 3:
		ctx["jingles_v"] = 3
		ctx["jingles"] = {"levelup": jingle([[0, 523.3], [0.11, 659.3], [0.22, 784.0], [0.33, 1046.5]], 1.3),
			"quest": jingle([[0, 392.0], [0.16, 523.3], [0.32, 659.3], [0.32, 392.0], [0.5, 784.0], [0.5, 523.3]], 1.6),
			"chapter": jingle([[0, 293.7], [0.0, 440.0], [0.45, 349.2], [0.45, 523.3], [0.9, 392.0], [0.9, 587.3], [0.9, 293.7]], 2.6),
			"swing": noise_burst(0.16, 0.25, 0.03, 0.05),  # a soft whoosh of air (it was too hissy)
			"hit": thud(110.0, 0.16, 0.7),  # the blade lands
			"hurt": thud(70.0, 0.25, 1.0),  # you take a hit: deeper, with a crunch
			"pickup": jingle([[0, 880.0], [0.07, 1318.5]], 0.35),
			"coin": jingle([[0, 1760.0], [0.05, 2349.3]], 0.4)}


func play_sfx(name: String) -> void:
	if not sfx or not ctx.jingles.has(name):
		return
	if name == "swing":
		# A fresh one-shot voice avoids any playback state carrying over between fast sword swings.
		var whoosh := AudioStreamPlayer.new()
		whoosh.stream = ctx.jingles[name]
		whoosh.volume_db = -16.0
		whoosh.pitch_scale = 1.0
		add_child(whoosh)
		whoosh.finished.connect(whoosh.queue_free)
		whoosh.play()
		return
	var player := sfx
	if sfx.playing:  # a hit during a jingle uses a free player, so neither cuts off
		player = null
		for p in extra:
			if not p.playing:
				player = p
		if player == null:
			player = AudioStreamPlayer.new()
			player.volume_db = sfx.volume_db
			add_child(player)
			extra.append(player)
	player.stream = ctx.jingles[name]
	player.volume_db = sfx.volume_db + float(SFX_DB.get(name, 0.0))
	player.pitch_scale = randf_range(0.92, 1.08) if name in ["hit", "hurt"] else 1.0
	player.play()


## A little plucked-lute jingle: notes = [[start seconds, frequency], ...], made into a WAV in memory.
func jingle(notes: Array, length: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for note in notes:
		var start := int(float(note[0]) * RATE)
		var f := float(note[1])
		for i in range(start, n):
			var t := float(i - start) / RATE
			var env := minf(t * 200.0, 1.0) * exp(-t * 3.2)  # quick pluck, slow ring
			if env < 0.001:
				break
			var v := sin(TAU * f * t) + 0.45 * sin(TAU * f * 2.0 * t) * exp(-t * 6.0) + 0.2 * sin(TAU * f * 3.0 * t) * exp(-t * 9.0)
			buf[i] += v * env * 0.22
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(buf[i] * minf(float(n - i) / 800.0, 1.0), -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = bytes
	return wav


## Filtered noise that swells and fades: whooshes. `bright` 0..1 = how hissy.
func noise_burst(length: float, bright: float, attack: float, peak: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / RATE
		low = lerpf(low, randf_range(-1.0, 1.0), lerpf(0.05, 0.6, bright))  # a simple low-pass on white noise
		var env := smoothstep(0.0, attack + peak, t) * (1.0 - smoothstep(attack + peak, length, t))
		buf[i] = low * env * 0.8
	return to_wav(buf)


## A short low knock with a bit of noise on top (hits).
func thud(freq: float, length: float, crunch: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := freq * (1.0 + 1.5 * exp(-t * 30.0))  # the pitch drops fast, like a body blow
		buf[i] = (sin(TAU * f * t) * exp(-t * 14.0) + randf_range(-1.0, 1.0) * crunch * 0.35 * exp(-t * 40.0)) * 0.7
	return to_wav(buf)


func to_wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = bytes
	return wav


func music_on() -> bool:
	return not ctx.state.get("music_off", false)


func next_track() -> void:
	var night: bool = float(ctx.get("night", 0.0)) > 0.5
	var list: Array = NIGHT_TRACKS if night else DAY_TRACKS
	var last: String = ctx.get("music_last", "")
	var choices := list.filter(func(f): return f != last)
	var file: String = (choices if not choices.is_empty() else list).pick_random()
	var bytes := FileAccess.get_file_as_bytes("res://music/" + file)
	if bytes.is_empty():
		return
	var stream := AudioStreamMP3.new()
	stream.data = bytes
	player.stream = stream
	player.volume_db = VOLUME_DB + float(TRACK_TRIM_DB.get(file, 0.0))
	player.play()
	ctx["music_last"] = file


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if not music_on():
		if player.playing:
			player.stop()
		return
	if not player.playing:
		wait -= delta
		if wait <= 0.0:
			wait = randf_range(PAUSE.x, PAUSE.y)
			next_track()


func key(event: InputEventKey) -> void:
	if event.keycode == KEY_K:
		set_music(not music_on())


func set_music(on: bool) -> void:
	ctx.state["music_off"] = not on
	W.show_notice("Music on (K)" if on else "Music off (K)")
	if on:
		wait = 0.5


func handle(c: Dictionary) -> bool:
	if c.get("cmd", "") != "music":
		return false
	var args: Array = c.get("args", [])
	set_music(args.is_empty() or str(args[0]).to_lower() != "off")
	return true
