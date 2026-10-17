class_name BossDirector
extends Node
## Boss 攻击表调度器（docs/integration-contracts.md §4.1）。挂在 Boss 节点下，
## 由 BossKit 驱动，负责：
##   · 按阶段 / 距离 / 冷却 / 权重 / 最短间隔从攻击表里选下一招（禁止连续重复）；
##   · 阶段阈值（HP 比例）与狂暴计时；
##   · 场地事件信号（火柱 / 落石 / 水流 / 舞台灯由 BossArena 或章节脚本订阅）；
##   · 暂停冻结 / 恢复（树暂停时物理帧本就不推进，显式 freeze() 供过场与测试使用，
##     两条路径都保证时钟不走、不出招）。
##
## 两种工作模式：
##   驾驶模式（auto_drive = true，新 Boss 用）：
##       attach(boss, kit, true) + start()；导演层自己选招并发 attack_requested(id)，
##       Boss 在回调里执行招式、结束时调 notify_attack_finished()。
##       （不回调也行：导演层按 Kit 的 duration 自动收回占用。）
##   协助模式（auto_drive = false，现有 Boss 迁移用）：
##       只做观测与事件：Boss 在真正起手 / 进阶段 / 死亡时调 notify_* 同步给导演层。
##       不抢占 Boss 自己的状态机、不改任何时序 —— 现有测试语义保持不变。
##
## 可读性：导演层串行出招 —— active_attack 非空时不会再选下一招，因此同一时刻
## 最多一条预警；每招前摇由 BossKit.validate_attack_table() 卡 >= 0.35 s。

signal fight_started
## 导演层选中一招（两种模式都会发；assist 模式下由 Boss 的 notify_attack_started 触发）。
signal attack_selected(entry: Dictionary)
## 驾驶模式专属：请求 Boss 执行这一招。
signal attack_requested(id: StringName)
signal attack_finished(id: StringName)
signal phase_entered(phase: int)
signal enrage_started
signal arena_event(id: StringName, data: Dictionary)
signal died
signal frozen_changed(frozen: bool)

const ATTACH_NAME := "BossDirector"

## true = 导演层自己调度出招（新 Boss）；false = 只观测（现有 Boss 迁移）。
@export var auto_drive: bool = false
## 随机种子；0 = 随机。测试固定种子可复现。
@export var rng_seed: int = 0

## 数据源与宿主（attach() 时写入）。
var kit: BossKit
var boss: Node
## 可选：直接指定玩家，缺省从 "player" 组取。
var player: Node2D

var running: bool = false
var frozen: bool = false
var enraged: bool = false
var phase: int = 1
## 战斗时钟（秒）：只统计未被冻结 / 暂停的时间。
var clock: float = 0.0
## 当前占用中的招式（{} = 空闲）。导演层靠它串行出招。
var active_attack: Dictionary = {}
var last_attack_id: StringName = &""
var attack_count: int = 0

var _hp: int = 0
var _max_hp: int = 0
var _death_notified: bool = false
var _busy_until: float = 0.0
var _next_allowed_at: float = 0.0
var _cooldowns: Dictionary = {}
var _fired_events: Dictionary = {}
var _rng := RandomNumberGenerator.new()


## 工厂：给 Boss 挂一个导演层。重复调用返回已有实例（顺带刷新配置）。
static func attach(p_boss: Node, p_kit: BossKit, p_auto_drive: bool = false) -> BossDirector:
	if p_boss == null:
		return null
	var existing := p_boss.get_node_or_null(ATTACH_NAME) as BossDirector
	if existing != null:
		existing.kit = p_kit
		existing.auto_drive = p_auto_drive
		return existing
	var director := BossDirector.new()
	director.name = ATTACH_NAME
	director.kit = p_kit
	director.boss = p_boss
	director.auto_drive = p_auto_drive
	p_boss.add_child(director)
	return director


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if boss == null:
		boss = get_parent()
	if kit == null:
		kit = BossKit.new()
	if _rng.seed == 0:
		_rng.randomize()
	if rng_seed != 0:
		_rng.seed = rng_seed
	set_physics_process(true)


# ---------------------------------------------------------------------------
# 战斗生命周期
# ---------------------------------------------------------------------------
## 开战：清时钟 / 冷却，发 fight_started，并触发 at_phase == 1 的场地事件。
func start() -> void:
	if running:
		return
	running = true
	clock = 0.0
	_active_attack_clear()
	_cooldowns.clear()
	_next_allowed_at = 0.0
	phase = 1
	enraged = false
	_death_notified = false
	emit_signal("fight_started")
	_fire_arena_events(BossKit.EVENT_PHASE_START)


func stop() -> void:
	running = false
	_active_attack_clear()


## 重试 / 重开：时钟与阶段归零，保留 kit。
func reset_fight() -> void:
	stop()
	clock = 0.0
	phase = 1
	enraged = false
	_hp = 0
	_max_hp = 0
	_death_notified = false
	_cooldowns.clear()
	_fired_events.clear()
	last_attack_id = &""
	attack_count = 0
	active_attack = {}
	_next_allowed_at = 0.0
	_busy_until = 0.0


## Boss 报告当前生命：阶段只升不降；current <= 0 时什么都不做（死亡走 notify_death）。
func set_hp(current: int, maximum: int) -> void:
	_hp = maxi(0, current)
	_max_hp = maxi(0, maximum)
	if _hp <= 0 or _max_hp <= 0 or kit == null:
		return
	var next := kit.phase_for_hp(_hp, _max_hp)
	if next > phase:
		_enter_phase(next)


## 死亡 / 清场：停表、抛事件的死亡场地事件。幂等。
func notify_death() -> void:
	if _death_notified:
		return
	_death_notified = true
	running = false
	_active_attack_clear()
	emit_signal("died")
	_fire_arena_events(BossKit.EVENT_PHASE_DEATH)


## 开场（现有 Boss 在 announce() 时调用）：触发 at_phase == 1 的场地事件。
## 幂等 —— 同一阶段的事件只会按 once 规则发一次。
func notify_intro() -> void:
	if kit == null:
		return
	_fire_arena_events(BossKit.EVENT_PHASE_START)


func _enter_phase(next: int) -> void:
	if next <= phase:
		return
	phase = next
	emit_signal("phase_entered", phase)
	_fire_arena_events(phase)


# ---------------------------------------------------------------------------
# 出招调度
# ---------------------------------------------------------------------------
## 从攻击表里挑下一招；不提交占用。没有合法招式返回 {}。
## 过滤顺序：阶段 → 狂暴限定 → 冷却 → 距离 → 禁止连续重复（池里还有其他招时）。
func choose_next(distance: float = 0.0) -> Dictionary:
	if not _can_pick():
		return {}
	if kit == null:
		return {}
	var pool := kit.attack_pool()
	if pool.is_empty():
		return {}
	var candidates: Array = []
	for entry in pool:
		var id: StringName = entry.id
		if int(entry.phase) > phase:
			continue
		if bool(entry.get("enrage_only", false)) and not enraged:
			continue
		if clock < float(_cooldowns.get(id, -INF)):
			continue
		if not _in_range(entry, distance):
			continue
		if id == last_attack_id and pool.size() > 1:
			continue
		candidates.append(entry)
	if candidates.is_empty():
		return {}
	return BossKit.weighted_pick(candidates, _rng)


## 挑一招并立刻提交占用（发 attack_selected / attack_requested）。没有合法招返回 {}。
func pick_and_start(distance: float = 0.0) -> Dictionary:
	var entry := choose_next(distance)
	if entry.is_empty():
		return {}
	_begin_attack(entry)
	return entry


## 协助模式：Boss 真正起手时报告。记录冷却 / 末招，供观测与场地事件使用。
## 只有导演层在驾驶（running）时才把这一招记为「占用中」；协助模式的 Boss 自己管
## 状态机，导演层不假装它忙。
func notify_attack_started(id: StringName) -> void:
	if kit == null:
		return
	var entry := _entry_by_id(id)
	if entry.is_empty():
		return
	last_attack_id = id
	attack_count += 1
	_busy_until = clock + kit.duration_for(entry, phase)
	_book(entry)
	active_attack = entry if running else {}
	emit_signal("attack_selected", entry)


## 招式结束（驾驶模式的 Boss 在收招时调用；不调也会按 duration 自动收回）。
func notify_attack_finished() -> void:
	if active_attack.is_empty():
		return
	var id: StringName = active_attack.id
	_active_attack_clear()
	emit_signal("attack_finished", id)


func is_busy() -> bool:
	return not active_attack.is_empty()


## 驾驶模式下由物理帧推进；headless 测试也可以手动 tick(delta) 精确推进。
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	if frozen or not running:
		return
	if get_tree() != null and get_tree().paused:
		return
	clock += delta
	if not active_attack.is_empty() and clock >= _busy_until:
		notify_attack_finished()
	if not enraged:
		var enrage_at := kit.enrage_after() if kit != null else -1.0
		if enrage_at > 0.0 and clock >= enrage_at:
			enraged = true
			emit_signal("enrage_started")
	if auto_drive and active_attack.is_empty():
		pick_and_start(_distance_to_player())


func _physics_process(delta: float) -> void:
	tick(delta)


# ---------------------------------------------------------------------------
# 暂停 / 冻结
# ---------------------------------------------------------------------------
## 冻结时钟与出招（过场 / 暂停菜单）。树暂停是另一条路径：PAUSABLE 节点不推进。
func freeze() -> void:
	if frozen:
		return
	frozen = true
	emit_signal("frozen_changed", true)


func resume() -> void:
	if not frozen:
		return
	frozen = false
	set_physics_process(true)
	emit_signal("frozen_changed", false)


func is_frozen() -> bool:
	return frozen


# ---------------------------------------------------------------------------
# 查询 / 诊断
# ---------------------------------------------------------------------------
## 当前阶段下这一招现在能不能出（阶段 / 冷却 / 占用 / 距离都已满足）。
func can_use(id: StringName, distance: float = 0.0) -> bool:
	if not _can_pick():
		return false
	var entry := _entry_by_id(id)
	if entry.is_empty():
		return false
	if int(entry.phase) > phase:
		return false
	if bool(entry.get("enrage_only", false)) and not enraged:
		return false
	if clock < float(_cooldowns.get(id, -INF)):
		return false
	if not _in_range(entry, distance):
		return false
	if id == last_attack_id and kit != null and kit.attack_pool().size() > 1:
		return false
	return true


## 快照（测试 / report.json / 调试用）。
func schedule_snapshot() -> Dictionary:
	var by_id: Dictionary = {}
	if kit != null:
		for entry in kit.attack_pool():
			by_id[String(entry.id)] = {
				"phase": int(entry.phase),
				"weight": float(entry.weight),
				"cooldown": float(kit.cooldown_for(entry, phase)),
				"windup": float(kit.windup_for(entry, phase)),
				"ready_in": maxf(0.0, float(_cooldowns.get(entry.id, -INF)) - clock),
			}
	return {
		"boss_id": String(kit.boss_id()) if kit != null else "",
		"running": running,
		"frozen": frozen,
		"enraged": enraged,
		"phase": phase,
		"max_phases": kit.max_phases() if kit != null else 0,
		"clock": clock,
		"hp": _hp,
		"max_hp": _max_hp,
		"attack_count": attack_count,
		"last_attack_id": String(last_attack_id),
		"active_attack_id": String(active_attack.get("id", "")),
		"next_attack_in": maxf(0.0, _next_allowed_at - clock),
		"attacks": by_id,
		"arena_events": kit.arena_events() if kit != null else [],
	}


## 距玩家的水平距离（没有玩家时返回 0 = 不因距离落选）。
func _distance_to_player() -> float:
	var target := player
	if target == null or not is_instance_valid(target):
		if get_tree() == null:
			return 0.0
		target = get_tree().get_first_node_in_group("player") as Node2D
	if target == null or boss == null or not (boss is Node2D):
		return 0.0
	return absf((boss as Node2D).global_position.x - target.global_position.x)


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------
func _can_pick() -> bool:
	if not running or frozen:
		return false
	if get_tree() != null and get_tree().paused:
		return false
	if not active_attack.is_empty():
		return false
	if clock < _next_allowed_at:
		return false
	return true


func _in_range(entry: Dictionary, distance: float) -> bool:
	if distance < float(entry.min_range):
		return false
	var max_range := float(entry.max_range)
	if max_range > 0.0 and distance > max_range:
		return false
	return true


func _begin_attack(entry: Dictionary) -> void:
	active_attack = entry
	last_attack_id = entry.id
	attack_count += 1
	_busy_until = clock + maxf(0.05, kit.duration_for(entry, phase))
	_book(entry)
	emit_signal("attack_selected", entry)
	if auto_drive:
		emit_signal("attack_requested", StringName(entry.id))


func _book(entry: Dictionary) -> void:
	if kit == null:
		return
	_cooldowns[StringName(entry.id)] = clock + kit.cooldown_for(entry, phase)
	_next_allowed_at = clock + kit.min_interval()


func _active_attack_clear() -> void:
	active_attack = {}


func _entry_by_id(id: StringName) -> Dictionary:
	if kit == null:
		return {}
	for entry in kit.attack_pool():
		if StringName(entry.id) == id:
			return entry
	return {}


func _fire_arena_events(at_phase: int) -> void:
	if kit == null:
		return
	for raw in kit.arena_events():
		var event := raw.duplicate(true)
		var id := StringName(String(event.get("id", "")))
		if String(id) == "":
			continue
		var event_phase := int(event.get("at_phase", BossKit.EVENT_PHASE_START))
		if event_phase != at_phase:
			continue
		var once := bool(event.get("once", true))
		if once and _fired_events.has(id):
			continue
		_fired_events[id] = true
		var data: Dictionary = event.get("data", {})
		emit_signal("arena_event", id, data)
