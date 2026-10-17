class_name Level01Parallax
extends Node
## Level01 backdrop extras: drifting fog, near-silhouette strip, mood tint,
## moon fill, WeatherFx / CineFx. Attaches into the authored `ParallaxBackdrop`
## (CanvasLayer + Parallax2D plates) and never replaces the three Gothicvania
## plates: sky ×1.9 with its moon, purple mountains ×1.7, graveyard ×1.85.
##
## Godot 4.7 的 ParallaxLayer 走 canvas_set_item_mirroring，把 repeat_times 写死成 1。
## 远山 192×1.7=326，引擎只再画一份 → 652px，刚好比 640 视口多一点。镜头前探/震屏
## 把循环缝扫到左边，紫山就像被裁掉。Parallax2D 可以指定 repeat_times，循环单元
## 仍是一张图的宽度，份数必须盖住视口再加一点余量。

const FOG_PATH := "res://assets/env/fog_band.png"
## 两层飘云夹在天空板和远山之间：高云薄慢，低云厚快。云量跟 WorldClock.cloud_alpha()
## （晴天几乎无云、雨天满天阴），位置随风漂——「云是随机出现的」由天气切换给出。
const CLOUD_HIGH_PATH := "res://assets/env/parallax_clouds_px.png"
const CLOUD_LOW_PATH := "res://assets/env/parallax_clouds_low_px.png"
## 云板本身是深紫，叠在品红天上要提亮成淡紫才读得出。
const CLOUD_TINT := Color(1.24, 1.08, 1.0)
## 地面雾：盖在玩法层前面、贴着地面线（320）滚过的一条软带，浓雾天才真正压上来。
## 带高 64×1.1≈70px，从 276 罩到 346：齐骑士腰，不遮 HUD。
const GROUND_FOG_Y := 276.0
const GROUND_FOG_SCALE := Vector2(2.0, 1.1)
## 雾幕：屏幕空间的淡紫罩层，alpha 跟 WorldClock.fog_veil_alpha()，让浓雾一眼可辨。
const FOG_VEIL_COLOR := Color(0.86, 0.79, 0.72)
const COVER_PAD := 128.0
const MIN_REPEAT_TIMES := 4
## 近景剪影带（scroll 0.65）：一段 512px 宽的图样平铺，只种暗紫软物，
## 填在远景 Hills(0.48) 与游玩层(1.0) 之间。石碑/雕像不进这层——
## 看起来能踩却够不着，叠在月亮/远山上会像「飞着的交互物」。
## feet 落在 Hills 墓园板与玩法地面重叠的山脚带（约 318–322），不是远空。
const SIL_PATTERN := [
	[Level01Env.DECOR_TREE_2, 64.0, 320.0, 0.44],
	[Level01Env.DECOR_BUSH_S, 150.0, 322.0, 0.70],
	[Level01Env.DECOR_BUSH_L, 250.0, 322.0, 0.50],
	[Level01Env.DECOR_TREE_3, 430.0, 320.0, 0.38],
	[Level01Env.DECOR_BUSH_L, 360.0, 322.0, 0.42],
]
const SIL_TINT := Color(0.16, 0.11, 0.10, 0.95)
const SIL_FEET_MIN := 300.0
const SIL_FEET_MAX := 340.0
const SIL_SPAN := 512.0
const TINT_FOLLOW := 2.8
## 第一章色调：远景板（天、远山、墓园坡、两层云）按明度映射到锈 / 余烬色阶再与原画混合，
## 品红月变成余烬月、紫山变成锈褐暮色。玩法层（平台、角色、道具）不进这道调色，
## 远景退后、前景跳出来。数值 = 混合量，0 就是原画。
const GRADE_SHADER := "res://assets/shaders/rust_grade.gdshader"
## Phase 3: the hue moves almost fully onto the ramp (kills the Gothicvania magenta) while the
## value structure does the separation: sky and glow behind, dark mountain silhouettes, mid-value
## graveyard slope, brightest values on the play layer. Fog bands are graded too so they read as
## warm haze instead of lavender.
## Phase 3b (user steer): keep MORE of the authored crimson / violet character - a partial
## rust shift (~40%), not a full recolour - and let value structure do the separation.
const GRADE := {"Far": 0.42, "Mid": 0.4, "Hills": 0.4, "SkyCloudsHigh": 0.4, "SkyCloudsLow": 0.4,
		"FogFar": 0.35, "FogNear": 0.35, "Foreground": 0.4, "GroundFog": 0.3}
## 玩法层（地砖、墓园 / 东翼装饰）走同一张 shader 的「煤灰 + 锈」色阶：明度次序不变，
## 平台亮沿、台阶边仍然读得出；人物、敌人、可交互物、毒池、钩点、火光不进这道调色，
## 角色和前摇因此从灰褐地面上跳出来。
const PLAY_GRADE_AMOUNT := 0.3
## Play-layer value lift: terrain and decor sit above the backdrop in value (phase-2 feedback: muddy).
const PLAY_VALUE := 1.08
const PLAY_GRADE_FOLDERS := ["Platforms", "GraveDecor", "BastionDecor", "CathedralDecor"]
const PLAY_RAMP := [Color("#0e0907"), Color("#45301f"), Color("#875b38"), Color("#cf914f"), Color("#ffe2ad")]
## 远景压暗：越远越沉进暮色，最亮的值留给玩法层（平台亮沿、角色）。
## Mountains (Mid) are the darkest plate so they silhouette against the horizon glow; the graveyard
## slope (Hills) is mid-value; the near grass strip (Foreground) is a dark frame.
const PLATE_VALUE := {"Far": 0.85, "Mid": 0.6, "Hills": 0.74, "SkyCloudsHigh": 0.9, "SkyCloudsLow": 0.85,
		"FogFar": 0.9, "FogNear": 0.9, "Foreground": 0.5, "GroundFog": 1.0}
## 第一章暖偏：全局 MoodTint（昼夜 / 天气）乘上余烬偏色——夜仍是夜，但是煤灰夜而不是紫夜。
const CHAPTER_WARM := Color(1.04, 0.97, 0.92)
const TINT_FLOOR := 0.3
## Default (chapter-1) palette. Keys: ramp = backdrop ramp (5 colours, dark→light),
## plates = layer name → blend, values = layer name → value_scale, warm = MoodTint bias,
## play_ramp / play_amount = play-layer ramp and blend.
## r > g > b at every stop: ember / rust / soot, never plum or magenta.
const RUST_RAMP := [Color("#0f0909"), Color("#3a1f18"), Color("#7a3d26"), Color("#c46e32"), Color("#ffc177")]
## Horizon glow: a screen-space additive gradient between the sky (plus clouds) and the
## mountains, so the sky reads as a warm haze over the horizon instead of flat murk and the
## dark mountain plate silhouettes against it. rgb = colour, a = peak strength.
const HORIZON_GLOW := Color(1.0, 0.36, 0.26, 0.34)
## [y fraction of the view, strength fraction] stops of the glow gradient, top → bottom.
const GLOW_STOPS := [[0.0, 0.0], [0.16, 0.12], [0.44, 0.62], [0.62, 1.0], [0.8, 0.72], [1.0, 0.35]]
## Top light: a warm lit lip along every platform top on the play layer (a = strength).
const TOP_LIGHT := Color(1.0, 0.72, 0.5, 0.5)
const TOP_LIGHT_DEPTH := 6
## Light pools: additive glow around lit fires (nests, torches, the forge heart), a = strength.
const LIGHT_POOL := Color(1.0, 0.6, 0.28, 0.22)
const POOL_FOLLOWS := [&"nest", &"torch", &"heart"]

## Chapter palette (defaults: GRADE, RUST_RAMP, CHAPTER_WARM, PLAY_RAMP). Chapters that reuse this sky stack (Level06 night
## graveyard) hand in their own ramp so they do not read as a copy of chapter 1.
var palette: Dictionary = {}

var _far_layer: Parallax2D
var _cloud_high: Parallax2D
var _cloud_low: Parallax2D
var _fog_far: Parallax2D
var _fog_near: Parallax2D
var _sil_layer: Parallax2D
var _foreground: Parallax2D
var _ground_fog: Parallax2D
var _fog_veil: ColorRect
var _mood_tint: CanvasModulate
var _moon_fill: DirectionalLight2D
var _glow: Sprite2D


func build(host: Node2D) -> void:
	var backdrop := host.get_node_or_null("ParallaxBackdrop") as Node
	if backdrop == null:
		return
	if backdrop is CanvasLayer:
		(backdrop as CanvasLayer).follow_viewport_enabled = false
	_far_layer = backdrop.get_node_or_null("Far") as Parallax2D
	for child in backdrop.get_children():
		if child is Parallax2D:
			cover_layer(child as Parallax2D)
	if _far_layer != null:
		# Clouds sit directly behind the mountains: after Far, before Mid.
		_cloud_high = _add_cloud_layer(backdrop, "SkyCloudsHigh", Vector2(0.10, 0.03), 6.0, CLOUD_HIGH_PATH)
		_cloud_low = _add_cloud_layer(backdrop, "SkyCloudsLow", Vector2(0.14, 0.05), 92.0, CLOUD_LOW_PATH)
		var slot := _far_layer.get_index() + 1
		if _cloud_high != null:
			backdrop.move_child(_cloud_high, slot)
			slot += 1
		if _cloud_low != null:
			backdrop.move_child(_cloud_low, slot)
	var fog_tex: Texture2D = null
	if ResourceLoader.exists(FOG_PATH):
		fog_tex = load(FOG_PATH) as Texture2D
	if fog_tex != null:
		_fog_far = _add_fog_layer(backdrop, "FogFar", Vector2(0.5, 0.1), 234.0, 0.13, fog_tex)
	_sil_layer = _add_silhouette_layer(backdrop)
	if fog_tex != null:
		_fog_near = _add_fog_layer(backdrop, "FogNear", Vector2(0.75, 0.14), 276.0, 0.2, fog_tex)
	grade_plates(backdrop, _palette())
	_add_horizon_glow(backdrop)
	var front := host.get_node_or_null("ParallaxForeground") as Node
	if front != null:
		if front is CanvasLayer:
			(front as CanvasLayer).follow_viewport_enabled = false
		# motion>1 只给幕前草。碑/石/土唇不进这张条，否则人一走坟自己在滑。
		_foreground = front.get_node_or_null("Foreground") as Parallax2D
		if _foreground != null:
			cover_layer(_foreground)
		if fog_tex != null:
			_ground_fog = _add_ground_fog(front, fog_tex)
		grade_plates(front, _palette())
		_fog_veil = _add_fog_veil(front)
	# 全局微紫色调：把厚涂角色与紫色墓地轻轻拉到同一冷色轴上。
	# CanvasModulate 与余烬巢 PointLight2D 叠在同一视口：夜里压暗，点光打出暖圈。
	# 视差板在独立 CanvasLayer 上，不受 MoodTint 牵连，夜晚远山仍能看清剪影。
	var tint := host.get_node_or_null("MoodTint") as CanvasModulate
	if tint == null:
		tint = CanvasModulate.new()
		tint.name = "MoodTint"
		host.add_child(tint)
	_mood_tint = tint
	_mood_tint.color = chapter_tint(WorldClock.mood_tint(), _warm())
	var moon := host.get_node_or_null("MoonFill") as DirectionalLight2D
	if moon == null:
		moon = DirectionalLight2D.new()
		moon.name = "MoonFill"
		moon.color = Color(0.72, 0.78, 1.0)
		moon.shadow_enabled = true
		moon.height = 0.65
		moon.rotation = deg_to_rad(-18.0)
		host.add_child(moon)
	_moon_fill = moon
	_snap_atmosphere()
	if host.get_node_or_null("WeatherFx") == null:
		var wx := WeatherFx.new()
		wx.name = "WeatherFx"
		host.add_child(wx)
	if host.get_node_or_null("CineFx") == null:
		var cine := CineFx.new()
		cine.name = "CineFx"
		host.add_child(cine)
	if host.get_node_or_null("WindFx") == null:
		var wind := WindFx.new()
		wind.name = "WindFx"
		host.add_child(wind)


func _process(delta: float) -> void:
	var drift := WorldClock.wind_vector().x
	if _far_layer != null:
		_far_layer.scroll_offset.x += drift * 8.0 * delta
	if _cloud_high != null:
		_cloud_high.scroll_offset.x += drift * 11.0 * delta
	if _cloud_low != null:
		_cloud_low.scroll_offset.x += drift * 17.0 * delta
	if _fog_far != null:
		_fog_far.scroll_offset.x += drift * 18.0 * delta
	if _fog_near != null:
		_fog_near.scroll_offset.x += drift * 32.0 * delta
	if _foreground != null:
		_foreground.scroll_offset.x += drift * 56.0 * delta
	if _ground_fog != null:
		_ground_fog.scroll_offset.x += drift * 24.0 * delta
	_follow_atmosphere(delta)


func _snap_atmosphere() -> void:
	_follow_atmosphere(999.0)


func _follow_atmosphere(delta: float) -> void:
	var k := 1.0 if delta > 10.0 else (1.0 - exp(-TINT_FOLLOW * delta))
	if _mood_tint != null:
		_mood_tint.color = _mood_tint.color.lerp(chapter_tint(WorldClock.mood_tint(), _warm()), k)
	if _fog_far != null:
		var fa := WorldClock.fog_far_alpha()
		_fog_far.modulate = _fog_far.modulate.lerp(Color(1, 1, 1, fa), k)
	if _fog_near != null:
		var na := WorldClock.fog_near_alpha()
		_fog_near.modulate = _fog_near.modulate.lerp(Color(1, 1, 1, na), k)
	if _sil_layer != null:
		_sil_layer.modulate = _sil_layer.modulate.lerp(WorldClock.silhouette_modulate(), k)
	if _far_layer != null:
		_far_layer.modulate = _far_layer.modulate.lerp(WorldClock.sky_modulate(), k)
	var cloud := WorldClock.cloud_alpha()
	if _cloud_high != null:
		var target := Color(_cloud_tint().r, _cloud_tint().g, _cloud_tint().b, cloud)
		_cloud_high.modulate = _cloud_high.modulate.lerp(target, k)
	if _cloud_low != null:
		var target := Color(_cloud_tint().r, _cloud_tint().g, _cloud_tint().b, cloud * 0.8)
		_cloud_low.modulate = _cloud_low.modulate.lerp(target, k)
	if _ground_fog != null:
		_ground_fog.modulate = _ground_fog.modulate.lerp(Color(1, 1, 1, WorldClock.ground_fog_alpha()), k)
	if _fog_veil != null:
		var veil: Color = palette.get("veil", FOG_VEIL_COLOR)
		veil.a = WorldClock.fog_veil_alpha()
		_fog_veil.color = _fog_veil.color.lerp(veil, k)
	if _glow != null:
		# Night / storm dim the horizon glow but never remove it (the forge city still smoulders).
		var glow: Color = palette.get("glow", HORIZON_GLOW)
		var dim := clampf(WorldClock.mood_luminance() / 0.82, 0.4, 1.1)
		_glow.modulate = _glow.modulate.lerp(Color(glow.r, glow.g, glow.b, glow.a * dim), k)
	if _moon_fill != null:
		var e := WorldClock.moon_fill_energy()
		_moon_fill.energy = e
		_moon_fill.enabled = e > 0.001


static func tile_width(sprite: Sprite2D) -> float:
	if sprite == null or sprite.texture == null:
		return 0.0
	return float(sprite.texture.get_width()) * absf(sprite.scale.x)


static func copies_for_view(tile: float, view_w: float = 0.0, pad: float = COVER_PAD) -> int:
	if tile < 1.0:
		return MIN_REPEAT_TIMES
	var view := view_w if view_w > 0.0 else float(PresentationMetrics.WORLD_SIZE.x)
	return maxi(MIN_REPEAT_TIMES, int(ceil((view + pad) / tile)))


## 一层只留一张图，让 Parallax2D 按 repeat_size 重复。repeat_times 必须大于 1，
## 否则又会回到「引擎只再画一份、640 视口露缝」的老问题。
static func cover_layer(layer: Parallax2D, view_w: float = 0.0) -> void:
	if layer == null:
		return
	layer.follow_viewport = false
	var sprites: Array[Sprite2D] = []
	for child in layer.get_children():
		if child is Sprite2D:
			sprites.append(child as Sprite2D)
	if sprites.is_empty():
		if layer.repeat_size.x >= 1.0:
			layer.repeat_times = maxi(layer.repeat_times, MIN_REPEAT_TIMES)
		return
	var spr := sprites[0]
	var tile := tile_width(spr)
	if tile < 1.0:
		return
	for i in range(sprites.size() - 1, 0, -1):
		var extra := sprites[i]
		layer.remove_child(extra)
		extra.free()
	# 略小于实际宽度，像素吸附时副本重叠一丁点，避免 326.4 → 326 露出天空缝。
	var step := floorf(tile)
	if step < 1.0:
		step = tile
	layer.repeat_size = Vector2(step, 0.0)
	layer.repeat_times = copies_for_view(step, view_w)


## 给远景板的精灵挂上章节调色（默认 GRADE / RUST_RAMP）。重复调用只会更新参数。
static func grade_plates(backdrop: Node, pal: Dictionary = {}) -> int:
	if backdrop == null or not ResourceLoader.exists(GRADE_SHADER):
		return 0
	var shader := load(GRADE_SHADER) as Shader
	var plates: Dictionary = pal.get("plates", GRADE)
	var values: Dictionary = pal.get("values", PLATE_VALUE)
	var ramp: Array = pal.get("ramp", RUST_RAMP)
	var graded := 0
	for layer_name in plates:
		var layer := backdrop.get_node_or_null(String(layer_name))
		if layer == null:
			continue
		for child in layer.get_children():
			if not child is Sprite2D:
				continue
			var spr := child as Sprite2D
			var mat := spr.material as ShaderMaterial
			if mat == null or mat.shader != shader:
				mat = ShaderMaterial.new()
				mat.shader = shader
				spr.material = mat
			mat.set_shader_parameter("amount", float(plates[layer_name]))
			mat.set_shader_parameter("value_scale", float(values.get(layer_name, 1.0)))
			for i in ramp.size():
				mat.set_shader_parameter("c%d" % i, ramp[i])
			graded += 1
	return graded


func _palette() -> Dictionary:
	return palette


func _cloud_tint() -> Color:
	return palette.get("cloud_tint", CLOUD_TINT)


func _warm() -> Color:
	return palette.get("warm", CHAPTER_WARM)


## 玩法层调色：给 PLAY_GRADE_FOLDERS 里的地形 / 装饰精灵挂共享的煤灰锈材质。
## 跳过人物、敌人、可交互物、毒池、钩点、火把以及已有材质的节点（发光、加色）。
static func grade_play_layer(host: Node, pal: Dictionary = {}, folders: Array = PLAY_GRADE_FOLDERS) -> int:
	if host == null or not ResourceLoader.exists(GRADE_SHADER):
		return 0
	var mat := play_grade_material(pal)
	var graded := 0
	var top: Color = pal.get("top_light", TOP_LIGHT)
	for folder_name in folders:
		var folder := host.get_node_or_null(String(folder_name))
		if folder != null:
			graded += _grade_tree(folder, mat)
			if top.a > 0.001:
				_light_tops(folder, top)
	return graded


## Lit platform lips only (chapters that keep their authored terrain colours).
static func light_tops(host: Node, top: Color, folders: Array = PLAY_GRADE_FOLDERS) -> void:
	if host == null or top.a <= 0.001:
		return
	for folder_name in folders:
		var folder := host.get_node_or_null(String(folder_name))
		if folder != null:
			_light_tops(folder, top)


## Warm lit lip along each platform top (additive, under the actors' feet line). Walls (one tile
## wide, tall) and platforms without a surface are skipped; idempotent.
static func _light_tops(node: Node, top: Color) -> void:
	for child in node.get_children():
		var plat := child as SolidPlatform
		if plat == null:
			if child is Node2D and not is_grade_exempt(child):
				_light_tops(child, top)
			continue
		if plat.get_node_or_null("TopLight") != null or not plat.cap_surface:
			continue
		if plat.size.x <= SolidPlatform.WORLD + 0.5 and plat.size.y > SolidPlatform.WORLD * 2.0:
			continue
		var lip := Sprite2D.new()
		lip.name = "TopLight"
		lip.texture = top_light_texture()
		lip.centered = false
		lip.scale = Vector2(plat.size.x, 1.0)
		lip.modulate = Color(top.r, top.g, top.b, top.a)
		lip.material = additive_material()
		lip.z_index = 1
		lip.add_to_group("no_grade")
		plat.add_child(lip)


static var _top_tex: Texture2D
static var _pool_tex: Texture2D
static var _add_mat: CanvasItemMaterial


static func additive_material() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat


## 1 px wide, TOP_LIGHT_DEPTH tall: a hot top row, then a quick falloff into the stone.
static func top_light_texture() -> Texture2D:
	if _top_tex == null:
		var img := Image.create(1, TOP_LIGHT_DEPTH, false, Image.FORMAT_RGBA8)
		for y in TOP_LIGHT_DEPTH:
			var a := 1.0 if y == 0 else 0.55 * pow(1.0 - float(y) / float(TOP_LIGHT_DEPTH), 1.6)
			img.set_pixel(0, y, Color(1, 1, 1, a))
		_top_tex = ImageTexture.create_from_image(img)
	return _top_tex


static func pool_texture() -> Texture2D:
	if _pool_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 128
		t.height = 128
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_pool_tex = t
	return _pool_tex


## Soft additive pools around every lit fire light under host (nest, torch, forge heart).
## Each pool follows its light's on/off and energy, so unlit nests stay dark. Idempotent.
static func add_light_pools(host: Node, pal: Dictionary = {}) -> int:
	var col: Color = pal.get("light_pool", LIGHT_POOL)
	if host == null or col.a <= 0.001:
		return 0
	var n := 0
	for node in host.find_children("*", "WorldLight", true, false):
		var light := node as WorldLight
		if not POOL_FOLLOWS.has(light.follow) or light.has_meta("light_pool"):
			continue
		var pool := LightPool.new()
		pool.name = "LightPool"
		pool.source = light
		pool.tint = col
		pool.texture = pool_texture()
		pool.material = additive_material()
		light.set_meta("light_pool", true)
		light.add_child(pool)
		n += 1
	return n


func _add_horizon_glow(backdrop: Node) -> void:
	var glow: Color = palette.get("glow", HORIZON_GLOW)
	var spr := add_glow(backdrop, glow, GLOW_STOPS, "Mid")
	if spr != null:
		_glow = spr


## Screen-space additive haze gradient on a backdrop CanvasLayer, drawn just under the layer
## named `under` (or on top when it is missing). stops = [[y fraction, strength], ...].
static func add_glow(backdrop: Node, glow: Color, stops: Array, under: String = "") -> Sprite2D:
	if backdrop == null or glow.a <= 0.001 or backdrop.get_node_or_null("HorizonGlow") != null:
		return null
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for stop in stops:
		offsets.append(float(stop[0]))
		colors.append(Color(1, 1, 1, float(stop[1])))
	g.offsets = offsets
	g.colors = colors
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 4
	t.height = 128
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	var spr := Sprite2D.new()
	spr.name = "HorizonGlow"
	spr.texture = t
	spr.centered = false
	var view := Vector2(PresentationMetrics.WORLD_SIZE)
	spr.scale = Vector2(view.x / 4.0, view.y / 128.0)
	spr.modulate = Color(glow.r, glow.g, glow.b, glow.a)
	spr.material = additive_material()
	backdrop.add_child(spr)
	# Chapter 1: over the sky and clouds, under the mountains.
	var anchor := backdrop.get_node_or_null(under) if under != "" else null
	if anchor != null:
		backdrop.move_child(spr, anchor.get_index())
	return spr


static func chapter_tint(c: Color, warm: Color = CHAPTER_WARM) -> Color:
	return Color(clampf(c.r * warm.r, TINT_FLOOR, 1.0), clampf(c.g * warm.g, TINT_FLOOR, 1.0),
			clampf(c.b * warm.b, TINT_FLOOR, 1.0), 1.0)


static func play_grade_material(pal: Dictionary = {}) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(GRADE_SHADER) as Shader
	mat.set_shader_parameter("amount", float(pal.get("play_amount", PLAY_GRADE_AMOUNT)))
	mat.set_shader_parameter("value_scale", float(pal.get("play_value", PLAY_VALUE)))
	var ramp: Array = pal.get("play_ramp", PLAY_RAMP)
	for i in ramp.size():
		mat.set_shader_parameter("c%d" % i, ramp[i])
	return mat


static func is_grade_exempt(node: Node) -> bool:
	return node is Interactable or node is HookAnchor or node is EnemyBase or node is Player \
			or node is ToxinPool or node is TorchLight or node.is_in_group("no_grade")


static func _grade_tree(node: Node, mat: ShaderMaterial) -> int:
	if is_grade_exempt(node):
		return 0
	var n := 0
	if (node is Sprite2D or node is AnimatedSprite2D) and (node as CanvasItem).material == null:
		(node as CanvasItem).material = mat
		n += 1
	for child in node.get_children():
		n += _grade_tree(child, mat)
	return n


func _add_fog_layer(backdrop: Node, layer_name: String, motion: Vector2, y: float, alpha: float, tex: Texture2D) -> Parallax2D:
	var layer := Parallax2D.new()
	layer.name = layer_name
	layer.scroll_scale = motion
	layer.follow_viewport = false
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.position = Vector2(0, y)
	spr.scale = Vector2(SIL_SPAN / float(tex.get_width()), 1.0)
	spr.modulate = Color.WHITE
	layer.add_child(spr)
	cover_layer(layer)
	layer.modulate = Color(1, 1, 1, alpha)
	backdrop.add_child(layer)
	return layer


func _add_cloud_layer(backdrop: Node, layer_name: String, motion: Vector2, y: float, path: String) -> Parallax2D:
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var layer := Parallax2D.new()
	layer.name = layer_name
	layer.scroll_scale = motion
	layer.follow_viewport = false
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.texture = tex
	spr.centered = false
	spr.position = Vector2(0, y)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(spr)
	cover_layer(layer)
	layer.modulate = Color(_cloud_tint().r, _cloud_tint().g, _cloud_tint().b, WorldClock.cloud_alpha())
	backdrop.add_child(layer)
	return layer


## Ground fog lives on the foreground CanvasLayer with scroll 1:1, i.e. pinned to
## the world and tiled: a band the knight wades through, not a screen overlay.
func _add_ground_fog(front: Node, tex: Texture2D) -> Parallax2D:
	var layer := Parallax2D.new()
	layer.name = "GroundFog"
	layer.scroll_scale = Vector2(1.0, 1.0)
	layer.follow_viewport = false
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.texture = tex
	spr.centered = false
	spr.position = Vector2(0, GROUND_FOG_Y)
	spr.scale = GROUND_FOG_SCALE
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(spr)
	cover_layer(layer)
	layer.modulate = Color(1, 1, 1, WorldClock.ground_fog_alpha())
	front.add_child(layer)
	return layer


## The foreground CanvasLayer does not follow the viewport, so a plain full-view
## ColorRect on it is screen-fixed: a veil over the world, still under the HUD.
func _add_fog_veil(front: Node) -> ColorRect:
	var veil := ColorRect.new()
	veil.name = "FogVeil"
	veil.position = Vector2.ZERO
	veil.size = Vector2(PresentationMetrics.WORLD_SIZE)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c: Color = palette.get("veil", FOG_VEIL_COLOR)
	c.a = WorldClock.fog_veil_alpha()
	veil.color = c
	front.add_child(veil)
	return veil


func _add_silhouette_layer(backdrop: Node) -> Parallax2D:
	var layer := Parallax2D.new()
	layer.name = "NearSilhouette"
	layer.scroll_scale = Vector2(0.65, 0.12)
	layer.follow_viewport = false
	layer.repeat_size = Vector2(SIL_SPAN, 0)
	layer.repeat_times = MIN_REPEAT_TIMES
	var any := false
	for item in SIL_PATTERN:
		var path := item[0] as String
		var spr := Level01Env.plant(
				layer,
				path,
				Vector2(float(item[1]), float(item[2])),
				float(item[3]),
				palette.get("sil_tint", SIL_TINT))
		if spr != null:
			any = true
	if any:
		backdrop.add_child(layer)
		return layer
	layer.free()
	return null
