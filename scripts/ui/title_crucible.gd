extends "res://scripts/ui/title_prop.gd"
## 吊运坩埚：沿屋架下的一条导轨往返；走到熔河上方停住、倾转、倒出一道铁水，落到河面溅火星。
##
## 画在远景（和光柱同一深度），导轨右端藏在右侧烟囱塔后面——坩埚是「从塔里取了铁水出来」的。
## 一轮约 22 秒（炉温 1.0 时）：装料 → 走向熔河 → 倾转 → 倒铁水 → 回正 → 走回去。
## 炉温低整体放慢，炉温 ≈ 0（熄火结局）停在右端不动、不发光。
##
## 铁水落到河面那一刻发 poured（TitleWorld 在那里溅火星、让炉光闪一下），倒的过程中
## 每 0.55 秒发一次 splashed（小簇火星）。节点：本体（导轨 / 小车 / 吊链 / 坩埚 / 铁水柱）
## + Glow（坩埚口的光晕、铁水柱的亮边、落点的光团）= 2 个。

signal poured(at: Vector2)
signal splashed(at: Vector2)

enum Phase { LOAD, TO_POUR, TILT, POUR, UNTILT, TO_LOAD }

const RAIL_Y := 60.0
const RAIL_X0 := 96.0
const RAIL_X1 := 604.0
## 装料位在右侧塔后面（x>550 被 MassRight 挡住）。
const LOAD_X := 572.0
## 倒铁水的位置：骑士右侧（x≈326）、两盏吊灯之间，铁水柱从屋架一直落到熔河。
const POUR_X := 352.0
const RIVER_Y := 336.0
const PIVOT_Y := 77.0
const STREAM_Y0 := PIVOT_Y + 7.0
const STREAM_SPEED := 420.0
const SPLASH_EVERY := 0.55
## 烘焙的坩埚姿态帧（tools/gen_title_props.py）：5 帧、每帧 40px，吊点在帧内的 (20, 16)。
const CUP_FRAMES := 5
const CUP_FRAME := 40
const CUP_PIVOT := Vector2(20.0, 16.0)
const T_LOAD := 2.0
const T_TO_POUR := 7.0
const T_TILT := 1.2
const T_POUR := 3.4
const T_UNTILT := 1.0
const T_TO_LOAD := 8.0
## 开屏就停在倒铁水的位置：铁水柱正在落下，几秒内就能看见落点和火星。
const START_AT := 0.0
## 坩埚口朝上时的四个角（相对吊点）与铁水面；倾转时绕吊点转（整数化后画多边形）。
const CUP: Array[Vector2] = [Vector2(-11.0, -2.0), Vector2(11.0, -2.0), Vector2(8.0, 16.0), Vector2(-8.0, 16.0)]
const SURFACE: Array[Vector2] = [Vector2(-9.0, 0.0), Vector2(9.0, 0.0), Vector2(7.0, 5.0), Vector2(-7.0, 5.0)]

var _phase: int = Phase.POUR
var _pt := START_AT
var _x := LOAD_X
var _tilt := 0.0
var _stream_top := 0.0
var _stream_bot := 0.0
var _landed := false
var _splash_t := 0.0
var _pours := 0
## 烘焙的坩埚姿态帧（缺图时为 null，_draw 不画铁体）。
var _cup_tex: Texture2D


func _setup() -> void:
	_cup_tex = load("res://assets/title/crucible_tilt.png") as Texture2D
	# 第一眼就是倾倒：坩埚已经翻过来，铁水柱从口沿往下长。不在这里发 poured，
	# 落到河面的那一帧才发，世界那边才会溅火星、让炉光闪一下。
	_phase = Phase.POUR
	_pt = 0.0
	_x = POUR_X
	_tilt = 1.0
	_stream_top = 0.0
	_stream_bot = 0.0
	_landed = false


## 1.0 = 标称速度；炉温 < 0.06 时 0（冻住）。
func speed() -> float:
	if heat < 0.06:
		return 0.0
	return clampf(heat, 0.25, 1.3)


func _duration(which: int) -> float:
	match which:
		Phase.LOAD:
			return T_LOAD
		Phase.TO_POUR:
			return T_TO_POUR
		Phase.TILT:
			return T_TILT
		Phase.POUR:
			return T_POUR
		Phase.UNTILT:
			return T_UNTILT
	return T_TO_LOAD


func _step(dt: float) -> void:
	var sp := speed()
	if sp <= 0.0:
		return
	var d := dt * sp
	_pt += d
	var dur := _duration(_phase)
	var p := clampf(_pt / dur, 0.0, 1.0)
	match _phase:
		Phase.LOAD:
			_x = LOAD_X
		Phase.TO_POUR:
			_x = lerpf(LOAD_X, POUR_X, smooth(p))
		Phase.TILT:
			_x = POUR_X
			_tilt = p
		Phase.POUR:
			_tilt = 1.0
			_stream_bot = minf(_stream_bot + STREAM_SPEED * d, stream_max())
			if not _landed and _stream_bot >= stream_max():
				_landed = true
				_pours += 1
				_splash_t = 0.0
				poured.emit(impact_point())
			elif _landed:
				_splash_t += d
				if _splash_t >= SPLASH_EVERY:
					_splash_t -= SPLASH_EVERY
					splashed.emit(impact_point())
		Phase.UNTILT:
			_tilt = 1.0 - p
			# 断流：铁水柱的上端离开坩埚口往下落。
			_stream_top = minf(_stream_top + STREAM_SPEED * d, _stream_bot)
		Phase.TO_LOAD:
			_x = lerpf(POUR_X, LOAD_X, smooth(p))
	if p >= 1.0:
		_go(_next_phase(_phase))


func _next_phase(which: int) -> int:
	return (which + 1) % Phase.size()


func _go(next: int) -> void:
	_phase = next
	_pt = 0.0
	match next:
		Phase.POUR:
			_stream_top = 0.0
			_stream_bot = 0.0
			_landed = false
			_splash_t = 0.0
		Phase.TO_LOAD:
			_tilt = 0.0
			_stream_top = 0.0
			_stream_bot = 0.0
			_landed = false


## 铁水柱的最大长度：从倾转后的坩埚口一直落到熔河面。
func stream_max() -> float:
	return RIVER_Y - STREAM_Y0


## 铁水落到河面的位置（本节点坐标）。
func impact_point() -> Vector2:
	return Vector2(POUR_X, RIVER_Y)


## 柱身上某一点的横坐标。along = 0 在壶沿，1 在河面。落点钉在 POUR_X。
func _stream_x(along: float) -> float:
	var lip := roundf(_x) + _swing() - _tilt * 10.0
	var bow := sin(along * 8.0 + _t * 6.0) * (1.0 + along)
	return lerpf(lip, float(POUR_X), along) + bow


func _moving() -> bool:
	return _phase == Phase.TO_POUR or _phase == Phase.TO_LOAD


## 行走时吊着的坩埚在链上轻轻晃 ±1px。
func _swing() -> float:
	return roundf(sin(_t * 1.3)) if _moving() and speed() > 0.0 else 0.0


func _cup_points(pad: float, source: Array[Vector2]) -> PackedVector2Array:
	var out := PackedVector2Array()
	var pivot := Vector2(roundf(_x) + _swing(), PIVOT_Y)
	var angle := -_tilt * (PI * 0.5)
	for p in source:
		var q := Vector2(p.x + signf(p.x) * pad, p.y + (pad if p.y > 1.0 else -pad))
		out.append((q.rotated(angle) + pivot).round())
	return out


func _draw() -> void:
	var rail_w := RAIL_X1 - RAIL_X0
	draw_rect(Rect2(RAIL_X0, RAIL_Y - 1.0, rail_w, 3.0), IRON_DARK)
	draw_rect(Rect2(RAIL_X0, RAIL_Y - 1.0, rail_w, 1.0), IRON)
	var tie := RAIL_X0 + 12.0
	while tie < RAIL_X1:
		draw_rect(Rect2(tie, RAIL_Y - 4.0, 2.0, 3.0), IRON_DARK)
		tie += 44.0
	var x := roundf(_x)
	# 小车
	draw_rect(Rect2(x - 6.0, RAIL_Y - 3.0, 12.0, 7.0), OUTLINE)
	draw_rect(Rect2(x - 5.0, RAIL_Y - 2.0, 10.0, 5.0), IRON)
	draw_rect(Rect2(x - 5.0, RAIL_Y - 2.0, 10.0, 1.0), IRON_LIGHT)
	# 吊链：一环一环往下（整数像素，错开半格）
	var cx := x + _swing()
	for i in 4:
		draw_rect(Rect2(cx - 1.0 + float(i % 2), RAIL_Y + 4.0 + 3.0 * float(i), 2.0, 2.0), IRON_LIGHT)
	# 坩埚铁体：烘焙的五帧倾转姿态（tools/gen_title_props.py），按倾角取最近一帧，不旋转贴图。
	if _cup_tex != null:
		var frame := clampi(roundi(_tilt * float(CUP_FRAMES - 1)), 0, CUP_FRAMES - 1)
		var origin := Vector2(roundf(_x) + _swing(), PIVOT_Y) - CUP_PIVOT
		draw_texture_rect_region(_cup_tex, Rect2(origin, Vector2(CUP_FRAME, CUP_FRAME)),
				Rect2(float(frame * CUP_FRAME), 0.0, CUP_FRAME, CUP_FRAME))
	var hot := heat01() > 0.1
	draw_colored_polygon(_cup_points(0.0, SURFACE), em(HOT) if hot else Color(0.30, 0.11, 0.09))
	# 铁水：从倾转后的壶沿落到熔河。上宽下窄，中间略弯，下端裂成铁滴。
	# 落点仍是 POUR_X / RIVER_Y，柱长算法不变。
	if _stream_bot > _stream_top:
		var y0 := STREAM_Y0 + _stream_top
		var y1 := STREAM_Y0 + _stream_bot
		var span := maxf(y1 - y0, 1.0)
		var steps := maxi(int(span / 3.0), 1)
		for i in steps:
			var along := float(i) / float(maxi(steps - 1, 1))
			var y := y0 + along * span
			var w := maxf(3.0, roundf(lerpf(7.0, 3.0, along)))
			var sx := _stream_x(along) - w * 0.5
			draw_rect(Rect2(floorf(sx), floorf(y), w, 3.0), em(HOT_DEEP.lerp(HOT, 1.0 - along * 0.35)))
			draw_rect(Rect2(floorf(sx + w * 0.5 - 1.0), floorf(y), 2.0, 3.0), em(HOT_CORE))
		if span > 28.0:
			for drop in 5:
				var phase := fposmod(_t * (80.0 + float(drop) * 13.0) + float(drop) * 18.0, span)
				if phase < span * 0.42:
					continue
				var drop_y := y0 + phase
				var drop_x := roundf(sin(_t * 3.0 + float(drop) * 2.2) * (3.0 + float(drop)))
				draw_rect(Rect2(POUR_X + drop_x, floorf(drop_y), 2.0, 2.0), em(HOT))
		if _landed:
			# 落点的飞溅：几粒会跳的亮点，比柱身更醒目
			var step := floorf(_t * 12.0)
			for spark in 8:
				var jx := sin(step * 1.9 + float(spark) * 2.3) * 11.0
				var jy := absf(sin(step * 2.7 + float(spark) * 1.1)) * 12.0
				draw_rect(Rect2(floorf(POUR_X + jx), floorf(RIVER_Y - 4.0 - jy), 2.0, 2.0), em(HOT_CORE))


func _draw_overlay() -> void:
	var h := heat01()
	if h < 0.06:
		return
	var cup_center := Vector2(roundf(_x) + _swing(), PIVOT_Y + 6.0)
	_glow_at(cup_center, 44.0 + 18.0 * _tilt, Color(1.0, 0.55, 0.2, (0.28 + 0.22 * _tilt) * h))
	if _stream_bot > _stream_top:
		var y0 := STREAM_Y0 + _stream_top
		var y1 := STREAM_Y0 + _stream_bot
		_glow_rect(Rect2(POUR_X - 7.0, y0, 14.0, y1 - y0), Color(1.0, 0.42, 0.12, 0.22 * h))
		_glow_rect(Rect2(POUR_X - 2.0, y0, 4.0, y1 - y0), Color(1.0, 0.92, 0.62, 0.55 * h))
		if _landed:
			var flick := 0.8 + 0.2 * sin(_t * 31.0)
			var ripple := 0.65 + 0.35 * sin(_t * 8.0)
			_glow_at(Vector2(POUR_X, RIVER_Y - 2.0), 110.0, Color(1.0, 0.55, 0.18, 0.62 * h * flick))
			_glow_at(Vector2(POUR_X, RIVER_Y - 6.0), 36.0, Color(1.0, 0.95, 0.7, 0.5 * h * flick))
			_glow_at(Vector2(POUR_X, RIVER_Y + 2.0), 48.0 + 18.0 * ripple,
					Color(1.0, 0.42, 0.12, 0.28 * h * ripple))


# --- 测试 / 工具用 ------------------------------------------------------------

func phase() -> int:
	return _phase


func is_pouring() -> bool:
	return _phase == Phase.POUR and _stream_bot > _stream_top


## 铁水已经落到河面了吗（POUR 阶段里）。
func has_landed() -> bool:
	return _landed


func pour_count() -> int:
	return _pours


func trolley_x() -> float:
	return _x


func tilt() -> float:
	return _tilt


func stream_length() -> float:
	return maxf(_stream_bot - _stream_top, 0.0)


## 立刻开始倾倒（跳到倒铁水的位置）；已经在倒就不动。
func force_pour() -> void:
	if _phase == Phase.LOAD or _phase == Phase.TO_POUR or _phase == Phase.TO_LOAD:
		_x = POUR_X
		_go(Phase.TILT)
