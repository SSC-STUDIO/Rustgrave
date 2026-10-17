class_name BossKit
extends RefCounted
## Boss 框架的数据接口（docs/integration-contracts.md §4.1）。
##
## 每一场 Boss 一份 Kit：名号、阶段数、攻击表、场地事件、演出步骤。Kit 只是
## 数据与查询函数，不持有节点、不改游戏状态；调度由 BossDirector 负责，空间与
## 机关由 BossArena 负责。
##
## 两种用法都合法（默认实现全部安全，空表 + 基础名号不会报错）：
##   1. 子类覆写（推荐给正式 Boss；Boss 脚本底部写 class MyKit extends BossKit）：
##        class MyKit extends BossKit:
##            func boss_title() -> String: return "..."
##            func attack_table() -> Array[Dictionary]: return [...]
##   2. 声明式（小 Boss / 测试 / 占位）：
##        BossKit.new({"title": "...", "attacks": [{"id": &"slam", ...}]})
##
## 攻击表条目（唯一必填是 id；其余有安全默认值）：
##   id: StringName                 招名。导演层调度、事件、测试都按它定位。
##   phase: int = 1                 从第几阶段起可选（<= 当前阶段才进池）。
##   weight: float = 1.0            权重；同条件下越大越常出。
##   cooldown: float = 1.0          同一招两次起手的最短间隔（秒）。
##   cooldown_by_phase: Array       按阶段覆盖 cooldown（下标 = phase - 1），可选。
##   min_range / max_range: float   与骑士的距离窗口；max_range <= 0 = 不限。
##   windup: float = 0.35           前摇秒数。可读性硬下限 0.35（见 BOSS_TELEGRAPH_MIN）。
##   windup_by_phase: Array         按阶段覆盖 windup（例：梦魇二阶段 0.58），可选。
##   active / recovery: float       判定 / 后摇秒数（导演层用来算占用时长）。
##   telegraph: StringName          读招暗号键（默认 = id）；暗号画面由招式自己画。
##   hitbox: Dictionary             {"offset": Vector2, "size": Vector2}，供「判定不出场地」校验；
##                                  远程 / 功能招式留空。
##   damaging: bool = true          false = 召唤 / 场地类功能招式，不套用伤害可读性下限的语义。
##   enrage_only: bool = false      只在狂暴计时触发后才可选。
##
## 场地事件条目：
##   id: StringName、at_phase: int（1 = 开战，2..N = 进入该阶段，0 = 死亡/清场）、
##   once: bool = true、data: Dictionary = {}。
##
## 可读性硬规则（契约 §4.1）：每招预警 >= BOSS_TELEGRAPH_MIN；同一时刻最多一条预警
## （BossDirector 串行出招保证）；hitbox 不出竞技场（BossArena / 测试校验）。

## 每招前摇的可读性硬下限。契约要求 Boss 的 CombatMarker 预警 >= 0.35 s，
## 比普通敌人的 CombatRules.TELEGRAPH_MIN(0.25) 更严。
const BOSS_TELEGRAPH_MIN := 0.35
## 两招之间（起手 -> 下一招起手）的最短间隔，防止高频连发。
const DEFAULT_MIN_INTERVAL := 0.6
## 单招默认冷却。
const DEFAULT_ATTACK_COOLDOWN := 1.0
## 单招默认占用时长（前摇之后的判定 + 后摇没写时的兜底）。
const DEFAULT_ATTACK_DURATION := 0.6
## 默认每招权重。
const DEFAULT_ATTACK_WEIGHT := 1.0
## 默认阶段阈值：2 / 3 阶段的常见切分。
const DEFAULT_PHASE_THRESHOLDS_2: Array[float] = [1.0, 0.5]
const DEFAULT_PHASE_THRESHOLDS_3: Array[float] = [1.0, 0.66, 0.33]
## 场地事件的特殊阶段号。
const EVENT_PHASE_DEATH := 0
const EVENT_PHASE_START := 1

## 声明式配表（子类可不用它，直接覆写方法更类型安全）。
var config: Dictionary = {}


func _init(p_config: Dictionary = {}) -> void:
	config = p_config.duplicate(true)


# ---------------------------------------------------------------------------
# 身份
# ---------------------------------------------------------------------------
## 存档 / 事件 / 测试用的稳定 id。
func boss_id() -> StringName:
	return StringName(String(config.get("id", "boss")))


## 名号卡标题（GameEvents.boss_appeared 的 boss_name）。
func boss_title() -> String:
	return String(config.get("title", "首领"))


## 名号卡副标题。
func boss_subtitle() -> String:
	return String(config.get("subtitle", ""))


## 阶段数：2 或 3（契约 §4.1）。默认 2。
func max_phases() -> int:
	return clampi(int(config.get("max_phases", 2)), 1, 3)


# ---------------------------------------------------------------------------
# 阶段
# ---------------------------------------------------------------------------
## 降序的生命比例阈值。下标 i 对应 (i+1) 阶段的入口，index 0 恒为 1.0。
## 例：[1.0, 0.5] 表示 <= 50% 生命进入二阶段。
func phase_thresholds() -> Array[float]:
	var raw: Variant = config.get("phase_thresholds", null)
	if raw is Array and not (raw as Array).is_empty():
		var out: Array[float] = []
		for value in raw:
			out.append(float(value))
		return out
	return _default_thresholds(max_phases())


## 当前生命（绝对点数）落在第几阶段（1..max_phases）。
func phase_for_hp(current: int, maximum: int) -> int:
	var phases := maxi(1, max_phases())
	if maximum <= 0:
		return 1
	var ratio := clampf(float(current) / float(maximum), 0.0, 1.0)
	var thresholds := phase_thresholds()
	var phase := 1
	for i in range(1, mini(thresholds.size(), phases)):
		if ratio <= float(thresholds[i]):
			phase = i + 1
	return phase


# ---------------------------------------------------------------------------
# 攻击表
# ---------------------------------------------------------------------------
## 攻击表（原样返回；用 attack_pool() 取归一化后的条目）。空表 = 没有可选招式。
func attack_table() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = config.get("attacks", [])
	if raw is Array:
		for entry in raw:
			if entry is Dictionary:
				out.append(entry)
	return out


## 归一化后的攻击表（每个条目都补齐默认字段并保证 id 唯一）。
func attack_pool() -> Array[Dictionary]:
	return normalize_attack_table(attack_table())


## 两招起手之间的最短间隔（秒）。导演层据此拒绝过早出招。
func min_interval() -> float:
	return maxf(0.0, float(config.get("min_interval", DEFAULT_MIN_INTERVAL)))


## 狂暴计时：开战超过这么多秒进入狂暴（<= 0 = 不使用计时狂暴）。
func enrage_after() -> float:
	return float(config.get("enrage_after", -1.0))


## 可读性下限（子类可放低，但契约要求 Boss 保持 >= 0.35）。
func telegraph_min() -> float:
	return float(config.get("telegraph_min", BOSS_TELEGRAPH_MIN))


## 某一阶段下这一招的前摇（秒）。windup_by_phase 可覆盖。
func windup_for(entry: Dictionary, phase: int) -> float:
	var override := _phase_value(entry.get("windup_by_phase", null), phase)
	if override >= 0.0:
		return override
	return maxf(0.0, float(entry.get("windup", telegraph_min())))


## 某一阶段下这一招的冷却（秒）。cooldown_by_phase 可覆盖。
func cooldown_for(entry: Dictionary, phase: int) -> float:
	var override := _phase_value(entry.get("cooldown_by_phase", null), phase)
	if override >= 0.0:
		return override
	return maxf(0.0, float(entry.get("cooldown", DEFAULT_ATTACK_COOLDOWN)))


## 这一招的占用时长（起手到可再次调度）：前摇 + 判定 + 后摇。
func duration_for(entry: Dictionary, phase: int) -> float:
	var windup := windup_for(entry, phase)
	var active := maxf(0.0, float(entry.get("active", 0.0)))
	var recovery := maxf(0.0, float(entry.get("recovery", DEFAULT_ATTACK_DURATION)))
	return maxf(windup, windup + active + recovery)


# ---------------------------------------------------------------------------
# 场地事件 / 演出步骤
# ---------------------------------------------------------------------------
## 场地事件（火柱 / 落石 / 水流 / 舞台灯…）。导演层在对应阶段发 arena_event 信号。
func arena_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw: Variant = config.get("arena_events", [])
	if raw is Array:
		for event in raw:
			if event is Dictionary:
				out.append(event)
	return out


## 返场演出步骤（Director 剧本格式）。现有两场 Boss 的演出仍由章节脚本负责，
## 新 Boss 从这里返回步骤给 Director/StoryStage 播放。
func intro_steps() -> Array:
	return config.get("intro_steps", [])


## 进入某一阶段的演出步骤（Director 剧本格式）。
func phase_steps(phase: int) -> Array:
	var steps: Variant = config.get("phase_steps", {})
	if steps is Dictionary:
		return (steps as Dictionary).get(phase, [])
	if steps is Array and phase >= 1 and phase <= (steps as Array).size():
		return (steps as Array)[phase - 1]
	return []


## 死亡演出步骤（Director 剧本格式）。
func death_steps() -> Array:
	return config.get("death_steps", [])


# ---------------------------------------------------------------------------
# 校验
# ---------------------------------------------------------------------------
## 整份 Kit 的自检：空数组 = 通过。测试与 Boss 作者都能直接调。
func validate() -> Array[String]:
	var problems := validate_attack_table(attack_table(), telegraph_min(), max_phases())
	problems.append_array(validate_arena_events(arena_events(), max_phases()))
	var thresholds := phase_thresholds()
	if thresholds.is_empty() or not is_equal_approx(float(thresholds[0]), 1.0):
		problems.append("phase_thresholds 必须以 1.0 开头（%s）" % [thresholds])
	if thresholds.size() != max_phases():
		problems.append("phase_thresholds 长度 %d != max_phases %d"
				% [thresholds.size(), max_phases()])
	for i in range(1, thresholds.size()):
		if float(thresholds[i]) >= float(thresholds[i - 1]):
			problems.append("phase_thresholds 必须严格降序（%s）" % [thresholds])
			break
	return problems


## 攻击表自检：id 唯一、前摇 >= 可读性下限、冷却 / 权重合法、阶段号合法。
static func validate_attack_table(table: Array, telegraph_min: float = BOSS_TELEGRAPH_MIN,
		max_phases: int = 2) -> Array[String]:
	var problems: Array[String] = []
	var seen: Dictionary = {}
	for raw in table:
		if not (raw is Dictionary):
			problems.append("攻击条目不是 Dictionary：%s" % [raw])
			continue
		var id := StringName(String((raw as Dictionary).get("id", "")))
		if String(id) == "":
			problems.append("攻击条目缺少 id：%s" % [raw])
			continue
		if seen.has(id):
			problems.append("攻击 id 重复：%s" % id)
			continue
		seen[id] = true
		var entry := normalize_attack(raw)
		var phase := int(entry.phase)
		if phase < 1 or phase > max_phases:
			problems.append("%s 的 phase %d 不在 1..%d" % [id, phase, max_phases])
		var windups: Array[float] = [float(entry.windup)]
		var by_phase: Variant = entry.get("windup_by_phase")
		if by_phase is Array:
			for value in by_phase:
				windups.append(float(value))
		for windup in windups:
			if windup < telegraph_min:
				problems.append("%s 前摇 %.3fs < 可读性下限 %.2fs" % [id, windup, telegraph_min])
		if float(entry.cooldown) < 0.0:
			problems.append("%s 冷却为负：%.2f" % [id, float(entry.cooldown)])
		if float(entry.weight) <= 0.0:
			problems.append("%s 权重必须 > 0" % id)
		if float(entry.max_range) > 0.0 and float(entry.max_range) < float(entry.min_range):
			problems.append("%s 的 max_range < min_range" % id)
		var hitbox: Dictionary = entry.get("hitbox", {})
		if not hitbox.is_empty():
			var size: Vector2 = hitbox.get("size", Vector2.ZERO)
			if size.x < 0.0 or size.y < 0.0:
				problems.append("%s 的 hitbox.size 不能为负" % id)
	return problems


## 场地事件自检：id 唯一、at_phase 合法、once 是 bool。
static func validate_arena_events(events: Array, max_phases: int = 2) -> Array[String]:
	var problems: Array[String] = []
	var seen: Dictionary = {}
	for raw in events:
		if not (raw is Dictionary):
			problems.append("场地事件不是 Dictionary：%s" % [raw])
			continue
		var id := StringName(String((raw as Dictionary).get("id", "")))
		if String(id) == "":
			problems.append("场地事件缺少 id：%s" % [raw])
			continue
		if seen.has(id):
			problems.append("场地事件 id 重复：%s" % id)
			continue
		seen[id] = true
		var at_phase := int((raw as Dictionary).get("at_phase", EVENT_PHASE_START))
		if at_phase < EVENT_PHASE_DEATH or at_phase > max_phases:
			problems.append("%s 的 at_phase %d 不在 0..%d" % [id, at_phase, max_phases])
	return problems


# ---------------------------------------------------------------------------
# 静态工具（导演层 / 测试 / 未来 Boss 共用）
# ---------------------------------------------------------------------------
## 补齐默认字段；不改原字典。
static func normalize_attack(entry: Dictionary) -> Dictionary:
	var out := entry.duplicate(true)
	out["id"] = StringName(String(entry.get("id", "")))
	out["phase"] = int(entry.get("phase", 1))
	out["weight"] = float(entry.get("weight", DEFAULT_ATTACK_WEIGHT))
	out["cooldown"] = float(entry.get("cooldown", DEFAULT_ATTACK_COOLDOWN))
	out["min_range"] = float(entry.get("min_range", 0.0))
	out["max_range"] = float(entry.get("max_range", 0.0))
	out["windup"] = float(entry.get("windup", BOSS_TELEGRAPH_MIN))
	out["active"] = float(entry.get("active", 0.0))
	out["recovery"] = float(entry.get("recovery", DEFAULT_ATTACK_DURATION))
	out["telegraph"] = StringName(String(entry.get("telegraph", out["id"])))
	out["damaging"] = bool(entry.get("damaging", true))
	out["enrage_only"] = bool(entry.get("enrage_only", false))
	if not (out.get("hitbox") is Dictionary):
		out["hitbox"] = {}
	return out


## 归一化整张表：补齐字段、剔除无 id 条目、去重（保留先出现的）。
static func normalize_attack_table(table: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw in table:
		if not (raw is Dictionary):
			continue
		var entry := normalize_attack(raw)
		var id: StringName = entry.id
		if String(id) == "" or seen.has(id):
			continue
		seen[id] = true
		out.append(entry)
	return out


## 攻击的横向触达（相对 Boss，含朝向翻转）：|offset.x| + size.x/2。
## 竞技场校验用它判断「这一招的判定会不会露出场地」。
static func hitbox_reach(entry: Dictionary) -> float:
	var hitbox: Dictionary = entry.get("hitbox", {})
	if hitbox.is_empty():
		return 0.0
	var offset: Vector2 = hitbox.get("offset", Vector2.ZERO)
	var size: Vector2 = hitbox.get("size", Vector2.ZERO)
	return absf(offset.x) + size.x * 0.5


## 攻击判定的矩形（相对 Boss 原点、朝右）。校验 hitbox 不出场地 / 贴地用。
static func hitbox_rect(entry: Dictionary) -> Rect2:
	var hitbox: Dictionary = entry.get("hitbox", {})
	if hitbox.is_empty():
		return Rect2()
	var offset: Vector2 = hitbox.get("offset", Vector2.ZERO)
	var size: Vector2 = hitbox.get("size", Vector2.ZERO)
	return Rect2(offset - size * 0.5, size)


## 按权重从候选里抽一条（rng 可以是 RandomNumberGenerator，也可以是 null）。
static func weighted_pick(candidates: Array, rng: RandomNumberGenerator = null) -> Dictionary:
	if candidates.is_empty():
		return {}
	var total := 0.0
	for entry in candidates:
		total += maxf(0.0, float((entry as Dictionary).get("weight", DEFAULT_ATTACK_WEIGHT)))
	if total <= 0.0:
		return (candidates[0] as Dictionary).duplicate(true)
	var roll := (rng.randf() if rng != null else randf()) * total
	var cursor := 0.0
	for entry in candidates:
		cursor += maxf(0.0, float((entry as Dictionary).get("weight", DEFAULT_ATTACK_WEIGHT)))
		if roll <= cursor:
			return (entry as Dictionary).duplicate(true)
	return (candidates[candidates.size() - 1] as Dictionary).duplicate(true)


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------
func _default_thresholds(phases: int) -> Array[float]:
	var out: Array[float] = DEFAULT_PHASE_THRESHOLDS_2.duplicate()
	if phases >= 3:
		out = DEFAULT_PHASE_THRESHOLDS_3.duplicate()
	return out


## 读 *by_phase 数组在 phase 上的值；缺失 / 非法返回 -1。
static func _phase_value(raw: Variant, phase: int) -> float:
	if raw is Array and phase >= 1 and phase <= (raw as Array).size():
		var value: Variant = (raw as Array)[phase - 1]
		if value is float or value is int:
			return float(value)
	return -1.0
