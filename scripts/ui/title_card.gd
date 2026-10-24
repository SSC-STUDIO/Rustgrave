class_name TitleCard
extends Control
## The dark, flat card behind the title's expanded dossier: a translucent body with
## stair-stepped corners (2px grid), a rust hairline border and an ember accent on the
## top edge. Pure drawing; the screen puts its labels on top.

const FILL := Color(0.05, 0.035, 0.07, 0.9)
const BORDER := Color("#4A2A18")
const ACCENT := Color("#C8721C")
const RIVET := Color("#FFC14A")


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	# body with the four corners cut in 2px steps
	draw_rect(Rect2(6.0, 0.0, w - 12.0, h), FILL)
	draw_rect(Rect2(2.0, 4.0, w - 4.0, h - 8.0), FILL)
	draw_rect(Rect2(0.0, 6.0, w, h - 12.0), FILL)
	# border
	draw_rect(Rect2(6.0, 0.0, w - 12.0, 1.0), BORDER)
	draw_rect(Rect2(6.0, h - 1.0, w - 12.0, 1.0), BORDER)
	draw_rect(Rect2(0.0, 6.0, 1.0, h - 12.0), BORDER)
	draw_rect(Rect2(w - 1.0, 6.0, 1.0, h - 12.0), BORDER)
	for i in 3:
		var o := 2.0 * float(i)
		draw_rect(Rect2(4.0 - o, 2.0 + o, 2.0, 2.0), BORDER)
		draw_rect(Rect2(w - 6.0 + o, 2.0 + o, 2.0, 2.0), BORDER)
		draw_rect(Rect2(4.0 - o, h - 4.0 - o, 2.0, 2.0), BORDER)
		draw_rect(Rect2(w - 6.0 + o, h - 4.0 - o, 2.0, 2.0), BORDER)
	# ember accent along the top edge + corner rivets
	draw_rect(Rect2(12.0, 1.0, w - 24.0, 2.0), ACCENT)
	draw_rect(Rect2(12.0, 3.0, w - 24.0, 1.0), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.3))
	for p in [Vector2(10.0, 10.0), Vector2(w - 14.0, 10.0), Vector2(10.0, h - 14.0), Vector2(w - 14.0, h - 14.0)]:
		draw_rect(Rect2(p.x, p.y, 4.0, 4.0), BORDER)
		draw_rect(Rect2(p.x + 1.0, p.y + 1.0, 2.0, 2.0), RIVET)
