class_name TitleSparks
extends Node2D
## All the loose particles of the title hall in ONE canvas item: embers rising off
## the pit, ash falling from the roof, dust turning in the light shaft, rust specks
## (the 'give' ending), steam puffs from the vents and one-shot spark bursts.
##
## Everything lives in fixed pools (no allocation per frame) and is drawn as whole
## pixel rects / texture cells, so it stays crisp and costs one `_draw` per frame.
## It deliberately avoids Fx and GameContext.world_effects(): those parent to the
## 'game_world' group, which is the wrong viewport on the title.

enum Kind { EMBER, ASH, DUST, SPECK, SPARK }

const STEAM_SHEET := "res://assets/title/steam.png"
const STEAM_FRAMES := 6
const STEAM_SIZE := 28
const MAX_PUFFS := 10
const CAPS := [64, 28, 28, 10, 48]       # per Kind, same order as the enum
const EMBER_HOT := Color(1.0, 0.76, 0.29)
const EMBER_MID := Color(1.0, 0.55, 0.0)
const EMBER_COLD := Color(0.55, 0.27, 0.07)
const ASH_COLOR := Color(0.78, 0.73, 0.66)
const DUST_COLOR := Color(0.72, 0.86, 0.82)
const SPECK_COLORS := [Color(0.80, 0.36, 0.30), Color(0.63, 0.32, 0.18), Color(0.90, 0.60, 0.40)]

## World area particles are born in / recycled over.
var bounds := Rect2(-16.0, -16.0, 672.0, 392.0)
## Where embers are born: [pit span x0, x1, y0, y1] and the forge-mouth span.
var pit := Rect2(120.0, 350.0, 420.0, 30.0)
var mouth := Rect2(456.0, 236.0, 50.0, 28.0)
## Top-left of the beam sprite in this node's coordinates (dust follows its slopes).
var beam_origin := Vector2(104.0, 18.0)
var speck_center := Vector2(326.0, 232.0)

var _start := PackedInt32Array([0, 0, 0, 0, 0])
var _active := PackedInt32Array([0, 0, 0, 0, 0])
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _size := PackedInt32Array()
var _alive := PackedByteArray()
var _tint := PackedColorArray()

var _vents := PackedVector2Array()
var _vent_rate := 0.0
var _vent_timer := PackedFloat32Array()
var _puff_pos := PackedVector2Array()
var _puff_age := PackedFloat32Array()
var _puff_life := PackedFloat32Array()
var _puff_drift := PackedFloat32Array()
var _steam: Texture2D
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _seeded := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.seed = 20260524
	var total := 0
	for k in CAPS.size():
		_start[k] = total
		total += int(CAPS[k])
	_pos.resize(total)
	_vel.resize(total)
	_age.resize(total)
	_life.resize(total)
	_phase.resize(total)
	_size.resize(total)
	_alive.resize(total)
	_tint.resize(total)
	_puff_pos.resize(MAX_PUFFS)
	_puff_age.resize(MAX_PUFFS)
	_puff_life.resize(MAX_PUFFS)
	_puff_drift.resize(MAX_PUFFS)
	for i in MAX_PUFFS:
		_puff_age[i] = 1.0
		_puff_life[i] = 1.0
	if ResourceLoader.exists(STEAM_SHEET):
		_steam = load(STEAM_SHEET) as Texture2D


## 0..1 densities per kind (embers, ash, dust, specks). Bursts are always available.
func set_rates(embers: float, ash: float, dust: float, specks: float) -> void:
	_set_active(Kind.EMBER, embers)
	_set_active(Kind.ASH, ash)
	_set_active(Kind.DUST, dust)
	_set_active(Kind.SPECK, specks)


func set_vents(points: PackedVector2Array, rate: float) -> void:
	_vents = points
	_vent_rate = maxf(rate, 0.0)
	_vent_timer.resize(points.size())
	for i in points.size():
		_vent_timer[i] = 0.4 + 0.7 * float(i)


func active_count(kind: int) -> int:
	return _active[kind]


func live_count() -> int:
	var n := 0
	for i in _alive.size():
		n += int(_alive[i])
	return n


func puff_count() -> int:
	var n := 0
	for i in MAX_PUFFS:
		if _puff_age[i] < _puff_life[i]:
			n += 1
	return n


## One-shot spark burst (focus on a menu row, confirm flash, a lantern flare).
func burst(at: Vector2, count: int, speed: float = 60.0, color: Color = EMBER_HOT) -> void:
	var k := int(Kind.SPARK)
	var first := _start[k]
	var spawned := 0
	for i in range(first, first + int(CAPS[k])):
		if spawned >= count:
			break
		if _alive[i] != 0:
			continue
		var ang := _rng.randf_range(-PI * 0.95, -PI * 0.05)
		var spd := speed * _rng.randf_range(0.35, 1.0)
		_pos[i] = at
		_vel[i] = Vector2(cos(ang), sin(ang)) * spd
		_age[i] = 0.0
		_life[i] = _rng.randf_range(0.35, 0.8)
		_size[i] = 2 if _rng.randf() < 0.45 else 1
		_phase[i] = _rng.randf() * TAU
		_tint[i] = color
		_alive[i] = 1
		spawned += 1


func _set_active(kind: int, rate: float) -> void:
	var n := int(roundf(float(CAPS[kind]) * clampf(rate, 0.0, 1.0)))
	_active[kind] = n


func _process(delta: float) -> void:
	_t += delta
	if _pos.is_empty():
		return
	if not _seeded:
		_seeded = true
		_populate()
	_update_embers(delta)
	_update_ash(delta)
	_update_dust(delta)
	_update_specks(delta)
	_update_sparks(delta)
	_update_steam(delta)
	queue_redraw()


## First frame: scatter the standing pools over the whole scene so it never opens empty.
func _populate() -> void:
	for kind in [Kind.EMBER, Kind.ASH, Kind.DUST, Kind.SPECK]:
		var first := _start[kind]
		for j in _active[kind]:
			var i := first + j
			match kind:
				Kind.EMBER:
					_spawn_ember(i, true)
				Kind.ASH:
					_spawn_ash(i, true)
				Kind.DUST:
					_spawn_dust(i)
				Kind.SPECK:
					_spawn_speck(i)


# --- embers -----------------------------------------------------------------

func _spawn_ember(i: int, initial: bool) -> void:
	var r := _rng.randf()
	var p := Vector2.ZERO
	if r < 0.58:
		p = Vector2(_rng.randf_range(pit.position.x, pit.end.x), _rng.randf_range(pit.position.y, pit.end.y))
	elif r < 0.84:
		p = Vector2(_rng.randf_range(mouth.position.x, mouth.end.x), _rng.randf_range(mouth.position.y, mouth.end.y))
	else:
		p = Vector2(_rng.randf_range(bounds.position.x, bounds.end.x), _rng.randf_range(300.0, bounds.end.y))
	_life[i] = _rng.randf_range(3.6, 8.5)
	_age[i] = 0.0
	if initial:
		# spread the first generation up the whole hall
		_age[i] = _life[i] * _rng.randf()
		p.y -= (p.y - 30.0) * (_age[i] / _life[i]) * 0.9
	_pos[i] = p
	_vel[i] = Vector2(_rng.randf_range(-3.0, 5.0), -_rng.randf_range(11.0, 34.0))
	_phase[i] = _rng.randf() * TAU
	_size[i] = 2 if _rng.randf() < 0.4 else 1
	_alive[i] = 1


func _update_embers(delta: float) -> void:
	var k := int(Kind.EMBER)
	var first := _start[k]
	for j in int(CAPS[k]):
		var i := first + j
		if j >= _active[k]:
			_alive[i] = 0
			continue
		if _alive[i] == 0:
			_spawn_ember(i, false)
		_age[i] += delta
		var p := _pos[i]
		p.y += _vel[i].y * delta
		p.x += (_vel[i].x + sin(_t * 1.6 + _phase[i]) * 7.0) * delta
		_pos[i] = p
		if _age[i] >= _life[i] or p.y < bounds.position.y:
			_spawn_ember(i, false)


# --- ash ---------------------------------------------------------------------

func _spawn_ash(i: int, initial: bool) -> void:
	_pos[i] = Vector2(_rng.randf_range(bounds.position.x, bounds.end.x),
			_rng.randf_range(bounds.position.y, bounds.end.y) if initial else bounds.position.y)
	_vel[i] = Vector2(_rng.randf_range(-4.0, 4.0), _rng.randf_range(5.0, 15.0))
	_phase[i] = _rng.randf() * TAU
	_size[i] = 1
	_age[i] = 0.0
	_life[i] = 1.0
	var c := _tint[i]
	c.a = _rng.randf_range(0.25, 0.55)
	_tint[i] = c
	_alive[i] = 1


func _update_ash(delta: float) -> void:
	var k := int(Kind.ASH)
	var first := _start[k]
	for j in int(CAPS[k]):
		var i := first + j
		if j >= _active[k]:
			_alive[i] = 0
			continue
		if _alive[i] == 0:
			_spawn_ash(i, false)
		var p := _pos[i]
		p.y += _vel[i].y * delta
		p.x += (_vel[i].x + sin(_t * 0.9 + _phase[i]) * 5.0) * delta
		_pos[i] = p
		if p.y > bounds.end.y:
			_spawn_ash(i, false)


# --- dust in the shaft --------------------------------------------------------

func _spawn_dust(i: int) -> void:
	var dy := _rng.randf_range(24.0, 290.0)
	var xl := beam_origin.x + 22.0 + 0.25 * dy          # beam.png edges: 8 + 0.25y .. 140 + 0.28y
	var xr := beam_origin.x + 126.0 + 0.28 * dy
	_pos[i] = Vector2(_rng.randf_range(xl, xr), beam_origin.y + dy)
	_vel[i] = Vector2(_rng.randf_range(-2.5, 2.5), _rng.randf_range(-5.0, 3.0))
	_phase[i] = _rng.randf() * TAU
	_size[i] = 1 if _rng.randf() < 0.7 else 2
	_age[i] = 0.0
	_life[i] = _rng.randf_range(5.0, 11.0)
	_alive[i] = 1


func _update_dust(delta: float) -> void:
	var k := int(Kind.DUST)
	var first := _start[k]
	for j in int(CAPS[k]):
		var i := first + j
		if j >= _active[k]:
			_alive[i] = 0
			continue
		if _alive[i] == 0:
			_spawn_dust(i)
		_age[i] += delta
		var p := _pos[i]
		p += _vel[i] * delta
		p.x += sin(_t * 0.7 + _phase[i]) * 3.0 * delta
		_pos[i] = p
		if _age[i] >= _life[i]:
			_spawn_dust(i)


# --- rust specks (give ending) ----------------------------------------------------

func _spawn_speck(i: int) -> void:
	_pos[i] = speck_center + Vector2(_rng.randf_range(-46.0, 46.0), _rng.randf_range(-44.0, 26.0))
	_vel[i] = Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-6.0, -1.0))
	_phase[i] = _rng.randf() * TAU
	_size[i] = 1 if _rng.randf() < 0.75 else 2
	_age[i] = 0.0
	_life[i] = _rng.randf_range(5.0, 10.0)
	_tint[i] = SPECK_COLORS[_rng.randi() % SPECK_COLORS.size()]
	_alive[i] = 1


func _update_specks(delta: float) -> void:
	var k := int(Kind.SPECK)
	var first := _start[k]
	for j in int(CAPS[k]):
		var i := first + j
		if j >= _active[k]:
			_alive[i] = 0
			continue
		if _alive[i] == 0:
			_spawn_speck(i)
		_age[i] += delta
		var p := _pos[i]
		p += _vel[i] * delta
		p.x += sin(_t * 1.1 + _phase[i]) * 4.0 * delta
		_pos[i] = p
		if _age[i] >= _life[i]:
			_spawn_speck(i)


# --- sparks --------------------------------------------------------------------------

func _update_sparks(delta: float) -> void:
	var k := int(Kind.SPARK)
	var first := _start[k]
	for j in int(CAPS[k]):
		var i := first + j
		if _alive[i] == 0:
			continue
		_age[i] += delta
		if _age[i] >= _life[i]:
			_alive[i] = 0
			continue
		var v := _vel[i]
		v.y += 90.0 * delta
		v *= 1.0 - 1.6 * delta
		_vel[i] = v
		_pos[i] += v * delta


# --- steam ---------------------------------------------------------------------------

func _update_steam(delta: float) -> void:
	if _steam == null:
		return
	for v in _vents.size():
		_vent_timer[v] -= delta * _vent_rate
		if _vent_timer[v] > 0.0 or _vent_rate <= 0.0:
			continue
		_vent_timer[v] = _rng.randf_range(0.8, 1.7)
		for i in MAX_PUFFS:
			if _puff_age[i] >= _puff_life[i]:
				_puff_pos[i] = _vents[v] + Vector2(_rng.randf_range(-2.0, 2.0), 0.0)
				_puff_age[i] = 0.0
				_puff_life[i] = _rng.randf_range(2.2, 3.4)
				_puff_drift[i] = _rng.randf_range(2.0, 8.0)
				break
	for i in MAX_PUFFS:
		if _puff_age[i] >= _puff_life[i]:
			continue
		_puff_age[i] += delta
		var p := _puff_pos[i]
		p.y -= (13.0 + 6.0 * (_puff_age[i] / _puff_life[i])) * delta
		p.x += _puff_drift[i] * delta
		_puff_pos[i] = p


# --- drawing ---------------------------------------------------------------------------

func _draw() -> void:
	if _pos.is_empty():
		return
	_draw_steam()
	_draw_pool(Kind.ASH)
	_draw_pool(Kind.DUST)
	_draw_pool(Kind.EMBER)
	_draw_pool(Kind.SPECK)
	_draw_pool(Kind.SPARK)


func _draw_steam() -> void:
	if _steam == null:
		return
	for i in MAX_PUFFS:
		if _puff_age[i] >= _puff_life[i]:
			continue
		var f := _puff_age[i] / _puff_life[i]
		var frame := mini(int(f * float(STEAM_FRAMES)), STEAM_FRAMES - 1)
		var a := minf(f * 6.0, 1.0) * (1.0 - f) * 0.9
		var p := _puff_pos[i]
		var dest := Rect2(floorf(p.x) - STEAM_SIZE * 0.5, floorf(p.y) - STEAM_SIZE + 6.0, STEAM_SIZE, STEAM_SIZE)
		draw_texture_rect_region(_steam, dest, Rect2(frame * STEAM_SIZE, 0, STEAM_SIZE, STEAM_SIZE),
				Color(0.88, 0.80, 0.76, a * 0.8))


func _draw_pool(kind: int) -> void:
	var first := _start[kind]
	for j in int(CAPS[kind]):
		var i := first + j
		if _alive[i] == 0:
			continue
		var p := _pos[i]
		var s := _size[i]
		var rect := Rect2(floorf(p.x), floorf(p.y), s, s)
		match kind:
			Kind.EMBER:
				var f := _age[i] / _life[i]
				var c := EMBER_HOT.lerp(EMBER_MID, clampf(f * 2.0, 0.0, 1.0))
				c = c.lerp(EMBER_COLD, clampf(f * 2.0 - 1.0, 0.0, 1.0))
				var flick := 0.78 + 0.22 * sin(floorf(_t * 9.0) * 2.1 + _phase[i])
				c.a = (1.0 - maxf(f - 0.65, 0.0) / 0.35) * flick
				draw_rect(rect, c)
				if s > 1:
					draw_rect(Rect2(rect.position.x, rect.position.y + 2.0, 1, 1), Color(c.r, c.g * 0.7, c.b, c.a * 0.5))
			Kind.ASH:
				var a := _tint[i].a
				draw_rect(rect, Color(ASH_COLOR.r, ASH_COLOR.g, ASH_COLOR.b, a))
			Kind.DUST:
				var f := _age[i] / _life[i]
				var tw := 0.5 + 0.5 * sin(_t * 1.3 + _phase[i])
				var a := sin(f * PI) * (0.18 + 0.42 * tw)
				draw_rect(rect, Color(DUST_COLOR.r, DUST_COLOR.g, DUST_COLOR.b, a))
			Kind.SPECK:
				var f := _age[i] / _life[i]
				var tw := 0.55 + 0.45 * sin(_t * 1.7 + _phase[i])
				var c: Color = _tint[i]
				c.a = sin(f * PI) * tw * 0.9
				draw_rect(rect, c)
			Kind.SPARK:
				var f := _age[i] / _life[i]
				var c: Color = _tint[i]
				c = c.lerp(EMBER_MID, clampf(f * 1.5, 0.0, 1.0))
				c.a = 1.0 - f
				draw_rect(rect, c)
