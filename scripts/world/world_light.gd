class_name WorldLight
extends PointLight2D
## Presentation point light. Hosts set `follow` / `lit`; WorldClock never owns this.
## Clock numbers stay the source of truth; this node carves, clamps, and stops leak.

const TEX_SIZE := 64.0
## ForgeShelter is 256×160. A 220 clock radius floods the boss floor.
const INDOOR_RADIUS_MAX := 112.0
## Residual coal, not a second room fill on top of WarmPool.
const HEART_RADIUS_MAX := 46.0
## Graveyard view of the remnant: doorway glow, not an indoor flood.
const INDOOR_OUTDOOR_RADIUS := 72.0

@export var follow: StringName = &""
@export var flicker: bool = false
@export var lit: bool = false
## 0 = use the follow default cap. Hosts may tighten further.
@export var radius_cap: float = 0.0
## follow = &"authored" 时的世界半径（像素）。场景氛围灯由宿主给死值，
## 相机不改它、时钟也不改它，只让 apply() 把它换算成 texture_scale。
@export var authored_radius: float = 96.0

var _flame_frame: int = 0
## Host-authored brightness for followers the clock does not drive (torch, skull, ghost).
## apply() writes the flicker back into `energy`, so the base has to be remembered
## separately: reading `energy` as the target multiplied last frame's flicker into the
## next one and every torch dimmed to black within a minute.
var _base_energy: float = -1.0
static var _radial_tight: Texture2D
static var _radial_soft: Texture2D


func _ready() -> void:
	shadow_enabled = true
	shadow_filter = Light2D.SHADOW_FILTER_NONE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_bind_presentation()
	apply(true)


func _process(_delta: float) -> void:
	apply(false)


func set_flame_frame(frame: int) -> void:
	_flame_frame = frame


func apply(snap: bool = false) -> void:
	_bind_presentation()
	var e := _present_energy()
	var r := _present_radius()
	if flicker and lit and not snap:
		e *= 0.92 + 0.16 * (float(_flame_frame % 8) / 7.0)
	if not lit:
		enabled = false
		energy = 0.0
		return
	enabled = e > 0.001
	energy = e
	texture_scale = (r * 2.0) / TEX_SIZE


func _bind_presentation() -> void:
	match follow:
		&"indoor":
			# Keep one blend operation throughout the doorway transition; only
			# energy and radius change as the atmosphere settles.
			blend_mode = Light2D.BLEND_MODE_MIX
			height = 0.32
			texture = _soft_texture()
		&"heart":
			blend_mode = Light2D.BLEND_MODE_ADD
			height = 0.22
			texture = _tight_texture()
		&"authored":
			# 场景氛围灯：宿主给死半径，不加投影，光心不外扩。
			blend_mode = Light2D.BLEND_MODE_ADD
			height = 0.20
			texture = _tight_texture()
		_:
			blend_mode = Light2D.BLEND_MODE_ADD
			# height 0 wraps every occluder; 0.40 keeps a readable nest shadow.
			height = 0.40
			texture = _tight_texture()


func _target_energy() -> float:
	if not lit:
		return 0.0
	match follow:
		&"nest":
			return WorldClock.nest_light_energy()
		&"indoor":
			var shelter := get_parent()
			if shelter != null and String(shelter.name) == "ForgeShelter":
				return WorldClock.indoor_fill_energy()
			return 0.85 if WorldClock.zone == WorldClock.Zone.INDOORS else 0.30
		&"heart":
			return WorldClock.heart_light_energy()
		_:
			if _base_energy < 0.0:
				_base_energy = energy
			return _base_energy


## Hosts that retune a free-running light after _ready() go through here.
func set_base_energy(value: float) -> void:
	_base_energy = maxf(value, 0.0)


func _present_energy() -> float:
	if not lit:
		return 0.0
	var e := _target_energy()
	if follow != &"nest":
		return e
	# ADD sits on CanvasModulate. Day luminance ~0.83 turns raw 1.35 into a white clip;
	# night already carves. Keep a readable day pool (>= 1.0) without the blowout.
	var lum := WorldClock.mood_luminance()
	var dayish := clampf((lum - 0.38) / 0.46, 0.0, 1.0)
	return e * lerpf(1.0, 0.82, dayish)


func _target_radius() -> float:
	match follow:
		&"nest":
			return WorldClock.nest_light_radius()
		&"indoor":
			return WorldClock.indoor_fill_radius()
		&"heart":
			return WorldClock.heart_light_radius()
		&"authored":
			return authored_radius
		_:
			return TEX_SIZE * texture_scale * 0.5


func _present_radius() -> float:
	var r := _target_radius()
	var cap := radius_cap
	if cap <= 0.0:
		match follow:
			&"indoor":
				cap = INDOOR_RADIUS_MAX
			&"heart":
				cap = HEART_RADIUS_MAX
	if cap > 0.0:
		r = minf(r, cap)
	if follow == &"indoor" and WorldClock.zone != WorldClock.Zone.INDOORS:
		r = minf(r, INDOOR_OUTDOOR_RADIUS)
	return r


func _tight_texture() -> Texture2D:
	if _radial_tight != null:
		return _radial_tight
	_radial_tight = _make_radial(3.0)
	return _radial_tight


func _soft_texture() -> Texture2D:
	if _radial_soft != null:
		return _radial_soft
	_radial_soft = _make_radial(2.0)
	return _radial_soft


func _make_radial(power: float) -> Texture2D:
	var size := int(TEX_SIZE)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var radius := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center) / radius
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, power)
			img.set_pixel(x, y, Color(1.0, 0.78, 0.42, a))
	return ImageTexture.create_from_image(img)
