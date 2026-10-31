class_name StoryFlow
extends RefCounted
## 节点进度、结局分镜衔接与动态前情提要（v4「焚名轮回」实时叙事版）。
##
## 关键改动：
##   · 彻底取消进出大区的 13 段强制黑屏章间播片（arrival_steps 恒返回空数组 []），
##     所有区域推进、岔路劝阻、串台破防与残片真相均由 NarrativeDirector + LiveVoiceBar 实时演绎。
##   · 保留序章（prologue）、四大结局（give / keep / snuff / true_break）与滚动字幕（credits）分镜。
##   · DONE_FLAGS 完整覆盖 14 个树状节点，并向下兼容旧版 level01..level10 完成旗标。

const BOUNDARIES: Array = []

const SPECIALS := {
	"pre_ending": {
		"staging": "heart",
		"lines": [
			"伊尔：到了。炉心门后就是终点。",
			"还火：顺着箭头把剑推进炉膛；守炉：停在门外替长明灯守夜。",
		],
	},
	"post_ending": {
		"give": "第四十九块焦黑胸牌落进坑底。第五十具泥模正在冷却。",
		"keep": "炉门外多了一尊不说话的灰卫。牧火信号转向下一座坟。",
		"snuff": "火种掐灭在掌心。这一次，没有人偶替骗局烧成灰。",
		"true_break": "二百年的炉约碎作废铁。你握着自己的真名，走进地面的天光。",
	},
}

## 14 节点完成旗标（与 NarrativeCatalog.STAGE_NODES 一一对应）。
const DONE_FLAGS := {
	"stage01": "stage01_done",
	"branch01": "branch01_done",
	"stage02": "stage02_done",
	"branch02": "branch02_done",
	"stage03": "stage03_done",
	"branch03": "branch03_done",
	"stage04": "stage04_done",
	"stage04b": "stage04b_done",
	"stage05": "stage05_done",
	"branch04": "branch04_done",
	"stage06": "stage06_done",
	"branch05": "branch05_done",
	"stage07": "stage07_done",
	"stage08_true": "true_ending_done",
}

const LEGACY_DONE_FLAGS := {
	"level01": "boss_dead",
	"level02": "undercroft_done",
	"level02b": "level02b_done",
	"level03": "level03_done",
	"level04": "level04_done",
	"level04b": "level04b_done",
	"level05": "level05_done",
	"level06": "level06_done",
	"level07": "level07_done",
	"level07b": "level07b_done",
	"level08": "level08_done",
	"level09": "level09_done",
	"level09b": "level09b_done",
	"level10": "game_complete",
}

const RECAP_FALLBACK := "你在腐液墓园苏醒。剑中女声自称伊尔，点亮路标催你送火种去炉心。"
const BOARD_FLAG_PREFIX := "board_seen_"


static func boundaries() -> Array:
	return BOUNDARIES.duplicate(true)


static func boundary_count() -> int:
	return BOUNDARIES.size()


static func for_edge(_from_id: String) -> Dictionary:
	return {}


static func edge_into(_to_id: String) -> Dictionary:
	return {}


static func staging_of(edge: Dictionary) -> String:
	return String(edge.get("staging", "door"))


static func interlude_flag(from_id: String) -> String:
	return "interlude_%s_seen" % from_id


static func board_id(from_id: String) -> String:
	return "interlude_%s" % from_id


static func lines_of(_edge: Dictionary) -> Array[String]:
	return []


## 无缝切房/切区契约：进关不再插入任何锁输入的黑屏章间分镜。
static func arrival_steps(_to_id: String) -> Array:
	return []


## 四大结局分镜步骤（give / keep / snuff / true_break）→ 滚动字幕（credits）。
static func ending_steps(kind: String) -> Array:
	return [
		{"kind": "board", "id": "ending_%s" % kind, "skip_all": false},
		{"kind": "board", "id": "credits", "skip_all": false},
	]


static func post_ending_line(kind: String) -> String:
	return String((SPECIALS["post_ending"] as Dictionary).get(kind, ""))


static func post_ending_steps(kind: String) -> Array:
	var lines := ChapterText.ending_lines_of(kind)
	if lines.is_empty():
		return []
	var steps: Array = [{"kind": "lock"}]
	for line in lines:
		steps.append({"kind": "caption", "text": String(line), "hold": 2.2})
	var closing := post_ending_line(kind)
	if closing != "":
		steps.append({"kind": "caption", "text": closing, "hold": 2.4})
	steps.append({"kind": "unlock"})
	return steps


static func done_flag(level_id: String) -> String:
	if DONE_FLAGS.has(level_id):
		return String(DONE_FLAGS[level_id])
	return String(LEGACY_DONE_FLAGS.get(level_id, ""))


static func cleared_chapters() -> Array[String]:
	var cleared: Array[String] = []
	for id in ChapterText.order():
		if NarrativeCatalog.is_node_cleared(id, SaveData.flags):
			cleared.append(id)
	return cleared


static func recap_text() -> String:
	var cleared := cleared_chapters()
	var frags := NarrativeCatalog.fragment_count(SaveData.flags)
	if cleared.is_empty() and frags == 0:
		return RECAP_FALLBACK
	var recent: Array = []
	for i in range(maxi(cleared.size() - 2, 0), cleared.size()):
		recent.append(cleared[i])
	var lines := ChapterText.recap_lines_for(recent)
	if frags > 0:
		lines.append("已寻回真名残片 %d / 5。" % frags)
	if lines.is_empty():
		return RECAP_FALLBACK
	return "  ".join(lines)


static func cleared_count(flags: Variant) -> int:
	if flags == null:
		return 0
	var n := 0
	for id in ChapterText.order():
		if NarrativeCatalog.is_node_cleared(id, flags):
			n += 1
	return n
