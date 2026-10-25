class_name PendulumHazard
extends Node2D
## 摆锤：钟舌 / 铁锤吊在一根链上来回摆（钟楼、铸钟厅、压碎机走廊）。
##
## 摆动是正弦、全程看得见——读招就是画面本身，所以没有额外预警；但相位出生即定、
## 摆幅 / 周期有上下限，保证存在可通过的窗口：
##   · 下摆到最低点时最快，两端最慢（骑士在摆端一侧通过最安全）；
##   · 每次摆过最低点重新武装一次判定（同一遍最多伤一次，冲刺 i-frames 可穿过）；
##   · 过场锁玩家时整条时间线冻结并收刀。
## 原点是吊点（顶端）；判定体是链端的一颗球。纯关卡机关：不写存档、不改玩家公式。

signal turned
signal passed_bottom

const GROUP := &"hazards"
const MIN_PERIOD := 1.8
const MAX_SWING_DEG := 70.0

@export_enum("clapper", "mace") var skin: String = "clapper"
@export var length: float = 96.0
@export var swing_deg: float = 52.0
@export var period: float = 3.2
@export_range(0.0, 1.0) var phase: float = 0.0
@export var head_radius: float = 10.0
@export var damage: int = 1
@export var hint_id: StringName = &"pendulum"

var _t := 0.0
var _vt := 0.0
var _hitbox: Hitbox
var _shape: CollisionShape2D
## 已经过了几个半周期（每个半周期开头就是一次过最低点）/ 几个摆端（每隔半周期一次）。
var _half_index := 0
var _turn_index := 0
var _armed := false
var _hold := false
var _on_screen := true


func _ready() -> void:
	add_to_group(GROUP)
	set_meta("hazard_kind", "pendulum")
	period = maxf(MIN_PERIOD, period)
	swing_deg = clampf(swing_deg, 8.0, MAX_SWING_DEG)
	_t = phase * period
	_build_hitbox()
	_build_notifier()
	if hint_id != &"":
		HazardFx.attach_hint(self, hint_id, danger_local_rect(), Vector2(96.0, 24.0))
	_half_index = _half_of(_t)
	_turn_index = _turn_of(_t)
	_sync_head()
	_arm(_direction_at(_t))
	queue_redraw()


## t 时刻已经过了几个半周期（0 = 第一次过最低点之前）。
func _half_of(t: float) -> int:
	return int(floor(t / (period * 0.5)))


## 摆端出现在 period/4 + k·period/2：这个序号每变一次就是到了一端。
func _turn_of(t: float) -> int:
	return int(floor((t - period * 0.25) / (period * 0.5)))


## 摆动方向：+1 向右，-1 向左（cos 的符号，过最低点时是 ±1）。
func _direction_at(t: float) -> float:
	var c := cos(TAU * t / period)
	return 1.0 if c >= 0.0 else -1.0


# --------------------------------------------------------------------------
# 摆动读数（纯函数；测试 / bot / LevelSanity 读这里）
# --------------------------------------------------------------------------

func angle_at(t: float) -> float:
	return deg_to_rad(swing_deg) * sin(TAU * t / maxf(MIN_PERIOD, period))


## 链端球心（节点本地坐标）；角度 0 = 垂直向下。
func head_local_at(t: float) -> Vector2:
	var a := angle_at(t)
	return Vector2(sin(a) * length, cos(a) * length)


func head_global_at(t: float) -> Vector2:
	return global_position + head_local_at(t)


func head_x_at(t: float) -> float:
	return head_global_at(t).x


## 摆动范围（节点本地坐标）：球心扫过的包围盒再加半径。
func danger_local_rect() -> Rect2:
	var amax := deg_to_rad(clampf(swing_deg, 8.0, MAX_SWING_DEG))
	var reach_x := sin(amax) * length
	var low_y := length
	var high_y := cos(amax) * length
	return Rect2(-reach_x - head_radius, high_y - head_radius,
			reach_x * 2.0 + head_radius * 2.0, low_y - high_y + head_radius * 2.0)


func danger_rect() -> Rect2:
	var local := danger_local_rect()
	return Rect2(global_position + local.position, local.size)


## 时刻 t 球心是否落在竖条 [x0, x1] 里（bot 判断"现在能不能过"）。
func head_over(x0: float, x1: float, t: float) -> bool:
	var x := head_x_at(t)
	return x >= minf(x0, x1) - head_radius and x <= maxf(x0, x1) + head_radius


func clock() -> float:
	return _t


func head_position() -> Vector2:
	return head_local_at(_t)


# --------------------------------------------------------------------------
# 构建 / 逐帧
# --------------------------------------------------------------------------

func _build_hitbox() -> void:
	_hitbox = Hitbox.new()
	_hitbox.name = "PendulumHitbox"
	_hitbox.damage = maxi(1, damage)
	_hitbox.team = &"enemy"
	_hitbox.blow = &"heavy"
	_shape = CollisionShape2D.new()
	_shape.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = head_radius
	_shape.shape = circle
	_hitbox.add_child(_shape)
	add_child(_hitbox)


func _build_notifier() -> void:
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.name = "OnScreen"
	notifier.rect = danger_local_rect().merge(Rect2(-6.0, -6.0, 12.0, 12.0)).grow(24.0)
	notifier.screen_entered.connect(func() -> void:
		_on_screen = true
		queue_redraw())
	notifier.screen_exited.connect(func() -> void: _on_screen = false)
	add_child(notifier)


func _physics_process(delta: float) -> void:
	tick(delta)


## 推进 delta 秒（测试可直接驱动）。
func tick(delta: float) -> void:
	if Director != null and Director.is_input_locked():
		if not _hold:
			_hold = true
			if _hitbox != null:
				_hitbox.monitoring = false
		return
	if _hold:
		_hold = false
		if _hitbox != null and _armed:
			_hitbox.monitoring = true
	_t += delta
	_vt += delta
	_sync_head()
	var turn := _turn_of(_t)
	if turn != _turn_index:
		_turn_index = turn
		turned.emit()
	var half := _half_of(_t)
	if half != _half_index:
		_half_index = half
		# 过最低点：重新武装（朝摆动方向推），并出一声沉重的风声。
		_arm(_direction_at(_t))
		HazardFx.play("pendulum", "fire", head_global_at(_t), -11.0)
		passed_bottom.emit()
	if _on_screen:
		queue_redraw()


func _sync_head() -> void:
	if _hitbox != null:
		_hitbox.position = head_local_at(_t)


func _arm(direction: float) -> void:
	if _hitbox == null:
		return
	_armed = true
	_hitbox.damage = maxi(1, damage)
	_hitbox.arm(Vector2(direction * 150.0, -90.0))
	if _hold:
		_hitbox.monitoring = false


# --------------------------------------------------------------------------
# 绘制
# --------------------------------------------------------------------------

func _draw() -> void:
	if not _on_screen:
		return
	var head := head_local_at(_t)
	# 吊点支架
	HazardFx.px_rect(self, Rect2(-6.0, -4.0, 12.0, 5.0), Color(0.2, 0.17, 0.15))
	HazardFx.px_rect(self, Rect2(-6.0, -4.0, 12.0, 1.0), Color(0.42, 0.34, 0.27))
	# 链：每 5px 一环，明暗交替
	var steps := maxi(2, int(head.length() / 5.0))
	for i in steps:
		var p := head * (float(i) / float(steps))
		var c := Color(0.36, 0.3, 0.26) if i % 2 == 0 else Color(0.2, 0.17, 0.15)
		HazardFx.px_rect(self, Rect2(p.x - 1.0, p.y - 1.0, 2.0, 3.0), c)
	# 拖影：两帧前、四帧前的球位置，半透明
	for k in 2:
		var ghost := head_local_at(_t - 0.035 * float(k + 1))
		_draw_head(ghost, 0.22 - 0.1 * float(k))
	_draw_head(head, 1.0)


func _draw_head(center: Vector2, alpha: float) -> void:
	var r := head_radius
	if skin == "mace":
		var iron := Color(0.3, 0.28, 0.27, alpha)
		var light := Color(0.58, 0.54, 0.5, alpha)
		HazardFx.px_rect(self, Rect2(center.x - r, center.y - r * 0.6, r * 2.0, r * 1.2), iron)
		HazardFx.px_rect(self, Rect2(center.x - r * 0.6, center.y - r, r * 1.2, r * 2.0), iron)
		HazardFx.px_rect(self, Rect2(center.x - r * 0.5, center.y - r * 0.6, r * 0.5, r * 0.5), light)
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				HazardFx.px_rect(self, Rect2(center.x + sx * r * 0.9 - 1.0, center.y + sy * r * 0.9 - 1.0, 3.0, 3.0),
						Color(0.72, 0.66, 0.58, alpha))
	else:
		var bronze := Color(0.62, 0.45, 0.22, alpha)
		var light := Color(0.92, 0.74, 0.36, alpha)
		var dark := Color(0.28, 0.18, 0.09, alpha)
		HazardFx.px_rect(self, Rect2(center.x - r * 0.5, center.y - r, r, r * 0.5), bronze)
		HazardFx.px_rect(self, Rect2(center.x - r, center.y - r * 0.5, r * 2.0, r * 1.2), bronze)
		HazardFx.px_rect(self, Rect2(center.x - r * 0.7, center.y + r * 0.6, r * 1.4, r * 0.5), dark)
		HazardFx.px_rect(self, Rect2(center.x - r, center.y - r * 0.5, 3.0, r * 1.2), light)
		HazardFx.px_rect(self, Rect2(center.x + r - 3.0, center.y - r * 0.5, 3.0, r * 1.2), dark)


## 球头在完整时段内不经过世界 x 区间；缺省为吊点下方14px宽的通道。
## 计算端点和所有摆端，避免只采样首尾而漏过中途的横扫。竖向净空由调用方检查。
func safe_window(duration: float = 0.0, x0: float = NAN, x1: float = NAN) -> bool:
	if is_nan(x0):
		x0 = global_position.x - 7.0
	if is_nan(x1):
		x1 = global_position.x + 7.0
	var span := maxf(0.0, duration)
	var cycle := maxf(MIN_PERIOD, period)
	var last := _t + minf(span, cycle)
	var lo := minf(head_x_at(_t), head_x_at(last))
	var hi := maxf(head_x_at(_t), head_x_at(last))
	var turn := ceili((_t - cycle * 0.25) / (cycle * 0.5))
	var turn_time := cycle * 0.25 + float(turn) * cycle * 0.5
	while turn_time <= last:
		var x := head_x_at(turn_time)
		lo = minf(lo, x)
		hi = maxf(hi, x)
		turn_time += cycle * 0.5
	return hi < minf(x0, x1) - head_radius or lo > maxf(x0, x1) + head_radius
