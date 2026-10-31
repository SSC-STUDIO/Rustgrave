extends Object
## 回火试炼（Tempering Trials）的静态数据源（v4 树状节点战役适配版）。
##
## 文件不带 class_name：所有使用方统一用 `const Catalog := preload("res://scripts/data/trial_catalog.gd")` 引用。
## 试炼只读战役旗标，绝不写回战役档；记录独立保存在 `user://rustgrave_trials.cfg`。

enum Track { BOSS_RUSH, TIME_ATTACK, BARE_STEEL }

const TRACKS: Array[int] = [Track.BOSS_RUSH, Track.TIME_ATTACK, Track.BARE_STEEL]

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
	Track.TIME_ATTACK: ["在已通关的节点里任选一章", "计时从落地说起，到推开终房出口为止",
			"热锻 / 钩锁 / 余烬步三枚锈核固定镶满，路上无补给"],
	Track.BARE_STEEL: ["在已通关的节点里任选一章", "剑鞘空着：没有锈核能力，也没有补给",
			"计时与限时疾行同口径，评级更苛刻"],
}

## 解锁门（契约 §5）：通关铸钟井（stage05，陆章）或任一结局后开放；兼容旧档 level07_done。
const UNLOCK_FLAG := "trial_unlocked"
const UNLOCK_CHAPTER := "stage05"

const RECORDS_VERSION := 1

const BASE_MAX_HP := 5
const EQUIPMENT := {
	"weapon": "broken_sword",
	"armor": "broken_armor",
	"trinket": "broken_pendant",
	"bag": [],
}
const LOADOUTS := {
	Track.BOSS_RUSH: {"hp": 5, "sockets": [], "pouch": []},
	Track.TIME_ATTACK: {"hp": 5, "sockets": [&"kiln_core", &"tether_core"],
			"pouch": [&"ember_core"]},
	Track.BARE_STEEL: {"hp": 5, "sockets": [], "pouch": []},
}

const DEATH_PENALTY_MS := {
	Track.BOSS_RUSH: 45000,
	Track.TIME_ATTACK: 20000,
	Track.BARE_STEEL: 30000,
}
const PAR_CHAPTER_MS := 120000
const PAR_BOSS_MS := 150000
const RANK_BOUNDS := [["S", 1.0], ["A", 1.35], ["B", 1.9]]
const RANKS: Array[StringName] = [&"S", &"A", &"B"]

## Boss 连战全部 8 位首领（含真结局首领司炉母模），按战役推进顺序排列。
## room 指定 StageLevel 直接载入的首领房间，spawn 为竞技场封门线左侧的安全接地坐标。
const BOSS_TABLE := [
	{
		"kind": "executioner",
		"level_id": "stage01",
		"room": "S5",
		"flag": "boss_dead",
		"title": "炉约刽子手 · 铸渣残躯",
		"scene": "res://scenes/enemies/ExecutionerBoss.tscn",
		"spawn": Vector2(96.0, 324.0),
	},
	{
		"kind": "hollow_bell",
		"level_id": "stage02",
		"room": "S3",
		"flag": "hollow_bell_dead",
		"title": "空钟 · 数魂残响",
		"scene": "res://scenes/enemies/HollowBell.tscn",
		"spawn": Vector2(96.0, 324.0),
	},
	{
		"kind": "capstan_warden",
		"level_id": "stage02",
		"room": "S6",
		"flag": "capstan_dead",
		"title": "绞盘守渠人",
		"scene": "res://scenes/enemies/CapstanWarden.tscn",
		"spawn": Vector2(96.0, 324.0),
	},
	{
		"kind": "silent_choir",
		"level_id": "stage03",
		"room": "S5",
		"flag": "choir_dead",
		"title": "无声唱诗班",
		"scene": "res://scenes/enemies/SilentChoir.tscn",
		"spawn": Vector2(96.0, 324.0),
	},
	{
		"kind": "bell_founder",
		"level_id": "stage05",
		"room": "S4",
		"flag": "founder_dead",
		"title": "铸钟人",
		"scene": "res://scenes/enemies/BellFounder.tscn",
		"spawn": Vector2(96.0, 324.0),
	},
	{
		"kind": "emberwind_herald",
		"level_id": "stage06",
		"room": "S5",
		"flag": "herald_dead",
		"title": "烬风先驱",
		"scene": "res://scenes/enemies/EmberwindHerald.tscn",
		"spawn": Vector2(96.0, 324.0),
	},
	{
		"kind": "nightmare_boss",
		"level_id": "stage07",
		"room": "S2",
		"flag": "nightmare_dead",
		"title": "锈 墓 梦 魇 · 护 门 战 马",
		"scene": "res://scenes/enemies/NightmareBoss.tscn",
		"spawn": Vector2(96.0, 324.0),
	},
	{
		"kind": "furnace_mother",
		"level_id": "stage08_true",
		"room": "T4",
		"flag": "furnace_mother_dead",
		"title": "司 炉 母 模 · 百 名 熔 核",
		"scene": "res://scenes/enemies/FurnaceMotherBoss.tscn",
		"spawn": Vector2(96.0, 324.0),
	},
]


static func boss_spawn(row: Dictionary) -> Vector2:
	return row.get("spawn", Vector2(96.0, 324.0))


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


# --- 解锁门 -------------------------------------------------------------------

static func unlocked() -> bool:
	if SaveData.has_flag(UNLOCK_FLAG):
		return true
	if _chapter_done(UNLOCK_CHAPTER) or SaveData.has_flag("level07_done"):
		return true
	if SaveData.ending != "" or SaveData.peek_ending() != "":
		return true
	return SaveData.has_flag("game_complete") or SaveData.has_flag("true_ending_done")


static func unlock_chapter_label() -> String:
	return "%s章" % ChapterText.number_of(UNLOCK_CHAPTER)


static func unlock_requirement() -> String:
	return "通关%s，或走完任一结局后解锁" % unlock_chapter_label()


static func chapter_flag(level_id: String) -> String:
	var flag := StoryFlow.done_flag(level_id)
	if flag != "":
		return flag
	return level_id + "_done"


static func _chapter_done(level_id: String) -> bool:
	if level_id == "":
		return false
	if NarrativeCatalog.STAGE_NODES.has(level_id):
		return NarrativeCatalog.is_node_cleared(level_id, SaveData.flags)
	return SaveData.has_flag(chapter_flag(level_id))


# --- 目标（章节 / Boss） -------------------------------------------------------

static func cleared_chapters() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for level_id in GameContext.LEVEL_ORDER:
		if _chapter_done(level_id):
			out.append(_chapter_entry(level_id))
	return out


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


static func available_bosses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in BOSS_TABLE:
		var row: Dictionary = entry
		if not _boss_ready(row):
			continue
		out.append((row as Dictionary).duplicate(true))
	return out


static func _boss_ready(row: Dictionary) -> bool:
	var scene := String(row.get("scene", ""))
	if scene == "" or not ResourceLoader.exists(scene):
		return false
	var flag := String(row.get("flag", ""))
	if flag != "" and SaveData.has_flag(flag):
		return true
	var level_id := String(row.get("level_id", ""))
	return _chapter_done(level_id)


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


static func target_title(track: int, target_id: String) -> String:
	if track == Track.BOSS_RUSH:
		for row in BOSS_TABLE:
			if String(row["kind"]) == target_id:
				return String(row["title"])
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

static func stages_for(track: int, target_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if track == Track.BOSS_RUSH:
		for row in available_bosses():
			if target_id != ALL_BOSSES_ID and target_id != String(row.get("kind", "")):
				continue
			var level_id := String(row.get("level_id", ""))
			var scene := String(GameContext.LEVELS.get(level_id, ""))
			if scene == "":
				continue
			out.append({
				"level_id": level_id,
				"room": String(row.get("room", "")),
				"scene": scene,
				"spawn": boss_spawn(row),
				"death_flag": String(row.get("flag", "")),
				"boss_kind": String(row.get("kind", "")),
				"title": String(row.get("title", "")),
			})
		return out
	var scene := String(GameContext.LEVELS.get(target_id, ""))
	if scene == "" or not _chapter_done(target_id):
		return out
	out.append({
		"level_id": target_id,
		"room": "",
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


static func par_ms(track: int, stage_count: int = 1) -> int:
	if track == Track.BOSS_RUSH:
		return PAR_BOSS_MS * maxi(1, stage_count)
	return PAR_CHAPTER_MS


static func death_penalty_ms(track: int) -> int:
	return int(DEATH_PENALTY_MS.get(track, 20000))


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


static func rank_color(rank: StringName) -> Color:
	match rank:
		&"S":
			return UiKit.EMBER
		&"A":
			return UiKit.RUST_MID
		_:
			return UiKit.ASH


static func track_rule_lines() -> Array[String]:
	var out: Array[String] = []
	for track in TRACKS:
		out.append("%s —— %s" % [track_name(track), track_tagline(track)])
	return out
