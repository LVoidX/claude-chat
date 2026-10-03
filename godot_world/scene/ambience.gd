extends Node3D
## Ambient sound, made in code (no sound files): a soft wind always, crickets at night and birdsong by day,
## following ctx["night"] from base.gd. Quiet on purpose; VOLUME_DB sets the overall level.

const ENABLED := false  # off: the hiss and chirps were annoying; set to true to bring the ambience back
const VOLUME_DB := -14.0
const RATE := 22050.0

var ctx: Dictionary
var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
var t := 0.0
var wind := 0.0  # filtered noise
var gust := 0.5
var bird_at := 2.0  # when the next bird call starts (seconds)
var bird_len := 0.0
var bird_t := -1.0
var bird_pitch := 3000.0
var cricket_rate := 0.0


func build(c: Dictionary) -> void:
	ctx = c
	if not ENABLED:
		return
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.25
	player = AudioStreamPlayer.new()
	player.stream = gen
	player.volume_db = VOLUME_DB
	add_child(player)
	player.play()
	playback = player.get_stream_playback()


func _process(_delta: float) -> void:
	if playback == null:
		return
	var night: float = ctx.get("night", 1.0)
	var frames := playback.get_frames_available()
	for i in frames:
		t += 1.0 / RATE
		# wind: smoothed noise with slow gusts
		gust += (randf() - 0.5) * 0.0004
		gust = clampf(gust, 0.2, 1.0)
		wind = lerpf(wind, randf() * 2.0 - 1.0, 0.02)
		var s := wind * 0.35 * gust
		# crickets: short bursts of a high chirp, three pulses at a time, from two crickets out of step
		if night > 0.05:
			for k in 2:
				var ct := fmod(t * (1.0 + k * 0.13) + k * 0.37, 1.1)
				if ct < 0.24 and fmod(ct, 0.08) < 0.045:
					s += sin(t * TAU * (4300.0 + k * 350.0)) * 0.12 * night
		# birds: now and then by day, a quick falling-and-rising whistle
		var day := 1.0 - night
		if day > 0.1:
			if bird_t < 0.0 and t > bird_at:
				bird_t = 0.0
				bird_len = randf_range(0.25, 0.6)
				bird_pitch = randf_range(2200.0, 3600.0)
			if bird_t >= 0.0:
				bird_t += 1.0 / RATE
				var u := bird_t / bird_len
				var f := bird_pitch * (1.0 + 0.25 * sin(u * TAU * 3.0))
				s += sin(bird_t * TAU * f) * 0.14 * day * sin(minf(u, 1.0) * PI)
				if u >= 1.0:
					bird_t = -1.0
					bird_at = t + randf_range(0.6, 5.0)
		playback.push_frame(Vector2(s, s))
