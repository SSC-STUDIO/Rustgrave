class_name GuideArrow
extends Node2D
## 《ICEY》式场景发光引导路标。
##
## 在 640×360 世界像素层绘制高辨识度的脉冲三连箭头与简短行动词（如「>>> 炉 座」「^^^ 钟 顶禁区」）。
## 既可入房即亮，也可挂在 BattleWaveArena 后等最后一波敌人清场时点亮。
## 不继承 Interactable、不加入 grounded 组，因此可自由悬停在门扉/高台旁且不影响 LevelSanity。

signal activated

enum Dir { RIGHT, LEFT, UP, DOWN }

@export var direction: Dir = Dir.RIGHT
@export var label_text: String = ""
@export var active_on_start: bool = true
@export var tint: Color = Color("#FFC14A")

var is_lit: bool = false
var _phase: float = 0.0
var _caption: Label


func _ready() -> void:
	z_index = 4
	_build_label()
	set_lit(active_on_start, false)


func _build_label() -> void:
	if _caption != null:
		return
	_caption = Label.new()
	_caption.name = "ArrowTag"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 8)
	_caption.add_theme_color_override("font_color", Color("#FFF0C8"))
	_caption.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.06, 0.92))
	_caption.add_theme_constant_override("outline_size", 2)
	_caption.position = Vector2(-42.0, -24.0)
	_caption.size = Vector2(84.0, 14.0)
	_caption.text = label_text
	add_child(_caption)


func set_lit(on: bool, play_cue: bool = true) -> void:
	var changed := is_lit != on
	is_lit = on
	visible = on
	if _caption != null:
		_caption.text = label_text
		_caption.visible = on and label_text != ""
	queue_redraw()
	if on and changed:
		if play_cue:
			UiKit.sfx(&"ui_tick", &"ui_select")
		activated.emit()


func activate() -> void:
	set_lit(true, true)


func _process(delta: float) -> void:
	if not is_lit:
		return
	_phase += delta * 4.5
	queue_redraw()


func _draw() -> void:
	if not is_lit:
		return
	var dir_vec := _dir_vector()
	var perp := Vector2(-dir_vec.y, dir_vec.x)
	# 背景柔光底晕
	var glow_alpha := 0.14 + 0.08 * sin(_phase)
	draw_circle(Vector2.ZERO, 16.0, Color(tint.r, tint.g, tint.b, glow_alpha))

	# 三枚依次亮起的像素折线箭头（ICEY 经典连闪路标感）
	for i in 3:
		var wave := sin(_phase - float(i) * 0.85)
		var alpha := clampf(0.38 + 0.58 * maxf(0.0, wave), 0.25, 0.98)
		var col := Color(tint.r, tint.g, tint.b, alpha)
		var center := dir_vec * (float(i - 1) * 8.0)
		var tip := center + dir_vec * 4.0
		var wing_a := center - dir_vec * 3.0 + perp * 5.0
		var wing_b := center - dir_vec * 3.0 - perp * 5.0
		draw_line(wing_a, tip, col, 2.0)
		draw_line(wing_b, tip, col, 2.0)


func _dir_vector() -> Vector2:
	match direction:
		Dir.LEFT:
			return Vector2.LEFT
		Dir.UP:
			return Vector2.UP
		Dir.DOWN:
			return Vector2.DOWN
	return Vector2.RIGHT
