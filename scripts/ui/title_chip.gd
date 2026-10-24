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
	_value.position = Vector2(30.0, 0.0)
	_value.size = Vector2(CHIP_SIZE.x - 38.0, CHIP_SIZE.y)
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
	draw_rect(Rect2(0.0, 0.0, w, h), FILL)
	draw_rect(Rect2(0.0, 0.0, w, 1.0), EDGE_LIT if lit else EDGE)
	draw_rect(Rect2(0.0, h - 1.0, w, 1.0), EDGE_LIT if lit else EDGE)
	draw_rect(Rect2(0.0, 0.0, 3.0, h), STRIPE_LIT if lit else STRIPE)
