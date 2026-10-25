class_name ConveyorBelt
extends SolidPlatform
## 传送带：一块会把站在上面的人（骑士和敌人）带着走的台面。
##
## 继承 SolidPlatform（皮肤 / 碰撞 / 遮光 / LevelSanity 台面统计都照旧），用
## `constant_linear_velocity` 让引擎把平台速度传给 CharacterBody2D，不碰玩家公式。
## `flip_period > 0` 时每隔这么久反向一次（中间留 0.6s 停转，方向变化先有"咔"的预兆）。
## 带速不超过骑士跑速的一半：顺着它是加速，逆着它要多走几步，不是跑步机。

const GROUP := &"hazards"
const MAX_SPEED := 54.0
const STOP_TIME := 0.6
const STRIPE := 8.0

## 像素 / 秒；正 = 向右。
@export var speed: float = 36.0
## 反向周期（秒，0 = 永不反向）。
@export var flip_period: float = 0.0
@export_range(0.0, 1.0) var phase: float = 0.0
@export var hint_id: StringName = &"conveyor"

var _t := 0.0
var _vt := 0.0
var _stripes: Node2D


func _ready() -> void:
	super._ready()
	add_to_group(GROUP)
	set_meta("hazard_kind", "conveyor")
	speed = clampf(speed, -MAX_SPEED, MAX_SPEED)
	_t = phase * maxf(0.0, flip_period) * 2.0
	_build_stripes()
	constant_linear_velocity = Vector2(velocity_at(_t), 0.0)
	if hint_id != &"":
		HazardFx.attach_hint(self, hint_id, Rect2(0.0, -28.0, size.x, 28.0), Vector2(96.0, 36.0))


## 时刻 t 的带速（像素/秒，含方向）。
func velocity_at(t: float) -> float:
	if flip_period <= 0.01:
		return speed
	var cycle := flip_period * 2.0
	var c := fposmod(t, cycle)
	var half := fposmod(c, flip_period)
	# 每个半周期的最后 STOP_TIME 秒停转，随后反向。
	if half > flip_period - minf(STOP_TIME, flip_period * 0.4):
		return 0.0
	return speed if c < flip_period else -speed


func current_velocity() -> float:
	return constant_linear_velocity.x


func clock() -> float:
	return _t


## 纹路滚动用的时间（只给表现读）。
func visual_time() -> float:
	return _vt


func _physics_process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	_t += delta
	_vt += delta
	var v := velocity_at(_t)
	if v != constant_linear_velocity.x:
		constant_linear_velocity = Vector2(v, 0.0)
	if _stripes != null:
		_stripes.queue_redraw()


func _build_stripes() -> void:
	var overlay := StripeOverlay.new()
	overlay.name = "Stripes"
	overlay.belt_size = size
	overlay.owner_belt = self
	overlay.z_index = 0
	_stripes = overlay
	add_child(overlay)


## 台面上一条会流动的人字纹。内嵌类不引用外层 class_name，所需数据由外层写进来。
class StripeOverlay extends Node2D:
	var belt_size: Vector2 = Vector2(64.0, 16.0)
	var owner_belt: Node = null
	var _on_screen := true

	func _ready() -> void:
		var notifier := VisibleOnScreenNotifier2D.new()
		notifier.rect = Rect2(Vector2.ZERO, belt_size).grow(8.0)
		notifier.screen_entered.connect(func() -> void:
			_on_screen = true
			queue_redraw())
		notifier.screen_exited.connect(func() -> void: _on_screen = false)
		add_child(notifier)

	func _draw() -> void:
		if not _on_screen or owner_belt == null:
			return
		var v: float = float(owner_belt.call("current_velocity"))
		var t: float = float(owner_belt.call("visual_time"))
		var offset := fposmod(t * v, 8.0)
		var moving := absf(v) > 0.5
		var base := Color(0.1, 0.08, 0.07, 0.75)
		HazardFx.px_rect(self, Rect2(0.0, 0.0, belt_size.x, 3.0), base)
		var x := -8.0 + offset
		while x < belt_size.x:
			var c := Color(0.92, 0.62, 0.22, 0.85) if moving else Color(0.5, 0.35, 0.2, 0.6)
			var x0 := clampf(x, 0.0, belt_size.x)
			var x1 := clampf(x + 3.0, 0.0, belt_size.x)
			if x1 > x0:
				HazardFx.px_rect(self, Rect2(x0, 0.0, x1 - x0, 1.0), c)
				if v >= 0.0:
					HazardFx.px_rect(self, Rect2(clampf(x + 1.0, 0.0, belt_size.x), 1.0, 2.0, 1.0), c)
				else:
					HazardFx.px_rect(self, Rect2(clampf(x - 1.0, 0.0, belt_size.x), 1.0, 2.0, 1.0), c)
			x += STRIPE


## 无搬运的完整停转窗口。运动中的带仍可走，但不能当作静止落脚点。
func safe_window(duration: float = 0.0) -> bool:
	if is_zero_approx(speed):
		return is_zero_approx(current_velocity())
	if flip_period <= 0.01:
		return false
	var half := fposmod(_t, flip_period)
	if half <= flip_period - minf(STOP_TIME, flip_period * 0.4):
		return false
	return maxf(0.0, duration) < flip_period - half
