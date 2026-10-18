extends Object
## 回火试炼（Tempering Trials）的静态数据源。
##
## 文件不带 class_name：多 agent 并行时全局类缓存不可靠，所有使用方统一用
## `const Catalog := preload("res://scripts/data/trial_catalog.gd")` 引用；
## 合并后若想要类型名再加回去也不影响调用点。
##
## 本文件只描述"有哪些赛道 / 打哪几关 / 用什么固定装载 / 什么算 S·A·B / 什么时候解锁"，
## 不碰场景加载、不写任何存档。运行时状态在 TrialRun（scripts/autoload/trial_run.gd），
## 记录在 TrialRecords（独立 user://rustgrave_trials.cfg）。
##
## 解锁口径（契约 §5）：战役写 `trial_unlocked` 旗标（第七章通关或任一结局）；
## 试炼只读旗标，绝不写回战役档。章节目录 / Boss 顺序从 GameContext.LEVEL_ORDER、
## StoryFlow.DONE_FLAGS 与下面的 BOSS_TABLE 推出，不另存一份章节表。
##
## Boss 列表：二期 Boss（CapstanWarden / SilentChoir / HollowBell / BellFounder /
## EmberwindHerald）先在 BOSS_TABLE 里占位，场景文件不存在时自动跳过 —— bosses-a/b
## 交付后只需核对 level_id / flag / spawn 三列，不用改代码。

enum Track { BOSS_RUSH, TIME_ATTACK, BARE_STEEL }

const TRACKS: Array[int] = [Track.BOSS_RUSH, Track.TIME_ATTACK, Track.BARE_STEEL]

## 记录文件 / 菜单 tab 的稳定 id（存档与 UI 都按这个字符串走，不存枚举序）。
const TRACK_IDS := {
	Track.BOSS_RUSH: &"boss_rush",
	Track.TIME_ATTACK: &"time_attack",
	Track.BARE_STEEL: &"bare_steel",
}
const TRACK_NAMES := {
	Track.BOSS_RUSH: "Boss 连战",
	Track.TIME_ATTACK: "限时疾行",
	Track.BARE_STEEL: "禁核锈行",
}
const TRACK_TAGLINES := {
	Track.BOSS_RUSH: "按已通关顺序，一场接一场",
	Track.TIME_ATTACK: "满编锈核，抢在时限内跑到出口",
	Track.BARE_STEEL: "不带锈核与补给，只剩一把锈剑",
}
const TRACK_RULES := {
	Track.BOSS_RUSH: ["只打已通关的 Boss，一场接一场", "每胜一场回复 1 点生命，不补满",
			"死亡即整场从头再来，死亡数计入评级"],
	Track.TIME_ATTACK: ["在已通关的章节里任选一章", "计时从落地说起，到推开出口为止",
			"热锻 / 钩锁 / 余烬步三枚锈核固定镶满，路上无补给"],
	Track.BARE_STEEL: ["在已通关的章节里任选一章", "剑鞘空着：没有锈核能力，也没有补给",
			"计时与限时疾行同口径，评级更苛刻"],
}

## 解锁门（契约 §5）：trial_unlocked 由战役写；这里兼容旧档直接看章节旗标 / 结局。
const UNLOCK_FLAG := "trial_unlocked"
const UNLOCK_CHAPTER := "level07"

## 记录文件里缺失的未知字段原样保留（TrialRecords 负责），版本号在这里单列。
const RECORDS_VERSION := 1

## 固定装载快照（契约 §5）：三条赛道用同一副甲/剑，只差锈核与生命。
## sockets = 固定镶进剑鞘的锈核 id；pouch = 口袋里的备用核（试炼里一律为空）。
const BASE_MAX_HP := 5
const EQUIPMENT := {
	"weapon": "broken_sword",
	"armor": "broken_armor",
	"trinket": "broken_pendant",
	"bag": [],
}
const LOADOUTS := {
	Track.BOSS_RUSH: {"hp": 5, "sockets": [], "pouch": []},
	# 剑只有两个插座（RustCoreInventory.socket_count = 2）：热锻 + 钩锁固定镶上，
	# 余烬核放口袋——三枚能力都在，但换核要自己停下来（仍算"无补给"，路上不掉核）。
	Track.TIME_ATTACK: {"hp": 5, "sockets": [&"kiln_core", &"tether_core"],
			"pouch": [&"ember_core"]},
	Track.BARE_STEEL: {"hp": 5, "sockets": [], "pouch": []},
}

## 评级：把死亡折算成罚时后和基准时间比。S = 基准内，A = 1.35 倍内，B = 1.9 倍内，
## 更慢也记 B（结算只分 S/A/B 三档，不给"失败"评级 —— 打完就是打完）。
const DEATH_PENALTY_MS := {
	Track.BOSS_RUSH: 45000,
	Track.TIME_ATTACK: 20000,
	Track.BARE_STEEL: 30000,
}
const PAR_CHAPTER_MS := 120000
const PAR_BOSS_MS := 150000
const RANK_BOUNDS := [["S", 1.0], ["A", 1.35], ["B", 1.9]]
const RANKS: Array[StringName] = [&"S", &"A", &"B"]

## Boss 连战的场次表。spawn 是骑士落点（Boss 竞技场外的安全位置）；
## 场景不存在时该行自动跳过，等 bosses-a/b 交付后补正 level_id / flag / spawn。
const BOSS_TABLE := [
	{
		"kind": "executioner",
		"level_id": "level01",
		"flag": "boss_dead",
		"title": "炉约刽子手 · 铸渣残躯",
		"scene": "res://scenes/enemies/ExecutionerBoss.tscn",
		"spawn": Vector2(1696, 300),
	},
	{
		"kind": "nightmare_boss",
		"level_id": "level10",
		"flag": "nightmare_dead",
		"title": "锈 墓 梦 魇 · 无 主 之 马",
		"scene": "res://scenes/enemies/NightmareBoss.tscn",
		"spawn": Vector2(1848, 300),
	},
	# --- 二期 Boss 占位（场景缺失 → 自动跳过；交付后核对三列即可） -----------------
	{
		"kind": "capstan_warden",
		"level_id": "level03",
		"flag": "level03_done",
		"title": "绞盘守卫",
		"scene": "res://scenes/enemies/CapstanWarden.tscn",
		"spawn": Vector2(96, 300),
	},
	{
		"kind": "silent_choir",
		"level_id": "level04",
		"flag": "level04_done",
		"title": "无声唱诗班",
		"scene": "res://scenes/enemies/SilentChoir.tscn",
		"spawn": Vector2(96, 300),
	},
	{
		"kind": "hollow_bell",
		"level_id": "level07",
		"flag": "level07_done",
		"title": "空钟",
		"scene": "res://scenes/enemies/HollowBell.tscn",
		"spawn": Vector2(96, 300),
	},
	{
		"kind": "bell_founder",
		"level_id": "level07b",
		"flag": "level07b_done",
		"title": "铸钟人",
		"scene": "res://scenes/enemies/BellFounder.tscn",
		"spawn": Vector2(96, 300),
	},
	{
		"kind": "emberwind_herald",
		"level_id": "level09b",
		"flag": "level09b_done",
		"title": "烬风先驱",
		"scene": "res://scenes/enemies/EmberwindHerald.tscn",
		"spawn": Vector2(96, 300),
	},
]

## Boss 连战里"全部"目标的稳定 id。
const ALL_BOSSES_ID := "all"


# --- 赛道 ---------------------------------------------------------------------

static func track_id(track: int) -> StringName:
	return TRACK_IDS.get(track, &"boss_rush")


static func track_name(track: int) -> String:
	return String(TRACK_NAMES.get(track, "试炼"))


static func track_tagline(track: int) -> String:
	return String(TRACK_TAGLINES.get(track, ""))


static func track_rules(track: int) -> Array:
	return (TRACK_RULES.get(track, []) as Array).duplicate()


## 菜单 / HUD 上的一行固定装载摘要。
static func loadout_summary(track: int) -> String:
	var loadout: Dictionary = LOADOUTS.get(track, LOADOUTS[Track.BOSS_RUSH])
	var parts := ["生命 %d" % int(loadout.get("hp", BASE_MAX_HP))]
	var sockets: Array = loadout.get("sockets", [])
	var names := PackedStringArray()
	for core_id in sockets:
		var core := AbilityCatalog.for_id(StringName(core_id))
		names.append(core.display_name if core != null else String(core_id))
	for core_id in loadout.get("pouch", []):
		var core := AbilityCatalog.for_id(StringName(core_id))
		names.append("袋:%s" % (core.display_name if core != null else String(core_id)))
	if names.is_empty():
		parts.append("无锈核")
	else:
		parts.append("锈核 " + " · ".join(names))
	if track == Track.BOSS_RUSH:
		parts.append("每场回复 1 HP")
	else:
		parts.append("计时到出口")
	return " · ".join(parts)


static func is_valid_track(track: int) -> bool:
	return TRACKS.has(track)


# --- 解锁门 ---------------------------------------------------------------------

## 试炼入口是否已解锁。战役在第七章通关 / 任一结局时写 trial_unlocked；
## 旧档没有这个旗标时直接看章节完成旗标与结局状态（只读）。
static func unlocked() -> bool:
	if SaveData.has_flag(UNLOCK_FLAG):
		return true
	if _chapter_done(UNLOCK_CHAPTER):
		return true
	if SaveData.ending != "" or SaveData.peek_ending() != "":
		return true
	return SaveData.has_flag("game_complete")


static func unlock_requirement() -> String:
	return "通关第七章，或走完任一结局后解锁"


## 章节完成旗标（沿用 StoryFlow.DONE_FLAGS，不另造一套）。
static func chapter_flag(level_id: String) -> String:
	if StoryFlow.DONE_FLAGS.has(level_id):
		return String(StoryFlow.DONE_FLAGS[level_id])
	return level_id + "_done"


static func _chapter_done(level_id: String) -> bool:
	if level_id == "":
		return false
	return SaveData.has_flag(chapter_flag(level_id))


# --- 目标（章节 / Boss） -------------------------------------------------------

## 已通关章节，按 GameContext.LEVEL_ORDER 顺序。[{id, title, flag}]
static func cleared_chapters() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for level_id in GameContext.LEVEL_ORDER:
		if _chapter_done(level_id):
			out.append(_chapter_entry(level_id))
	return out


## 全部章节（未通关也列出）—— 菜单用来显示灰行，测试用来验证顺序。
static func all_chapters() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for level_id in GameContext.LEVEL_ORDER:
		out.append(_chapter_entry(level_id))
	return out


static func _chapter_entry(level_id: String) -> Dictionary:
	var title := ChapterText.title_of(level_id)
	if title == "":
		title = level_id
	return {
		"id": level_id,
		"title": title,
		"subtitle": ChapterText.subtitle_of(level_id),
		"flag": chapter_flag(level_id),
		"done": _chapter_done(level_id),
	}


## 可打的 Boss（对应章节已通关 + Boss 场景已交付），按 LEVEL_ORDER 排序。
static func available_bosses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in BOSS_TABLE:
		var row: Dictionary = entry
		if not _boss_ready(row):
			continue
		out.append((row as Dictionary).duplicate(true))
	return out


## Boss 行是否可打：场景存在 + 该 Boss 所在章节已通关（或旧档直接用 boss 死亡旗标）。
static func _boss_ready(row: Dictionary) -> bool:
	var scene := String(row.get("scene", ""))
	if scene == "" or not ResourceLoader.exists(scene):
		return false
	var flag := String(row.get("flag", ""))
	if flag != "" and SaveData.has_flag(flag):
		return true
	var level_id := String(row.get("level_id", ""))
	return _chapter_done(level_id)


## 某条赛道当前可选的目标列表。Boss 连战固定只有一格"全部 Boss"。
static func targets_for(track: int) -> Array[Dictionary]:
	if track == Track.BOSS_RUSH:
		var bosses := available_bosses()
		if bosses.is_empty():
			return []
		return [{
			"id": ALL_BOSSES_ID,
			"title": "全 部 Boss",
			"subtitle": "%d 场连战" % bosses.size(),
			"done": true,
		}]
	var out: Array[Dictionary] = []
	for entry in cleared_chapters():
		out.append((entry as Dictionary).duplicate(true))
	return out


## 目标显示名（结算 / 记录 / 菜单共用同一口径）。
static func target_title(track: int, target_id: String) -> String:
	if track == Track.BOSS_RUSH:
		return "全 部 Boss"
	for entry in all_chapters():
		if String(entry.get("id", "")) == target_id:
			return String(entry.get("title", target_id))
	return target_id


static func target_subtitle(track: int, target_id: String) -> String:
	if track == Track.BOSS_RUSH:
		return "%d 场连战" % available_bosses().size()
	for entry in all_chapters():
		if String(entry.get("id", "")) == target_id:
			return String(entry.get("subtitle", ""))
	return ""


# --- 场次（实际加载哪一关） -----------------------------------------------------

## 一个目标要顺序加载的场次。BOSS_RUSH = 每只 Boss 一场；限时 / 禁核 = 单章。
## 每场：{level_id, scene, spawn, boss_kind, title}
static func stages_for(track: int, target_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if track == Track.BOSS_RUSH:
		for row in available_bosses():
			var level_id := String(row.get("level_id", ""))
			var scene := String(GameContext.LEVELS.get(level_id, ""))
			if scene == "":
				continue
			out.append({
				"level_id": level_id,
				"scene": scene,
				"spawn": (row.get("spawn", Vector2.INF) as Vector2),
				"boss_kind": String(row.get("kind", "")),
				"title": String(row.get("title", "")),
			})
		return out
	var scene := String(GameContext.LEVELS.get(target_id, ""))
	if scene == "" or not _chapter_done(target_id):
		return out
	out.append({
		"level_id": target_id,
		"scene": scene,
		"spawn": Vector2.INF,
		"boss_kind": "",
		"title": target_title(track, target_id),
	})
	return out


# --- 固定装载 / 评级 ------------------------------------------------------------

static func loadout_for(track: int) -> Dictionary:
	var row: Dictionary = LOADOUTS.get(track, LOADOUTS[Track.BOSS_RUSH])
	return (row as Dictionary).duplicate(true)


## 基准时间：一章 2:00；Boss 连战每场 2:30。
static func par_ms(track: int, stage_count: int = 1) -> int:
	if track == Track.BOSS_RUSH:
		return PAR_BOSS_MS * maxi(1, stage_count)
	return PAR_CHAPTER_MS


static func death_penalty_ms(track: int) -> int:
	return int(DEATH_PENALTY_MS.get(track, 20000))


## 把死亡折算成罚时后的成绩（评级与"是否变快"都用它，原始用时照原样记录）。
static func score_ms(track: int, elapsed_ms: int, deaths: int) -> int:
	return maxi(0, elapsed_ms) + maxi(0, deaths) * death_penalty_ms(track)


static func rank_for(track: int, elapsed_ms: int, deaths: int,
		stage_count: int = 1) -> StringName:
	var score := score_ms(track, elapsed_ms, deaths)
	var par := par_ms(track, stage_count)
	for entry in RANK_BOUNDS:
		if float(score) <= float(par) * float(entry[1]):
			return StringName(entry[0])
	return &"B"


## 评级颜色（与 UI 调色板同源）：S 余烬金、A 锈橙、B 灰烬。
static func rank_color(rank: StringName) -> Color:
	match rank:
		&"S":
			return UiKit.EMBER
		&"A":
			return UiKit.RUST_MID
		_:
			return UiKit.ASH


## 赛道 tab 的一行副题（菜单底部说明用）。
static func track_rule_lines() -> Array[String]:
	var out: Array[String] = []
	for track in TRACKS:
		out.append("%s —— %s" % [track_name(track), track_tagline(track)])
	return out
