extends Node2D
## 远景深层（FarVault，视差深度 -0.45）：
## 位于 HallFar 背景层之后，通过空气透视呈现高大拱顶骨架、两座远烟囱、高窗、
## 以及自高窗投射出的 3 道轻微摆动光柱与浮尘。
##
## 约束与规范：
## 1. 节点预算：单节点（Node2D），0 个子节点，0 盏 PointLight2D。
## 2. 栅格规范：全部顶点与尺寸均在 2px 栅格上整像素绘制（snap2）。
## 3. 空气透视：冷灰蓝调（Blue-grey tones）、提亮暗部、低对比度，与近景暖色铁桥形成强烈纵深反差。
## 4. 光柱与浮尘：双重正弦缓慢摆动，按 6fps 更新绘制命令。

# --- 调色板（空气透视：冷、亮、低对比） ---
const COL_RIB_DARK := Color(0.13, 0.16, 0.23, 0.88)       # 拱顶骨架暗侧（蓝灰）
const COL_RIB_MID := Color(0.18, 0.22, 0.30, 0.88)        # 骨架主色
const COL_RIB_LIGHT := Color(0.28, 0.35, 0.44, 0.82)      # 骨架受光棱线（高窗冷天光）
const COL_BRACING := Color(0.15, 0.19, 0.26, 0.75)        # 拱间纵梁与交叉撑杆

const COL_CHIMNEY_BODY := Color(0.13, 0.17, 0.24, 0.90)   # 远烟囱筒体
const COL_CHIMNEY_LIT := Color(0.19, 0.24, 0.33, 0.90)    # 烟囱向光面
const COL_CHIMNEY_RIM := Color(0.30, 0.38, 0.48, 0.85)    # 烟囱加劲箍与帽沿

const COL_WIN_FRAME := Color(0.10, 0.13, 0.19, 0.92)      # 高窗石/铁窗框
const COL_WIN_GLASS_HALO := Color(0.32, 0.45, 0.56, 0.30) # 高窗外圈光晕
const COL_WIN_GLASS := Color(0.48, 0.64, 0.74, 0.65)      # 高窗透光玻璃（苍青）
const COL_WIN_GLASS_CORE := Color(0.72, 0.85, 0.92, 0.85) # 高窗白亮核心

const COL_SHAFT_PENUMBRA := Color(0.52, 0.68, 0.78, 0.026) # 光柱外层柔边
const COL_SHAFT_BODY := Color(0.64, 0.78, 0.88, 0.052)     # 光柱主体
const COL_SHAFT_CORE := Color(0.80, 0.90, 0.96, 0.082)     # 光柱内层高光
const COL_SHAFT_RAY := Color(0.90, 0.95, 1.0, 0.11)        # 中心细亮束

const COL_MOTE := Color(0.86, 0.94, 1.0, 0.55)             # 漂浮微尘

# --- 高窗规格 [中心X, 拱顶Y, 窗台Y, 宽度] ---
const WINDOWS: Array = [
	[164.0, 36.0, 96.0, 22.0], # 左窗 (Window 0)
	[276.0, 26.0, 94.0, 26.0], # 中左主天窗 (Window 1)
	[464.0, 38.0, 92.0, 20.0], # 右窗 (Window 2)
]

# --- 光柱规格 [来源窗索引, 基础倾角(rad), 长度, 顶宽, 底宽, 强度权重, 谐波1(A, w, phi), 谐波2(A, w, phi)] ---
const SHAFTS: Array = [
	# Shaft 0: 来源于 Window 0，稍向右偏斜 ~16度
	[0, 0.28, 224.0, 18.0, 56.0, 0.85, Vector3(0.032, 0.16, 0.0), Vector3(0.010, 0.41, 1.2)],
	# Shaft 1: 来源于 Window 1，主光柱，微倾 ~11.5度
	[1, 0.20, 246.0, 22.0, 68.0, 1.00, Vector3(0.036, 0.19, 2.1), Vector3(0.012, 0.47, 0.5)],
	# Shaft 2: 来源于 Window 2，右侧光柱，~8度
	[2, 0.14, 212.0, 16.0, 48.0, 0.75, Vector3(0.028, 0.14, 4.3), Vector3(0.009, 0.38, 2.8)],
]

# --- 浮尘预设 [所属光柱, 初始进度(0..1), 横向偏移(-1..1), 漂移速度, 摆幅, 漂移频, 闪烁频] ---
const MOTES: Array = [
	[0, 0.15, -0.40, 0.025, 2.0, 1.1, 1.8],
	[0, 0.35,  0.30, 0.018, 3.0, 0.8, 2.2],
	[0, 0.55, -0.20, 0.030, 2.5, 1.4, 1.5],
	[0, 0.75,  0.50, 0.022, 2.0, 0.9, 2.6],
	[0, 0.90, -0.10, 0.015, 3.5, 1.2, 1.9],
	[1, 0.12,  0.20, 0.028, 2.5, 1.0, 2.1],
	[1, 0.25, -0.50, 0.020, 3.0, 1.3, 1.7],
	[1, 0.38,  0.10, 0.032, 2.0, 0.7, 2.4],
	[1, 0.48,  0.60, 0.019, 3.5, 1.2, 1.6],
	[1, 0.62, -0.30, 0.026, 2.5, 0.9, 2.8],
	[1, 0.72,  0.40, 0.022, 3.0, 1.1, 2.0],
	[1, 0.85, -0.15, 0.030, 2.0, 1.5, 1.9],
	[1, 0.95,  0.25, 0.017, 3.5, 0.8, 2.3],
	[2, 0.18, -0.35, 0.024, 2.0, 1.2, 1.8],
	[2, 0.40,  0.45, 0.021, 3.0, 0.9, 2.5],
	[2, 0.58, -0.10, 0.029, 2.5, 1.4, 1.6],
	[2, 0.78,  0.30, 0.018, 2.0, 1.0, 2.2],
	[2, 0.88, -0.45, 0.025, 3.5, 1.3, 1.7],
]

var _t: float = 0.0
var _cloud: float = 1.0
var _step := -1
var _quad_buffer := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	_t += delta
	var step := int(_t * 6.0)
	if step == _step:
		return
	_step = step
	queue_redraw()


## 外部光照/云影调节接缝（TitleWorld 调度）
func set_cloud(cloud: float) -> void:
	_cloud = clampf(cloud, 0.0, 1.0)


## 2px 栅格对齐
static func snap2(v: Vector2) -> Vector2:
	return Vector2(roundf(v.x * 0.5) * 2.0, roundf(v.y * 0.5) * 2.0)


static func snap2_f(v: float) -> float:
	return roundf(v * 0.5) * 2.0


func _draw() -> void:
	_draw_chimneys()
	_draw_windows()
	_draw_vault_ribs()
	_draw_light_shafts()
	_draw_dust_motes()


# ----------------------------------------------------------------- 远烟囱 -------

func _draw_chimneys() -> void:
	# 烟囱 1：左侧 x=112，耸立于齿轮与机房空隙深处
	_draw_single_chimney(112.0, 22.0, 230.0, 12.0, 18.0, [64.0, 114.0, 168.0])
	# 烟囱 2：右侧 x=528，高插于炉口后上方穹顶
	_draw_single_chimney(528.0, 14.0, 230.0, 14.0, 20.0, [54.0, 106.0, 162.0])


func _draw_single_chimney(cx: float, top_y: float, bot_y: float, w_top: float, w_bot: float, hoops: Array) -> void:
	var hw_top := w_top * 0.5
	var hw_bot := w_bot * 0.5
	# 筒体本体多边形（梯形）
	var p0 := snap2(Vector2(cx - hw_top, top_y + 4.0))
	var p1 := snap2(Vector2(cx + hw_top, top_y + 4.0))
	var p2 := snap2(Vector2(cx + hw_bot, bot_y))
	var p3 := snap2(Vector2(cx - hw_bot, bot_y))
	draw_colored_polygon(PackedVector2Array([p0, p1, p2, p3]), COL_CHIMNEY_BODY)

	# 向光棱线（右侧 2px 提亮）
	draw_line(p1, p2, COL_CHIMNEY_LIT, 2.0)

	# 顶部加宽喇叭帽口
	var cap_hw := hw_top + 3.0
	draw_rect(Rect2(snap2(Vector2(cx - cap_hw, top_y)), snap2(Vector2(cap_hw * 2.0, 4.0))), COL_CHIMNEY_RIM)
	draw_rect(Rect2(snap2(Vector2(cx - cap_hw, top_y + 1.0)), snap2(Vector2(cap_hw * 2.0, 2.0))), COL_CHIMNEY_LIT)

	# 加劲环箍 (Reinforcing Hoops)
	for hy in hoops:
		var t := (float(hy) - top_y) / (bot_y - top_y)
		var cur_hw := lerpf(hw_top, hw_bot, t) + 1.5
		var hoop_rect := Rect2(snap2(Vector2(cx - cur_hw, float(hy))), snap2(Vector2(cur_hw * 2.0, 3.0)))
		draw_rect(hoop_rect, COL_CHIMNEY_RIM)


# ----------------------------------------------------------------- 高拱窗 -------

func _draw_windows() -> void:
	for win in WINDOWS:
		var cx: float = win[0]
		var arch_top_y: float = win[1]
		var sill_y: float = win[2]
		var w: float = win[3]
		var hw := w * 0.5
		var spring_y := arch_top_y + (sill_y - arch_top_y) * 0.35

		# 1. 外围柔光晕 (Outer Halo)
		var halo_rect := Rect2(snap2(Vector2(cx - hw - 4.0, arch_top_y - 2.0)), snap2(Vector2(w + 8.0, sill_y - arch_top_y + 6.0)))
		draw_rect(halo_rect, COL_WIN_GLASS_HALO)

		# 2. 窗体轮廓与玻璃底色 (Window Body)
		var win_rect := Rect2(snap2(Vector2(cx - hw, spring_y)), snap2(Vector2(w, sill_y - spring_y)))
		draw_rect(win_rect, COL_WIN_GLASS)

		# 3. 尖拱顶 (Pointed Arch Head)
		var arch_pts := PackedVector2Array()
		arch_pts.append(snap2(Vector2(cx - hw, spring_y)))
		arch_pts.append(snap2(Vector2(cx - hw * 0.5, arch_top_y + 4.0)))
		arch_pts.append(snap2(Vector2(cx, arch_top_y)))
		arch_pts.append(snap2(Vector2(cx + hw * 0.5, arch_top_y + 4.0)))
		arch_pts.append(snap2(Vector2(cx + hw, spring_y)))
		draw_colored_polygon(arch_pts, COL_WIN_GLASS)

		# 4. 玻璃明亮中心带 (Luminous Glass Core)
		var core_hw := hw * 0.5
		draw_rect(Rect2(snap2(Vector2(cx - core_hw, spring_y + 2.0)), snap2(Vector2(core_hw * 2.0, sill_y - spring_y - 4.0))), COL_WIN_GLASS_CORE)

		# 5. 窗棂与格栅 (Stone Tracery & Mullion/Transom)
		# 窗框外围 (2px)
		draw_polyline(arch_pts, COL_WIN_FRAME, 2.0)
		draw_line(snap2(Vector2(cx - hw, spring_y)), snap2(Vector2(cx - hw, sill_y)), COL_WIN_FRAME, 2.0)
		draw_line(snap2(Vector2(cx + hw, spring_y)), snap2(Vector2(cx + hw, sill_y)), COL_WIN_FRAME, 2.0)
		# 突出窗台 (Sill ledge)
		draw_rect(Rect2(snap2(Vector2(cx - hw - 3.0, sill_y)), snap2(Vector2(w + 6.0, 3.0))), COL_WIN_FRAME)
		# 中竖窗棂 (Central Mullion)
		draw_line(snap2(Vector2(cx, arch_top_y + 2.0)), snap2(Vector2(cx, sill_y)), COL_WIN_FRAME, 2.0)
		# 横隔横梁 (Transoms)
		draw_line(snap2(Vector2(cx - hw, spring_y)), snap2(Vector2(cx + hw, spring_y)), COL_WIN_FRAME, 2.0)
		var mid_transom := (spring_y + sill_y) * 0.5
		draw_line(snap2(Vector2(cx - hw, mid_transom)), snap2(Vector2(cx + hw, mid_transom)), COL_WIN_FRAME, 2.0)


# ------------------------------------------------------------- 拱顶肋架与骨骼 ---

func _draw_vault_ribs() -> void:
	# 5 道主拱肋分布在天穹，纵贯视口跨度
	var rib_spans := [
		Vector3(-36.0, 126.0, 24.0), # Span X0, X1, Apex Y
		Vector3(126.0, 276.0, 16.0),
		Vector3(276.0, 442.0, 14.0),
		Vector3(442.0, 582.0, 18.0),
		Vector3(582.0, 688.0, 26.0),
	]
	var spring_y := 148.0
	var pier_bot_y := 228.0

	for span in rib_spans:
		var x0: float = span.x
		var x1: float = span.y
		var apex_y: float = span.z
		var apex_x := (x0 + x1) * 0.5

		# 尖拱肋多段线构建
		var rib_outer := PackedVector2Array()
		var rib_inner := PackedVector2Array()
		var steps := 8
		for i in range(steps + 1):
			var s := float(i) / float(steps)
			var rx := lerpf(x0, apex_x, s)
			var ry := apex_y + (spring_y - apex_y) * pow(1.0 - s, 1.45)
			rib_outer.append(snap2(Vector2(rx, ry)))
			rib_inner.append(snap2(Vector2(rx, ry + 3.0)))
		for i in range(1, steps + 1):
			var s := float(i) / float(steps)
			var rx := lerpf(apex_x, x1, s)
			var ry := apex_y + (spring_y - apex_y) * pow(s, 1.45)
			rib_outer.append(snap2(Vector2(rx, ry)))
			rib_inner.append(snap2(Vector2(rx, ry + 3.0)))

		# 绘制拱肋（外缘、内缘与厚度）
		draw_polyline(rib_inner, COL_RIB_DARK, 2.0)
		draw_polyline(rib_outer, COL_RIB_MID, 2.0)
		# 拱顶高光棱线
		draw_polyline(rib_outer, COL_RIB_LIGHT, 1.0)

		# 拱座下垂柱身 (Pier Wall)
		draw_line(snap2(Vector2(x0, spring_y)), snap2(Vector2(x0, pier_bot_y)), COL_RIB_MID, 3.0)
		draw_line(snap2(Vector2(x0 + 1.0, spring_y)), snap2(Vector2(x0 + 1.0, pier_bot_y)), COL_RIB_LIGHT, 1.0)

	# 顶部纵向主脊梁 (Longitudinal Ridge Beam)
	draw_line(snap2(Vector2(-48.0, 16.0)), snap2(Vector2(688.0, 16.0)), COL_BRACING, 2.0)
	draw_line(snap2(Vector2(-48.0, 17.0)), snap2(Vector2(688.0, 17.0)), COL_RIB_LIGHT, 1.0)

	# 中层横撑拉梁与交叉桁架 (Tie-Beams & Lattice)
	draw_line(snap2(Vector2(-48.0, 102.0)), snap2(Vector2(688.0, 102.0)), COL_BRACING, 2.0)
	draw_line(snap2(Vector2(-48.0, 142.0)), snap2(Vector2(688.0, 142.0)), COL_BRACING, 2.0)
	for x in range(-32, 680, 48):
		draw_line(snap2(Vector2(float(x), 102.0)), snap2(Vector2(float(x + 24), 142.0)), COL_BRACING, 1.0)
		draw_line(snap2(Vector2(float(x + 24), 102.0)), snap2(Vector2(float(x), 142.0)), COL_BRACING, 1.0)


# ------------------------------------------------------------- 摆动光柱与浮尘 ---

func _draw_light_shafts() -> void:
	for shaft in SHAFTS:
		var win_idx: int = shaft[0]
		var theta_base: float = shaft[1]
		var length: float = shaft[2]
		var w_top: float = shaft[3]
		var w_bot: float = shaft[4]
		var weight: float = shaft[5]
		var h1: Vector3 = shaft[6]
		var h2: Vector3 = shaft[7]

		var win = WINDOWS[win_idx]
		var p_top := Vector2(win[0], win[2]) # 从窗台发出

		# 双谐波摆角计算 (Dual-Harmonic Sine Oscillation)
		var theta := theta_base + h1.x * sin(_t * h1.y + h1.z) + h2.x * sin(_t * h2.y + h2.z)
		# 强度微幅呼吸
		var breathe := (0.88 + 0.12 * sin(_t * 0.22 + float(win_idx) * 1.7)) * weight * _cloud

		var dir := Vector2(sin(theta), cos(theta))
		var norm := Vector2(dir.y, -dir.x) # 法向量
		var p_bot := p_top + dir * length

		# 1. 外层柔和半影 (Outer Penumbra Quad)
		_draw_beam_quad(p_top, p_bot, norm, w_top * 1.35, w_bot * 1.25, Color(COL_SHAFT_PENUMBRA.r, COL_SHAFT_PENUMBRA.g, COL_SHAFT_PENUMBRA.b, COL_SHAFT_PENUMBRA.a * breathe))
		# 2. 主体积光柱 (Main Body Quad)
		_draw_beam_quad(p_top, p_bot, norm, w_top, w_bot, Color(COL_SHAFT_BODY.r, COL_SHAFT_BODY.g, COL_SHAFT_BODY.b, COL_SHAFT_BODY.a * breathe))
		# 3. 核心亮轴 (Core Quad)
		_draw_beam_quad(p_top, p_bot, norm, w_top * 0.45, w_bot * 0.40, Color(COL_SHAFT_CORE.r, COL_SHAFT_CORE.g, COL_SHAFT_CORE.b, COL_SHAFT_CORE.a * breathe))
		# 4. 中心天光脊线 (Center Ray Line)
		draw_line(snap2(p_top), snap2(p_bot), Color(COL_SHAFT_RAY.r, COL_SHAFT_RAY.g, COL_SHAFT_RAY.b, COL_SHAFT_RAY.a * breathe), 2.0)


func _draw_beam_quad(p_top: Vector2, p_bot: Vector2, norm: Vector2, wt: float, wb: float, col: Color) -> void:
	if col.a <= 0.002:
		return
	var hwt := wt * 0.5
	var hwb := wb * 0.5
	_quad_buffer[0] = snap2(p_top - norm * hwt)
	_quad_buffer[1] = snap2(p_top + norm * hwt)
	_quad_buffer[2] = snap2(p_bot + norm * hwb)
	_quad_buffer[3] = snap2(p_bot - norm * hwb)
	draw_colored_polygon(_quad_buffer, col)


func _draw_dust_motes() -> void:
	for mote in MOTES:
		var shaft_idx: int = mote[0]
		var u0: float = mote[1]
		var v_lat: float = mote[2]
		var speed: float = mote[3]
		var drift_amp: float = mote[4]
		var drift_freq: float = mote[5]
		var twinkle_freq: float = mote[6]

		var shaft = SHAFTS[shaft_idx]
		var win = WINDOWS[int(shaft[0])]
		var p_top := Vector2(win[0], win[2])
		var theta_base: float = shaft[1]
		var length: float = shaft[2]
		var w_top: float = shaft[3]
		var w_bot: float = shaft[4]
		var h1: Vector3 = shaft[6]
		var h2: Vector3 = shaft[7]

		var theta := theta_base + h1.x * sin(_t * h1.y + h1.z) + h2.x * sin(_t * h2.y + h2.z)
		var dir := Vector2(sin(theta), cos(theta))
		var norm := Vector2(dir.y, -dir.x)
		var p_bot := p_top + dir * length

		# 沿光柱运动进度 (0..1 循环循环)
		var prog := fposmod(u0 - _t * speed, 1.0)
		var cur_center := p_top.lerp(p_bot, prog)
		var cur_w := lerpf(w_top, w_bot, prog)

		# 横向正弦轻晃
		var lat_offset := v_lat * 0.5 * cur_w + drift_amp * sin(_t * drift_freq + float(shaft_idx))
		var mote_pos := snap2(cur_center + norm * lat_offset)

		# 边缘与端点羽化 + 闪烁 (Edge fade & Twinkle)
		var edge_fade := sin(prog * PI) * (1.0 - absf(v_lat) * 0.7)
		var twinkle := 0.6 + 0.4 * sin(_t * twinkle_freq + u0 * 10.0)
		var alpha := COL_MOTE.a * edge_fade * twinkle * _cloud

		if alpha > 0.04:
			draw_rect(Rect2(mote_pos, Vector2(2.0, 2.0)), Color(COL_MOTE.r, COL_MOTE.g, COL_MOTE.b, alpha))


# ---------------------------------------------------------------- 查询接口 -------

func light_shaft_count() -> int:
	return SHAFTS.size()


func chimney_count() -> int:
	return 2


func window_count() -> int:
	return WINDOWS.size()
