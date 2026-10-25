class_name TitleLampCursor
extends Control
## 标题屏的光标是一盏真的吊灯，不是贴在字上的铁条。
##
## 链子从字标下沿垂到当前选中的那一行，灯笼停在字的左侧，光沿着菜单漫开：
## 离灯越近的字越暖，选中的那一行被灯芯照亮。灯随选中项用弹簧落下，
## 垂直速度会把它荡开一点，像厅里其它的链子。
##
## 画在菜单后面（TitleScreen 调整了子节点顺序）：字盖在光上，灯笼落在
## 字列左侧的空处，所以灯是看得见的，字仍然清楚。

const LANTERN := "res://assets/title/lantern.png"
const GLOW := "res://assets/title/glow.png"
const FRAME := Vector2(12.0, 17.0)
const SCALE := 2.0
## 世界里一节链是 6px；标题 UI 把 640 的活景放大到 1280，链节也放大一倍。
const LINK_H := 12.0
const STIFFNESS := 72.0
const DAMPING := 16.5
## 灯芯到一行中线超过这么多像素，那一行就不再被这盏灯照到。
const FALLOFF := 92.0
const CORE_DROP := 20.0

## 链子的上端（设计像素）。菜单在它下面。
var anchor := Vector2(90.0, 176.0)

var _menu: MenuList
var _target_y := 280.0
var _y := 176.0
var _vy := 0.0
var _swing := 0.0
var _t := 0.0
var _flick := 1.0
var _flare := 0.0
var _lit := 1.0
var _lit_target := 1.0
var _step := -1
var _body: TextureRect
var _halo: TextureRect
var _atlas: AtlasTexture


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_y = anchor.y + CORE_DROP
	_target_y = _y
	var sheet := load(LANTERN) as Texture2D
	_atlas = AtlasTexture.new()
	_atlas.atlas = sheet
	_atlas.region = Rect2(FRAME.x, 0.0, FRAME.x, FRAME.y)
	_halo = TextureRect.new()
	_halo.name = "Halo"
	_halo.texture = load(GLOW) as Texture2D
	_halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_halo.stretch_mode = TextureRect.STRETCH_SCALE
	_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_halo.material = blend
	add_child(_halo)
	_body = TextureRect.new()
	_body.name = "Lantern"
	_body.texture = _atlas
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_body.stretch_mode = TextureRect.STRETCH_SCALE
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.custom_minimum_size = FRAME * SCALE
	_body.size = FRAME * SCALE
	add_child(_body)
	_place()


## 每帧由 TitleScreen 推进。菜单还没排好版（行高为 0）时灯停在上端。
func advance(delta: float, menu: MenuList) -> void:
	_menu = menu
	var step_left := maxf(delta, 0.0)
	while step_left > 0.0:
		var dt := minf(step_left, 0.05)
		step_left -= dt
		_t += dt
		_integrate(dt)
	_flicker()
	_place()
	_light_rows()
	queue_redraw()


## 测试用：立刻落到当前选中行，不走弹簧。
func snap() -> void:
	_pick_target()
	_y = _target_y
	_vy = 0.0
	_swing = 0.0
	_place()
	_light_rows()
	queue_redraw()


func flare(amount: float = 1.0) -> void:
	_flare = maxf(_flare, amount)


## 退场：火焰灭掉（灯笼换成冷的那一帧）。位置交给外面的淡出。
func douse() -> void:
	_lit_target = 0.0


func lantern_center() -> Vector2:
	return Vector2(_lantern_x(), _y)


func lantern_y() -> float:
	return _y


func _integrate(dt: float) -> void:
	_pick_target()
	if not is_equal_approx(_lit, _lit_target):
		_lit = move_toward(_lit, _lit_target, dt * 2.4)
	if _flare > 0.0:
		_flare = maxf(0.0, _flare - dt * 1.8)
	var acc := (_target_y - _y) * STIFFNESS - _vy * DAMPING
	_vy += acc * dt
	_y += _vy * dt
	var pend := clampf(-_vy * 0.04, -16.0, 16.0)
	_swing = lerpf(_swing, pend, 1.0 - exp(-7.0 * dt))


func _pick_target() -> void:
	if _menu == null:
		return
	var id := _menu.selected_id()
	for item in _menu.items():
		var row := item as MenuItem
		if row == null or row.id != id or row.size.y < 1.0:
			continue
		var to_local := get_global_transform().affine_inverse() * row.get_global_transform()
		_target_y = (to_local * (row.size * 0.5)).y
		return


func _flicker() -> void:
	var step := int(_t * 12.0)
	if step == _step:
		return
	_step = step
	var n := sin(float(step) * 1.7) * 0.6 + sin(float(step) * 4.3) * 0.4
	_flick = 1.0 + 0.16 * n


func _lantern_x() -> float:
	var idle := sin(_t * TAU / 3.6) * 2.0 * _lit
	return anchor.x + _swing + idle


func _place() -> void:
	if _body == null:
		return
	var core := lantern_center()
	var body_size := FRAME * SCALE
	# 灯芯在帧内 (6, 10)，放大两倍后在灯笼贴图的 (12, 20)。
	_body.position = (core - Vector2(body_size.x * 0.5, CORE_DROP)).round()
	_body.size = body_size
	var energy := _lit * (_flick + _flare * 0.85)
	var lit_frame := energy > 0.08
	_atlas.region = Rect2(FRAME.x if lit_frame else 0.0, 0.0, FRAME.x, FRAME.y)
	var pool := 168.0 + 36.0 * _flare
	_halo.visible = energy > 0.02
	_halo.size = Vector2(pool, pool)
	_halo.position = (core - _halo.size * 0.5).round()
	var a := clampf(0.34 * energy, 0.0, 0.72)
	_halo.modulate = Color(1.0, 0.62, 0.28, a)


func _light_rows() -> void:
	if _menu == null:
		return
	var origin := get_global_transform().affine_inverse()
	for item in _menu.items():
		var row := item as MenuItem
		if row == null or not row.lamp or row.size.y < 1.0:
			continue
		var to_local := origin * row.get_global_transform()
		var center_y := (to_local * (row.size * 0.5)).y
		var dist := absf(center_y - _y)
		var light := clampf(1.0 - dist / FALLOFF, 0.0, 1.0)
		light *= light
		row.set_lamp_light(light * _lit)


func _draw() -> void:
	var end := lantern_center() - Vector2(0.0, CORE_DROP)
	var drop := end.y - anchor.y
	if drop < LINK_H:
		return
	var n := int(drop / LINK_H)
	for i in n:
		var t := float(i) / float(maxi(n - 1, 1))
		var y := anchor.y + float(i) * LINK_H
		var x := roundf(lerpf(anchor.x, end.x, t))
		if i % 2 == 0:
			draw_rect(Rect2(x - 2.0, y, 6.0, 2.0), Color("#7A6258"))
			draw_rect(Rect2(x - 4.0, y + 2.0, 2.0, 8.0), Color("#4A3E44"))
			draw_rect(Rect2(x + 4.0, y + 2.0, 2.0, 8.0), Color("#241C22"))
			draw_rect(Rect2(x - 2.0, y + 10.0, 6.0, 2.0), Color("#241C22"))
		else:
			draw_rect(Rect2(x - 2.0, y, 6.0, LINK_H), Color("#4A3E44"))
			draw_rect(Rect2(x - 2.0, y, 2.0, LINK_H), Color("#7A6258"))
			draw_rect(Rect2(x + 2.0, y, 2.0, LINK_H), Color("#241C22"))
