class_name TitleChip
extends Control
## A small stat on the title screen's journey column: a one-glyph name, a short value,
## and a hairline. `lit` means there is a record to show. No plate — the text sits
## on the furnace the way the menu sits on the left wall.

const CHIP_SIZE := Vector2(98.0, 26.0)
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
	# 刻在机壳上的一行：底下一根发丝，左边一粒菱形。有记录时菱形是余烬色。
	var mark := STRIPE_LIT if lit else STRIPE
	var c := Vector2(4.0, h * 0.5 - 1.0)
	for dy in range(-2, 3):
		var half := 2 - absi(dy)
		draw_rect(Rect2(c.x - half, c.y + dy, float(2 * half + 1), 1.0), mark)
	draw_rect(Rect2(0.0, h - 2.0, w, 1.0), Color(mark.r, mark.g, mark.b, 0.55 if lit else 0.35))
