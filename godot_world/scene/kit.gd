extends Node3D
## Shared materials for the medieval buildings (castle.gd, village.gd): stone blocks, plaster, timber, thatch,
## slate, planks. The textures are drawn here in code and mapped in world space (triplanar), so a box of any
## size shows stones / planks at their real size instead of one stretched picture. Use: kit.mat("stone").
## Made on first use, so it works whatever order the parts are built in.

var _mats := {}


func mat(kind: String, tint := Color.WHITE) -> StandardMaterial3D:
	var key := "%s|%s" % [kind, tint.to_html()]
	if key in _mats:
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.roughness = 0.92
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	match kind:
		"stone":
			m.albedo_texture = blocks_texture(Color("#9a948a"), Color("#5e5a54"), 4, 8, 0.10)
			m.uv1_scale = Vector3.ONE * 0.5  # one texture = 2 m: stones about 50 x 25 cm
		"dark_stone":
			m.albedo_texture = blocks_texture(Color("#6e6a64"), Color("#3f3c38"), 4, 6, 0.12)
			m.uv1_scale = Vector3.ONE * 0.5
		"plaster":
			m.albedo_texture = noise_texture(Color("#cfc0a0"), 0.06)
			m.uv1_scale = Vector3.ONE * 0.4
		"timber":
			m.albedo_texture = streak_texture(Color("#4f3622"), 0.18, false)
			m.uv1_scale = Vector3.ONE * 1.5
		"planks":
			m.albedo_texture = planks_texture(Color("#7a5a3a"))
			m.uv1_scale = Vector3.ONE * 0.6
		"thatch":
			m.albedo_texture = streak_texture(Color("#b8954f"), 0.28, true)
			m.uv1_scale = Vector3.ONE * 0.8
		"slate":
			m.albedo_texture = blocks_texture(Color("#475266"), Color("#2c3240"), 6, 8, 0.10)
			m.uv1_scale = Vector3.ONE * 0.9
		_:
			m.albedo_texture = noise_texture(Color("#888888"), 0.1)
	m.albedo_color = tint
	_mats[key] = m
	return m


## A box with one of the materials (pos is its centre). collide = solid.
func block(W, parent: Node, pos: Vector3, size: Vector3, kind: String, collide := true, tint := Color.WHITE) -> MeshInstance3D:
	var node: MeshInstance3D = W.box(parent, pos, size, Color.WHITE, "cube", collide)
	node.material_override = mat(kind, tint)
	return node


func _image(size: int) -> Image:
	return Image.create(size, size, false, Image.FORMAT_RGB8)


func _done(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Courses of stones with mortar between, each stone its own shade.
func blocks_texture(stone: Color, mortar: Color, rows: int, cols: int, spread: float) -> ImageTexture:
	var s := 128
	var img := _image(s)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(stone.r * 1000) + rows
	var h := s / rows
	var w := s / (cols / 2)
	for r in rows:
		var shift := (w / 2) if r % 2 else 0
		for c in range(-1, cols / 2 + 1):
			var shade := stone.darkened(rng.randf_range(-spread, spread * 1.5))
			var x0 := c * w + shift
			for y in range(r * h, (r + 1) * h):
				for x in range(x0, x0 + w):
					if x < 0 or x >= s:
						continue
					var edge := y == r * h or x == x0
					var grain := rng.randf_range(-0.04, 0.04)
					img.set_pixel(x, y, mortar if edge else shade.lightened(grain))
	return _done(img)


func noise_texture(base: Color, spread: float) -> ImageTexture:
	var s := 64
	var img := _image(s)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(base.g * 999)
	for y in s:
		for x in s:
			img.set_pixel(x, y, base.darkened(rng.randf_range(-spread * 0.5, spread)))
	return _done(img)


## Long streaks along y (thatch straw, wood grain); `wavy` makes them uneven like bundled straw.
func streak_texture(base: Color, spread: float, wavy: bool) -> ImageTexture:
	var s := 64
	var img := _image(s)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(base.r * 777)
	for x in s:
		var shade := base.darkened(rng.randf_range(-spread * 0.4, spread))
		for y in s:
			var c := shade
			if wavy and (y + x * 3) % 16 < 2:
				c = c.darkened(0.25)  # the rows where the straw is tied down
			img.set_pixel(x, y, c.lightened(rng.randf_range(-0.03, 0.03)))
	return _done(img)


func planks_texture(base: Color) -> ImageTexture:
	var s := 64
	var img := _image(s)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for p in 4:
		var shade := base.darkened(rng.randf_range(-0.1, 0.18))
		for y in range(p * 16, (p + 1) * 16):
			for x in s:
				var c := shade.darkened(0.45) if y == p * 16 else shade.lightened(rng.randf_range(-0.04, 0.04))
				img.set_pixel(x, y, c)
	return _done(img)
