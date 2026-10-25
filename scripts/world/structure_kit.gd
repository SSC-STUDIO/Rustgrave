extends RefCounted
## Structural member textures: rolled-steel sections, bracing flats, sawn timber,
## hoist decks and concrete footings. Generated at the QHD companion density (4
## texels per logical pixel) so they sit beside the redrawn masonry at the same
## detail, and coloured from the chapter's own masonry so the workshop's steel
## rusts the same brown as its walls.

const DENSITY := 4
const STEEL := "steel"
const TIMBER := "timber"

static var _cache: Dictionary = {}


## Masonry face for a material family. The stone family samples the intact middle
## course of the lavender church slab its decks are cut from.
static func masonry(family: String) -> Texture2D:
	var key := "masonry:" + family
	if _cache.has(key):
		return _cache[key]
	var texture: Texture2D
	if family == "stone":
		var slab := DensityTextures.load_texture(SolidPlatform.STONE_SLABS[0])
		var image := _readable(slab.get_image())
		var density := image.get_width() / int(slab.get_width())
		var course := ImageTexture.create_from_image(image.get_region(Rect2i(0, 16 * density, 48 * density, 16 * density)))
		course.set_size_override(Vector2i(48, 16))
		texture = course
	else:
		var path := "res://assets/env/%s_fill.png" % family
		if not ResourceLoader.exists(path):
			path = "res://assets/env/nave_fill.png"
		texture = DensityTextures.load_texture(path)
	_cache[key] = texture
	return texture


## Mean colour of the family's masonry; steel and timber borrow its light and grime.
static func tint(family: String) -> Color:
	var key := "tint:" + family
	if _cache.has(key):
		return _cache[key]
	var mean := Color(0.4, 0.36, 0.34)
	var texture := masonry(family)
	var image := _readable(texture.get_image()) if texture != null else null
	if image != null:
		var r := 0.0
		var g := 0.0
		var b := 0.0
		var count := 0
		for y in range(0, image.get_height(), 2):
			for x in range(0, image.get_width(), 2):
				var c := image.get_pixel(x, y)
				if c.a > 0.5:
					r += c.r
					g += c.g
					b += c.b
					count += 1
		if count > 0:
			mean = Color(r / count, g / count, b / count)
	_cache[key] = mean
	return mean


static func steel_colors(family: String) -> Dictionary:
	var base := tint(family).lerp(Color(0.36, 0.37, 0.4), 0.35)
	return {
		"edge": base.lightened(0.5),
		"light": base.lightened(0.28),
		"mid": base,
		"web": base.darkened(0.22),
		"dark": base.darkened(0.55),
		"rust": base.lerp(Color(0.55, 0.27, 0.12), 0.45),
	}


static func wood_colors(family: String) -> Dictionary:
	var base := Color(0.44, 0.3, 0.19).lerp(tint(family), 0.2)
	return {
		"light": base.lightened(0.22),
		"mid": base,
		"grain": base.darkened(0.25),
		"dark": base.darkened(0.55),
		"strap": Color(0.3, 0.31, 0.33).lerp(tint(family), 0.25),
	}


## Rolled I-section seen from the web side: two flanges, the recessed web, bolt pairs.
static func column(family: String) -> Texture2D:
	var key := "column:" + family
	if not _cache.has(key):
		var p := steel_colors(family)
		var img := _canvas(6, 16)
		_rect(img, 0, 0, 6, 16, p["web"])
		_rect(img, 0, 0, 1.25, 16, p["light"])
		_rect(img, 0.25, 0, 0.5, 16, p["edge"])
		_rect(img, 1.25, 0, 0.5, 16, p["dark"])
		_rect(img, 4.75, 0, 1.25, 16, p["mid"])
		_rect(img, 5.5, 0, 0.5, 16, p["dark"])
		_weep(img, _rng(key), p, 1.75, 4.75, false)
		for y in [3.0, 11.0]:
			_bolt(img, 2.0, y, p["light"], p["dark"])
			_bolt(img, 3.5, y, p["light"], p["dark"])
		_cache[key] = _finish(img, 6, 16)
	return _cache[key]


## Plate girder: top flange in the light, bottom flange in shadow, a stiffener per tile.
static func girder(family: String) -> Texture2D:
	var key := "girder:" + family
	if not _cache.has(key):
		var p := steel_colors(family)
		var img := _canvas(16, 6)
		_rect(img, 0, 0, 16, 6, p["web"])
		_rect(img, 0, 0, 16, 1.25, p["light"])
		_rect(img, 0, 0, 16, 0.25, p["edge"])
		_rect(img, 0, 1.25, 16, 0.5, p["dark"])
		_rect(img, 0, 4.75, 16, 1.25, p["mid"])
		_rect(img, 0, 5.5, 16, 0.5, p["dark"])
		_rect(img, 0, 1.75, 0.75, 3.0, p["light"])
		_rect(img, 0.75, 1.75, 0.5, 3.0, p["dark"])
		_weep(img, _rng(key), p, 1.75, 4.75, true)
		for x in [4.5, 11.5]:
			_bolt(img, x, 0.25, p["light"], p["dark"])
			_bolt(img, x, 4.75, p["light"], p["dark"])
		_cache[key] = _finish(img, 16, 6)
	return _cache[key]


## Flat bracing bar, riveted once per tile.
static func flat(family: String) -> Texture2D:
	var key := "flat:" + family
	if not _cache.has(key):
		var p := steel_colors(family)
		var img := _canvas(16, 2)
		_rect(img, 0, 0, 16, 2, p["mid"])
		_rect(img, 0, 0, 16, 0.5, p["light"])
		_rect(img, 0, 1.5, 16, 0.5, p["dark"])
		_bolt(img, 1.0, 0.5, p["light"], p["dark"])
		_cache[key] = _finish(img, 16, 2)
	return _cache[key]


## Squared timber post, grain running up.
static func post(family: String) -> Texture2D:
	var key := "post:" + family
	if not _cache.has(key):
		var p := wood_colors(family)
		var img := _canvas(6, 16)
		_grain(img, _rng(key), p, true)
		_rect(img, 0, 0, 0.5, 16, p["light"])
		_rect(img, 5.25, 0, 0.75, 16, p["dark"])
		_cache[key] = _finish(img, 6, 16)
	return _cache[key]


## Timber beam with an iron strap per tile.
static func beam(family: String) -> Texture2D:
	var key := "beam:" + family
	if not _cache.has(key):
		var p := wood_colors(family)
		var strap: Color = p["strap"]
		var img := _canvas(16, 7)
		_grain(img, _rng(key), p, false)
		_rect(img, 0, 0, 16, 0.5, p["light"])
		_rect(img, 0, 6.25, 16, 0.75, p["dark"])
		_rect(img, 7.0, 0.5, 1.5, 5.75, strap)
		_rect(img, 7.0, 0.5, 1.5, 0.25, strap.lightened(0.3))
		_bolt(img, 7.25, 2.75, strap.lightened(0.4), p["dark"])
		_cache[key] = _finish(img, 16, 7)
	return _cache[key]


## Hoist deck in side view. Timber: plank ends on a strapped stringer. Steel: a
## tread plate on a channel frame. The bottom 2 px stay open below the frame.
static func deck(material: String, family: String) -> Texture2D:
	var key := "deck:%s:%s" % [material, family]
	if _cache.has(key):
		return _cache[key]
	var img := _canvas(16, 16)
	var rng := _rng(key)
	if material == STEEL:
		var s := steel_colors(family)
		_rect(img, 0, 0, 16, 3, s["mid"])
		_rect(img, 0, 0, 16, 0.5, s["edge"])
		for i in 8:
			_rect(img, i * 2.0 + float(i % 2), 1.0, 1.0, 0.75, s["light"])
		_rect(img, 0, 3, 16, 9, s["web"])
		_rect(img, 0, 3, 16, 0.5, s["dark"])
		_rect(img, 0, 3.5, 0.75, 8.5, s["light"])
		_rect(img, 0.75, 3.5, 0.5, 8.5, s["dark"])
		_weep(img, rng, s, 3.5, 12.0, true)
		for x in [4.0, 12.0]:
			_bolt(img, x, 4.5, s["light"], s["dark"])
			_bolt(img, x, 9.5, s["light"], s["dark"])
		_rect(img, 0, 12, 16, 2, s["mid"])
		_rect(img, 0, 13.5, 16, 0.5, s["dark"])
	else:
		var w := wood_colors(family)
		var strap: Color = w["strap"]
		for i in 4:
			var x := float(i) * 4.0
			var face: Color = w["light"] if i % 2 == 0 else (w["mid"] as Color).lightened(0.12)
			_rect(img, x, 0, 4, 4, face)
			_rect(img, x, 0, 4, 0.5, face.lightened(0.2))
			_rect(img, x + 3.5, 0, 0.5, 4, w["dark"])
			_rect(img, x + 1.5, 1.5, 1.0, 1.0, face.darkened(0.18))
		_rect(img, 0, 4, 16, 9, w["mid"])
		_grain_rows(img, rng, w, 4.5, 12.5)
		_rect(img, 0, 4, 16, 0.5, w["dark"])
		_rect(img, 6.75, 4, 2.5, 9, strap)
		_rect(img, 6.75, 4, 2.5, 0.5, strap.lightened(0.3))
		_bolt(img, 7.5, 6.0, strap.lightened(0.4), w["dark"])
		_bolt(img, 7.5, 10.5, strap.lightened(0.4), w["dark"])
		_rect(img, 0, 13, 16, 1, w["dark"])
	_cache[key] = _finish(img, 16, 16)
	return _cache[key]


## Poured footing under steel: flecked grey that belongs to no chapter.
static func concrete() -> Texture2D:
	var key := "concrete"
	if not _cache.has(key):
		var img := _canvas(16, 4)
		var rng := _rng(key)
		_rect(img, 0, 0, 16, 4, Color(0.42, 0.42, 0.44))
		_rect(img, 0, 0, 16, 0.5, Color(0.56, 0.56, 0.58))
		for i in 40:
			var x := rng.randi_range(0, img.get_width() - 1)
			var y := rng.randi_range(2, img.get_height() - 1)
			img.set_pixel(x, y, Color(0.3, 0.3, 0.32) if rng.randf() < 0.6 else Color(0.52, 0.52, 0.55))
		_cache[key] = _finish(img, 16, 4)
	return _cache[key]


## ------------------------------------------------------------ internals --

static func _canvas(w: int, h: int) -> Image:
	var image := Image.create_empty(w * DENSITY, h * DENSITY, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	return image


static func _finish(image: Image, w: int, h: int) -> Texture2D:
	var texture := ImageTexture.create_from_image(image)
	texture.set_size_override(Vector2i(w, h))
	return texture


static func _rng(key: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	return rng


## Logical-pixel rectangle, written in texels.
static func _rect(img: Image, x: float, y: float, w: float, h: float, color: Color) -> void:
	var r := Rect2i(roundi(x * DENSITY), roundi(y * DENSITY), roundi(w * DENSITY), roundi(h * DENSITY))
	r = r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if r.size.x > 0 and r.size.y > 0:
		img.fill_rect(r, color)


static func _bolt(img: Image, x: float, y: float, light: Color, dark: Color) -> void:
	_rect(img, x, y, 1.0, 1.0, dark)
	_rect(img, x, y, 0.5, 0.5, light)


## Rust weeping down a web band (a..b across the member, logical px).
static func _weep(img: Image, rng: RandomNumberGenerator, p: Dictionary, a: float, b: float, horizontal: bool) -> void:
	var lo := roundi(a * DENSITY)
	var hi := roundi(b * DENSITY)
	var rust: Color = p["rust"]
	var dark: Color = p["dark"]
	var along := img.get_width() if horizontal else img.get_height()
	for i in 18:
		var run := rng.randi_range(3, 10)
		var across := rng.randi_range(lo, maxi(lo, hi - 1))
		var start := rng.randi_range(0, maxi(0, along - run))
		for k in run:
			var c := rust if rng.randf() < 0.7 else dark
			if horizontal:
				img.set_pixel(clampi(start + k, 0, img.get_width() - 1), clampi(across, 0, img.get_height() - 1), c)
			else:
				img.set_pixel(clampi(across, 0, img.get_width() - 1), clampi(start + k, 0, img.get_height() - 1), c)


## Sawn grain lines along the member, plus one knot.
static func _grain(img: Image, rng: RandomNumberGenerator, p: Dictionary, vertical: bool) -> void:
	img.fill(p["mid"])
	var across := img.get_width() if vertical else img.get_height()
	var along := img.get_height() if vertical else img.get_width()
	for line in range(1, across - 1, 3):
		if rng.randf() < 0.45:
			continue
		var color: Color = p["grain"] if rng.randf() < 0.7 else p["light"]
		var wobble := rng.randf_range(0.0, TAU)
		for t in along:
			var o := clampi(line + roundi(sin(wobble + t * 0.11) * 0.8), 0, across - 1)
			if vertical:
				img.set_pixel(o, t, color)
			else:
				img.set_pixel(t, o, color)
	var cx := rng.randi_range(DENSITY, img.get_width() - DENSITY - 1)
	var cy := rng.randi_range(DENSITY, img.get_height() - DENSITY - 1)
	var rx := 1 if vertical else 2
	var ry := 2 if vertical else 1
	for dy in range(-ry, ry + 1):
		for dx in range(-rx, rx + 1):
			img.set_pixel(clampi(cx + dx, 0, img.get_width() - 1), clampi(cy + dy, 0, img.get_height() - 1), p["dark"])


static func _grain_rows(img: Image, rng: RandomNumberGenerator, p: Dictionary, y0: float, y1: float) -> void:
	for row in range(roundi(y0 * DENSITY), roundi(y1 * DENSITY), 3):
		if rng.randf() < 0.4:
			continue
		var color: Color = p["grain"] if rng.randf() < 0.75 else p["light"]
		var wobble := rng.randf_range(0.0, TAU)
		for x in img.get_width():
			img.set_pixel(x, clampi(row + roundi(sin(wobble + x * 0.09) * 0.8), 0, img.get_height() - 1), color)


static func _readable(image: Image) -> Image:
	if image != null and image.is_compressed():
		image = image.duplicate() as Image
		image.decompress()
	return image
