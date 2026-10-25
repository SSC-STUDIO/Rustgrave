extends Node2D
## 魂光：从熔河升起来的淡蓝光点——被炉约烧掉名字的人，魂还在火里。
##
## 一个固定池（16 个）、一个 _draw、加色材质（不加 PointLight2D）。放在 TitleWorld 的 Glow 层
## （不被环境色压暗）：它是光，不是被光照的东西。
##   普通：从河面慢慢浮起一小段（40–110px）就淡掉——魂还困着，上不去；
##   escape（还火结局）：一路升到屋顶豁口、顺着光柱出去——魂放走了。
## rate 决定同时有几个（0..1 × 16）；kick(n) 是一次性多放几个（菜单聚焦「离开锈墓」时）。
## 本文件不写 class_name：TitleWorld 按 preload 取用。

const CAP := 22
const RIVER_X0 := 170.0
const RIVER_X1 := 520.0
const RIVER_Y0 := 334.0
const RIVER_Y1 := 352.0
## 屋顶豁口（光柱落下来的地方）：逃出去的魂往这里飘。
const GAP_X := 232.0
const KICK_SECONDS := 4.0
const CORE := Color(0.92, 0.97, 1.0)
const HALO := Color(0.55, 0.78, 1.0)

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _size := PackedInt32Array()
var _alive := PackedByteArray()
## 0..1：菜单聚焦「离开锈墓」时 TitleWorld 推进来的一阵加亮（会自己衰减）。
var boost := 0.0

var _rate := 0.0
var _escape := false
var _extra := 0
var _extra_left := 0.0
var _t := 0.0
var _seeded := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	material = Fx.additive_mat()
	_rng.seed = 20261024
	_pos.resize(CAP)
	_vel.resize(CAP)
	_age.resize(CAP)
	_life.resize(CAP)
	_phase.resize(CAP)
	_size.resize(CAP)
	_alive.resize(CAP)


## rate：0..1（同时有几个）；escape：true = 一路升出屋顶（还火结局）。
func set_flow(new_rate: float, escape: bool) -> void:
	_rate = clampf(new_rate, 0.0, 1.0)
	if escape != _escape or _rate <= 0.0:
		# 换了走法（或一个也不要了）：现有的全部收掉，按新规矩重新出生。
		_escape = escape
		_clear()
	else:
		_escape = escape
	_seeded = false


## 一次性多放 n 个（持续 KICK_SECONDS 秒内会补位）。
func kick(n: int) -> void:
	_extra = clampi(n, 0, CAP)
	_extra_left = KICK_SECONDS


func _clear() -> void:
	for i in _alive.size():
		_alive[i] = 0


## 池里允许同时存在的魂光数（rate × 池 + 临时多放的）。
func target_count() -> int:
	var n := int(roundf(_rate * float(CAP)))
	if _extra_left > 0.0:
		n += _extra
	return clampi(n, 0, CAP)


func live_count() -> int:
	var n := 0
	for i in _alive.size():
		n += int(_alive[i])
	return n


func is_escaping() -> bool:
	return _escape


func rate() -> float:
	return _rate


## 活着的魂光里最高的一只的 y（没有 = 一个很大的数）。
func highest_y() -> float:
	var best := 100000.0
	for i in _alive.size():
		if _alive[i] != 0:
			best = minf(best, _pos[i].y)
	return best


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if _pos.is_empty():
		return
	var left := maxf(delta, 0.0)
	while left > 0.0:
		var dt := minf(left, 0.1)
		left -= dt
		_step(dt)
	queue_redraw()


func _step(dt: float) -> void:
	_t += dt
	if _extra_left > 0.0:
		_extra_left = maxf(_extra_left - dt, 0.0)
	var allowed := target_count()
	if not _seeded:
		_seeded = true
		# 第一次：把现有名额一次铺开在升起的路上，打开画面就有魂光，而不是从河面一只只冒出来。
		for i in allowed:
			if _alive[i] == 0:
				_spawn(i, true)
	for i in CAP:
		if _alive[i] == 0:
			if i < allowed:
				_spawn(i, false)
			continue
		_age[i] += dt
		var p := _pos[i]
		p += _vel[i] * dt
		p.x += sin(_t * 1.1 + _phase[i]) * 5.0 * dt
		_pos[i] = p
		if _age[i] >= _life[i]:
			_alive[i] = 0
			if i < allowed:
				_spawn(i, false)


func _spawn(i: int, initial: bool) -> void:
	var at := Vector2(_rng.randf_range(RIVER_X0, RIVER_X1), _rng.randf_range(RIVER_Y0, RIVER_Y1))
	_phase[i] = _rng.randf() * TAU
	_size[i] = 3 if _rng.randf() < 0.4 else 2
	if _escape:
		_life[i] = _rng.randf_range(9.0, 13.0)
		_vel[i] = Vector2((GAP_X - at.x) / _life[i] * 0.7, -_rng.randf_range(22.0, 30.0))
	else:
		_life[i] = _rng.randf_range(5.0, 8.0)
		_vel[i] = Vector2(_rng.randf_range(-3.0, 3.0), -_rng.randf_range(8.0, 14.0))
	_age[i] = _life[i] * _rng.randf() * 0.9 if initial else 0.0
	_pos[i] = at + _vel[i] * _age[i]
	_alive[i] = 1


func _draw() -> void:
	if _pos.is_empty():
		return
	for i in CAP:
		if _alive[i] == 0:
			continue
		var f := _age[i] / maxf(_life[i], 0.001)
		var twinkle := 0.55 + 0.45 * sin(_t * 2.6 + _phase[i])
		var a := minf(pow(maxf(sin(f * PI), 0.0), 0.65) * twinkle * (1.15 + boost * 0.6), 1.0)
		if a <= 0.02:
			continue
		var s := _size[i]
		var x := floorf(_pos[i].x)
		var y := floorf(_pos[i].y)
		draw_rect(Rect2(x - 2.0, y - 2.0, float(s + 4), float(s + 4)), Color(HALO.r, HALO.g, HALO.b, a * 0.28))
		draw_rect(Rect2(x - 1.0, y - 1.0, float(s + 2), float(s + 2)), Color(HALO.r, HALO.g, HALO.b, a * 0.45))
		draw_rect(Rect2(x, y, float(s), float(s)), Color(CORE.r, CORE.g, CORE.b, a))
		draw_rect(Rect2(x, y - 3.0, 2.0, 1.0), Color(HALO.r, HALO.g, HALO.b, a * 0.55))
		draw_rect(Rect2(x, y + float(s) + 1.0, 2.0, 1.0), Color(HALO.r, HALO.g, HALO.b, a * 0.4))
