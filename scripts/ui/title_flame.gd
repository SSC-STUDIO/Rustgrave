extends "res://scripts/ui/title_prop.gd"
## 单口火焰：连根的逐帧像素火舌 + 少量飞火 / 浮力 / 穿堂风，
## 体量更小，给余烬巢这类单点火源用。定长池；节点 = 本体 + Glow + RootedFlame。
##
## 火焰根部是本节点原点（y 向上为负）。burning = false 时收敛成炭里一点红。

const FireStrip := preload("res://scripts/fx/connected_fire_strip.gd")
const POOL := 14
## 与 title_braziers.gd 同一条风：常年的穿堂风 + 两层起伏 + ~30s 一阵的阵风。
const WIND_BASE := 7.0
const WIND_SWAY := 5.0
const WIND_GUST := 20.0

## 体量倍率（巢火比火盆矮一点）。
var scale01 := 0.85
var burning := true

var _px := PackedFloat32Array()
var _py := PackedFloat32Array()
var _vx := PackedFloat32Array()
var _vy := PackedFloat32Array()
var _age := PackedFloat32Array()
var _span := PackedFloat32Array()
var _emit := 0.0
var _rng := 0x1F123BB5
var _wind := 0.0
var _fire: FireStrip


func _setup() -> void:
	_px.resize(POOL)
	_py.resize(POOL)
	_vx.resize(POOL)
	_vy.resize(POOL)
	_age.resize(POOL)
	_span.resize(POOL)
	_span.fill(0.0)
	_age.fill(1.0)
	_fire = FireStrip.new()
	_fire.name = "RootedFlame"
	_fire.size_scale = scale01 * 0.8
	add_child(_fire)


## 确定性伪随机（异或移位）：截图 / 测试两轮跑出同一条火焰。
func _rand() -> float:
	_rng ^= _rng << 13
	_rng ^= _rng >> 17
	_rng ^= _rng << 5
	_rng &= 0x7FFFFFFF
	if _rng == 0:
		_rng = 0x1F123BB5
	return float(_rng % 10000) / 10000.0


func _step(dt: float) -> void:
	_wind = WIND_BASE + WIND_SWAY * sin(_t * 0.37) + 2.5 * sin(_t * 1.13 + 1.7) \
			+ pow(maxf(0.0, sin(_t * 0.21 + 1.3)), 6.0) * WIND_GUST
	if burning:
		_emit += 26.0 * scale01 * dt
		while _emit >= 1.0:
			_emit -= 1.0
			_spawn()
	for p in POOL:
		if _age[p] >= _span[p]:
			continue
		_age[p] += dt
		_vy[p] -= 28.0 * dt
		_vx[p] += (_wind - _vx[p] * 1.6) * 2.0 * dt
		_vx[p] += sin(_t * 6.1 + float(p) * 2.39) * 12.0 * dt
		_px[p] += _vx[p] * dt
		_py[p] += _vy[p] * dt
	_fire.time = _t
	_fire.size_scale = scale01 * 0.8
	_fire.levels[0] = minf(heat, 1.2) if burning else 0.0
	_fire.queue_redraw()


func _spawn() -> void:
	for p in POOL:
		if _age[p] < _span[p]:
			continue
		_px[p] = (_rand() - 0.5) * 6.0 * scale01
		_py[p] = 0.0
		_vx[p] = (_rand() - 0.5) * 3.0
		_vy[p] = -(12.0 + _rand() * 8.0) * scale01
		_age[p] = 0.0
		_span[p] = (0.38 + _rand() * 0.34) * (0.6 + 0.5 * scale01)
		return


## 火的色阶：白热核心 → 余烬 → 橙 → 锈红 → 将熄。
func _flame_color(t: float) -> Color:
	if t > 0.78:
		return Color(1.0, 0.96, 0.78)
	if t > 0.55:
		return Color(1.0, 0.76, 0.29)
	if t > 0.34:
		return Color(1.0, 0.52, 0.16)
	if t > 0.16:
		return Color(0.82, 0.32, 0.10)
	return Color(0.45, 0.16, 0.06)


func _draw() -> void:
	if not burning:
		# 巢熄了：炭里一点将熄未熄的红。
		if heat > 0.1:
			var glint := 0.45 + 0.35 * sin(_t * 1.7)
			draw_rect(Rect2(-2.0, 0.0, 2.0, 1.0), em(Color(0.7, 0.18, 0.06, glint)))
		return
	# 火苗上方散开的烟：一粒，随风飘得比火远。
	var ph := fposmod(_t * 0.16, 1.0)
	var sx := sin(_t * 0.9) * 2.0 + _wind * ph * 0.9
	draw_rect(Rect2(roundf(sx), roundf(-18.0 * scale01 - ph * 14.0), 2.0, 2.0),
			Color(0.16, 0.12, 0.14, 0.28 * sin(PI * ph)))


func _draw_overlay() -> void:
	if not burning:
		return
	for p in POOL:
		if _age[p] >= _span[p]:
			continue
		var t := 1.0 - _age[p] / _span[p]
		var c := _flame_color(t)
		# 主火舌已有连贯轮廓；粒子只保留稀疏、细小的飞火。
		if p % 4 != 0 or t > 0.55:
			continue
		var w := 1.0
		_overlay.draw_rect(Rect2(roundf(_px[p] - w * 0.5), roundf(_py[p]), w, w),
				Color(c.r * lift.r, c.g * lift.g, c.b * lift.b, 0.32 * t))
	var flick := 0.88 + 0.12 * sin(floorf(_t * 9.0) * 2.1)
	_glow_at(Vector2(0.0, -7.0 * scale01), (26.0 + 14.0 * scale01) * flick,
			Color(1.0, 0.55, 0.2, 0.34 * flick))


# --- 测试 / 工具用 ------------------------------------------------------------

func flame_count() -> int:
	var n := 0
	for p in POOL:
		if _age[p] < _span[p]:
			n += 1
	return n
