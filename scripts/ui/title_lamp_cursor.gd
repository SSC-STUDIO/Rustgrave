class_name TitleLampCursor
extends Control
## The title menu's cursor: one lantern on a chain, hung from the left truss.
## It swings down onto the selected row and the row's letters take their light
## from how close the flame is. No PointLight2D — the pool is an additive glow,
## same trick the hall lanterns use once the eight-light budget is spent.

const LANTERN := "res://assets/title/lantern.png"
const GLOW := "res://assets/title/glow.png"
const FRAME := Vector2(12, 17)
const ANCHOR_X := 24.0
const CORE_Y := 20.0
const CHAIN_TOP := 28.0
const LINK_H := 6
const OMEGA := 14.0

var _target_center := 280.0
var _target_y := 260.0
var _y := -48.0
var _vy := 0.0
var _sway := 0.0
var _armed := false
var _lit := 0.0
var _lit_target := 0.0
var _flare := 0.0
var _t := 0.0
var _tex: Texture2D
var _glow: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tex = load(LANTERN) as Texture2D
	_glow = TextureRect.new()
	_glow.name = "Pool"
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.texture = load(GLOW) as Texture2D
	_glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.show_behind_parent = true
	_glow.size = Vector2(150.0, 150.0)
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = blend
	_glow.modulate = Color(1.0, 0.62, 0.28, 0.0)
	add_child(_glow)
	_place_glow()


## Where the flame should sit, in this control's coordinates (the row's centre).
func set_target_center_y(y: float) -> void:
	_target_center = y
	_target_y = y - CORE_Y


func lantern_center() -> Vector2:
	return Vector2(ANCHOR_X + roundf(_sway), roundf(_y) + CORE_Y)


## Start following. The chain is already coiled above the frame; it drops in.
func arm() -> void:
	_armed = true
	_lit_target = 1.0


## Drop straight onto the current row and light the flame. Used when the intro is skipped.
func ignite(instant: bool = false) -> void:
	_armed = true
	_lit_target = 1.0
	if instant:
		_lit = 1.0
		_vy = 0.0
		_sway = 0.0
		_y = _target_y
		_place_glow()
		queue_redraw()


## The flame dies. The chain stays until the title fades it with the rest of the chrome.
func douse() -> void:
	_lit_target = 0.0
	_flare = 0.0


func flare(strength: float = 1.0) -> void:
	if _lit_target > 0.5:
		_flare = maxf(_flare, strength)


## Deterministic step for tests. Real frames go through _process.
func advance(seconds: float) -> void:
	var left := maxf(seconds, 0.0)
	while left > 0.0:
		var step := minf(0.05, left)
		left -= step
		_step_motion(step)


func _process(delta: float) -> void:
	if not _armed:
		return
	_step_motion(delta)


func _step_motion(delta: float) -> void:
	_t += delta
	var acc := (_target_y - _y) * OMEGA * OMEGA - _vy * (2.0 * OMEGA)
	_vy += acc * delta
	_y += _vy * delta
	var idle := sin(_t * TAU / 3.6) * _lit
	var travel := clampf(-_vy * 0.02, -7.0, 7.0)
	_sway = move_toward(_sway, travel + idle, delta * 36.0)
	if not is_equal_approx(_lit, _lit_target):
		_lit = move_toward(_lit, _lit_target, delta * 2.4)
	if _flare > 0.0:
		_flare = maxf(0.0, _flare - delta * 1.7)
	_place_glow()
	queue_redraw()


func _place_glow() -> void:
	if _glow == null:
		return
	var core := lantern_center()
	_glow.position = core - _glow.size * 0.5
	var amount := clampf(_lit * (0.85 + _flare * 0.7), 0.0, 1.15)
	_glow.modulate = Color(1.0, 0.64, 0.30, amount * 0.34)
	_glow.visible = amount > 0.02


func _draw() -> void:
	var end_y := roundf(_y)
	var top := CHAIN_TOP
	if end_y < top:
		top = minf(0.0, end_y)
	var n := int(maxf(end_y - top, 0.0) / float(LINK_H))
	var sway := int(roundf(_sway))
	for i in n:
		var y := int(top) + i * LINK_H
		var along := float(i) / float(maxi(n - 1, 1))
		var x := int(roundf(float(sway) * pow(along, 1.55))) + int(ANCHOR_X)
		if i % 2 == 0:
			draw_rect(Rect2(x - 1, y, 3, 1), Color("#7A6258"))
			draw_rect(Rect2(x - 2, y + 1, 1, 4), Color("#4A3E44"))
			draw_rect(Rect2(x + 2, y + 1, 1, 4), Color("#241C22"))
			draw_rect(Rect2(x - 1, y + 5, 3, 1), Color("#241C22"))
		else:
			draw_rect(Rect2(x - 1, y, 3, LINK_H), Color("#4A3E44"))
			draw_rect(Rect2(x - 1, y, 1, LINK_H), Color("#7A6258"))
			draw_rect(Rect2(x + 1, y, 1, LINK_H), Color("#241C22"))
	if _tex == null:
		return
	var frame := 1 if _lit > 0.08 else 0
	var origin := Vector2(ANCHOR_X + float(sway) - FRAME.x, end_y)
	draw_texture_rect_region(_tex, Rect2(origin, FRAME * 2.0),
			Rect2(float(frame) * FRAME.x, 0.0, FRAME.x, FRAME.y))
