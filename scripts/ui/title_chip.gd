class_name TitleChip
extends Control
## A small stat chip on the title screen's journey column: a dark tag with a one-glyph
## name and a short value (rank, skin, trials, arena). `lit` chips have a record to show.

const CHIP_SIZE := Vector2(98.0, 26.0)
const FILL := Color(0.055, 0.04, 0.075, 0.66)
const EDGE := Color("#3A2012")
const EDGE_LIT := Color("#8B4513")
const STRIPE := Color("#4A3E44")
const STRIPE_LIT := Color("#FFC14A")

var tag_text := ""
var value_text := ""
var lit := false

var _tag: Label
var _value: Label


func _init() -> void:
	custom_minimum_size = CHIP_SIZE
	size = CHIP_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_tag = UiKit.label(tag_text, &"TinyLabel")
	_tag.name = "Tag"
	_tag.position = Vector2(9.0, 0.0)
	_tag.size = Vector2(22.0, CHIP_SIZE.y)
	_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_tag)
	_value = UiKit.label(value_text, &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_value.name = "Value"
	_value.position = Vector2(34.0, 0.0)
	_value.size = Vector2(CHIP_SIZE.x - 42.0, CHIP_SIZE.y)
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value.clip_text = true
	_value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_value)
	_apply()


func set_chip(tag: String, value: String, is_lit: bool) -> void:
	tag_text = tag
	value_text = value
	lit = is_lit
	_apply()


func _apply() -> void:
	if _tag == null:
		return
	_tag.text = tag_text
	_value.text = value_text
	_tag.modulate = Color(UiKit.EMBER_ASH.r, UiKit.EMBER_ASH.g, UiKit.EMBER_ASH.b, 0.75 if lit else 0.45)
	_value.modulate = Color(1.0, 1.0, 1.0, 1.0 if lit else 0.55)
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	# 阶梯切角（2px 栅格）：芯片与档案卡、铁条用同一种边角语汇。
	draw_rect(Rect2(2.0, 0.0, w - 4.0, h), FILL)
	draw_rect(Rect2(0.0, 2.0, w, h - 4.0), FILL)
	var edge := EDGE_LIT if lit else EDGE
	draw_rect(Rect2(2.0, 0.0, w - 4.0, 1.0), edge)
	draw_rect(Rect2(2.0, h - 1.0, w - 4.0, 1.0), edge)
	draw_rect(Rect2(0.0, 2.0, 1.0, h - 4.0), Color(edge.r, edge.g, edge.b, 0.55))
	draw_rect(Rect2(w - 1.0, 2.0, 1.0, h - 4.0), Color(edge.r, edge.g, edge.b, 0.55))
	# 顶光 / 底影：一点钢板厚度。
	draw_rect(Rect2(3.0, 1.0, w - 6.0, 1.0), Color(0.9, 0.7, 0.5, 0.06))
	draw_rect(Rect2(3.0, h - 2.0, w - 6.0, 1.0), Color(0.0, 0.0, 0.0, 0.22))
	draw_rect(Rect2(0.0, 2.0, 3.0, h - 4.0), STRIPE_LIT if lit else STRIPE)
	# 标签和值之间一道 1px 内分隔，四枚芯片看起来像同一套仪表。
	draw_rect(Rect2(28.0, 6.0, 1.0, h - 12.0),
			Color(EDGE.r, EDGE.g, EDGE.b, 0.9))
