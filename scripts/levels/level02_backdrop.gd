class_name Level02Backdrop
extends Node2D
## 地窟背景：没有天空。最底一层是深青黑的底色，其上是古堡室内墙（拱窗、灯笼壁龛）
## 的慢速视差，再前一层是柱子剪影。整关一个固定的冷青 CanvasModulate，不跟昼夜走——
## 地下本来就没有白天。

const WALL_PATH := "res://assets/external/gothicvania_patreon/Old-dark-Castle-tileset-Files/PNG/old-dark-castle-interior-background.png"
const COLUMN_PATH := "res://assets/env/column_big_cut.png"
const VOID_COLOR := Color(0.035, 0.07, 0.085)
const WALL_SCROLL := Vector2(0.42, 0.18)
## 墙板 960×304；铺到 y=48 让画中的石地板压在关卡地面（320）附近。
const WALL_Y := 48.0
const WALL_TINT := Color(0.78, 0.9, 0.9)
const COLUMN_SCROLL := Vector2(0.66, 0.3)
const COLUMN_TINT := Color(0.16, 0.24, 0.25, 0.9)
const COLUMN_SPACING := 352.0
const COLUMN_FEET_Y := 336.0
const COLUMN_SCALE := 0.9
## 冷青调：比 Level01 的夜晚略亮，能看清苔盖与骑士，同时保留地窟的沉。
const MOOD := Color(0.66, 0.82, 0.84)
const BREATH_AMP := 0.03
const BREATH_RATE := 0.35

var _mood: CanvasModulate
var _wall: Parallax2D
var _columns: Parallax2D
var _t := 0.0


func build(host: Node2D) -> void:
	var backdrop := host.get_node_or_null("ParallaxBackdrop") as CanvasLayer
	if backdrop == null:
		backdrop = CanvasLayer.new()
		backdrop.name = "ParallaxBackdrop"
		backdrop.layer = -10
		host.add_child(backdrop)
	backdrop.follow_viewport_enabled = false
	if backdrop.get_node_or_null("Void") == null:
		var void_rect := ColorRect.new()
		void_rect.name = "Void"
		void_rect.color = VOID_COLOR
		void_rect.position = Vector2(-64, -64)
		void_rect.size = Vector2(PresentationMetrics.WORLD_SIZE) + Vector2(128, 128)
		void_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backdrop.add_child(void_rect)
	_wall = _add_layer(backdrop, "Wall", WALL_PATH, WALL_SCROLL, Vector2(0, WALL_Y), 1.0, WALL_TINT)
	_columns = _add_columns(backdrop)
	# Phase-3 rules (ChapterLook), undercroft colours: teal hall, window-green haze, moss lips.
	ChapterLook.apply(host, backdrop, ThemeBackdrop.THEMES["undercroft"]["look"], String(_columns.name) if _columns != null else "")
	var tint := host.get_node_or_null("MoodTint") as CanvasModulate
	if tint == null:
		tint = CanvasModulate.new()
		tint.name = "MoodTint"
		host.add_child(tint)
	tint.color = MOOD
	_mood = tint
	if host.get_node_or_null("CineFx") == null:
		var cine := CineFx.new()
		cine.name = "CineFx"
		host.add_child(cine)


func _process(delta: float) -> void:
	_t += delta * BREATH_RATE
	if _mood != null:
		var k := 1.0 + sin(_t * TAU) * BREATH_AMP
		_mood.color = Color(MOOD.r * k, MOOD.g * k, MOOD.b * k, 1.0)


static func mood_color() -> Color:
	return MOOD


func _add_layer(parent: Node, layer_name: String, path: String, scroll: Vector2, pos: Vector2,
		scale_k: float, tint: Color) -> Parallax2D:
	if not ResourceLoader.exists(path):
		return null
	var tex := ArtTexture.load_texture(path)
	if tex == null:
		return null
	var layer := Parallax2D.new()
	layer.name = layer_name
	layer.scroll_scale = scroll
	layer.follow_viewport = false
	parent.add_child(layer)
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = pos
	spr.scale = Vector2(scale_k, scale_k)
	spr.modulate = tint
	layer.add_child(spr)
	Level01Parallax.cover_layer(layer)
	return layer


## 柱子剪影：一根大柱贴图按间距重复，压成暗青色，站在墙板和地面之间。
func _add_columns(parent: Node) -> Parallax2D:
	if not ResourceLoader.exists(COLUMN_PATH):
		return null
	var tex := ArtTexture.load_texture(COLUMN_PATH)
	if tex == null:
		return null
	var layer := Parallax2D.new()
	layer.name = "Columns"
	layer.scroll_scale = COLUMN_SCROLL
	layer.follow_viewport = false
	layer.repeat_size = Vector2(COLUMN_SPACING, 0.0)
	layer.repeat_times = Level01Parallax.copies_for_view(COLUMN_SPACING)
	parent.add_child(layer)
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.scale = Vector2(COLUMN_SCALE, COLUMN_SCALE)
	spr.position = Vector2(96.0, COLUMN_FEET_Y - float(tex.get_height()) * COLUMN_SCALE)
	spr.modulate = COLUMN_TINT
	layer.add_child(spr)
	return layer
