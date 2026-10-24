class_name TitleChain
extends Node2D
## A hanging chain for the live title scene. The origin is the chain's top anchor,
## `length` its drop in pixels. It sways in whole pixels and is drawn link by link
## (face-on and edge-on links alternate), so nothing is ever sub-pixel or rotated.
## TitleLantern extends this and hangs a lit cage on the end.

const LINK_H := 6
const OUTLINE := Color("#0B0910")

var length := 80.0
## Horizontal swing of the lower end, in pixels.
var swing_amp := 2.0
var swing_period := 6.0
var swing_phase := 0.0
## Plain chains end in a small iron weight; lanterns hang their own body instead.
var weight := true
var col_dark := Color("#241C22")
var col_mid := Color("#4A3E44")
var col_light := Color("#7A6258")

var _t := 0.0
var _off := 0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_t = swing_phase * 0.37


func _process(delta: float) -> void:
	_t += delta
	var off := int(roundf(sin(_t * TAU / maxf(swing_period, 0.1) + swing_phase) * swing_amp))
	if off != _off:
		_off = off
		_on_sway()
		queue_redraw()


## The lower end of the chain in this node's coordinates (whole pixels).
func bottom_point() -> Vector2:
	return Vector2(float(_off), length)


func _on_sway() -> void:
	pass


func _draw() -> void:
	var n := int(length / float(LINK_H))
	for i in n:
		var y := i * LINK_H
		var t := float(y) / maxf(length, 1.0)
		var x := int(roundf(float(_off) * pow(t, 1.5)))
		if i % 2 == 0:
			draw_rect(Rect2(x - 1, y, 3, 1), col_light)
			draw_rect(Rect2(x - 2, y + 1, 1, 4), col_mid)
			draw_rect(Rect2(x + 2, y + 1, 1, 4), col_dark)
			draw_rect(Rect2(x - 1, y + 5, 3, 1), col_dark)
		else:
			draw_rect(Rect2(x - 1, y, 3, LINK_H), col_mid)
			draw_rect(Rect2(x - 1, y, 1, LINK_H), col_light)
			draw_rect(Rect2(x + 1, y, 1, LINK_H), col_dark)
	if weight:
		var wx := _off
		var wy := n * LINK_H
		draw_rect(Rect2(wx - 3, wy, 7, 5), OUTLINE)
		draw_rect(Rect2(wx - 2, wy + 1, 5, 3), col_mid)
		draw_rect(Rect2(wx - 2, wy + 1, 2, 1), col_light)
