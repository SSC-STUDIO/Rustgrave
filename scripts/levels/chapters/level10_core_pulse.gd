extends CyclicHazard
## 炉心三口脉冲只订阅本场梦魇；每次相变先收刀，从完整休止/预警重新错相。
## 不改Boss攻击表；Boss死亡的同一帧收刀，重载已死Boss时布局不会创建本节点。

var enabled := false
var phase_id := 0
var start_delay := 0.0
var slot := 0
var encounter: BossArena
var nightmare: Node2D


func bind_encounter(boss: Node2D, arena: BossArena, index: int) -> void:
	nightmare = boss
	encounter = arena
	slot = index
	encounter.arena_started.connect(func() -> void: configure_phase(1))
	encounter.arena_cleared.connect(stop)
	GameEvents.boss_phase_changed.connect(_on_phase_changed)
	stop()


func _on_phase_changed(title: String, next_phase: int) -> void:
	if not is_instance_valid(nightmare) or not is_instance_valid(encounter) or not encounter.active:
		return
	if title != String(nightmare.get_script().get_script_constant_map()["BOSS_TITLE"]):
		return
	configure_phase(next_phase)


func configure_phase(next_phase: int) -> void:
	phase_id = clampi(next_phase, 1, 3)
	_set_armed(false)
	_enter(State.REST)
	_t = 0.0
	enabled = phase_id > 1 or slot == 1
	rest_time = [4.5, 3.0, 2.0][phase_id - 1]
	telegraph_time = 0.8 if phase_id == 3 else 0.9
	active_time = 0.8
	start_delay = 0.0 if phase_id == 1 else float(slot) * period() / 3.0
	queue_redraw()


func tick(delta: float) -> void:
	if not enabled:
		return
	if _is_frozen():
		super.tick(0.0)
		return
	if start_delay > 0.0:
		var consumed := minf(start_delay, delta)
		start_delay -= consumed
		delta -= consumed
		if delta <= 0.0:
			return
	super.tick(delta)


func seconds_until_active() -> float:
	return start_delay + super.seconds_until_active() if enabled else INF


func stop() -> void:
	enabled = false
	_enter(State.REST)
	_set_armed(false)
	queue_redraw()
