extends CyclicHazard
## 章内熔注口：吊台仍在过场中运动，喷口解锁时读取吊台时钟，避免初相同步后漂移。
## 未联动吊台的竞技场浇口保持熄灭，直到原 BossArena 阶段事件点火。

var lift_ref: MovingPlatform
var ignited := true


func _ready() -> void:
	process_physics_priority = 10 # MovingPlatform 的默认优先级0先更新。
	if is_instance_valid(lift_ref):
		phase = fposmod(lift_ref._t, period()) / period()
	super._ready()
	if not ignited:
		stop()


func _physics_process(delta: float) -> void:
	if not ignited:
		return
	if is_instance_valid(lift_ref) and not _is_frozen():
		_t = lift_ref._t - delta
	super._physics_process(delta)


func trigger(_data: Dictionary = {}) -> void:
	ignited = true
	_t = rest_time
	_enter(State.WARN)
	queue_redraw()


func stop() -> void:
	ignited = false
	_enter(State.REST)
	_set_armed(false)
	queue_redraw()
