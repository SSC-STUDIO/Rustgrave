class_name SolidPlatform
extends StaticBody2D
## Two texture families so terrain reads correctly at a glance:
## - "ground": grass top + cemetery dirt that fades to near-black — for
##   terrain rooted in the earth (bottoms may run off-screen unfinished).
## - "floating": church hovering-slab stones — finished top face, closed
##   left/right ends, ragged hanging underside that shows sky through the
##   gaps. For airborne steps, which must never show a raw dirt
##   cross-section nor a boxy filled bottom.
## - "stone": cathedral paving — two rows of cracked flagstone cut from the
##   48px church slabs, then the same cemetery earth underneath. Marks the
##   Executioner's nave apart from the graveyard grass without new art.
## - "moss" / "moss_float": Level02 undercroft — moss-capped teal brick cut
##   from the Old Dark Castle interior set; the float variant is the small
##   mossy block split into end/mid/end pieces.
## - Chapter families (tools/gen_theme_tiles.py), each a slab skin plus a
##   "<name>_float" ledge: "brick" (town street brick + plank ledges),
##   "castle" (bell-tower olive brick, gold trim), "iron" (workshop rust
##   iron), "basalt" (forge slag rock), "rampart" (city-wall grey stone).
## Missing art falls back to a ColorRect (headless/tests).

@export var size: Vector2 = Vector2(64, 16)
@export var fill: Color = Color("#2a1e32")
@export var cap_surface: bool = true
## Grass caps overhanging the open left/right ends of the surface row.
## Disable the side that butts against a wall / level boundary.
@export var cap_left: bool = true
@export var cap_right: bool = true
## Multiplied onto every tile; pits/interiors can sit darker than open ground.
@export var tone: Color = Color.WHITE
## "auto": thin, wide platforms count as floating; everything else is ground.
@export_enum("auto", "ground", "floating", "stone", "moss", "moss_float",
		"brick", "brick_float", "castle", "castle_float", "iron", "iron_float",
		"basalt", "basalt_float", "rampart", "rampart_float", "nave", "nave_float") var skin: String = "auto"

const TOP_A := "res://assets/env/tile_top_a.png"
const TOP_B := "res://assets/env/tile_top_b.png"
const TOP_LEFT := "res://assets/env/tile_top_left.png"
const TOP_RIGHT := "res://assets/env/tile_top_right.png"
const FILL_PLAIN := "res://assets/env/tile_fill_plain.png"
const FILL_PLAIN_B := "res://assets/env/tile_fill_plain_b.png"
const FILL_SKULL := "res://assets/env/tile_fill_skull.png"
const FILL_EDGE_L := "res://assets/env/tile_fill_edge_l.png"
const FILL_EDGE_R := "res://assets/env/tile_fill_edge_r.png"
const FILL_FADE_A := "res://assets/env/tile_fill_fade_a.png"
const FILL_FADE_B := "res://assets/env/tile_fill_fade_b.png"
const FILL_DEEP := "res://assets/env/tile_fill_deep.png"
const FLOAT_LEFT := "res://assets/env/float_left.png"
const FLOAT_RIGHT := "res://assets/env/float_right.png"
## 四种中段：同一石板的不同切段（含镜像），垂挂轮廓各不相同。
const FLOAT_MIDS: Array[String] = [
	"res://assets/env/float_mid_a.png",
	"res://assets/env/float_mid_b.png",
	"res://assets/env/float_mid_c.png",
	"res://assets/env/float_mid_d.png",
]
## 悬浮石台整体略偏冷灰，和草顶暖土在同一色板里拉开对比。
const FLOAT_TONE := Color(0.82, 0.8, 0.95)
## 48×48 教堂石板：上 16px 带亮沿的板面，16–32px 是裂纹石身，下面是残缺底。
const STONE_SLABS: Array[String] = [
	"res://assets/env/slab_a.png",
	"res://assets/env/slab_b.png",
	"res://assets/env/slab_c.png",
]
## 石板行数：板面 + 石身；再往下回到墓园深土，铺路只是压在坟土上。
const STONE_ROWS := 2
## 铺路略偏冷紫，和柱子/拱门同一族，草地暖土留给墓园。
const STONE_TONE := Color(0.88, 0.84, 0.98)
## 地窟苔砖：48×48，上 16px 苔盖 + 两行青砖；再往下是同色系的暗砖填充。
const MOSS_SLABS: Array[String] = [
	"res://assets/env/moss_slab_a.png",
	"res://assets/env/moss_slab_b.png",
	"res://assets/env/moss_slab_c.png",
]
const MOSS_ROWS := 3
const MOSS_FILL := "res://assets/env/moss_fill.png"
const MOSS_TONE := Color(0.96, 1.0, 0.94)
const MOSS_FLOAT_LEFT := "res://assets/env/moss_float_left.png"
const MOSS_FLOAT_MID := "res://assets/env/moss_float_mid.png"
const MOSS_FLOAT_RIGHT := "res://assets/env/moss_float_right.png"
## Chapter slab families: [slabs, slab rows, deep fill, tone, seed salt].
## Entry: [slabs, slab rows, main fill, tone, seed salt, variant fill]. The fills are real
## masonry (tools/gen_theme_tiles.py masonry_tile) so the ground reads as foundation going
## down into the dark, not a slab over a black void.
const SLAB_SKINS := {
	"brick": [["res://assets/env/brick_slab_a.png", "res://assets/env/brick_slab_b.png",
			"res://assets/env/brick_slab_c.png"], 3, "res://assets/env/brick_fill.png", Color.WHITE, 0x6b21,
			"res://assets/env/brick_fill_b.png"],
	"castle": [["res://assets/env/castle_slab_a.png", "res://assets/env/castle_slab_b.png",
			"res://assets/env/castle_slab_c.png"], 3, "res://assets/env/castle_fill.png", Color.WHITE, 0x7c41,
			"res://assets/env/castle_fill_b.png"],
	"iron": [["res://assets/env/iron_slab_a.png", "res://assets/env/iron_slab_b.png",
			"res://assets/env/iron_slab_c.png"], 2, "res://assets/env/iron_fill.png", Color.WHITE, 0x1a09,
			"res://assets/env/iron_fill_b.png"],
	"basalt": [["res://assets/env/basalt_slab_a.png", "res://assets/env/basalt_slab_b.png",
			"res://assets/env/basalt_slab_c.png"], 2, "res://assets/env/basalt_fill.png", Color.WHITE, 0x2b3c,
			"res://assets/env/basalt_fill_b.png"],
	"rampart": [["res://assets/env/rampart_slab_a.png", "res://assets/env/rampart_slab_b.png",
			"res://assets/env/rampart_slab_c.png"], 2, "res://assets/env/rampart_fill.png", Color.WHITE, 0x3d4e,
			"res://assets/env/rampart_fill_b.png"],
	# Cathedral / nave paving: the church slab in a slate ramp instead of saturated lavender.
	"nave": [["res://assets/env/nave_slab_a.png", "res://assets/env/nave_slab_b.png",
			"res://assets/env/nave_slab_c.png"], 2, "res://assets/env/nave_fill.png", Color.WHITE, 0x4a5c,
			"res://assets/env/nave_fill_b.png"],
}
## Chapter ledges: [left, right, mids].
const FLOAT_SKINS := {
	"brick_float": ["res://assets/env/brick_float_left.png", "res://assets/env/brick_float_right.png",
			["res://assets/env/brick_float_mid_a.png", "res://assets/env/brick_float_mid_b.png",
			"res://assets/env/brick_float_mid_c.png"]],
	"castle_float": ["res://assets/env/castle_float_left.png", "res://assets/env/castle_float_right.png",
			["res://assets/env/castle_float_mid_a.png", "res://assets/env/castle_float_mid_b.png"]],
	"iron_float": ["res://assets/env/iron_float_left.png", "res://assets/env/iron_float_right.png",
			["res://assets/env/iron_float_mid_a.png", "res://assets/env/iron_float_mid_b.png",
			"res://assets/env/iron_float_mid_c.png", "res://assets/env/iron_float_mid_d.png"]],
	"basalt_float": ["res://assets/env/basalt_float_left.png", "res://assets/env/basalt_float_right.png",
			["res://assets/env/basalt_float_mid_a.png", "res://assets/env/basalt_float_mid_b.png",
			"res://assets/env/basalt_float_mid_c.png", "res://assets/env/basalt_float_mid_d.png"]],
	"nave_float": ["res://assets/env/nave_float_left.png", "res://assets/env/nave_float_right.png",
			["res://assets/env/nave_float_mid_a.png", "res://assets/env/nave_float_mid_b.png",
			"res://assets/env/nave_float_mid_c.png", "res://assets/env/nave_float_mid_d.png"]],
	"rampart_float": ["res://assets/env/rampart_float_left.png", "res://assets/env/rampart_float_right.png",
			["res://assets/env/rampart_float_mid_a.png", "res://assets/env/rampart_float_mid_b.png",
			"res://assets/env/rampart_float_mid_c.png", "res://assets/env/rampart_float_mid_d.png"]],
}
const WORLD := 16.0
## Row brightness: surface row full, then darken toward DEPTH_FLOOR by row 4.
const DEPTH_FLOOR := 0.4
## Chance for a skull accent in the dirt band (row 1). Rare on purpose.
const SKULL_CHANCE := 0.12


func setup(pos: Vector2, sz: Vector2, col: Color) -> void:
	position = pos
	size = sz
	fill = col


## 重新上色并重建贴片视觉（碰撞体与 LightOccluder2D 不动）。
## 关卡在自己的 `_ready` 里给种别统一材质色阶时用：子节点 `_ready` 已经跑过，
## 只改 `tone` 不会重画。只重建 Sprite / ColorRect，不碰碰撞与遮挡。
func apply_tone(new_tone: Color) -> void:
	tone = new_tone
	for child in get_children():
		if child is Sprite2D or child is ColorRect:
			remove_child(child)
			child.free()
	_build_visual()


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build_visual()
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	col.shape = shape
	col.position = size * 0.5
	add_child(col)
	_add_light_occluder()


func _build_visual() -> void:
	var floating := skin == "floating" \
			or (skin == "auto" and size.y <= WORLD + 0.5 and size.x > WORLD + 0.5)
	if floating and _build_floating(FLOAT_LEFT, FLOAT_RIGHT, FLOAT_MIDS, FLOAT_TONE):
		return
	if skin == "moss_float" and _build_floating(MOSS_FLOAT_LEFT, MOSS_FLOAT_RIGHT,
			[MOSS_FLOAT_MID] as Array[String], MOSS_TONE):
		return
	if skin == "stone" and _build_slabs(STONE_SLABS, STONE_ROWS, STONE_TONE, FILL_DEEP,
			[FILL_PLAIN, FILL_PLAIN_B] as Array[String], 0x5710):
		return
	if skin == "moss" and _build_slabs(MOSS_SLABS, MOSS_ROWS, MOSS_TONE, MOSS_FILL,
			[] as Array[String], 0x3055):
		return
	if FLOAT_SKINS.has(skin):
		var f: Array = FLOAT_SKINS[skin]
		var mids: Array[String] = []
		mids.assign(f[2])
		if _build_floating(f[0], f[1], mids, Color.WHITE):
			return
	if SLAB_SKINS.has(skin):
		var d: Array = SLAB_SKINS[skin]
		var slabs: Array[String] = []
		slabs.assign(d[0])
		var variants: Array[String] = []
		if d.size() > 5:
			variants.append(String(d[5]))
		if _build_slabs(slabs, int(d[1]), d[3], d[2], variants, int(d[4])):
			return
	var tops: Array[Texture2D] = []
	for path in [TOP_A, TOP_B]:
		var t := _load_tex(path)
		if t != null:
			tops.append(t)
	var fills: Array[Texture2D] = []
	for path in [FILL_PLAIN, FILL_PLAIN_B]:
		var t := _load_tex(path)
		if t != null:
			fills.append(t)
	if tops.is_empty() and fills.is_empty():
		_fallback_rect()
		return
	if fills.is_empty():
		fills = tops
	if tops.is_empty():
		tops = fills
	var cap_l := _load_tex(TOP_LEFT)
	var cap_r := _load_tex(TOP_RIGHT)
	var skull := _load_tex(FILL_SKULL)
	var edge_l := _load_tex(FILL_EDGE_L)
	var edge_r := _load_tex(FILL_EDGE_R)
	var fades: Array[Texture2D] = []
	for path in [FILL_FADE_A, FILL_FADE_B]:
		var t := _load_tex(path)
		if t != null:
			fades.append(t)
	var deep := _load_tex(FILL_DEEP)

	# Deterministic per-platform variation (stable across reloads).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector4(position.x, position.y, size.x, size.y))

	var cols := maxi(1, int(ceil(size.x / WORLD)))
	var rows := maxi(1, int(ceil(size.y / WORLD)))
	var thin := size.y <= WORLD + 0.5
	var wall := size.x <= WORLD + 0.5 and size.y > WORLD * 2.0
	var use_surface := cap_surface and not wall
	for r in rows:
		for c in cols:
			var tex: Texture2D
			var flip := false
			var is_left := c == 0
			var is_right := c == cols - 1
			if use_surface and (thin or r == 0):
				if cap_left and is_left and cap_l != null and cols > 1:
					tex = cap_l
				elif cap_right and is_right and cap_r != null and cols > 1:
					tex = cap_r
				else:
					tex = tops[rng.randi_range(0, tops.size() - 1)]
					flip = rng.randf() < 0.5
			elif use_surface and r == 1:
				# Dirt band right under the grass; edge shading on open ends.
				if cap_left and is_left and edge_l != null and cols > 1:
					tex = edge_l
				elif cap_right and is_right and edge_r != null and cols > 1:
					tex = edge_r
				elif skull != null and rng.randf() < SKULL_CHANCE:
					tex = skull
					flip = rng.randf() < 0.5
				else:
					tex = fills[rng.randi_range(0, fills.size() - 1)]
					flip = rng.randf() < 0.5
			elif use_surface and r == 2:
				# 过渡行：以安静的暗土为主，偶尔一块骸骨渐隐 tile 作点缀，
				# 连排骷髅会变成一条"骷髅带"。
				if not fades.is_empty() and rng.randf() < 0.22:
					tex = fades[rng.randi_range(0, fades.size() - 1)]
				else:
					tex = fills[rng.randi_range(0, fills.size() - 1)]
				flip = rng.randf() < 0.5
			elif use_surface and r >= 3 and deep != null:
				tex = deep if rng.randf() < 0.72 else fills[rng.randi_range(0, fills.size() - 1)]
				flip = rng.randf() < 0.5
			else:
				tex = fills[rng.randi_range(0, fills.size() - 1)]
				flip = rng.randf() < 0.5
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.centered = false
			spr.flip_h = flip
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var src := float(tex.get_width())
			var s := WORLD / maxf(1.0, src)
			spr.scale = Vector2(s, s)
			spr.position = Vector2(c * WORLD, r * WORLD)
			var remain_x := size.x - c * WORLD
			var remain_y := size.y - r * WORLD
			if remain_x < WORLD - 0.01 or remain_y < WORLD - 0.01:
				spr.region_enabled = true
				var rw := minf(src, remain_x / s)
				var rh := minf(float(tex.get_height()), remain_y / s)
				# Right-end partials keep the outer edge of the art (caps and
				# edge shading live on the right side of those tiles).
				var rx := src - rw if is_right and rw < src else 0.0
				spr.region_rect = Rect2(rx, 0, rw, rh)
			spr.z_index = -1
			spr.modulate = _row_tint(r, rows, use_surface)
			add_child(spr)


## 悬浮石台：左右端头 + 随机中段，顶面与碰撞体顶对齐，薄石板 + 短垂岩（透明）。
## 端头永远画完整 16px（非整数宽度时右端头向左回收对齐 size.x，盖在中段上）。
func _build_floating(left_path: String, right_path: String, mid_paths: Array[String],
		float_tone: Color) -> bool:
	var lcap := _load_tex(left_path)
	var rcap := _load_tex(right_path)
	var mids: Array[Texture2D] = []
	for path in mid_paths:
		var t := _load_tex(path)
		if t != null:
			mids.append(t)
	if lcap == null or rcap == null or mids.is_empty():
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector4(position.x, position.y, size.x, size.y))
	# 中段先铺（16..size.x-16），端头最后画压在上面，保证两端永远是完整收边。
	# 每格随机取一种中段且不与前一格重复，长台的垂挂轮廓才不会按 16px 打拍子。
	var x := WORLD
	var prev := -1
	while x < size.x - WORLD - 0.01:
		var i := rng.randi_range(0, mids.size() - 1)
		if i == prev and mids.size() > 1:
			i = (i + 1 + rng.randi_range(0, mids.size() - 2)) % mids.size()
		prev = i
		_add_float_piece(mids[i], x, minf(WORLD, size.x - WORLD - x), float_tone)
		x += WORLD
	_add_float_piece(lcap, 0.0, WORLD, float_tone)
	_add_float_piece(rcap, size.x - WORLD, WORLD, float_tone)
	return true


func _add_float_piece(tex: Texture2D, x: float, width: float, float_tone: Color) -> void:
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = Vector2(x, 0)
	if width < float(tex.get_width()) - 0.01:
		spr.region_enabled = true
		spr.region_rect = Rect2(0, 0, width, float(tex.get_height()))
	spr.z_index = -1
	spr.modulate = Color(
		tone.r * float_tone.r, tone.g * float_tone.g, tone.b * float_tone.b, tone.a
	)
	add_child(spr)


## 石板铺面（教堂铺路 / 地窟苔砖）：前 slab_rows 行从三块 48px 石板上随机切 16px 段
## （列位、板号、镜像都随机，长地板才不会按 48px 打拍子），之后的行用 deep_path
## 的暗填充压深。deep_path 缺失时回落到墓园土块。
func _build_slabs(slab_paths: Array[String], slab_rows: int, slab_tone: Color,
		deep_path: String, fill_paths: Array[String], seed_salt: int) -> bool:
	var slabs: Array[Texture2D] = []
	for path in slab_paths:
		var t := _load_tex(path)
		if t != null:
			slabs.append(t)
	if slabs.is_empty():
		return false
	var deep := _load_tex(deep_path)
	var fills: Array[Texture2D] = []
	for path in fill_paths:
		var t := _load_tex(path)
		if t != null:
			fills.append(t)
	if fills.is_empty() and deep == null:
		fills = slabs
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector4(position.x, position.y, size.x, size.y)) ^ seed_salt
	var cols := maxi(1, int(ceil(size.x / WORLD)))
	var rows := maxi(1, int(ceil(size.y / WORLD)))
	var slab_cols := int(float(slabs[0].get_width()) / WORLD)
	var slab_max_rows := int(float(slabs[0].get_height()) / WORLD)
	for r in rows:
		for c in cols:
			var remain_x := size.x - c * WORLD
			var remain_y := size.y - r * WORLD
			var w := minf(WORLD, remain_x)
			var h := minf(WORLD, remain_y)
			var spr := Sprite2D.new()
			spr.centered = false
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			spr.position = Vector2(c * WORLD, r * WORLD)
			spr.z_index = -1
			if r < mini(slab_rows, slab_max_rows):
				spr.texture = slabs[rng.randi_range(0, slabs.size() - 1)]
				spr.region_enabled = true
				var sx := float(rng.randi_range(0, maxi(0, slab_cols - 1))) * WORLD
				spr.region_rect = Rect2(sx, r * WORLD, w, h)
				spr.flip_h = rng.randf() < 0.5
				var k := _row_tint(r, rows, true)
				spr.modulate = Color(k.r * slab_tone.r, k.g * slab_tone.g, k.b * slab_tone.b, k.a)
			else:
				var tex: Texture2D
				if deep != null and (fills.is_empty() or rng.randf() < 0.72):
					tex = deep
				else:
					tex = fills[rng.randi_range(0, fills.size() - 1)]
				spr.texture = tex
				spr.flip_h = rng.randf() < 0.5
				var src := float(tex.get_width())
				var s := WORLD / maxf(1.0, src)
				spr.scale = Vector2(s, s)
				if w < WORLD - 0.01 or h < WORLD - 0.01:
					spr.region_enabled = true
					spr.region_rect = Rect2(0, 0, minf(src, w / s), minf(float(tex.get_height()), h / s))
				spr.modulate = _row_tint(r, rows, true)
			add_child(spr)
	return true


## Surface stays bright; each row below sinks toward DEPTH_FLOOR by row 4.
func _row_tint(r: int, rows: int, use_surface: bool) -> Color:
	var depth := 0.0
	if use_surface:
		depth = clampf(float(r - 1) / 3.0, 0.0, 1.0) if r >= 1 else 0.0
	else:
		depth = clampf(float(r) / maxf(1.0, float(rows - 1)) * 0.7, 0.0, 1.0)
	var k := lerpf(1.0, DEPTH_FLOOR, depth)
	return Color(tone.r * k, tone.g * k, tone.b * k, tone.a)


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return ArtTexture.load_texture(path)
	return null


## Occluder matches the collision rectangle only — never the hanging float skin.
func _add_light_occluder() -> void:
	if get_node_or_null("LightOccluder") != null:
		return
	var occ := LightOccluder2D.new()
	occ.name = "LightOccluder"
	var poly := OccluderPolygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(size.x, 0.0),
		Vector2(size.x, size.y),
		Vector2(0.0, size.y),
	])
	occ.occluder = poly
	add_child(occ)


func _fallback_rect() -> void:
	var rect := ColorRect.new()
	rect.name = "VisualRect"
	rect.size = size
	rect.color = fill
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
