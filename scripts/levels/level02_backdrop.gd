class_name Level02Backdrop
extends Node2D
## 地窟背景：没有天空。最底一层是深青黑的底色，往上依次是——
##   ① HallFar：更深一进的拱顶大厅剪影（只留窗光，最慢）；
##   ② Wall：古堡室内墙（拱窗、灯笼壁龛）的慢速视差；
##   ③ Columns：柱子剪影。
## 整关一个固定的冷青 CanvasModulate，不跟昼夜走——地下本来就没有白天。
## 补 ① 之前只有墙与柱两层，糊成一张纸：现在墙后还有一进大厅。

const WALL_PATH := "res://assets/external/gothicvania_patreon/Old-dark-Castle-tileset-Files/PNG/old-dark-castle-interior-background.png"
const COLUMN_PATH := "res://assets/env/column_big_cut.png"
## 远景大厅板：Gothic Castle 的 480×336 背景板只取上部（拱顶与尖窗），
## 压成暗青剪影，窗光的像素留在板上由 tint 统一染色。
const HALL_FAR_PATH := "res://assets/external/gothicvania_patreon/Gothic-Castle-Files/PNG/layers/gothic-castle-background.png"
const HALL_FAR_REGION := Rect2(0, 0, 480, 200)
const HALL_FAR_SCROLL := Vector2(0.16, 0.06)
const HALL_FAR_Y := 40.0
const HALL_FAR_TINT := Color(0.34, 0.46, 0.48)
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
var _hall_far: Parallax2D
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
	_hall_far = _add_hall_far(backdrop)
	_wall = _add_layer(backdrop, "Wall", WALL_PATH, WALL_SCROLL, Vector2(0, WALL_Y), 1.0, WALL_TINT)
	_columns = _add_columns(backdrop)
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


## 远景大厅剪影：只取城堡板的拱顶与尖窗（上部 200px），压成暗青，用最慢的
## 视差铺在苔砖墙后面。region 裁掉板下半部的楼梯/地面，才不会有第二条地平线。
func _add_hall_far(parent: Node) -> Parallax2D:
	if not ResourceLoader.exists(HALL_FAR_PATH):
		return null
	var tex := load(HALL_FAR_PATH) as Texture2D
	if tex == null:
		return null
	var layer := Parallax2D.new()
	layer.name = "HallFar"
	layer.scroll_scale = HALL_FAR_SCROLL
	layer.follow_viewport = false
	parent.add_child(layer)
	var spr := Sprite2D.new()
	spr.name = "Sprite"
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = Vector2(0, HALL_FAR_Y)
	spr.region_enabled = true
	spr.region_rect = HALL_FAR_REGION
	spr.modulate = HALL_FAR_TINT
	layer.add_child(spr)
	Level01Parallax.cover_layer(layer)
	return layer


func _add_layer(parent: Node, layer_name: String, path: String, scroll: Vector2, pos: Vector2,
		scale_k: float, tint: Color) -> Parallax2D:
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
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
	var tex := load(COLUMN_PATH) as Texture2D
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
