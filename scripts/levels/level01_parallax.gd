class_name Level01Parallax
extends Node
## Level01 backdrop extras: rust-moon sky swap, horizon ember haze, volumetric
## moonbeams, drifting fog, near-silhouette strip, mood tint, moon fill,
## WeatherFx / CineFx. Attaches into the authored `ParallaxBackdrop`
## (CanvasLayer + Parallax2D plates).
##
## The authored Gothicvania plates are magenta by design. A derived rust pair
## (assets/env/parallax_sky_rust.png / parallax_mountains_rust.png, written by
## tools/gen_theme_tiles.py) replaces the sky and far mountains for the
## graveyard theme so chapter 1 reads rust/ember instead of candy magenta; the
## originals stay on disk and are the fallback when a derived asset is missing.
## The swap is gated on the theme id, so a chapter that reuses this stack with a
## different identity can keep the authored plates.
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
## 云板也是墓园包的紫罗兰厚涂。锈月夜里紫云会被读成霓虹缎带，所以 gen_theme_tiles.py
## 另出两张灰烬/暖尘派生板（轮廓与 alpha 不动，只换色），原板留作回落。
const CLOUD_HIGH_RUST_PATH := "res://assets/env/parallax_clouds_rust.png"
const CLOUD_LOW_RUST_PATH := "res://assets/env/parallax_clouds_low_rust.png"
## 紫云原板仍要的提亮（只有派生素材缺失、回落到原板时才用）。
const CLOUD_TINT_MAGENTA := Color(1.22, 1.02, 1.28)
## 地面雾：盖在玩法层前面、贴着地面线（320）滚过的一条软带，浓雾天才真正压上来。
## 带高 64×1.1≈70px，从 276 罩到 346：齐骑士腰，不遮 HUD。
const GROUND_FOG_Y := 276.0
const GROUND_FOG_SCALE := Vector2(2.0, 1.1)
## 雾幕：屏幕空间的淡紫罩层，alpha 跟 WorldClock.fog_veil_alpha()，让浓雾一眼可辨。
const FOG_VEIL_COLOR := Color(0.80, 0.77, 0.92)
const COVER_PAD := 128.0
const MIN_REPEAT_TIMES := 4
## 近景剪影带（scroll 0.65）：一段 512px 宽的图样平铺，只种暗紫软物，
## 填在远景 Hills(0.48) 与游玩层(1.0) 之间。石碑/雕像不进这层——
## 看起来能踩却够不着，叠在月亮/远山上会像「飞着的交互物」。
## feet 落在 Hills 墓园板与玩法地面重叠的山脚带（约 318–322），不是远空。
## 图样要不止一种重复的灌木形：小/大灌木 + 三种树，错开 x 与缩放，平铺时才不发呆。
const SIL_PATTERN := [
	[Level01Env.DECOR_TREE_2, 64.0, 320.0, 0.44],
	[Level01Env.DECOR_TREE_1, 8.0, 320.0, 0.30],
	[Level01Env.DECOR_BUSH_S, 150.0, 322.0, 0.70],
	[Level01Env.DECOR_BUSH_S, 300.0, 322.0, 0.58],
	[Level01Env.DECOR_BUSH_L, 250.0, 322.0, 0.50],
	[Level01Env.DECOR_TREE_3, 430.0, 320.0, 0.38],
	[Level01Env.DECOR_BUSH_L, 360.0, 322.0, 0.42],
	[Level01Env.DECOR_TREE_2, 470.0, 320.0, 0.30],
]
const SIL_TINT := Color(0.17, 0.14, 0.24, 0.95)
const SIL_FEET_MIN := 300.0
const SIL_FEET_MAX := 340.0
const SIL_SPAN := 512.0
const TINT_FOLLOW := 2.8

## ---------------------------------------------------- graveyard rust identity --
## 原板（品红月夜）与派生板（锈月夜）。gradient-map 由 tools/gen_theme_tiles.py 做，
## 原板保留入库，派生板只是「同一张画的另一套色阶」，所以许可链见 CREDITS。
const SKY_PLATE := "res://assets/env/parallax_sky.png"
const SKY_RUST_PLATE := "res://assets/env/parallax_sky_rust.png"
const MOUNTAINS_PLATE := "res://assets/env/parallax_mountains.png"
const MOUNTAINS_RUST_PLATE := "res://assets/env/parallax_mountains_rust.png"
## 只有墓园主题换锈月板：章节身份色（docs/art-spec.md）决定，换主题就不静默换画。
const GRAVEYARD_THEME := "graveyard"

## 地平线暖雾带：天空板与远山之间的一条加法暖光，把地平线从品红拉回锈橙。
## 图样 8×112 逐行渐隐（顶部 0、山脚最亮），横向拉满 640，远山板把下半截挡住，
## 只露出山峰后面的一圈暖雾——「山后起雾」而不是盖在角色身上的一张纸。
const HORIZON_NODE := "HorizonHaze"
const HORIZON_Y := 28.0
const HORIZON_TEX_SIZE := Vector2i(8, 112)
const HORIZON_SPAN := 640.0
const HORIZON_SCROLL := Vector2(0.12, 0.05)
## 低 alpha：远山后面一圈暖光。再亮就会把「锈月夜」读成沙尘暴落日。
const HORIZON_ALPHA := 0.13

## 月光束：2–3 条加法光柱从锈月方向斜落，挂在 Hills 板之上、雾层之下，
## 永远在 backdrop CanvasLayer（layer<0）里，盖不到玩法层。
## scroll 与天空板一致（0.08/0.04），镜头移动时与月亮锁在一起；风只推 scroll_offset。
const MOONBEAM_NODE := "Moonbeams"
const MOONBEAM_TEX_SIZE := Vector2i(32, 192)
const MOONBEAM_SPAN := 640.0
const MOONBEAM_SCROLL := Vector2(0.08, 0.04)
const MOONBEAM_ALPHA := 0.24
const MOONBEAM_SPOTS := [
	Vector3(240.0, 62.0, -8.0),
	Vector3(368.0, 48.0, 3.0),
	Vector3(512.0, 78.0, -4.0),
]

## 前景草：作者板只有一条 624px 图样，镜头一推就看出同一丛草在滑。
## 再挂一条裁片（312px 相位不同）+ 更快的 scroll，前景变成两层，脚下草不再齐步走。
const FOREGROUND_PLATE := "res://assets/env/normalized/parallax_foreground_px.png"
const FRINGE_NODE := "ForegroundFringe"
const FRINGE_REGION := Rect2(96, 0, 312, 64)
const FRINGE_Y := 347.0
const FRINGE_SCROLL := Vector2(1.38, 0.2)
const FRINGE_ALPHA := 0.42


## 云板派生后已是灰烬/暖尘色，只做一点暖白校正（不能再压蓝，否则雨天的云会发红）。
## 乘数由 Palette.EMBER_ASH 归一化到红通道 = 1 后向白 lerp，不引入调色板外裸色。
## 回落到原紫板时用旧提亮值，原板在品红天上仍然读得出。
static func cloud_tint(derived: bool = true) -> Color:
	if not derived:
		return CLOUD_TINT_MAGENTA
	var c := Palette.EMBER_ASH
	var k := 1.0 / maxf(c.r, 0.001)
	return Color(c.r * k, c.g * k, c.b * k).lerp(Color.WHITE, 0.60)


var _far_layer: Parallax2D
var _mid_layer: Parallax2D
var _cloud_high: Parallax2D
var _cloud_low: Parallax2D
var _horizon: Parallax2D
var _moonbeams: Parallax2D
var _fog_far: Parallax2D
var _fog_near: Parallax2D
var _sil_layer: Parallax2D
var _foreground: Parallax2D
var _fringe: Parallax2D
var _ground_fog: Parallax2D
var _fog_veil: ColorRect
var _mood_tint: CanvasModulate
var _moon_fill: DirectionalLight2D
var _theme_id := GRAVEYARD_THEME
## True when the ash/dust cloud derivation is in use (drives cloud_tint + fallback).
var _cloud_rust := false

## Procedural textures / material are per-process singletons (tests build several
## hosts): never regenerate per node, never allocate per frame.
static var _horizon_tex: Texture2D
static var _moonbeam_tex: Texture2D
static var _add_mat: CanvasItemMaterial


func build(host: Node2D, theme_id: String = GRAVEYARD_THEME) -> void:
	_theme_id = theme_id
	var backdrop := host.get_node_or_null("ParallaxBackdrop") as Node
	if backdrop == null:
		return
	if backdrop is CanvasLayer:
		(backdrop as CanvasLayer).follow_viewport_enabled = false
	_far_layer = backdrop.get_node_or_null("Far") as Parallax2D
	_mid_layer = backdrop.get_node_or_null("Mid") as Parallax2D
	for child in backdrop.get_children():
		if child is Parallax2D:
			cover_layer(child as Parallax2D)
	# 章节身份色：只有墓园主题换锈月板；派生板缺失时回落原板。
	if theme_id == GRAVEYARD_THEME:
		use_rust_plates(backdrop)
	if _far_layer != null:
		# Clouds sit directly behind the mountains: after Far, before Mid.
		var cloud_high_path := CLOUD_HIGH_PATH
		var cloud_low_path := CLOUD_LOW_PATH
		if theme_id == GRAVEYARD_THEME:
			cloud_high_path = plate_path(CLOUD_HIGH_RUST_PATH, CLOUD_HIGH_PATH)
			cloud_low_path = plate_path(CLOUD_LOW_RUST_PATH, CLOUD_LOW_PATH)
			_cloud_rust = cloud_high_path != CLOUD_HIGH_PATH or cloud_low_path != CLOUD_LOW_PATH
		_cloud_high = _add_cloud_layer(backdrop, "SkyCloudsHigh", Vector2(0.10, 0.03), 6.0, cloud_high_path)
		_cloud_low = _add_cloud_layer(backdrop, "SkyCloudsLow", Vector2(0.14, 0.05), 92.0, cloud_low_path)
		var slot := _far_layer.get_index() + 1
		if _cloud_high != null:
			backdrop.move_child(_cloud_high, slot)
			slot += 1
		if _cloud_low != null:
			backdrop.move_child(_cloud_low, slot)
	# 地平线暖雾在云之后、远山之前：山把下半截挡住，只漏出一圈暖光。
	_horizon = _add_horizon_haze(backdrop)
	if _horizon != null:
		var haze_slot := 0
		if _cloud_low != null:
			haze_slot = _cloud_low.get_index() + 1
		elif _cloud_high != null:
			haze_slot = _cloud_high.get_index() + 1
		elif _far_layer != null:
			haze_slot = _far_layer.get_index() + 1
		if _mid_layer != null and haze_slot > _mid_layer.get_index():
			haze_slot = _mid_layer.get_index()
		backdrop.move_child(_horizon, haze_slot)
	# 月光束在山与墓园板之前（可见），在雾与剪影之后（被空气吃掉一点）。
	_moonbeams = _add_moonbeams(backdrop)
	var fog_tex: Texture2D = null
	if ResourceLoader.exists(FOG_PATH):
		fog_tex = load(FOG_PATH) as Texture2D
	if fog_tex != null:
		_fog_far = _add_fog_layer(backdrop, "FogFar", Vector2(0.5, 0.1), 234.0, 0.13, fog_tex)
	_sil_layer = _add_silhouette_layer(backdrop)
	if fog_tex != null:
		_fog_near = _add_fog_layer(backdrop, "FogNear", Vector2(0.75, 0.14), 276.0, 0.2, fog_tex)
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
		_fringe = _add_foreground_fringe(front)
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
	_mood_tint.color = WorldClock.mood_tint()
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


## plates: sky ×1.9 with its moon, purple mountains ×1.7, graveyard ×1.85.
## 派生 PNG 被删掉时这里什么也不做，作者板继续用（启动不依赖派生素材）。
func use_rust_plates(backdrop: Node) -> bool:
	if backdrop == null:
		return false
	var changed := swap_plate_texture(backdrop.get_node_or_null("Far") as Parallax2D, sky_plate_path())
	if swap_plate_texture(backdrop.get_node_or_null("Mid") as Parallax2D, mountains_plate_path()):
		changed = true
	return changed


static func plate_path(derived: String, original: String) -> String:
	if derived != "" and derived != original and ResourceLoader.exists(derived):
		return derived
	return original


static func sky_plate_path(theme_id: String = GRAVEYARD_THEME) -> String:
	if theme_id != GRAVEYARD_THEME:
		return SKY_PLATE
	return plate_path(SKY_RUST_PLATE, SKY_PLATE)


static func mountains_plate_path(theme_id: String = GRAVEYARD_THEME) -> String:
	if theme_id != GRAVEYARD_THEME:
		return MOUNTAINS_PLATE
	return plate_path(MOUNTAINS_RUST_PLATE, MOUNTAINS_PLATE)


## 换一张板的贴图，保留作者写的 scroll / scale / pos。缺文件时返回 false 且不碰
## 现有贴图——派生素材永远不是启动硬依赖。
static func swap_plate_texture(layer: Parallax2D, path: String) -> bool:
	if layer == null or path == "" or not ResourceLoader.exists(path):
		return false
	var spr := layer.get_node_or_null("Sprite") as Sprite2D
	if spr == null:
		return false
	if spr.texture != null and String(spr.texture.resource_path) == path:
		return false
	var tex := load(path) as Texture2D
	if tex == null:
		return false
	spr.texture = tex
	return true


func _process(delta: float) -> void:
	var drift := WorldClock.wind_vector().x
	if _far_layer != null:
		_far_layer.scroll_offset.x += drift * 8.0 * delta
	if _cloud_high != null:
		_cloud_high.scroll_offset.x += drift * 11.0 * delta
	if _cloud_low != null:
		_cloud_low.scroll_offset.x += drift * 17.0 * delta
	if _horizon != null:
		_horizon.scroll_offset.x += drift * 6.0 * delta
	if _moonbeams != null:
		_moonbeams.scroll_offset.x += drift * 2.5 * delta
	if _fog_far != null:
		_fog_far.scroll_offset.x += drift * 18.0 * delta
	if _fog_near != null:
		_fog_near.scroll_offset.x += drift * 32.0 * delta
	if _foreground != null:
		_foreground.scroll_offset.x += drift * 56.0 * delta
	if _fringe != null:
		_fringe.scroll_offset.x += drift * 72.0 * delta
	if _ground_fog != null:
		_ground_fog.scroll_offset.x += drift * 24.0 * delta
	_follow_atmosphere(delta)


## 0 = 白昼，1 = 深夜。用 time_of_day 的连续函数而不是 WorldClock.phase：
## phase 在边界上是阶跃的，光柱/暖雾直接读它会在换阶段那一帧跳一下。
## 黄昏/黎明各 0.12 个周期做 smoothstep，绕回处（x=0 与 x=1）数值连续。
static func night_weight(time_of_day: float) -> float:
	var x := fposmod(time_of_day, 1.0)
	if x < 0.12:
		return 1.0 - smoothstep(0.0, 0.12, x)
	if x < 0.50:
		return 0.0
	if x < 0.62:
		return smoothstep(0.50, 0.62, x)
	return 1.0


## 地平线暖雾的颜色取 Palette 的 rust/ember 家族，不写裸 RGB。
static func horizon_tint() -> Color:
	return Palette.RUST_MID.lerp(Palette.EMBER, 0.30)


## 月光是锈月，光柱用锈白：白天几乎看不见，雨雾里偏冷一点。
static func moonbeam_color(rain_opacity: float = 0.0) -> Color:
	var c := Palette.EMBER_ASH.lerp(Palette.RUST_LIGHT, 0.35)
	return c.lerp(Palette.IRON, clampf(rain_opacity, 0.0, 1.0) * 0.45)


func _snap_atmosphere() -> void:
	_follow_atmosphere(999.0)


func _follow_atmosphere(delta: float) -> void:
	var k := 1.0 if delta > 10.0 else (1.0 - exp(-TINT_FOLLOW * delta))
	if _mood_tint != null:
		_mood_tint.color = _mood_tint.color.lerp(WorldClock.mood_tint(), k)
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
	if _mid_layer != null:
		# 远山跟着天空板一起过昼夜：锈色山体不会在夜里比天还亮。
		_mid_layer.modulate = _mid_layer.modulate.lerp(WorldClock.sky_modulate(), k)
	var cloud := WorldClock.cloud_alpha()
	var cloud_rgb := cloud_tint(_cloud_rust)
	if _cloud_high != null:
		var target := Color(cloud_rgb.r, cloud_rgb.g, cloud_rgb.b, cloud)
		_cloud_high.modulate = _cloud_high.modulate.lerp(target, k)
	if _cloud_low != null:
		var target := Color(cloud_rgb.r, cloud_rgb.g, cloud_rgb.b, cloud * 0.8)
		_cloud_low.modulate = _cloud_low.modulate.lerp(target, k)
	# 月亮光柱 + 地平线暖雾：都只读时钟/天气的连续量（云量、雾幕、雨量、风力），
	# 目标值本身平滑，再叠一层 lerp，昼夜/天气交叉里不会闪。
	var night := night_weight(WorldClock.time_of_day)
	var clear_sky := 1.0 - clampf(WorldClock.cloud_alpha() / 0.9, 0.0, 1.0)
	var veil := clampf(WorldClock.fog_veil_alpha() / 0.35, 0.0, 1.0)
	var rain := WorldClock.rain_opacity()
	var gust := clampf(WorldClock.gust, 0.70, 1.25)
	if _moonbeams != null:
		var beams_target := MOONBEAM_ALPHA * (0.28 + 0.72 * night) \
				* (0.45 + 0.55 * clear_sky) * (1.0 - 0.45 * veil) \
				* (1.0 - 0.25 * rain) * (0.90 + 0.10 * gust)
		var bc := moonbeam_color(rain)
		_moonbeams.modulate = _moonbeams.modulate.lerp(Color(bc.r, bc.g, bc.b, beams_target), k)
	if _horizon != null:
		var haze_target := HORIZON_ALPHA * (0.55 + 0.45 * (1.0 - night)) * (1.0 + 0.45 * veil)
		var hc := horizon_tint()
		_horizon.modulate = _horizon.modulate.lerp(Color(hc.r, hc.g, hc.b, haze_target), k)
	if _ground_fog != null:
		_ground_fog.modulate = _ground_fog.modulate.lerp(Color(1, 1, 1, WorldClock.ground_fog_alpha()), k)
	if _fog_veil != null:
		var veil_color := FOG_VEIL_COLOR
		veil_color.a = WorldClock.fog_veil_alpha()
		_fog_veil.color = _fog_veil.color.lerp(veil_color, k)
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


## 地平线暖雾带：一张 8×112 的锈→余烬竖向渐变，横向拉满 640、平方渐隐，
## 加法混色挂在远山后面。远山把下半截挡住，只在峰线后面漏出一圈暖光。
func _add_horizon_haze(backdrop: Node) -> Parallax2D:
	var tex := _horizon_texture()
	if tex == null:
		return null
	var layer := Parallax2D.new()
	layer.name = HORIZON_NODE
	layer.scroll_scale = HORIZON_SCROLL
	layer.follow_viewport = false
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = Vector2(0, HORIZON_Y)
	spr.scale = Vector2(HORIZON_SPAN / float(tex.get_width()), 1.0)
	spr.material = _additive_material()
	layer.add_child(spr)
	cover_layer(layer)
	layer.modulate = Color(1, 1, 1, HORIZON_ALPHA)
	layer.set_meta("occlusion_alpha", HORIZON_ALPHA)
	backdrop.add_child(layer)
	return layer


## 月光束：2–3 条从锈月方向斜落的加法光柱。坐标在 backdrop 的 640 视口空间，
## 层按 640px 平铺，所以镜头走到哪都有一组同样的光柱；每条柱子从顶端（月亮侧）
## 往下淡出，颜色由 _follow_atmosphere 按昼夜/天气连续调制。
func _add_moonbeams(backdrop: Node) -> Parallax2D:
	var tex := _moonbeam_texture()
	if tex == null:
		return null
	var layer := Parallax2D.new()
	layer.name = MOONBEAM_NODE
	layer.scroll_scale = MOONBEAM_SCROLL
	layer.follow_viewport = false
	var made := 0
	for spot in MOONBEAM_SPOTS:
		var v: Vector3 = spot
		var spr := Sprite2D.new()
		spr.name = "Shaft%d" % made
		spr.texture = tex
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.material = _additive_material()
		spr.position = Vector2(v.x, v.y)
		spr.rotation = deg_to_rad(v.z)
		spr.scale = Vector2(1.6, 1.4)
		spr.modulate = Color(1, 1, 1, 0.82 - 0.20 * float(made))
		layer.add_child(spr)
		made += 1
	if made == 0:
		layer.free()
		return null
	layer.repeat_size = Vector2(MOONBEAM_SPAN, 0.0)
	layer.repeat_times = copies_for_view(MOONBEAM_SPAN)
	layer.modulate = Color(1, 1, 1, MOONBEAM_ALPHA)
	layer.set_meta("occlusion_alpha", MOONBEAM_ALPHA)
	backdrop.add_child(layer)
	return layer


## 前景第二层草：从作者前景板裁一段（相位与作者 624px 板不同），用更快的
## scroll 再铺一条暗锈色草缘。只动画面、不进玩法层、不改碰撞。
func _add_foreground_fringe(front: Node) -> Parallax2D:
	if not ResourceLoader.exists(FOREGROUND_PLATE):
		return null
	var tex := load(FOREGROUND_PLATE) as Texture2D
	if tex == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = FRINGE_REGION
	var layer := Parallax2D.new()
	layer.name = FRINGE_NODE
	layer.scroll_scale = FRINGE_SCROLL
	layer.follow_viewport = false
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.texture = atlas
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = Vector2(0, FRINGE_Y)
	var tint := Palette.RUST_SHADOW
	tint.a = FRINGE_ALPHA
	spr.modulate = tint
	layer.add_child(spr)
	cover_layer(layer)
	front.add_child(layer)
	return layer


static func _additive_material() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat


## 锈→余烬的竖向渐变：RGB 从 Rust Mid 走到 Ember，alpha 从 0 平方升到山脚最亮。
## 只做一张 ImageTexture，进程内共享。
static func _horizon_texture() -> Texture2D:
	if _horizon_tex != null:
		return _horizon_tex
	var w := HORIZON_TEX_SIZE.x
	var h := HORIZON_TEX_SIZE.y
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var v := float(y) / float(h - 1)
		var c := Palette.RUST_MID.lerp(Palette.EMBER, 0.30 + 0.45 * v)
		var a := pow(v, 1.6) * 0.9
		for x in w:
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	_horizon_tex = ImageTexture.create_from_image(img)
	return _horizon_tex


## 光柱贴图：顶部宽亮、向下收细，横向软边（和 ThemeBackdrop 的箭窗光柱同做法），
## 白色 alpha，只靠 modulate 上色。
static func _moonbeam_texture() -> Texture2D:
	if _moonbeam_tex != null:
		return _moonbeam_tex
	var w := MOONBEAM_TEX_SIZE.x
	var h := MOONBEAM_TEX_SIZE.y
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := float(y) / float(h - 1)
		var along := pow(1.0 - t, 1.35) * 0.6
		for x in w:
			var cx := absf(float(x) - float(w - 1) * 0.5) / (float(w) * 0.5)
			var a := clampf(along * pow(1.0 - cx, 1.7), 0.0, 0.55)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_moonbeam_tex = ImageTexture.create_from_image(img)
	return _moonbeam_tex


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
	var c := cloud_tint(_cloud_rust)
	layer.modulate = Color(c.r, c.g, c.b, WorldClock.cloud_alpha())
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
	var c := FOG_VEIL_COLOR
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
				SIL_TINT)
		if spr != null:
			any = true
	if any:
		backdrop.add_child(layer)
		return layer
	layer.free()
	return null





