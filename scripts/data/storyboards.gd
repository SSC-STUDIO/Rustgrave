extends RefCounted
## 剧情分镜数据（纯数据 + 纯函数，没有场景引用）。
##
## 一段分镜 = 若干镜头（shot）。镜头 = 一个布景 set + 几个演员 actors + 一种运镜 cam +
## 一种粒子 fx + 几句台词 lines。台词全部来自 ChapterText / StoryFlow（文本单一源），
## 这里只负责「配画面」：
##   prologue          新游戏开场前的序章：交代炉约 / 守炉人 / 火种 / 伊尔 / 你 / 代价
##   interlude_<from>  13 段章间：epilogue 配上一章的地方，teaser 配下一站，终章前再配代价
##   ending_<kind>     三个结局（give / keep / snuff）+ 收束句
##   credits           滚动字幕
##
## 画面两层：镜头有 `art`（assets/story/<art>.png 的关键插图）且文件存在时用插图；
## 没有就由 storyboard_stage.gd 用现成像素素材 + 程序化演员实时拼出来（兜底必须能独立成立）。
##
## 布景 set：ThemeBackdrop 的主题名（graveyard / undercroft / forge / forge_core / cathedral /
## belltower / ramparts / town / industrial）+ title_hall（标题大厅）+ dark（纯黑）。
## 演员 [kind, x(0..1), scale]：knight seed flame souls swords gate figure yir ash_guard ring。
## 运镜：still push pan_right pan_left rise。粒子：embers ash dust none。

const PROLOGUE := "prologue"
const CREDITS := "credits"
const ART_DIR := "res://assets/story/"
## 台词节奏：打字速度（字/秒）与每句停留。估算时长、播放器、测试都读这里。
const CHARS_PER_SEC := 22.0
const LINE_HOLD := 1.3
const SHOT_FADE := 0.5

## 章间每个边界的画面：[A（epilogue 的地方）, B（teaser 的地方）, C（终章前的代价）]。
const INTERLUDE_VISUALS := {
	"level01": [["graveyard", [["seed", 0.5, 1.0]], "push", "embers"],
			["undercroft", [["knight", 0.3, 2.0]], "pan_right", "dust"]],
	"level02": [["undercroft", [["knight", 0.35, 2.0]], "still", "dust"],
			["industrial", [], "pan_right", "dust"]],
	"level02b": [["industrial", [["knight", 0.4, 2.0]], "pan_right", "dust"],
			["town", [], "rise", "ash"]],
	"level03": [["town", [["knight", 0.35, 2.0]], "pan_right", "ash"],
			["cathedral", [["flame", 0.72, 0.6]], "push", "embers"]],
	"level04": [["cathedral", [["seed", 0.5, 1.0]], "push", "embers"],
			["undercroft", [["gate", 0.62, 1.0]], "pan_right", "dust"]],
	"level04b": [["undercroft", [["yir", 0.6, 1.6]], "push", "embers"],
			["industrial", [["knight", 0.3, 2.0]], "pan_right", "ash"]],
	"level05": [["industrial", [["knight", 0.4, 2.0]], "still", "embers"],
			["graveyard", [], "rise", "ash"]],
	"level06": [["graveyard", [["knight", 0.35, 2.0]], "still", "ash"],
			["belltower", [], "rise", "dust"]],
	"level07": [["belltower", [["seed", 0.5, 1.0]], "push", "dust"],
			["forge", [], "pan_right", "embers"]],
	"level07b": [["forge", [["figure", 0.68, 1.6], ["seed", 0.3, 1.0]], "push", "embers"],
			["forge", [["flame", 0.5, 1.0]], "pan_right", "embers"]],
	"level08": [["forge", [["knight", 0.4, 2.0]], "still", "embers"],
			["ramparts", [], "rise", "ash"]],
	"level09": [["ramparts", [["ash_guard", 0.55, 1.5]], "pan_right", "ash"],
			["ramparts", [], "pan_left", "ash"]],
	"level09b": [["ramparts", [["ash_guard", 0.6, 1.6]], "push", "ash"],
			["forge_core", [["gate", 0.7, 1.0]], "push", "embers"],
			["forge_core", [["gate", 0.7, 1.0], ["seed", 0.4, 1.0], ["knight", 0.22, 2.0]], "still", "embers"]],
}

## 结局画面：每个结局一组「镜头 → 用哪几句 ChapterText 结局字幕」。
const ENDING_VISUALS := {
	"give": [
		[["forge_core", [["gate", 0.72, 1.0], ["knight", 0.3, 2.0], ["seed", 0.46, 1.0]], "push", "embers"], [0]],
		[["forge_core", [["souls", 0.5, 1.0], ["flame", 0.72, 1.4]], "rise", "embers"], [1]],
		[["forge_core", [["souls", 0.4, 1.0], ["yir", 0.62, 1.6]], "push", "ash"], [2, 3]],
		[["forge_core", [["knight", 0.38, 2.0], ["yir", 0.62, 1.6], ["souls", 0.5, 1.0]], "rise", "ash"], [4]],
	],
	"keep": [
		[["forge_core", [["gate", 0.72, 1.0], ["knight", 0.3, 2.0], ["seed", 0.46, 1.0]], "push", "embers"], [0]],
		[["forge_core", [["flame", 0.7, 1.4], ["knight", 0.32, 2.0]], "still", "embers"], [1]],
		[["forge_core", [["yir", 0.55, 1.6], ["seed", 0.4, 1.0]], "push", "embers"], [2]],
		[["forge_core", [["knight", 0.32, 2.0], ["flame", 0.7, 1.4]], "pan_left", "embers"], [3, 4]],
	],
	"snuff": [
		[["forge", [["knight", 0.35, 2.0], ["seed", 0.55, 1.0]], "push", "embers"], [0]],
		[["forge", [["yir", 0.6, 1.6]], "still", "ash"], [1]],
		[["dark", [["souls", 0.5, 1.0]], "still", "ash"], [2]],
		[["dark", [["flame", 0.5, 0.35]], "still", "ash"], [3]],
	],
}

## 滚动字幕（不写人名：只写这个游戏自己的话）。
const CREDITS_LINES: Array[String] = [
	"锈  墓",
	"RUSTGRAVE",
	"",
	"余烬骑士的旅程",
	"",
	"炉约  二百年",
	"守炉人  一百年",
	"伊尔  最后一个",
	"",
	"被困的名字",
	"会记得你在炉前做过的选择。",
	"",
	"谢谢你玩到这里。",
]
const CREDITS_SECONDS := 16.0


static func shots(id: String) -> Array:
	if id == PROLOGUE:
		return _prologue()
	if id == CREDITS:
		return _credits()
	if id.begins_with("interlude_"):
		return _interlude(id.trim_prefix("interlude_"))
	if id.begins_with("ending_"):
		return _ending(id.trim_prefix("ending_"))
	return []


static func has(id: String) -> bool:
	return not shots(id).is_empty()


static func interlude_id(from_id: String) -> String:
	return "interlude_%s" % from_id


static func ending_id(kind: String) -> String:
	return "ending_%s" % kind


## 一段分镜里按顺序出现的全部台词（测试与故事页用）。
static func lines_of(id: String) -> Array[String]:
	var out: Array[String] = []
	for shot in shots(id):
		for line in (shot as Dictionary).get("lines", []):
			out.append(String(line))
	return out


static func shot_seconds(shot: Dictionary) -> float:
	var total := SHOT_FADE + float(shot.get("seconds", 0.0))
	for line in shot.get("lines", []):
		total += float(String(line).length()) / CHARS_PER_SEC + LINE_HOLD
	return total


## 不被打断时的总时长（秒）。Director.estimate_seconds 的 board 步骤读它。
static func seconds_of(id: String) -> float:
	var total := 0.0
	for shot in shots(id):
		total += shot_seconds(shot as Dictionary)
	return total


## 故事页的名字：序章 / 章间 · 壹→贰 / 结局 · 还火 / 滚动字幕。
static func title_of(id: String) -> String:
	if id == PROLOGUE:
		return "序章"
	if id == CREDITS:
		return "滚动字幕"
	if id.begins_with("ending_"):
		return "结局 · %s" % ending_name(id.trim_prefix("ending_"))
	if id.begins_with("interlude_"):
		var edge := StoryFlow.for_edge(id.trim_prefix("interlude_"))
		if not edge.is_empty():
			return "章间 · %s → %s" % [ChapterText.number_of(String(edge["from"])),
					ChapterText.number_of(String(edge["to"]))]
	return id


static func ending_name(kind: String) -> String:
	match kind:
		"give":
			return "还火"
		"keep":
			return "守炉"
		"snuff":
			return "熄火"
	return kind


## 存档里记「看过」用的旗标（SaveData 旗标是字符串集合）。
static func seen_flag(id: String) -> String:
	return "%s%s" % [StoryFlow.BOARD_FLAG_PREFIX, id]


## 故事页可回放的分镜：序章、看过的章间（按战役顺序）、结局、滚动字幕。
## flags 是存档旗标（Array 或 PackedStringArray 都行）。
static func replay_list(flags: Variant) -> Array[String]:
	var out: Array[String] = []
	if flags.has(seen_flag(PROLOGUE)) or flags.has("opening_seen"):
		out.append(PROLOGUE)
	for edge in StoryFlow.boundaries():
		var id := interlude_id(String((edge as Dictionary)["from"]))
		if flags.has(StoryFlow.interlude_flag(String((edge as Dictionary)["from"]))):
			out.append(id)
	for kind in ["give", "keep", "snuff"]:
		if flags.has(seen_flag(ending_id(kind))):
			out.append(ending_id(kind))
	if flags.has(seen_flag(CREDITS)):
		out.append(CREDITS)
	return out


static func _shot(set_id: String, actors: Array, cam: String, fx: String, lines: Array,
		art: String = "") -> Dictionary:
	return {"set": set_id, "actors": actors, "cam": cam, "fx": fx, "lines": lines, "art": art}


static func _from_visual(visual: Array, lines: Array, art: String = "") -> Dictionary:
	return _shot(String(visual[0]), visual[1] as Array, String(visual[2]), String(visual[3]), lines, art)


## 序章：8 个镜头，约 40 秒。每个专名第一次出现就地解释（炉约 / 守炉人 / 炉心 / 火种 / 炉座 /
## 伊尔 / 余烬骑士），关键插图 4 张（有就用，没有就实时拼）。改字时 docs/story.md §9 同步。
static func _prologue() -> Array:
	return [
		_shot("title_hall", [], "push", "embers",
				["锈墓。一座建在大炉子上的城。", "二百年来，它的灯从没灭过。"], "prologue_city"),
		_shot("forge", [["swords", 0.5, 1.0], ["flame", 0.5, 1.2]], "pan_right", "embers",
				["靠的是炉约：人死了，名字刻上剑，剑投进炉里烧。", "烧剑的人叫守炉人。烧一个名字，亮一盏灯。"],
				"prologue_names"),
		_shot("forge", [["souls", 0.5, 1.0]], "rise", "ash",
				["名字烧掉了，人就回不来了。", "魂被困在铁里，出不去。"]),
		_shot("forge_core", [["flame", 0.5, 0.35]], "still", "ash",
				["一百年前，城底的大炉子——炉心——熄了。", "守炉人把最后一口火封进一枚小核——火种。"]),
		_shot("cathedral", [["seed", 0.5, 1.0]], "push", "embers",
				["他们把火种放上炉口的石台——炉座——当灯芯，又烧了一百年。", "灯，一年比一年暗。"]),
		_shot("undercroft", [["yir", 0.42, 1.8], ["seed", 0.64, 1.0]], "push", "embers",
				["伊尔：我是最后一个守炉人。", "伊尔：我不想再烧了。我把自己封进火种，嵌进这把剑。"], "prologue_yir"),
		_shot("graveyard", [["knight", 0.5, 2.0], ["seed", 0.5, 0.8]], "rise", "embers",
				["伊尔：醒来吧，余烬骑士。你是守炉人造的人偶，锈了，我从渣里把你捡回来。",
				"伊尔：带着火种去炉心，把它还给炉。被烧的魂，就能走了。"], "prologue_knight"),
		_shot("graveyard", [["knight", 0.5, 2.0], ["flame", 0.78, 0.5]], "push", "embers",
				["火种连着你的命。这就是你要付的代价。", "还火的人，自己也要进炉。"]),
	]


static func _interlude(from_id: String) -> Array:
	var edge := StoryFlow.for_edge(from_id)
	if edge.is_empty():
		return []
	var visuals: Array = INTERLUDE_VISUALS.get(from_id, []) as Array
	if visuals.size() < 2:
		return []
	var out: Array = []
	out.append(_from_visual(visuals[0] as Array, edge.get("epilogue", []) as Array))
	out.append(_from_visual(visuals[1] as Array, edge.get("teaser", []) as Array))
	if String(edge.get("special", "")) == "pre_ending" and visuals.size() >= 3:
		out.append(_from_visual(visuals[2] as Array, _pre_ending_lines()))
	return out


static func _pre_ending_lines() -> Array:
	return (StoryFlow.SPECIALS["pre_ending"]["lines"] as Array).duplicate()


static func _ending(kind: String) -> Array:
	var groups: Array = ENDING_VISUALS.get(kind, []) as Array
	var all_lines := ChapterText.ending_lines_of(kind)
	if groups.is_empty() or all_lines.is_empty():
		return []
	var out: Array = []
	for group in groups:
		var pair: Array = group as Array
		var indices: Array = pair[1] as Array
		var picked: Array = []
		var pictured := false
		for index in indices:
			var i := int(index)
			if i < 0 or i >= all_lines.size():
				continue
			var line := String(all_lines[i])
			picked.append(line)
			if _ending_line_wants_art(kind, line):
				pictured = true
		var art := ("ending_%s" % kind) if pictured else ""
		out.append(_from_visual(pair[0] as Array, picked, art))
	var closing := StoryFlow.post_ending_line(kind)
	if closing != "":
		out.append(_shot("dark", [], "still", "ash", [closing]))
	return out


## 结局插图挂在画面真正发生的那一句上，不挂在开门的第一镜。
## give：魂光升起、伊尔回头、人散成铁屑。keep：坐在炉边守下去。snuff：全城暗下去，炉门里一点红。
static func _ending_line_wants_art(kind: String, line: String) -> bool:
	match kind:
		"give":
			return line.contains("铁屑") or line.contains("散成")
		"keep":
			return line.contains("守下去")
		"snuff":
			return line.contains("一点红")
	return false


static func _credits() -> Array:
	var lines: Array = []
	for line in CREDITS_LINES:
		lines.append(line)
	return [{"set": "dark", "actors": [], "cam": "still", "fx": "embers", "lines": [], "art": "",
			"scroll": lines, "seconds": CREDITS_SECONDS}]
