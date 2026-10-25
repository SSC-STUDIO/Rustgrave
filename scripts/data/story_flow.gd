class_name StoryFlow
extends RefCounted
## 章与章之间的承接数据（contract §1.3）+ 已通关章节的「前情提要」口径。
##
## 一个边界 = 出章门口的离场字幕（ChapterText.exit_captions，由 LevelExit 念）
## + 进下一章时**一次**的章间分镜：epilogue（上一章的余波，2–3 句）+ teaser（下一章的钩子，
## 1 句），由 storyboards.gd 配上画面，然后才是章节卡与醒来句。全部文本与 docs/story.md §12 同步。
##
## 章间只说剧情：你刚做了什么、为什么要去下一站。**不许**出现设计术语（幕 / 第几幕 / 债）
## 或未定义的旧称呼；伊尔的动作必须是「封进火种之前」的她，玩家听到的是火种里的回声
## （chapter_text_test / story_flow_test 会拦）。台词用「伊尔：……」写，分镜会把说话人单独画出来。
##
## 执行器是 scripts/levels/chapter_transition.gd；这里只放纯数据与纯函数，方便测试。
## 存档旗标：章间一次 = `interlude_<from>_seen`（不写任何章节完成旗标）；章节完成旗标
## 各自沿用既有存档口径（level01 是 boss_dead，终章是 game_complete），见 DONE_FLAGS。

## 13 个边界，顺序 = ChapterText.order() 的相邻两章。staging 决定没有分镜画面时的兜底布景，
## 也是分镜选背景主题的依据（见 storyboards.gd）。
const BOUNDARIES := [
	{
		"from": "level01", "to": "level02", "staging": "door",
		"epilogue": ["火种在炉座上亮了。你把它收回剑里。", "炉座下面的石板松开了，露出一个洞。"],
		"teaser": ["伊尔：下面有钟声。去找它，路在钟下面。"],
	},
	{
		"from": "level02", "to": "level02b", "staging": "water",
		"epilogue": ["回声停了，可真钟还在钟楼里响。", "地窟只有一扇钟门，通向运渣渠。"],
		"teaser": ["伊尔：先开闸。渣退了，才有路走。"],
	},
	{
		"from": "level02b", "to": "level03", "staging": "canal",
		"epilogue": ["闸开了，渣退下去，露出一条斜坡。", "斜坡通上城。下城的路，只剩圣殿的暗门。"],
		"teaser": ["上面是座死城。圣殿就在城的尽头。"],
	},
	{
		"from": "level03", "to": "level04", "staging": "town",
		"epilogue": ["你穿过空城。窗里亮的是锈苔，不是人。", "没有人拦你。他们早就自己走下去了。"],
		"teaser": ["伊尔：圣殿里有炉约的账本。去读它。"],
	},
	{
		"from": "level04", "to": "level04b", "staging": "crypt",
		"epilogue": ["账本上记着：烧了多少名字，换了多少盏灯。", "最后一页被撕走了。是伊尔撕的。"],
		"teaser": ["暗门通向地窖，末页就在那里。"],
	},
	{
		"from": "level04b", "to": "level05", "staging": "workshop",
		"epilogue": ["末页上写着：把火还给炉，让名字走。", "伊尔：我早就想这么做了。所以我把火种交给你。"],
		"teaser": ["暗门后面是工坊。那里能给你的剑接上死人的手艺。"],
	},
	{
		"from": "level05", "to": "level06", "staging": "rain",
		"epilogue": ["剑接上了第一枚锈核。你能借死人的手艺开门了。", "运渣道一路向上，通到雨里。"],
		"teaser": ["上去是雨里的墓园。钟楼在墓园后面。"],
	},
	{
		"from": "level06", "to": "level07", "staging": "bell",
		"epilogue": ["哈伦空手入土，他的剑成了钟楼的门闩。", "锻工们都知道一条旧话：还火的人，自己也要进炉。"],
		"teaser": ["钟楼上，真钟还在响。可钟舌去哪了？"],
	},
	{
		"from": "level07", "to": "level07b", "staging": "foundry",
		"epilogue": ["没人敲钟，钟自己在响。是炉心的回声。", "钟舌被熔成了火种。你背上的声音，就是伊尔。"],
		"teaser": ["井道通向铸钟厅。火种就是在那里铸成的。"],
	},
	{
		"from": "level07b", "to": "level08", "staging": "slag",
		"epilogue": ["铸钟人倒下前说：拿去，这是开门的钥匙。", "炉心门认火种，不认人。火种在你背上。"],
		"teaser": ["伊尔：下面是渣渊。我就是在那儿捡到你的。"],
	},
	{
		"from": "level08", "to": "level09", "staging": "rampart",
		"epilogue": ["你在这里被浇铸，铁成了，你先锈了。", "伊尔把自己封进火种之前，从渣里捡起了你。"],
		"teaser": ["梯子往上是城墙。墙挡的是炉风，不是人。"],
	},
	{
		"from": "level09", "to": "level09b", "staging": "wind",
		"epilogue": ["墙上站着的灰，是死了还在守墙的灰卫。", "风还是热的。炉心就在风的那头。"],
		"teaser": ["风口后面的崖道，通向炉心门。"],
	},
	{
		"from": "level09b", "to": "level10", "staging": "heart", "special": "pre_ending",
		"epilogue": ["最后一个灰卫让开了路，说：替我看看那团火。", "崖道尽头没有风，只有热。"],
		"teaser": ["炉心门就在下面。梦魇是不肯进炉的那匹战马。"],
	},
]

## 结局前后的特殊序列。结局字幕本身在 ChapterText.ENDINGS（文本单一源），
## 这里补的是「进终章前把两个选择的代价说清」与「结局之后的收束句」。
const SPECIALS := {
	"pre_ending": {
		"staging": "heart",
		"lines": ["伊尔：到了。门后只有一团火，和一个选择。",
				"还火：把剑推进炉，被困的名字都能走。可火种连着你，你也会散成铁。",
				"守炉：留下剑，你做新的守炉人。火不灭，名字不走，城一直半醒。"],
	},
	"post_ending": {
		"give": "被困了二百年的名字，终于都走了。",
		"keep": "炉火还亮着。城一直半醒。",
		"snuff": "火种灭了。再没有人替名字问一句。",
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
const RECAP_FALLBACK := "你刚醒。剑里有火种和伊尔，她要你把火种带回炉心。"

## 看过的分镜记在存档旗标里（故事页「回放」只列看过的）。
const BOARD_FLAG_PREFIX := "board_seen_"


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


## 进入 to_id 的那条边界；第一章没有（序章分镜与开场负责）。
static func edge_into(to_id: String) -> Dictionary:
	for edge in BOUNDARIES:
		if String(edge["to"]) == to_id:
			return (edge as Dictionary).duplicate(true)
	return {}


static func staging_of(edge: Dictionary) -> String:
	return String(edge.get("staging", "door"))


## 章间的一次性旗标：interlude_<from>_seen（contract §1.3）。
static func interlude_flag(from_id: String) -> String:
	return "interlude_%s_seen" % from_id


## 这个边界的分镜 id（storyboards.gd 按它出画面）。
static func board_id(from_id: String) -> String:
	return "interlude_%s" % from_id


## 一个边界要念的全部台词，按顺序：epilogue → teaser →（终章前）两个选择的代价。
## 分镜、测试、docs 同步都读这一份。
static func lines_of(edge: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for line in (edge.get("epilogue", []) as Array):
		out.append(String(line))
	for line in (edge.get("teaser", []) as Array):
		out.append(String(line))
	if String(edge.get("special", "")) == "pre_ending":
		for line in ((SPECIALS["pre_ending"] as Dictionary)["lines"] as Array):
			out.append(String(line))
	return out


## 进章时播的章间步骤（纯构造，测试直接读）。分镜自己念台词，所以这里只有 lock / board /
## unlock；目标一句不再在章间重复，由章节自己的醒来流程给（避免同一句念两遍）。
static func arrival_steps(to_id: String) -> Array:
	var edge := edge_into(to_id)
	if edge.is_empty():
		return []
	return [
		{"kind": "lock"},
		{"kind": "board", "id": board_id(String(edge["from"]))},
		{"kind": "unlock"},
	]


## 结局演出的分镜步骤：结局分镜（storyboards.gd 的 `ending_<kind>`）→ 滚动字幕（`credits`）。
## 没有 fx / lock：调用方自己决定前后摇。id 与 Storyboards.ending_id / CREDITS 一致（测试会对）。
static func ending_steps(kind: String) -> Array:
	return [
		{"kind": "board", "id": "ending_%s" % kind, "skip_all": false},
		{"kind": "board", "id": "credits", "skip_all": false},
	]


## 结局后的收束句（框架文本；真正的结局字幕在 ChapterText.ENDINGS.lines）。
static func post_ending_line(kind: String) -> String:
	return String((SPECIALS["post_ending"] as Dictionary).get(kind, ""))


## 结局播放器的字幕版步骤（没有分镜时的兜底，也给测试读）：
## 结局字幕（ChapterText，含「—— 锈墓・完 ——」）+ 收束句。
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


## 已通关章节数，按 DONE_FLAGS 的真实口径数（标题回看页和故事页共用）。
static func cleared_count(flags: Variant) -> int:
	var n := 0
	for id in ChapterText.order():
		var flag := done_flag(id)
		if flag != "" and flags.has(flag):
			n += 1
	return n
