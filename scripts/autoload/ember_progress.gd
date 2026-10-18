extends Node
## 余烬阶位运行时（Autoload）：把 XP 来源落进 SaveData 的 v3 profile，并在升阶时
## 发一条可被 UI 订阅的信号。
##
## 分工：
##   · EmberRank（纯数据）——门槛/阶名/解锁表/进度数学；
##   · EmberProgress（本文件）——award_xp()、存档落盘、升阶解锁、信号/播报；
##   · 角色面板 / 标题档案（后续里程碑）只读 SaveData + 订阅 rank_changed。
##
## 试炼（TrialRun）里战役档只读：award 会被挡下，等结算回标题后再补发。
## 本文件不写任何战役旗标/节点状态，只写 profile。

signal rank_changed(info: Dictionary)

const Rank := preload("res://scripts/data/ember_rank.gd")
const TrialRunScript := preload("res://scripts/autoload/trial_run.gd")
## 阶位解锁进 profile.extras 的键（数组，元素是 id 字符串）。
const UNLOCKS_KEY := "unlocked_progression"

static var _node: Node = null
static var _last_award: Dictionary = {}


func _ready() -> void:
	_node = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not GameEvents.boss_defeated.is_connected(_on_boss_defeated):
		GameEvents.boss_defeated.connect(_on_boss_defeated)


func _exit_tree() -> void:
	if _node == self:
		_node = null
	if GameEvents.boss_defeated.is_connected(_on_boss_defeated):
		GameEvents.boss_defeated.disconnect(_on_boss_defeated)


func _on_boss_defeated() -> void:
	award_boss()


# ---------------------------------------------------------------- awards --

static func award_boss() -> Dictionary:
	return award_xp(Rank.BOSS_XP, &"boss")


static func award_chapter() -> Dictionary:
	return award_xp(Rank.CHAPTER_XP, &"chapter")


static func award_trial() -> Dictionary:
	return award_xp(Rank.TRIAL_XP, &"trial")


static func award_arena_win() -> Dictionary:
	return award_xp(Rank.ARENA_WIN_XP, &"arena_win")


static func award_arena_loss() -> Dictionary:
	return award_xp(Rank.ARENA_LOSS_XP, &"arena_loss")


## 发 XP：更新阶位/属性点/解锁，写 profile（有档时），返回本次结果。
## 试炼进行中返回 {"blocked": "trial"}，不写任何东西。
static func award_xp(amount: int, source: StringName = &"") -> Dictionary:
	if amount <= 0:
		return {}
	if TrialRunScript.blocks_campaign_save():
		return {"blocked": "trial"}
	var rank_before: int = SaveData.ember_rank
	var points_before: int = SaveData.attribute_points
	var xp_before: int = SaveData.ember_xp
	var xp_after: int = xp_before + amount
	var rank_after: int = Rank.rank_for_xp(xp_after)
	var points_after: int = points_before + maxi(0, rank_after - rank_before)
	var leveled: bool = rank_after > rank_before
	var unlocks: Array[StringName] = []
	if leveled:
		unlocks = _grant_unlocks(rank_before, rank_after)
	SaveData.set_ember_state(rank_after, xp_after, points_after)
	if leveled or SaveData.has_save():
		SaveData.persist_profile()
	_last_award = {
		"amount": amount,
		"source": source,
		"xp_before": xp_before,
		"xp_after": xp_after,
		"rank_before": rank_before,
		"rank_after": rank_after,
		"points_after": points_after,
		"leveled": leveled,
		"unlocks": unlocks,
		"summary": Rank.summary(xp_after),
	}
	if leveled:
		GameEvents.announcement.emit("余烬升阶 · %s" % Rank.summary(xp_after))
		_emit_changed(_last_award)
	return _last_award


static func last_award() -> Dictionary:
	return _last_award


## 把 rank_before+1 .. rank_after 的解锁追加进 profile.extras（去重）。
static func _grant_unlocks(rank_before: int, rank_after: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var existing: Variant = SaveData.get_extra(UNLOCKS_KEY, [])
	var owned: Array = []
	if existing is Array:
		for value in (existing as Array):
			owned.append(String(value))
	for rank in range(rank_before + 1, rank_after + 1):
		for id in Rank.rewards_for_rank(rank):
			if not owned.has(String(id)):
				owned.append(String(id))
				out.append(id)
	SaveData.set_extra(UNLOCKS_KEY, owned)
	return out


static func _emit_changed(info: Dictionary) -> void:
	if _node == null or not is_instance_valid(_node):
		return
	(_node as Node).emit_signal("rank_changed", info)


## 测试用：清掉上一个结果（不影响 SaveData）。
static func clear_cache() -> void:
	_last_award = {}
