class_name StoryFlow
extends RefCounted
## 章与章之间的承接数据（contract §1.3）+ 已通关章节的「前情提要」口径。
##
## 一个边界 = 出章门口的离场字幕（ChapterText.exit_captions，由 LevelExit 念）
## + 进下一章时**一次**的间幕：epilogue（上一章的余波，2–3 句）+ teaser（下一章的钩子，
## 1 句）+ 一句本章目标，然后才是章节卡与醒来句。全部文本与 docs/story.md §12 同步。
##
## M1R3 canon：间幕只说剧情——你刚做了什么、你欠她一次问火、下一站为什么要去。
## **不许**出现设计术语（幕 / 第几幕 / 债）或未定义的旧称呼；伊尔的动作必须是
## 「封核之前」的她，玩家听到的是核里的回声（chapter_text_test / story_flow_test 会拦）。
##
## 间幕执行器是 scripts/levels/chapter_transition.gd；这里只放纯数据与纯函数，方便测试。
## 存档旗标：间幕一次 = `interlude_<from>_seen`（不写任何章节完成旗标）；章节完成旗标
## 各自沿用既有存档口径（level01 是 boss_dead，终章是 game_complete），见 DONE_FLAGS。

## 13 个边界，顺序 = ChapterText.order() 的相邻两章。staging 决定间幕布景画什么。
const BOUNDARIES := [
	{
		"from": "level01", "to": "level02", "staging": "door",
		"epilogue": ["炉座只认点过的核。你把残芯点亮，又收回剑里。", "城醒了一层，往下又开了一扇门。"],
		"teaser": ["跟着钟声往下。地窟底下，才找得到上城的路。"],
	},
	{
		"from": "level02", "to": "level02b", "staging": "water",
		"epilogue": ["钟停了。你停的只是回声。", "真钟还在钟楼响，钟舌已经被人惦记上了。",
				"去炉心没有直路：渠顶旧街通圣殿，圣殿地窖才有下城的暗门。"],
		"teaser": ["门后是运渣水渠。渠在城上，炉心在城下——要下去，得先上去。"],
	},
	{
		"from": "level02b", "to": "level03", "staging": "canal",
		"epilogue": ["闸开了。渣往低处退，露出上城的斜坡。", "守渠人到死都绞着闸。"],
		"teaser": ["上面是死城。圣殿还亮着一盏守灯。"],
	},
	{
		"from": "level03", "to": "level04", "staging": "town",
		"epilogue": ["你穿过死城。窗里的灯是锈苔，不是人。", "你欠她一次问火。往下走，才有机会还。"],
		"teaser": ["圣殿的守灯还亮着。炉约的账在灯下。"],
	},
	{
		"from": "level04", "to": "level04b", "staging": "crypt",
		"epilogue": ["账翻到末页，被人撕走了。", "封进核之前，是伊尔自己把它撕下来的。"],
		"teaser": ["暗门通地窖。末页在下面。"],
	},
	{
		"from": "level04b", "to": "level05", "staging": "workshop",
		"epilogue": ["末页是伊尔的字：把火还给炉。", "封进核之前，她把残芯嵌进你背上的剑，把剑交给你。"],
		"teaser": ["末页上留着她封进核前画的一笔，指向工坊。接核的剑槽在那里切开。"],
	},
	{
		"from": "level05", "to": "level06", "staging": "rain",
		"epilogue": ["剑在工坊接上第一枚锈核。核里是死人做过的行当。", "下一个机关，靠死人的手艺打开。"],
		"teaser": ["运渣道通向雨里的墓园。钟楼的门闩来自一把剑。"],
	},
	{
		"from": "level06", "to": "level07", "staging": "bell",
		"epilogue": ["哈伦空手入土。薇尔留下，她的剑走了。", "两个锻工都知道炉约的末条：还火的人，自己也要进炉。"],
		"teaser": ["钟楼在雨上面。真钟还在响——可没人敲它。"],
	},
	{
		"from": "level07", "to": "level07b", "staging": "foundry",
		"epilogue": ["钟楼上没有人敲钟。钟自己响。", "你背上的回声是核里的伊尔，材料就是这口钟的钟舌。"],
		"teaser": ["铸钟厅里有最后一枚核的模子。"],
	},
	{
		"from": "level07b", "to": "level08", "staging": "slag",
		"epilogue": ["铸钟人倒下前说：拿去。用它开门——门认核不认人。", "残芯一直是灯芯，也是炉心门的钥匙。"],
		"teaser": ["锈核的原料从渣里捞。下到渣底，看你锈掉的地方。"],
	},
	{
		"from": "level08", "to": "level09", "staging": "rampart",
		"epilogue": ["你在这里淬火失败。铁成了，你先锈了。", "封进核之前，伊尔从渣面把你捡回去，把残芯嵌进你背上的剑，点亮你。"],
		"teaser": ["梯子往上是城墙。墙挡的不是人，是炉风。"],
	},
	{
		"from": "level09", "to": "level09b", "staging": "wind",
		"epilogue": ["墙上的灰都站着。灰卫死了还在守墙。", "墙挡了两百年的炉风，风还是热的。"],
		"teaser": ["风口后面的崖道通向炉心门。没有灰卫回来过。"],
	},
	{
		"from": "level09b", "to": "level10", "staging": "heart", "special": "pre_ending",
		"epilogue": ["最后一个灰卫让开路。他说：替我看看火该不该还。", "风口后面没有风，只有热。"],
		"teaser": ["炉心门就在下面。先问火一句，门才开——钥匙在你背上。"],
	},
]

## 结局前后的特殊序列。结局字幕本身在 ChapterText.ENDINGS（文本单一源），
## 这里补的是「进终章前先问火、门才开」与「结局之后的收束句」。
const SPECIALS := {
	"pre_ending": {
		"staging": "heart",
		"lines": ["先在门外问火一句：这火该不该还？门才会开。",
				"送剑：火应你一句，名字和伊尔归火，你散成铁。",
				"守火：火不答，铁里的名字还困着；你永留炉边，城一直半醒，她还在。"],
	},
	"post_ending": {
		"give": "这一问，火应了一句，你听不真。",
		"keep": "这一问，火没有回答。城一直半醒。",
		"snuff": "这一问，没有人答。",
	},
}

## 章节完成旗标（存档口径，沿用既有实现；不改存档结构）。
const DONE_FLAGS := {
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

## 还没通关任何章节时，暂停菜单的「前情提要」用这一句。
const RECAP_FALLBACK := "你刚醒。剑里有残芯和伊尔，她等你问火一句。"

## 间幕播完后进章节卡；这两个数字是节奏，不是预算。
const EPILOGUE_HOLD := 2.2
const TEASER_HOLD := 2.6
const OBJECTIVE_HOLD := 1.8


static func boundaries() -> Array:
	return BOUNDARIES.duplicate(true)


static func boundary_count() -> int:
	return BOUNDARIES.size()


## 从 from_id 出发的边界；没有则空字典。
static func for_edge(from_id: String) -> Dictionary:
	for edge in BOUNDARIES:
		if String(edge["from"]) == from_id:
			return (edge as Dictionary).duplicate(true)
	return {}


## 进入 to_id 的那条边界；第一章没有（开场分镜负责）。
static func edge_into(to_id: String) -> Dictionary:
	for edge in BOUNDARIES:
		if String(edge["to"]) == to_id:
			return (edge as Dictionary).duplicate(true)
	return {}


static func staging_of(edge: Dictionary) -> String:
	return String(edge.get("staging", "door"))


## 间幕的一次性旗标：interlude_<from>_seen（contract §1.3）。
static func interlude_flag(from_id: String) -> String:
	return "interlude_%s_seen" % from_id


## 进章时播的间幕步骤（纯构造，测试直接读）。from 为上一章 id。
## 顺序：epilogue 2–3 句 → teaser 1 句 → （终章前的两个选择代价）→ 本章目标一句。
static func arrival_steps(to_id: String) -> Array:
	var edge := edge_into(to_id)
	if edge.is_empty():
		return []
	var steps: Array = [{"kind": "lock"}]
	for line in edge.get("epilogue", []):
		steps.append({"kind": "caption", "text": String(line), "hold": EPILOGUE_HOLD})
	for line in edge.get("teaser", []):
		steps.append({"kind": "caption", "text": String(line), "hold": TEASER_HOLD})
	if String(edge.get("special", "")) == "pre_ending":
		for line in SPECIALS["pre_ending"]["lines"]:
			steps.append({"kind": "caption", "text": String(line), "hold": EPILOGUE_HOLD})
	var objective := ChapterText.objective_of(to_id)
	if objective != "":
		steps.append({"kind": "caption", "text": "目标 · %s" % objective, "hold": OBJECTIVE_HOLD})
	steps.append({"kind": "unlock"})
	return steps


## 结局后的收束句（框架文本；真正的结局字幕在 ChapterText.ENDINGS.lines）。
static func post_ending_line(kind: String) -> String:
	return String(SPECIALS["post_ending"].get(kind, ""))


## 结局播放器的完整步骤：结局字幕（ChapterText，含「—— 锈墓・完 ——」）+ 收束句。
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
	return String(DONE_FLAGS.get(level_id, ""))


## 已通关章节 id（按战役顺序）。
static func cleared_chapters() -> Array[String]:
	var cleared: Array[String] = []
	for id in ChapterText.order():
		var flag := done_flag(id)
		if flag != "" and SaveData.has_flag(flag):
			cleared.append(id)
	return cleared


## 暂停菜单「前情提要」：最近 1–2 个已通关章节的 recap（没通关过的给一句兜底）。
static func recap_text() -> String:
	var cleared := cleared_chapters()
	if cleared.is_empty():
		return RECAP_FALLBACK
	var recent: Array = []
	for i in range(maxi(cleared.size() - 2, 0), cleared.size()):
		recent.append(cleared[i])
	var lines := ChapterText.recap_lines_for(recent)
	if lines.is_empty():
		return RECAP_FALLBACK
	return "  ".join(lines)
