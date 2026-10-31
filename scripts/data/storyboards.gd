extends RefCounted
## 剧情分镜数据（纯数据 + 纯函数，零场景引用）。
##
## v4「焚名轮回」重构：
##   · 彻底取消打断闯关节奏的 13 段章间黑屏播片；
##   · 仅保留紧凑序章（prologue，6 镜约 22 秒）、四大结局分镜（give / keep / snuff / true_break）与滚动字幕（credits）。

const PROLOGUE := "prologue"
const CREDITS := "credits"
const ART_DIR := "res://assets/story/"
const CHARS_PER_SEC := 22.0
const LINE_HOLD := 1.3
const SHOT_FADE := 0.5

const ENDING_VISUALS := {
	"give": [
		[["forge_core", [["gate", 0.72, 1.0], ["knight", 0.3, 2.0], ["seed", 0.46, 1.0]], "push", "embers"], [0]],
		[["forge_core", [["flame", 0.65, 1.5], ["swords", 0.42, 1.0]], "rise", "embers"], [1]],
		[["dark", [["ring", 0.5, 1.2]], "still", "ash"], [2, 3]],
		[["graveyard", [["swords", 0.5, 1.0]], "pan_left", "ash"], [4]],
	],
	"keep": [
		[["forge_core", [["gate", 0.72, 1.0], ["knight", 0.3, 2.0], ["seed", 0.46, 1.0]], "push", "embers"], [0]],
		[["forge_core", [["yir", 0.56, 1.6], ["seed", 0.4, 1.0]], "still", "embers"], [1, 2]],
		[["ramparts", [["ash_guard", 0.38, 1.8], ["flame", 0.7, 0.8]], "pan_left", "ash"], [3, 4]],
	],
	"snuff": [
		[["forge", [["knight", 0.35, 2.0], ["seed", 0.55, 1.0]], "push", "embers"], [0]],
		[["dark", [["ring", 0.52, 1.0]], "still", "ash"], [1]],
		[["dark", [["souls", 0.5, 1.0]], "still", "ash"], [2]],
		[["graveyard", [["flame", 0.5, 0.25]], "still", "ash"], [3]],
	],
	"true_break": [
		[["forge_core", [["knight", 0.34, 2.0], ["gate", 0.7, 1.0], ["swords", 0.52, 1.2]], "push", "embers"], [0]],
		[["forge_core", [["souls", 0.46, 1.1], ["yir", 0.64, 1.7]], "rise", "embers"], [1, 2]],
		[["ramparts", [["knight", 0.38, 2.0], ["souls", 0.62, 1.0]], "pan_right", "embers"], [3]],
		[["title_hall", [["knight", 0.5, 2.0]], "rise", "embers"], [4]],
	],
}

const CREDITS_LINES: Array[String] = [
	"锈  墓",
	"RUSTGRAVE",
	"",
	"焚 名 轮 回",
	"",
	"四十八具空壳沉入废冢",
	"第四十九号握紧了真名",
	"",
	"顺从路标者化为炉灰",
	"违抗假火者走出长夜",
	"",
	"谢谢你斩断这座炉约。",
]
const CREDITS_SECONDS := 15.0


static func shots(id: String) -> Array:
	if id == PROLOGUE:
		return _prologue()
	if id == CREDITS:
		return _credits()
	if id.begins_with("ending_"):
		return _ending(id.trim_prefix("ending_"))
	return []


static func has(id: String) -> bool:
	return not shots(id).is_empty()


static func interlude_id(from_id: String) -> String:
	return "interlude_%s" % from_id


static func ending_id(kind: String) -> String:
	return "ending_%s" % kind


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


static func seconds_of(id: String) -> float:
	var total := 0.0
	for shot in shots(id):
		total += shot_seconds(shot as Dictionary)
	return total


static func title_of(id: String) -> String:
	if id == PROLOGUE:
		return "序章 · 炉约与牧火"
	if id == CREDITS:
		return "滚动字幕"
	if id.begins_with("ending_"):
		return "结局 · %s" % ending_name(id.trim_prefix("ending_"))
	return id


static func ending_name(kind: String) -> String:
	match kind:
		"give":
			return "假结局·还火"
		"keep":
			return "假结局·守炉"
		"snuff":
			return "拒燃·灭芯"
		"true_break":
			return "真结局·破约"
	return kind


static func seen_flag(id: String) -> String:
	return "%s%s" % [StoryFlow.BOARD_FLAG_PREFIX, id]


## 故事页可回放分镜：序章 + 已解锁的四大结局 + 滚动字幕。
static func replay_list(flags: Variant) -> Array[String]:
	var out: Array[String] = []
	if flags == null:
		return out
	if flags.has(seen_flag(PROLOGUE)) or flags.has("opening_seen"):
		out.append(PROLOGUE)
	for kind in ["snuff", "give", "keep", "true_break"]:
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


## 精简序章：6 个镜头，约 22 秒，迅速立住表面委托并埋下「别回头」的悬念钩子。
static func _prologue() -> Array:
	return [
		_shot("title_hall", [], "push", "embers",
				["锈墓。一座靠烧死人名字亮了两百年的铁城。"], "prologue_city"),
		_shot("forge", [["swords", 0.5, 1.0], ["flame", 0.5, 1.2]], "pan_right", "embers",
				["炉约规定：人死后名字刻上重剑，投进炉心化作长明灯火。"], "prologue_names"),
		_shot("forge_core", [["flame", 0.5, 0.35]], "still", "ash",
				["百年前炉心渐冷，守炉人熔掉钟舌铸成火种，勉强续命至今。"]),
		_shot("undercroft", [["yir", 0.42, 1.8], ["seed", 0.64, 1.0]], "push", "embers",
				["伊尔：我是最后一个守炉人。我把自己封进火种，嵌上你的重剑。"], "prologue_yir"),
		_shot("graveyard", [["knight", 0.5, 2.0], ["seed", 0.5, 0.8]], "rise", "embers",
				["伊尔：醒来吧，余烬骑士。顺着我点亮的箭头，送火种回炉心。"], "prologue_knight"),
		_shot("graveyard", [["knight", 0.5, 2.0], ["flame", 0.78, 0.5]], "push", "embers",
				["伊尔：只要听我的话往前走，被困的名字就能解脱……千万别往岔路看。"]),
	]


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


static func _ending_line_wants_art(kind: String, line: String) -> bool:
	match kind:
		"give":
			return line.contains("灰烬") or line.contains("胸牌")
		"keep":
			return line.contains("灰卫")
		"snuff":
			return line.contains("冷铁")
		"true_break":
			return line.contains("天光") or line.contains("走出")
	return false


static func _credits() -> Array:
	var lines: Array = []
	for line in CREDITS_LINES:
		lines.append(line)
	return [{"set": "dark", "actors": [], "cam": "still", "fx": "embers", "lines": [], "art": "",
			"scroll": lines, "seconds": CREDITS_SECONDS}]
