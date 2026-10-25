extends "res://scripts/ui/title_prop.gd"
## 桥头两座火盆：独立铁盆图 + 连根逐帧火舌 + 稀疏飞火与加色光晕。
## 随进度点亮：
##   没通关任何一章 / 熄火结局 = 两盆都是冷的（炉膛压暗，只有炭里一点将熄的红）；
##   通关第一章起点第一座，第七章起点第二座，亮度随幕次递增；
##   还火结局两盆稳稳地亮着；守炉结局两盆最亮（火舌更高、光晕更大）。
## boost 是菜单聚焦「余烬竞技场」时的一次加亮（0..1，由 TitleWorld 衰减）：
## 亮着的盆更旺，冷盆也会跳起一点火。
##
## 火舌以原创16帧像素轮廓表现，普通混合保留橙红外缘。另有定长飞火池：粒子从炉口升起，
## 受浮力加速、被侧风（bridge 大厅里朝炉口的穿堂风 + 周期阵风）推着走，一边上升
## 一边从白热核心冷成锈红，最后散成几粒随风飘的烟。阵风过境时两盆火会一起歪。
##
## 摆在 TitleWorld 的 Stage 上、桥面之后、近侧栏杆（BridgeFront）之后。左侧机房
## mass_left 画到世界 x=240，视差深度 1 时指针还能再把它往右推 9px，所以火盆左缘
## 要留在 x≥256。骑士站在 x=326，两盆分立骑士两侧：左盆 272 躲开机房视差线，右盆 426 在骑士右侧。
## 节点：本体（两个炉膛 + 烟）+ Glow（飞火与光晕）+ RootedFlames = 3个。

const FURNACE := "res://assets/title/brazier_furnace.png"
const FireStrip := preload("res://scripts/fx/connected_fire_strip.gd")
## gh_furnace 是 32×96 的整座炉子（烟囱 + 炉膛 + 底座）：火盆只要下面 36 行。
const REGION_Y := 60.0
const REGION_H := 36.0
## 炉膛里那团火的底边在这 36 行里的 y。
const FLAME_AT := 12.0
const FEET_Y := 266.0
const XS: Array[float] = [272.0, 426.0]
const DEAD := Color(0.30, 0.28, 0.32)
const LIT := Color(1.45, 1.25, 1.05)

## 每盆火焰的粒子数上限。发射速率按点亮程度调，池子是定长的。
const POOL := 26
## 穿堂风：基础风 + 快慢两层起伏 + 周期阵风（正 = 朝炉口方向吹）。
const WIND_BASE := 7.0
const WIND_SWAY := 5.0
const WIND_GUST := 20.0

var boost := 0.0

var _levels: Array[float] = [0.0, 0.0]
var _body: Texture2D
## 粒子池：两盆共用一段定长数组（下标 = 盆 * POOL + 槽位）。
var _px := PackedFloat32Array()
var _py := PackedFloat32Array()
var _vx := PackedFloat32Array()
var _vy := PackedFloat32Array()
var _age := PackedFloat32Array()
var _span := PackedFloat32Array()
var _emit: Array[float] = [0.0, 0.0]
var _rng := 0x2545F491
var _wind := 0.0
var _fire: FireStrip


func _setup() -> void:
	_body = DensityTextures.load_texture(FURNACE)
	var n := POOL * XS.size()
	_px.resize(n)
	_py.resize(n)
	_vx.resize(n)
	_vy.resize(n)
	_age.resize(n)
	_span.resize(n)
	# 全部置死（age >= span = 不在场）。
	_span.fill(0.0)
	_age.fill(1.0)
	_fire = FireStrip.new()
	_fire.name = "RootedFlames"
	_fire.origins = PackedVector2Array([Vector2(XS[0], flame_base_y() + 1.0),
			Vector2(XS[1], flame_base_y() + 1.0)])
	_fire.levels = PackedFloat32Array([0.0, 0.0])
	_fire.offsets = PackedFloat32Array([0.0, 0.43])
	add_child(_fire)


func set_levels(first: float, second: float) -> void:
	_levels[0] = first
	_levels[1] = second


## 现在这座盆的有效亮度（含加亮）。0 = 没火。
func level_of(index: int) -> float:
	var base := _levels[index]
	return maxf(base * (1.0 + boost * 0.8), boost * 0.35)


func flame_base_y() -> float:
	return FEET_Y - REGION_H + FLAME_AT


## 确定性伪随机（异或移位）：截图 / 测试两轮跑出同一条火焰。
func _rand() -> float:
	_rng ^= _rng << 13
	_rng ^= _rng >> 17
	_rng ^= _rng << 5
	_rng &= 0x7FFFFFFF
	if _rng == 0:
		_rng = 0x2545F491
	return float(_rng % 10000) / 10000.0


## 侧风（px/s²）：常年的穿堂风 + 两层起伏，阵风每 ~30 秒压过来一阵。
func _wind_at(t: float) -> float:
	var sway := WIND_BASE + WIND_SWAY * sin(t * 0.37) + 2.5 * sin(t * 1.13 + 1.7)
	var gust := pow(maxf(0.0, sin(t * 0.21 + 1.3)), 6.0) * WIND_GUST
	return sway + gust


func _step(dt: float) -> void:
	_wind = _wind_at(_t)
	for i in XS.size():
		var level := clampf(level_of(i), 0.0, 1.4)
		if level > 0.04:
			# 点亮程度 → 每秒新粒子数；守炉（>1）更密更高。
			_emit[i] += 34.0 * minf(level, 1.2) * dt
			while _emit[i] >= 1.0:
				_emit[i] -= 1.0
				_spawn(i, level)
		for s in POOL:
			var p := i * POOL + s
			if _age[p] >= _span[p]:
				continue
			_age[p] += dt
			# 浮力：越烧越往上蹿；侧风 + 抖动往两边推。
			_vy[p] -= 30.0 * dt
			_vx[p] += (_wind - _vx[p] * 1.6) * 2.0 * dt
			_vx[p] += sin(_t * 6.1 + float(p) * 2.39) * 14.0 * dt
			_px[p] += _vx[p] * dt
			_py[p] += _vy[p] * dt
		_fire.levels[i] = level * minf(heat, 1.0)
	_fire.time = _t
	_fire.queue_redraw()


## 从炉口托起一粒火：初速向上，横向一点随机，寿命随点亮程度拉长（火舌更高）。
func _spawn(i: int, level: float) -> void:
	for s in POOL:
		var p := i * POOL + s
		if _age[p] < _span[p]:
			continue
		_px[p] = XS[i] + (_rand() - 0.5) * 7.0
		_py[p] = flame_base_y() + 1.0
		_vx[p] = (_rand() - 0.5) * 3.0
		_vy[p] = -(13.0 + _rand() * 9.0) * (0.75 + 0.45 * minf(level, 1.0))
		_age[p] = 0.0
		_span[p] = (0.42 + _rand() * 0.38) * (0.7 + 0.5 * minf(level, 1.0))
		return


func _draw() -> void:
	if _body == null:
		return
	for i in XS.size():
		var level := level_of(i)
		var tint := DEAD.lerp(LIT, clampf(level, 0.0, 1.0))
		draw_texture_rect_region(_body, Rect2(XS[i] - 16.0, FEET_Y - REGION_H, 32.0, REGION_H),
				Rect2(0.0, REGION_Y, 32.0, REGION_H), tint)
		if level < 0.05 and heat > 0.1:
			# 冷盆：炭里还有一点将熄未熄的红
			var glint := 0.45 + 0.35 * sin(_t * 1.7 + float(i) * 2.0)
			draw_rect(Rect2(XS[i] - 3.0, flame_base_y() + 1.0, 2.0, 1.0), em(Color(0.7, 0.18, 0.06, glint)))
			draw_rect(Rect2(XS[i] + 2.0, flame_base_y() + 2.0, 1.0, 1.0), em(Color(0.6, 0.15, 0.05, glint * 0.7)))
		elif level >= 0.05:
			# 火苗上方散开的烟：两粒，随风飘得比火远得多。
			for k in 2:
				var ph := fposmod(_t * 0.16 + float(k) * 0.53 + float(i) * 0.31, 1.0)
				var sx := XS[i] + sin(float(k) * 4.2 + _t * 0.9) * 2.0 + _wind * ph * 0.9
				var sy := flame_base_y() - 20.0 - ph * 18.0
				var fade := sin(PI * ph)
				draw_rect(Rect2(roundf(sx), roundf(sy), 2.0, 2.0),
						Color(0.16, 0.12, 0.14, 0.30 * fade * minf(level, 1.0)))


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


func _draw_overlay() -> void:
	for i in XS.size():
		var level := level_of(i)
		if level < 0.04:
			continue
		var alpha_scale := clampf(0.5 + 0.4 * level, 0.0, 1.0)
		for s in POOL:
			var p := i * POOL + s
			if _age[p] >= _span[p]:
				continue
			var t := 1.0 - _age[p] / _span[p]
			var c := _flame_color(t)
			# 炉口那几粒新火连成一片底焰；往上瘦成 1px 火舌。
			if s % 5 != 0 or t > 0.55:
				continue
			var w := 1.0
			_overlay.draw_rect(
					Rect2(roundf(_px[p] - w * 0.5), roundf(_py[p]), w, w),
					Color(c.r * lift.r, c.g * lift.g, c.b * lift.b, 0.32 * t * alpha_scale))
		var x := XS[i]
		var flick := 0.88 + 0.12 * sin(floorf(_t * 9.0) * 2.1 + float(i))
		_glow_at(Vector2(x, flame_base_y() - 8.0), 34.0 + 26.0 * clampf(level, 0.0, 1.3),
				Color(1.0, 0.55, 0.2, 0.30 * clampf(level, 0.0, 1.3) * flick))


# --- 测试 / 工具用 ------------------------------------------------------------

func levels() -> Array[float]:
	return _levels.duplicate()


func lit_count() -> int:
	var n := 0
	for level in _levels:
		if level > 0.05:
			n += 1
	return n


func brightest() -> float:
	return maxf(_levels[0], _levels[1])


## 当前侧风（截图 / 测试可读：阵风过境时火焰该往一边倒）。
func wind() -> float:
	return _wind


## 在场火焰粒子数（测试读：冷盆 = 0，点亮后 > 0）。
func flame_count() -> int:
	var n := 0
	for p in _age.size():
		if _age[p] < _span[p]:
			n += 1
	return n
