extends Control
## 分镜画面：640×360 的实时拼图（由 StoryboardPlayer 放大 2 倍显示）。
##
## 一个镜头 = 布景（ThemeBackdrop 的主题图层 + 标题大厅）+ 演员（骑士用真实帧动画，
## 其余是程序化像素剪影）+ 运镜（still / push / pan_right / pan_left / rise）+ 粒子。
## 镜头带 art 且 assets/story/<art>.png（或 .jpg）存在时，改用关键插图当底（演员不再画，
## 粒子保留）；文件不存在 / 还没导入时静默退回实时拼，不报错、不留空画面。
##
## 这里不读输入、不定时：时间全由 tick(delta) 推进，所以暂停 / 挂起时播放器不调 tick，
## 整幅画面（含骑士的待机动画）一起冻住。没有任何场景引用，可以单独实例化
## （tests/storyboard_test.gd）。

const WORLD := Vector2(640.0, 360.0)
const GROUND_Y := 286.0
const DIR_TITLE := "res://assets/title/"
const ART_DIR := "res://assets/story/"
## 关键插图认的扩展名，按顺序找第一个存在的（生成工具给的是 .jpg，手绘 / 导出可能是 .png）。
const ART_EXTS: Array[String] = ["png", "jpg"]
## 数据层（storyboards.gd）能用的词汇：新增演员 / 布景 / 运镜 / 粒子要和这里一起改，
## tests/storyboard_test.gd 把每个镜头逐个对一遍。ThemeBackdrop 的主题名另外也都能当布景。
const ACTOR_KINDS: Array[String] = [
	"knight", "seed", "flame", "souls", "swords", "gate", "figure", "yir", "ash_guard", "ring",
]
const CAMS: Array[String] = ["still", "push", "pan_right", "pan_left", "rise"]
const FXS: Array[String] = ["embers", "ash", "dust", "none"]
const EXTRA_SETS: Array[String] = ["dark", "graveyard", "title_hall"]
const CAM_PUSH := 0.08
## 插图按屏宽 90% 铺（16:9 对 16:9）。底边贴着字幕渐变的顶（舞台 y=320，屏上 640），
## 慢推 4% 之后只有最底下一窄条进到渐变的透明上沿，剑和人脚仍在字幕之上。
const ART_WIDTH_RATIO := 0.90
const ART_TOP := 2.0
const ART_CAPTION_TOP := 320.0
const ART_MAX_H := 336.0
const ART_PUSH := 0.04
const CAM_PAN := 22.0
const CAM_RISE := 16.0

const GRAVEYARD := {
	"void": Color(0.03, 0.05, 0.07),
	"mood": Color(0.78, 0.86, 0.9),
	"layers": [
		{"path": "res://assets/env/parallax_sky.png", "scroll": Vector2(0.08, 0.04),
				"pos": Vector2(0, -24), "scale": 1.9, "tint": Color(0.8, 0.9, 1.0)},
		{"path": "res://assets/env/parallax_mountains.png", "scroll": Vector2(0.22, 0.06),
				"pos": Vector2(0, 48), "scale": 1.7, "tint": Color(0.75, 0.85, 0.9)},
		{"path": "res://assets/env/parallax_graveyard.png", "scroll": Vector2(0.48, 0.1),
				"pos": Vector2(0, 168), "scale": 1.85, "tint": Color(0.7, 0.8, 0.82)},
	],
}

const TITLE_HALL := {
	"void": Color(0.02, 0.015, 0.03),
	"mood": Color(1.0, 0.92, 0.88),
	"layers": [
		{"path": DIR_TITLE + "hall_far.png", "scroll": Vector2(0.1, 0.04),
				"pos": Vector2(-32, -4), "scale": 1.0, "tint": Color.WHITE, "single": true},
		{"path": DIR_TITLE + "hall_mid.png", "scroll": Vector2(0.2, 0.06),
				"pos": Vector2(-32, -4), "scale": 1.0, "tint": Color.WHITE, "single": true},
		{"path": DIR_TITLE + "beam.png", "scroll": Vector2(0.15, 0.05),
				"pos": Vector2(146, 16), "scale": 1.0, "tint": Color(0.42, 0.6, 0.7, 0.55),
				"single": true, "additive": true},
		{"path": DIR_TITLE + "glow.png", "scroll": Vector2(0.1, 0.05),
				"pos": Vector2(10, 290), "scale": 1.0, "tint": Color(1.0, 0.4, 0.14, 0.5),
				"single": true, "additive": true},
		{"path": DIR_TITLE + "roof.png", "scroll": Vector2(0.3, 0.1),
				"pos": Vector2(-32, -10), "scale": 1.0, "tint": Color.WHITE, "single": true},
	],
}

const DARK := {"void": Color(0.0, 0.0, 0.0), "mood": Color.WHITE, "layers": []}

var _world: Node2D
var _back: Node2D
var _actors: Node2D
var _motes_back: Node2D
var _motes_front: Node2D
var _black: ColorRect
var _vignette: Sprite2D
var _layers: Array[Dictionary] = []
var _animated: Array[Node2D] = []
## 骑士的待机帧动画：自己的 _process 在暂停时（播放器是 ALWAYS）照样会走，所以关掉它，
## 由 tick() 手动推进——播放器冻住时画面才是真的静止。
var _knight_anims: Array[FrameAnimSprite] = []
var _motes: Array[Node2D] = []
var _clock := 0.0
var _shot_t := 0.0
var _dur := 5.0
var _cam := "still"
## 插图镜头用更小的推近：图已经缩进字幕安全区，再推 8% 会把人和剑顶进字幕条，线性过滤也会更糊。
var _using_art := false
var _info: Dictionary = {}
var _extra_actors := 0


func _init() -> void:
	name = "StoryboardStage"
	custom_minimum_size = WORLD
	size = WORLD
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	_build_base()


func _build_base() -> void:
	if _world != null:
		return
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	_back = Node2D.new()
	_back.name = "Back"
	_world.add_child(_back)
	_motes_back = Node2D.new()
	_motes_back.name = "MotesBack"
	_motes_back.z_index = 5
	_world.add_child(_motes_back)
	_actors = Node2D.new()
	_actors.name = "Actors"
	_actors.z_index = 10
	_world.add_child(_actors)
	_motes_front = Node2D.new()
	_motes_front.name = "MotesFront"
	_motes_front.z_index = 20
	_world.add_child(_motes_front)
	_vignette = Sprite2D.new()
	_vignette.name = "Vignette"
	_vignette.centered = false
	_vignette.z_index = 30
	_vignette.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var vt := UiKit.tex(DIR_TITLE + "vignette.png")
	if vt != null:
		_vignette.texture = vt
		_vignette.scale = WORLD / vt.get_size()
	add_child(_vignette)
	_black = ColorRect.new()
	_black.name = "Black"
	_black.color = Color(0.0, 0.0, 0.0, 1.0)
	_black.size = WORLD
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.z_index = 100
	add_child(_black)


# ------------------------------------------------------------------ public ------

## 换一个镜头。expected_seconds 只用来算运镜进度（镜头真实时长由播放器决定）。
func show_shot(shot: Dictionary, expected_seconds: float) -> void:
	_build_base()
	_clear_shot()
	_shot_t = 0.0
	_dur = maxf(expected_seconds, 0.5)
	_cam = String(shot.get("cam", "still"))
	var set_id := String(shot.get("set", "dark"))
	var art_path := resolve_art(shot)
	# 文件在却加载失败（损坏 / 导入到一半）也退回实时拼，不留一整块黑。
	var art_used := art_path != "" and _build_art(art_path)
	_using_art = art_used
	if not art_used:
		art_path = ""
		_build_backdrop(set_id)
		_build_ground()
		for raw in shot.get("actors", []):
			_add_actor(raw as Array)
	_build_motes(String(shot.get("fx", "none")))
	if _vignette != null and not _using_art:
		_vignette.modulate.a = 1.0
	_info = {
		"set": set_id, "cam": _cam, "art": String(shot.get("art", "")), "art_used": art_used,
		"art_path": art_path,
		"layers": _layers.size(), "actors": _animated.size() + _count_extra_actors(),
		"motes": _motes.size(),
	}
	_apply_camera(0.0)


## 镜头的构成（测试读）：set / cam / art / art_used / art_path / layers / actors / motes。
func info() -> Dictionary:
	return _info.duplicate()


func tick(delta: float) -> void:
	_clock += delta
	_shot_t += delta
	var p := clampf(_shot_t / _dur, 0.0, 1.0)
	_apply_camera(p)
	for actor in _animated:
		if is_instance_valid(actor):
			actor.call("advance", _shot_t)
	for anim in _knight_anims:
		if is_instance_valid(anim):
			anim._process(delta)
	for m in _motes:
		if is_instance_valid(m):
			m.call("step", delta)


## 0 = 全显，1 = 全黑。镜头之间的切换和整段分镜的淡入淡出都用它。
func set_black(amount: float) -> void:
	if _black != null:
		_black.color.a = clampf(amount, 0.0, 1.0)


func black_amount() -> float:
	return _black.color.a if _black != null else 1.0


## 这个布景名舞台认不认识（不认识的会退成纯黑，不报错）。
static func supports_set(set_id: String) -> bool:
	return EXTRA_SETS.has(set_id) or ThemeBackdrop.THEMES.has(set_id)


## shot.art 对应的关键插图路径（.png 优先，其次 .jpg）；都不存在返回空串（回退实时拼）。
static func resolve_art(shot: Dictionary) -> String:
	return art_file(String(shot.get("art", "")))


## 插图 id → 资源路径；id 为空或文件不存在 / 未导入返回空串。
static func art_file(art_id: String) -> String:
	if art_id == "":
		return ""
	for ext in ART_EXTS:
		var path := "%s%s.%s" % [ART_DIR, art_id, ext]
		if ResourceLoader.exists(path):
			return path
	return ""


# ---------------------------------------------------------------- building ------

func _clear_shot() -> void:
	for container in [_back, _actors, _motes_back, _motes_front]:
		if container == null:
			continue
		for child in (container as Node).get_children():
			child.queue_free()
	_layers.clear()
	_animated.clear()
	_knight_anims.clear()
	_motes.clear()
	_extra_actors = 0
	# 上一镜的氛围色染在 Back 上。不复位的话，下一张插图会吃到上一章的色调。
	if _back != null:
		_back.modulate = Color.WHITE


func _count_extra_actors() -> int:
	return _extra_actors


func _theme_for(set_id: String) -> Dictionary:
	match set_id:
		"dark":
			return DARK
		"graveyard":
			return GRAVEYARD
		"title_hall":
			return TITLE_HALL
	var themes: Dictionary = ThemeBackdrop.THEMES
	if themes.has(set_id):
		# Dictionary 下标是 Variant，直接 return 会和返回类型 Dictionary 冲突。
		return themes[set_id] as Dictionary
	return DARK


func _build_backdrop(set_id: String) -> void:
	# 不叫 theme：Control 自带 theme 属性，局部变量会遮住它。
	var backdrop := _theme_for(set_id)
	var void_rect := ColorRect.new()
	void_rect.name = "Void"
	void_rect.color = backdrop.get("void", Color.BLACK) as Color
	void_rect.position = Vector2(-64.0, -64.0)
	void_rect.size = WORLD + Vector2(128.0, 128.0)
	void_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.add_child(void_rect)
	var mood := backdrop.get("mood", Color.WHITE) as Color
	# 分镜是「回忆」，比关卡亮一点：把关卡的氛围色往白里提 28%，保留各章的色相。
	_back.modulate = mood.lerp(Color.WHITE, 0.28)
	var i := 0
	for layer_def in backdrop.get("layers", []):
		_add_layer(layer_def as Dictionary, i)
		i += 1


func _add_layer(def: Dictionary, index: int) -> void:
	var tex := UiKit.tex(String(def.get("path", "")))
	if tex == null:
		return
	var k := float(def.get("scale", 1.0))
	var region := def.get("region", Rect2()) as Rect2
	var tex_w := region.size.x if region.has_area() else float(tex.get_width())
	var holder := Node2D.new()
	holder.name = "Layer%d" % index
	var base := def.get("pos", Vector2.ZERO) as Vector2
	var tint := def.get("tint", Color.WHITE) as Color
	var additive := bool(def.get("additive", false))
	if bool(def.get("tile", false)):
		var wall := _sprite(tex, tint, additive)
		wall.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		wall.region_enabled = true
		wall.region_rect = Rect2(0.0, 0.0, 960.0 / k, 720.0 / k)
		wall.scale = Vector2(k, k)
		wall.position = Vector2(-160.0, -180.0)
		holder.add_child(wall)
		base = Vector2.ZERO
	elif bool(def.get("single", false)):
		var one := _sprite(tex, tint, additive)
		one.scale = Vector2(k, k)
		if region.has_area():
			one.region_enabled = true
			one.region_rect = region
		holder.add_child(one)
	else:
		var step := float(def.get("repeat", 0.0))
		if step <= 0.0:
			step = tex_w * k
		var count := int(ceil((WORLD.x + 160.0) / maxf(step, 8.0))) + 2
		for n in count:
			var spr := _sprite(tex, tint, additive)
			spr.scale = Vector2(k, k)
			spr.position = Vector2(float(n - 1) * step, 0.0)
			if region.has_area():
				spr.region_enabled = true
				spr.region_rect = region
			holder.add_child(spr)
	holder.position = base
	_back.add_child(holder)
	_layers.append({"node": holder, "base": base, "scroll": def.get("scroll", Vector2(0.3, 0.1))})


func _sprite(tex: Texture2D, tint: Color, additive: bool) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.modulate = tint
	if additive:
		spr.material = Fx.additive_mat()
	return spr


## 铺插图；加载失败返回 false（调用方退回实时拼）。
## 尽量铺满屏宽，顶上可以裁掉一条天，底边贴字幕渐变，不把剑和人脚压进字里。
func _build_art(path: String) -> bool:
	var tex := UiKit.tex(path)
	if tex == null:
		return false
	var void_rect := ColorRect.new()
	void_rect.name = "ArtVoid"
	void_rect.color = Color(0.012, 0.008, 0.016)
	void_rect.position = Vector2(-40.0, -40.0)
	void_rect.size = WORLD + Vector2(80.0, 80.0)
	void_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.add_child(void_rect)
	var spr := _sprite(tex, Color.WHITE, false)
	# 1280 的图缩进 640 里仍是缩小。线性过滤只防 4% 推镜时的最近邻闪烁，不会把像素放大糊掉。
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var fit := minf(ART_WIDTH_RATIO * WORLD.x / maxf(tw, 1.0), ART_MAX_H / maxf(th, 1.0))
	spr.scale = Vector2(fit, fit)
	var drawn := tex.get_size() * fit
	var top := ART_CAPTION_TOP - drawn.y
	if top > ART_TOP:
		top = ART_TOP + (ART_CAPTION_TOP - ART_TOP - drawn.y) * 0.25
	spr.position = Vector2(roundf((WORLD.x - drawn.x) * 0.5), roundf(top))
	var holder := Node2D.new()
	holder.name = "Art"
	holder.add_child(spr)
	_back.add_child(holder)
	_layers.append({"node": holder, "base": Vector2.ZERO, "scroll": Vector2(0.12, 0.0)})
	if _vignette != null:
		_vignette.modulate.a = 0.22
	return true


## 地面渐隐：演员站的地方压一条暗带，字幕条后面不会被亮景吃掉对比度。
func _build_ground() -> void:
	var band := Polygon2D.new()
	band.name = "Ground"
	band.polygon = PackedVector2Array([
		Vector2(-40.0, GROUND_Y - 40.0), Vector2(WORLD.x + 40.0, GROUND_Y - 40.0),
		Vector2(WORLD.x + 40.0, WORLD.y + 40.0), Vector2(-40.0, WORLD.y + 40.0)])
	band.vertex_colors = PackedColorArray([
		Color(0.02, 0.015, 0.03, 0.0), Color(0.02, 0.015, 0.03, 0.0),
		Color(0.02, 0.015, 0.03, 0.9), Color(0.02, 0.015, 0.03, 0.9)])
	_back.add_child(band)


func _add_actor(spec: Array) -> void:
	if spec.size() < 3:
		return
	var kind := String(spec[0])
	var x := roundf(WORLD.x * clampf(float(spec[1]), 0.0, 1.0))
	var sc := float(spec[2])
	if kind == "knight":
		_add_knight(x, sc)
		return
	var actor := Actor.new()
	actor.name = "Actor_%s" % kind
	actor.setup(kind, sc, float(_actors.get_child_count()) * 1.7)
	actor.position = Vector2(x, GROUND_Y + Actor.ground_offset(kind))
	_actors.add_child(actor)
	_animated.append(actor)


func _add_knight(x: float, sc: float) -> void:
	var knight := Node2D.new()
	knight.name = "Actor_knight"
	knight.position = Vector2(x, GROUND_Y)
	knight.scale = Vector2(sc, sc)
	_actors.add_child(knight)
	var skin := SkinCatalog.DEFAULT_SKIN
	if SaveData.skin_id != "" and SkinCatalog.has(StringName(SaveData.skin_id)):
		skin = StringName(SaveData.skin_id)
	var frames := SkinCatalog.frames_for(skin, &"idle")
	if frames.is_empty():
		# 没有帧（极端兜底）：用剪影顶上，分镜不能因为缺素材而没有主角。
		var sil := Actor.new()
		sil.setup("knight", 1.0, 0.0)
		knight.add_child(sil)
		_animated.append(sil)
		return
	var anim := FrameAnimSprite.new()
	anim.name = "KnightSprite"
	anim.register("idle", frames, 10.0, true, SkinCatalog.offset_for(skin, &"idle"))
	anim.play("idle")
	anim.modulate = SkinCatalog.tint_of(skin)
	anim.set_process(false)
	_knight_anims.append(anim)
	var visual := Node2D.new()
	visual.name = "Visual"
	knight.add_child(visual)
	visual.add_child(anim)
	var sword := Greatsword.new()
	visual.add_child(sword)
	sword.show_carried()
	# 巨剑没有自己的画面时钟；留着 process 会在分镜被暂停时仍空转。
	sword.set_process(false)
	_extra_actors += 1


func _build_motes(fx_id: String) -> void:
	var spec := {"embers": [44, true], "ash": [38, false], "dust": [30, false]}
	if not spec.has(fx_id):
		return
	var arr: Array = spec[fx_id] as Array
	var motes := Motes.new()
	motes.name = "Motes_%s" % fx_id
	motes.setup(fx_id, int(arr[0]))
	if bool(arr[1]):
		motes.material = Fx.additive_mat()
	_motes_front.add_child(motes)
	_motes.append(motes)


# ------------------------------------------------------------------ camera ------

func _apply_camera(p: float) -> void:
	if _world == null:
		return
	var s := 1.0
	var shift_x := 0.0
	var shift_y := 0.0
	match _cam:
		"push":
			s = 1.0 + (ART_PUSH if _using_art else CAM_PUSH) * p
		"pan_right":
			shift_x = lerpf(-CAM_PAN, CAM_PAN, p)
		"pan_left":
			shift_x = lerpf(CAM_PAN, -CAM_PAN, p)
		"rise":
			shift_y = lerpf(-CAM_RISE, CAM_RISE, p)
	_world.scale = Vector2(s, s)
	_world.position = (WORLD * 0.5 * (1.0 - s)).round()
	for entry in _layers:
		var node := entry["node"] as Node2D
		if not is_instance_valid(node):
			continue
		var sc := entry["scroll"] as Vector2
		var base := entry["base"] as Vector2
		var off := Vector2(-shift_x * (0.3 + sc.x), shift_y * (0.4 + sc.y * 2.0))
		node.position = (base + off).round()
	_actors.position = Vector2(-shift_x, shift_y).round()


# ------------------------------------------------------------------ actors ------

## 程序化像素剪影演员。原点在脚底，向上是负 y；Node2D.scale 放大整只。
## `_draw` 画不发光的部分，GlowNode（加色混合）画火光 / 魂光 / 眼光。
class Actor extends Node2D:
	var kind := ""
	var sc := 1.0
	var t := 0.0
	var phase := 0.0
	var _glow: Node2D

	static func ground_offset(k: String) -> float:
		match k:
			"souls":
				return -4.0
			"ring":
				return -60.0
		return 0.0

	func setup(k: String, scale_k: float, phase_v: float) -> void:
		kind = k
		sc = scale_k
		phase = phase_v
		scale = Vector2(scale_k, scale_k)
		_glow = GlowNode.new()
		_glow.material = Fx.additive_mat()
		add_child(_glow)

	func advance(clock: float) -> void:
		t = clock
		queue_redraw()
		if _glow != null:
			_glow.queue_redraw()

	func _draw() -> void:
		match kind:
			"knight":
				_draw_knight()
			"swords":
				_draw_swords()
			"gate":
				_draw_gate()
			"figure":
				_draw_figure()
			"yir":
				_draw_yir()
			"ash_guard":
				_draw_guard()

	func draw_glow(c: CanvasItem) -> void:
		match kind:
			"seed":
				_glow_seed(c)
			"flame":
				_glow_flame(c)
			"souls":
				_glow_souls(c)
			"swords":
				_glow_swords(c)
			"gate":
				_glow_gate(c)
			"figure":
				_glow_figure(c)
			"yir":
				_glow_yir(c)
			"ring":
				_glow_ring(c)

	# -- 不发光的部分 --

	func _draw_knight() -> void:
		var steel := Color(0.34, 0.33, 0.37)
		var dark := Color(0.12, 0.11, 0.14)
		draw_rect(Rect2(-6.0, -14.0, 5.0, 14.0), dark)
		draw_rect(Rect2(1.0, -14.0, 5.0, 14.0), dark)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-9.0, -14.0), Vector2(-10.0, -30.0), Vector2(-5.0, -36.0),
			Vector2(5.0, -36.0), Vector2(10.0, -30.0), Vector2(9.0, -14.0)]), steel)
		draw_rect(Rect2(-5.0, -46.0, 10.0, 10.0), steel)
		draw_rect(Rect2(-3.0, -42.0, 6.0, 2.0), dark)
		draw_line(Vector2(-8.0, -28.0), Vector2(-14.0, -52.0), Color(0.3, 0.2, 0.15), 2.0)

	func _draw_swords() -> void:
		var steel := Color(0.3, 0.31, 0.35)
		var edge := Color(0.55, 0.56, 0.6)
		var hilt := Color(0.2, 0.13, 0.1)
		for i in 9:
			var fi := float(i) - 4.0
			var x := fi * 20.0
			var h := 70.0 + float((i * 37) % 5) * 7.0
			var top := Vector2(x + fi * 1.4, -h)
			draw_line(Vector2(x, -22.0), top, steel, 3.0)
			draw_line(Vector2(x + 1.0, -22.0), top + Vector2(1.0, 0.0), edge, 1.0)
			draw_line(Vector2(x - 7.0, -22.0), Vector2(x + 7.0, -22.0), hilt, 3.0)
			draw_line(Vector2(x, -22.0), Vector2(x, -4.0), hilt, 3.0)
			draw_rect(Rect2(x - 2.0, -4.0, 4.0, 4.0), hilt)

	func _draw_gate() -> void:
		var w := 38.0
		var h := 128.0
		var stone := Color(0.2, 0.17, 0.19)
		var door := Color(0.07, 0.05, 0.06)
		draw_rect(Rect2(-w - 9.0, -h + w * 0.6, 14.0, h - w * 0.6), stone)
		draw_rect(Rect2(w - 5.0, -h + w * 0.6, 14.0, h - w * 0.6), stone)
		var pts := PackedVector2Array([Vector2(-w, 0.0), Vector2(-w, -(h - w))])
		for i in range(1, 12):
			var a := PI * float(i) / 12.0
			pts.append(Vector2(-cos(a) * w, -(h - w) - sin(a) * w))
		pts.append(Vector2(w, -(h - w)))
		pts.append(Vector2(w, 0.0))
		draw_colored_polygon(pts, door)
		for i in 5:
			draw_rect(Rect2(-w + 6.0, -14.0 - float(i) * 22.0, w * 2.0 - 12.0, 2.0), Color(0.12, 0.09, 0.1))

	func _draw_figure() -> void:
		var body := Color(0.08, 0.06, 0.065)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-22.0, 0.0), Vector2(-26.0, -40.0), Vector2(-16.0, -78.0), Vector2(0.0, -92.0),
			Vector2(16.0, -80.0), Vector2(26.0, -44.0), Vector2(22.0, 0.0)]), body)
		draw_circle(Vector2(3.0, -102.0), 10.0, body)
		draw_line(Vector2(20.0, -70.0), Vector2(50.0, -112.0), Color(0.22, 0.14, 0.1), 4.0)
		draw_rect(Rect2(40.0, -126.0, 24.0, 16.0), Color(0.18, 0.17, 0.19))
		draw_line(Vector2(24.0, -78.0), Vector2(24.0, -4.0), Color(0.45, 0.2, 0.1, 0.5), 1.0)

	func _draw_yir() -> void:
		var bob := sin(t * 1.6 + phase) * 3.0
		var cloak := Color(0.78, 0.84, 0.95, 0.46)
		var pale := Color(0.88, 0.92, 1.0, 0.62)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-16.0, -6.0 + bob), Vector2(-20.0, -40.0 + bob), Vector2(-10.0, -68.0 + bob),
			Vector2(0.0, -76.0 + bob), Vector2(10.0, -68.0 + bob), Vector2(20.0, -40.0 + bob),
			Vector2(16.0, -6.0 + bob)]), cloak)
		for i in 3:
			var x := float(i - 1) * 11.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(x - 6.0, -8.0 + bob), Vector2(x + 6.0, -8.0 + bob),
				Vector2(x + sin(t * 2.0 + float(i)) * 3.0, 6.0 + bob)]), cloak)
		draw_circle(Vector2(0.0, -84.0 + bob), 8.0, pale)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-10.0, -78.0 + bob), Vector2(0.0, -98.0 + bob), Vector2(10.0, -78.0 + bob)]),
			Color(0.62, 0.7, 0.86, 0.5))

	func _draw_guard() -> void:
		var ash := Color(0.43, 0.42, 0.41)
		var shade := Color(0.26, 0.25, 0.25)
		draw_rect(Rect2(-9.0, -26.0, 7.0, 26.0), shade)
		draw_rect(Rect2(2.0, -26.0, 7.0, 26.0), shade)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-13.0, -26.0), Vector2(-15.0, -56.0), Vector2(-7.0, -66.0),
			Vector2(7.0, -66.0), Vector2(15.0, -56.0), Vector2(13.0, -26.0)]), ash)
		draw_rect(Rect2(-7.0, -80.0, 14.0, 14.0), ash)
		draw_rect(Rect2(-4.0, -75.0, 8.0, 2.0), Color(0.08, 0.07, 0.07))
		draw_line(Vector2(18.0, -4.0), Vector2(20.0, -104.0), Color(0.36, 0.33, 0.3), 2.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(17.0, -104.0), Vector2(21.0, -104.0), Vector2(19.0, -118.0)]), Color(0.55, 0.54, 0.52))
		for i in 10:
			var life := fposmod(t * 0.35 + float(i) * 0.1, 1.0)
			var x := -14.0 + float((i * 13) % 28) + sin(t + float(i)) * 3.0
			var y := -66.0 + life * 66.0
			draw_rect(Rect2(roundf(x), roundf(y), 2.0, 2.0), Color(0.68, 0.66, 0.64, (1.0 - life) * 0.8))

	# -- 发光的部分（加色混合） --

	func _glow_seed(c: CanvasItem) -> void:
		var f := 0.8 + 0.2 * sin(t * 5.0 + phase)
		var o := Vector2(0.0, -22.0)
		c.draw_circle(o, 17.0, Color(1.0, 0.5, 0.15, 0.10 * f))
		c.draw_circle(o, 10.0, Color(1.0, 0.62, 0.2, 0.24 * f))
		c.draw_circle(o, 5.0, Color(1.0, 0.84, 0.5, 0.85))
		c.draw_circle(o, 2.0, Color(1.0, 1.0, 0.9, 1.0))

	func _flame_tongue(c: CanvasItem, x: float, w: float, h: float, ph: float, col: Color) -> void:
		var sway := sin(t * 6.0 + ph) * w * 0.35
		c.draw_colored_polygon(PackedVector2Array([
			Vector2(x - w, 0.0), Vector2(x - w * 0.7, -h * 0.35),
			Vector2(x - w * 0.25 + sway * 0.5, -h * 0.7), Vector2(x + sway, -h),
			Vector2(x + w * 0.25 + sway * 0.5, -h * 0.7), Vector2(x + w * 0.7, -h * 0.35),
			Vector2(x + w, 0.0)]), col)

	func _glow_flame(c: CanvasItem) -> void:
		var f := 0.85 + 0.15 * sin(t * 9.0 + phase) + 0.05 * sin(t * 23.0)
		c.draw_circle(Vector2(0.0, -26.0), 46.0, Color(1.0, 0.4, 0.1, 0.07 * f))
		c.draw_circle(Vector2(0.0, -22.0), 28.0, Color(1.0, 0.48, 0.12, 0.10 * f))
		_flame_tongue(c, -11.0, 10.0, 46.0 * f, phase, Color(1.0, 0.42, 0.1, 0.55))
		_flame_tongue(c, 0.0, 13.0, 64.0 * f, phase + 1.3, Color(1.0, 0.52, 0.14, 0.6))
		_flame_tongue(c, 12.0, 9.0, 40.0 * f, phase + 2.6, Color(1.0, 0.42, 0.1, 0.55))
		_flame_tongue(c, 0.0, 7.0, 40.0 * f, phase + 0.5, Color(1.0, 0.86, 0.5, 0.7))

	func _glow_souls(c: CanvasItem) -> void:
		for i in 14:
			var ph := float(i) * 1.7 + phase
			var life := fposmod(t * 0.12 + float(i) * 0.071, 1.0)
			var x := sin(ph * 2.3 + t * 0.4) * (30.0 + float(i % 5) * 18.0)
			var y := -life * 170.0
			var a := sin(life * PI)
			c.draw_circle(Vector2(x, y), 5.0, Color(0.6, 0.8, 1.0, a * 0.14))
			c.draw_rect(Rect2(roundf(x) - 1.0, roundf(y) - 1.0, 3.0, 3.0), Color(0.84, 0.94, 1.0, a * 0.95))
			for j in range(1, 4):
				c.draw_rect(Rect2(roundf(x), roundf(y) + float(j) * 5.0, 1.0, 2.0),
						Color(0.7, 0.86, 1.0, a * 0.5 / float(j)))

	func _glow_swords(c: CanvasItem) -> void:
		var burning := int(t * 0.5) % 9
		for i in 9:
			var fi := float(i) - 4.0
			var h := 70.0 + float((i * 37) % 5) * 7.0
			var top := Vector2(fi * 20.0 + fi * 1.4, -h)
			var a := 0.5 + 0.4 * sin(t * 3.0 + float(i) * 1.3)
			c.draw_rect(Rect2(roundf(top.x) - 1.0, roundf(top.y) - 2.0, 2.0, 3.0), Color(1.0, 0.6, 0.2, a))
			if i == burning:
				c.draw_circle(top, 12.0, Color(1.0, 0.5, 0.12, 0.18 * a))
				c.draw_line(Vector2(top.x, top.y + 4.0), Vector2(top.x, -24.0), Color(1.0, 0.55, 0.15, 0.4 * a), 2.0)

	func _glow_gate(c: CanvasItem) -> void:
		var open := clampf(t / 6.0, 0.0, 1.0)
		var gap := 3.0 + open * 20.0
		var f := 0.85 + 0.15 * sin(t * 4.0)
		c.draw_circle(Vector2(0.0, -64.0), 70.0, Color(1.0, 0.45, 0.14, 0.07 * f))
		c.draw_rect(Rect2(-gap * 0.5, -118.0, gap, 118.0), Color(1.0, 0.62, 0.22, 0.5 * f))
		c.draw_rect(Rect2(-gap * 0.2, -112.0, gap * 0.4, 112.0), Color(1.0, 0.92, 0.7, 0.8 * f))

	func _glow_figure(c: CanvasItem) -> void:
		var f := 0.7 + 0.3 * sin(t * 2.4 + phase)
		c.draw_rect(Rect2(-1.0, -104.0, 3.0, 2.0), Color(1.0, 0.5, 0.15, 0.9 * f))
		c.draw_rect(Rect2(6.0, -104.0, 3.0, 2.0), Color(1.0, 0.5, 0.15, 0.9 * f))
		c.draw_circle(Vector2(52.0, -118.0), 14.0, Color(1.0, 0.45, 0.12, 0.12 * f))

	func _glow_yir(c: CanvasItem) -> void:
		var bob := sin(t * 1.6 + phase) * 3.0
		var f := 0.8 + 0.2 * sin(t * 3.0)
		var o := Vector2(0.0, -46.0 + bob)
		c.draw_circle(o, 40.0, Color(0.9, 0.7, 0.5, 0.07 * f))
		c.draw_circle(o, 9.0, Color(1.0, 0.62, 0.2, 0.3 * f))
		c.draw_circle(o, 4.0, Color(1.0, 0.88, 0.6, 0.9))

	func _glow_ring(c: CanvasItem) -> void:
		var life := fposmod(t * 0.6 + phase, 1.0)
		c.draw_arc(Vector2.ZERO, 14.0 + life * 90.0, 0.0, TAU, 48, Color(1.0, 0.7, 0.3, (1.0 - life) * 0.7), 2.0)


class GlowNode extends Node2D:
	func _draw() -> void:
		var parent := get_parent()
		if parent != null:
			parent.call("draw_glow", self)


## 一层漂浮的像素粒子（火星 / 灰 / 尘）。固定粒子数，没有逐帧分配。
class Motes extends Node2D:
	var kind := "embers"
	var pos := PackedVector2Array()
	var vel := PackedVector2Array()
	var life := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()

	func setup(k: String, n: int) -> void:
		kind = k
		rng.seed = 7
		pos.resize(n)
		vel.resize(n)
		life.resize(n)
		for i in n:
			_respawn(i, true)

	func _respawn(i: int, initial: bool) -> void:
		var x := rng.randf_range(-10.0, 650.0)
		match kind:
			"embers":
				pos[i] = Vector2(x, rng.randf_range(200.0, 380.0) if initial else 380.0)
				vel[i] = Vector2(rng.randf_range(-6.0, 8.0), rng.randf_range(-34.0, -12.0))
			"ash":
				pos[i] = Vector2(x, rng.randf_range(-10.0, 360.0) if initial else -10.0)
				vel[i] = Vector2(rng.randf_range(2.0, 9.0), rng.randf_range(9.0, 22.0))
			_:
				pos[i] = Vector2(x, rng.randf_range(0.0, 360.0))
				vel[i] = Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-2.0, 2.0))
		life[i] = rng.randf_range(0.3, 1.0) if initial else 1.0

	func step(delta: float) -> void:
		for i in pos.size():
			pos[i] += vel[i] * delta
			life[i] -= delta * (0.18 if kind == "dust" else 0.12)
			if life[i] <= 0.0 or pos[i].y < -20.0 or pos[i].y > 390.0:
				_respawn(i, false)
		queue_redraw()

	func _draw() -> void:
		for i in pos.size():
			var p := Vector2(floorf(pos[i].x), floorf(pos[i].y))
			var a := clampf(life[i], 0.0, 1.0)
			match kind:
				"embers":
					draw_rect(Rect2(p, Vector2(2.0, 2.0)), Color(1.0, 0.45 + 0.4 * a, 0.12, a))
				"ash":
					draw_rect(Rect2(p, Vector2(2.0, 1.0)), Color(0.72, 0.7, 0.68, 0.55 * a))
				_:
					draw_rect(Rect2(p, Vector2(1.0, 1.0)), Color(0.85, 0.8, 0.7, 0.28 * a))
