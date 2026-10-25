class_name TitleLantern
extends TitleChain
## A swaying lantern on a chain for the title hall: cold iron cage when unlit, a
## flickering point light plus an additive halo when lit. Brightness steps at
## ~12 fps like the world's torches so the flame reads as pixel-art, not a fade.

const SHEET := "res://assets/title/lantern.png"
const GLOW := "res://assets/title/glow.png"
const FRAME_W := 12
const FRAME_H := 17
const FLICKER_FPS := 12.0
## Where the glass core sits below the chain end.
const CORE := Vector2(0.0, 10.0)

var base_energy := 1.0
var light_radius := 86.0
var tint := Color(1.0, 0.68, 0.34)
## 0 = steady flame (the 'give' ending), 1 = normal flicker.
var flicker := 1.0

var _body: Sprite2D
var _halo: Sprite2D
var _light: PointLight2D
var _lit_amount := 0.0
var _lit_target := 0.0
var _flare := 0.0
var _flick := 1.0
var _step := -1
var _seed := 0.0
var _last_energy := -1.0


func _ready() -> void:
	super._ready()
	weight = false
	_seed = swing_phase * 3.7
	_body = Sprite2D.new()
	_body.name = "Body"
	_body.texture = DensityTextures.load_texture(SHEET)
	_body.hframes = 2
	_body.centered = false
	_body.offset = Vector2(-FRAME_W * 0.5, 0.0)
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_body)
	_halo = Sprite2D.new()
	_halo.name = "Halo"
	_halo.texture = DensityTextures.load_texture(GLOW)
	_halo.material = Fx.additive_mat()
	_halo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_halo.scale = Vector2.ONE * (light_radius * 0.5 / 64.0)
	_halo.visible = false
	add_child(_halo)
	_light = PointLight2D.new()
	_light.name = "Light"
	_light.texture = DensityTextures.load_texture(GLOW)
	_light.texture_scale = light_radius * 2.0 / 128.0
	_light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_light.shadow_enabled = false
	_light.energy = 0.0
	_light.enabled = false
	add_child(_light)
	_on_sway()
	_refresh(true)


func light_node() -> PointLight2D:
	return _light


func is_lit() -> bool:
	return _lit_target > 0.5


func lit_amount() -> float:
	return _lit_amount


func set_lit(on: bool, instant: bool = false) -> void:
	_lit_target = 1.0 if on else 0.0
	if instant:
		_lit_amount = _lit_target
	_refresh(true)


## A brief brightening (menu focus, intro pop). Decays on its own.
func flare(strength: float) -> void:
	if is_lit():
		_flare = maxf(_flare, strength)


func _on_sway() -> void:
	if _body == null:
		return
	var b := bottom_point()
	_body.position = b
	var core := b + CORE
	_halo.position = core
	_light.position = core


func _process(delta: float) -> void:
	super._process(delta)
	if _body == null:
		return
	if not is_equal_approx(_lit_amount, _lit_target):
		_lit_amount = move_toward(_lit_amount, _lit_target, delta * 5.0)
		_refresh(true)
	if _flare > 0.0:
		_flare = maxf(0.0, _flare - delta * 1.6)
	var step := int(_t * FLICKER_FPS + _seed)
	if step != _step:
		_step = step
		var n := sin(float(step) * 1.7 + _seed) * 0.6 + sin(float(step) * 4.3 + _seed * 2.0) * 0.4
		_flick = 1.0 + flicker * 0.18 * n
		_refresh(false)
	elif _flare > 0.0:
		_refresh(false)


func _refresh(force: bool) -> void:
	if _body == null:
		return
	var amount := _lit_amount
	var energy := base_energy * amount * (_flick + _flare * 0.9)
	if not force and is_equal_approx(energy, _last_energy):
		return
	_last_energy = energy
	_body.frame = 1 if amount > 0.08 else 0
	var on := amount > 0.01
	_light.enabled = on
	_light.energy = energy
	_light.color = tint
	_halo.visible = on
	if on:
		# the additive halo sits on the ambient-dimmed canvas, so push it up to read
		_halo.modulate = Color(tint.r, tint.g, tint.b, clampf(0.26 * energy, 0.0, 0.9))
