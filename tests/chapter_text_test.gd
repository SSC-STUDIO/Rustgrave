extends TestCase
## ChapterText 是战役剧情的唯一文本源（v3「看得懂」重写版）：14 章齐备、章号/标题唯一、
## 每条文本都在预算内，和 docs/story.md 的「文本锚点」「术语表」「人物」逐条同步
## （改故事漏改一边就红），并锁住 v3 canon：6 个专名都有白话解释、第一章续火、钟舌线、
## 代价预埋、三个结局都交代名字/你/城的下场（盲测可读性的回归门）。

const DOC_PATH := "res://docs/story.md"
const EXPECTED_TERMS: Array[String] = [
	"炉约", "炉心", "火种", "守炉人", "锈核", "余烬巢",
]
const EXPECTED_CAST: Array[String] = [
	"余烬骑士", "伊尔", "刽子手", "守炉人", "灰卫", "哈伦", "薇尔", "梦魇",
]
## 玩家文本里出现的专名，docs 里必须有定义（术语表 / 人物 / 节拍表的 Boss 列 / 地名列）。
const LORE_NOUNS: Array[String] = [
	"炉约", "火种", "锈核", "余烬巢", "灰卫",
	"伊尔", "刽子手", "哈伦", "薇尔", "梦魇", "守炉人",
	"空钟", "绞盘守渠人", "无声唱诗班", "铸钟人", "炉风先驱",
]
## 禁词：旧称呼、设计/元语言、v2 的旧术语。
const FORBIDDEN: Array[String] = [
	"陵墓", "塞进剑", "你这把剑", "你这一把", "收索", "断头者", "守芯者",
	"顺渣上城", "点亮炉心", "欠伊尔一次回答", "不是灯芯",
	"第一幕", "第二幕", "幕", "债",
	"借他们的手艺往前", "钟不响",
	"插座", "封核", "封进核", "提前离场结局", "炉心大门", "炉心之门",
	"净化偶", "残芯", "送剑", "守火", "复燃",
]

var _docs := ""


func setup() -> void:
	_docs = _read(DOC_PATH)


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	ok(file != null, "can read %s" % path)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _section(keyword: String) -> PackedStringArray:
	var out := PackedStringArray()
	var inside := false
	for raw in _docs.split("\n"):
		var line := String(raw).strip_edges()
		if line.begins_with("## "):
			if inside:
				break
			inside = line.contains(keyword)
			continue
		if inside:
			out.append(String(raw))
	return out


# --- 结构 -----------------------------------------------------------------------

func test_every_chapter_is_complete_and_matches_level_order() -> void:
	eq(ChapterText.order(), GameContext.LEVEL_ORDER, "registry order follows GameContext.LEVEL_ORDER")
	eq(ChapterText.order().size(), 14, "fourteen chapters")
	for id in GameContext.LEVEL_ORDER:
		ok(ChapterText.has(id), "%s is registered" % id)
		var entry: Dictionary = ChapterText.CHAPTERS[id]
		for key in ["number", "name", "act", "objective", "wake", "exit_captions",
				"steles", "boss_intro", "recap"]:
			ok(entry.has(key), "%s has field %s" % [id, key])
		ok(ChapterText.number_of(id) != "", "%s has a display number" % id)
		ok(ChapterText.name_of(id) != "", "%s has a place name" % id)
		ok(ChapterText.wake_of(id) != "", "%s has a wake line" % id)
		ok(ChapterText.objective_of(id) != "", "%s has an objective" % id)
		ok(ChapterText.recap_of(id) != "", "%s has a recap line" % id)
		ok(not ChapterText.act_of(id).is_empty(), "%s belongs to an act" % id)
		ok(ChapterText.steles_of(id).size() >= 2, "%s has at least two steles" % id)
		if id != "level10":
			ok(ChapterText.exit_captions_of(id).size() >= 1, "%s has door captions" % id)
		else:
			eq(ChapterText.exit_captions_of(id).size(), 0, "the final door is an ending choice")


func test_display_numbers_names_and_titles_are_unique() -> void:
	var numbers := {}
	var places := {}
	var titles := {}
	var ids_by_number := {}
	for id in ChapterText.order():
		var number := ChapterText.number_of(id)
		var place := ChapterText.name_of(id)
		var title := ChapterText.title_of(id)
		ok(not numbers.has(number), "display number %s is used once" % number)
		ok(not places.has(place), "place name %s is used once" % place)
		ok(not titles.has(title), "title %s is used once" % title)
		numbers[number] = id
		places[place] = id
		titles[title] = id
		ids_by_number[number] = id
		ok(title.begins_with("锈墓・"), "%s title is a Rustgrave title" % id)
		ok(title.contains(" — "), "%s title has the chapter-card separator" % id)
		eq(ChapterText.subtitle_of(id), "锈墓・" + number, "%s subtitle is the numbered line" % id)
		eq(ChapterText.title_of(id), "%s — %s" % [ChapterText.subtitle_of(id), place],
				"%s title is subtitle + place name" % id)
	for expected in ["壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖", "拾",
			"拾壹", "拾贰", "拾叁", "拾肆"]:
		ok(ids_by_number.has(expected), "chapter number %s is present" % expected)
	eq(ids_by_number["叁"], "level02b", "the slag conduit is chapter three")
	eq(ids_by_number["拾肆"], "level10", "the forge core is the last chapter")


func test_text_budgets_keep_lines_readable() -> void:
	for id in ChapterText.order():
		var wake := ChapterText.wake_of(id)
		ok(wake.length() <= 30, "%s wake is <=30 chars (%d)" % [id, wake.length()])
		var objective := ChapterText.objective_of(id)
		ok(objective.length() <= 16,
				"%s objective is <=16 chars (%d)" % [id, objective.length()])
		var recap := ChapterText.recap_of(id)
		ok(recap.length() <= 40, "%s recap is <=40 chars (%d)" % [id, recap.length()])
		for caption in ChapterText.exit_captions_of(id):
			ok(String(caption).length() <= 30,
					"%s exit caption stays short: %s" % [id, caption])
		ok(ChapterText.exit_captions_of(id).size() <= 2,
				"%s exit captions are 1-2 lines" % id)
		for stele in ChapterText.steles_of(id):
			var text := String(stele.get("text", ""))
			var lines := text.split("\n")
			ok(lines.size() <= 2, "%s/%s stele is <=2 lines" % [id, stele.get("node", "")])
			ok(text.length() <= 44,
					"%s/%s stele is <=2x22 chars (%d)" % [id, stele.get("node", ""), text.length()])
			ok(String(stele.get("node", "")) != "", "%s stele has a node name" % id)
			ok(String(stele.get("title", "")) != "", "%s stele has a title" % id)
		var seen := {}
		for stele in ChapterText.steles_of(id):
			var node := String(stele.get("node", ""))
			ok(not seen.has(node), "%s stele node %s is unique" % [id, node])
			seen[node] = true


# --- docs 同步 ------------------------------------------------------------------

func _anchor_rows() -> Array:
	var rows: Array = []
	for raw in _section("文本锚点"):
		var line := String(raw).strip_edges()
		if not line.begins_with("| level"):
			continue
		var cells := line.split("|")
		if cells.size() < 8:
			continue
		rows.append({
			"id": String(cells[1]).strip_edges(),
			"number": String(cells[2]).strip_edges(),
			"name": String(cells[3]).strip_edges(),
			"objective": String(cells[4]).strip_edges(),
			"wake": String(cells[5]).strip_edges(),
			"recap": String(cells[6]).strip_edges(),
		})
	return rows


func test_docs_story_anchors_match_registry() -> void:
	ok(_docs != "", "docs/story.md is readable")
	var rows := _anchor_rows()
	eq(rows.size(), 14, "docs/story.md pins all fourteen chapters")
	var by_id := {}
	for row in rows:
		by_id[String(row["id"])] = row
	for id in ChapterText.order():
		ok(by_id.has(id), "%s is pinned in docs/story.md" % id)
		if not by_id.has(id):
			continue
		var row: Dictionary = by_id[id]
		eq(String(row["number"]), ChapterText.number_of(id), "%s display number is in sync" % id)
		eq(String(row["name"]), ChapterText.name_of(id), "%s place name is in sync" % id)
		eq(String(row["objective"]), ChapterText.objective_of(id), "%s objective is in sync" % id)
		eq(String(row["wake"]), ChapterText.wake_of(id), "%s wake line is in sync" % id)
		eq(String(row["recap"]), ChapterText.recap_of(id), "%s recap is in sync" % id)


## 两列表格（| 键 | 值 |）→ 字典。skip 里的首列文字当表头跳过。
func _two_column_rows(keyword: String, header: String) -> Dictionary:
	var out := {}
	for raw in _section(keyword):
		var line := String(raw).strip_edges()
		if not line.begins_with("|"):
			continue
		var cells := line.split("|")
		if cells.size() < 4:
			continue
		var key := String(cells[1]).strip_edges()
		if key == header or key.begins_with("---"):
			continue
		out[key] = String(cells[2]).strip_edges()
	return out


func test_docs_glossary_matches_registry() -> void:
	var glossary := _two_column_rows("术语表", "术语")
	eq(ChapterText.TERMS.size(), 6, "glossary covers six terms")
	eq(glossary.size(), 6, "docs glossary lists six terms")
	for term in EXPECTED_TERMS:
		ok(ChapterText.TERMS.has(term), "%s is a defined term" % term)
		ok(glossary.has(term), "docs explains %s" % term)
		eq(ChapterText.term_of(term), String(glossary.get(term, "")),
				"%s explanation is identical in docs and registry" % term)
	for term in ChapterText.TERMS:
		ok(EXPECTED_TERMS.has(String(term)), "%s is not an accidental extra term" % term)
		var plain := ChapterText.term_of(String(term))
		ok(plain.length() >= 8, "%s gets a real plain-language explanation" % term)
		ok(plain.length() <= 60, "%s explanation stays short (%d)" % [term, plain.length()])


func test_docs_cast_matches_registry() -> void:
	var cast := _two_column_rows("人物", "人物")
	eq(ChapterText.CAST.size(), 8, "eight cast entries")
	eq(cast.size(), 8, "docs lists eight characters")
	for who in EXPECTED_CAST:
		ok(ChapterText.CAST.has(who), "%s is in the cast" % who)
		eq(ChapterText.cast_of(who), String(cast.get(who, "")),
				"%s identity is identical in docs and registry" % who)


func test_glossary_leaves_no_undefined_proper_noun() -> void:
	ok(_docs != "", "docs/story.md is readable")
	var defined := {}
	for term in ChapterText.TERMS:
		defined[String(term)] = true
	for who in ChapterText.CAST:
		defined[String(who)] = true
	for raw in _docs.split("\n"):
		var line := String(raw).strip_edges()
		if not line.begins_with("|"):
			continue
		var cells := line.split("|")
		# 节拍表：| 章 | id | 目标 | 阻碍 | Boss | 发现 | 去向 |
		if cells.size() >= 9 and String(cells[2]).strip_edges().begins_with("level"):
			var boss := String(cells[5]).strip_edges()
			boss = boss.split("（")[0].strip_edges()
			if boss != "" and boss != "—":
				defined[boss] = true
	for noun in LORE_NOUNS:
		ok(defined.has(noun), "proper noun %s is defined in docs/story.md" % noun)
	for verbatim in EXPECTED_TERMS:
		ok(ChapterText.TERMS.has(verbatim), "%s is a glossary term, not jargon" % verbatim)


# --- 说话人 / 标题 ----------------------------------------------------------------

func test_split_speaker_only_knows_named_speakers() -> void:
	var yir := ChapterText.split_speaker("伊尔：醒醒。")
	eq(yir[0], "伊尔", "a known speaker is split out")
	eq(yir[1], "醒醒。", "the body is what is left")
	var plain := ChapterText.split_speaker("炉约二百年：前一百年烧剑。")
	eq(plain[0], "", "a place-like prefix is not a speaker")
	eq(plain[1], "炉约二百年：前一百年烧剑。", "the text is kept whole")
	var cast_line := ChapterText.split_speaker("还火：把剑推进炉。")
	eq(cast_line[0], "", "a choice label is not a speaker")
	var none := ChapterText.split_speaker("钟声又响了。")
	eq(none[0], "", "no colon, no speaker")
	for who in ChapterText.SPEAKERS:
		ok(ChapterText.CAST.has(who) or who == "守渠人" or who == "铸钟人",
				"speaker %s is someone the player met" % who)


func test_every_spoken_prefix_names_a_real_speaker() -> void:
	# 「X：…」里的 X 一旦是 2–4 字的名字，就该在 SPEAKERS 里（否则名牌认不出，整句当旁白）。
	var checked := 0
	for line in ChapterText.all_prose():
		var cut := String(line).find("：")
		if cut < 2 or cut > 4:
			continue
		var who := String(line).substr(0, cut)
		if ChapterText.CAST.has(who) or ChapterText.SPEAKERS.has(who):
			ok(ChapterText.SPEAKERS.has(who), "%s is spoken but not in SPEAKERS" % who)
			checked += 1
	ok(checked >= 6, "several spoken lines carry a nameplate (%d)" % checked)


func test_title_lines_are_short_statements() -> void:
	ok(ChapterText.TITLE_LINES.size() >= 3, "the title epitaph rotates a few lines")
	for line in ChapterText.TITLE_LINES:
		ok(String(line).length() <= 18, "title line stays short: %s" % line)
		ok(not String(line).contains("："), "title lines are statements, not dialogue")


# --- 开场 / 结局 / 事件 ---------------------------------------------------------

func _opening_text() -> String:
	return " ".join(ChapterText.opening_lines())


func test_opening_is_seven_short_beats_with_a_voice() -> void:
	var lines := ChapterText.opening_lines()
	eq(lines.size(), 7, "the in-level opening has seven beats")
	var opening: Dictionary = ChapterText.OPENING
	eq(opening.size(), 7, "OPENING has exactly seven keys")
	for key in opening:
		var hits := 0
		for line in lines:
			if String(line) == String(opening[key]):
				hits += 1
		eq(hits, 1, "opening beat %s is said exactly once" % key)
	for line in lines:
		ok(String(line).length() <= 22, "opening line is a pin, not a paragraph: %s" % line)
	var all := _opening_text()
	ok(all.contains("伊尔：") and all.contains("火种"), "the voice is Yir, the thing is the fire seed")
	ok(String(opening["sword"]).contains("剑"), "she says where she is")
	ok(String(opening["echo"]).contains("封进火种之前"),
			"the opening marks Yir's words as from before she sealed herself")
	ok(String(opening["goal"]).contains("炉心"), "the goal is the furnace heart")
	ok(String(opening["route"]).contains("炉座"), "the first step is the furnace stand")
	ok(String(opening["obstacle"]).contains("刽子手"), "the first obstacle is named")
	ok(ChapterText.FIRST_CORE_LINE.contains("锈核") and ChapterText.FIRST_CORE_LINE.contains("手艺"),
			"the first skill core explains 锈核 in plain words")
	ok(not all.contains("炉约") and not all.contains("守炉人"),
			"the world is told by the prologue storyboard, not repeated in the level opening")


func test_endings_resolve_names_you_and_the_city() -> void:
	for kind in ["give", "keep", "snuff"]:
		var lines := ChapterText.ending_lines_of(kind)
		ok(lines.size() >= 4, "%s ending has a sequence" % kind)
		ok(ChapterText.ending_summary_of(kind) != "", "%s ending has a summary" % kind)
		ok(String(lines[lines.size() - 1]).contains("完"), "%s ending closes the campaign" % kind)
	var give := " ".join(ChapterText.ending_lines_of("give"))
	var keep := " ".join(ChapterText.ending_lines_of("keep"))
	var snuff := " ".join(ChapterText.ending_lines_of("snuff"))
	ok(give.contains("门开了"), "give starts after the door opens (the question comes before the door)")
	ok(give.contains("名字") and give.contains("走了出来"), "give says what happens to the names")
	ok(give.contains("火种连着你的命") and give.contains("散成铁"),
			"give says why you scatter: the fire seed is tied to your life")
	ok(give.contains("城终于睡下"), "give puts the city to sleep")
	ok(give.contains("伊尔：谢谢你"), "give lets Yir say goodbye")
	ok(keep.contains("没有松手") and keep.contains("守着"), "keep: you stay and hold the fire")
	ok(keep.contains("名字也没有走"), "keep: the names remain trapped")
	ok(keep.contains("城一直半醒"), "keep: the city stays half-awake")
	ok(keep.contains("新的守炉人"), "keep: you become the next keeper — the loop continues")
	ok(keep.contains("伊尔：你不该留下的"), "keep keeps Yir's voice")
	ok(snuff.contains("熄灭了火种") and snuff.contains("没来得及说完"), "snuff is explicit and ends Yir mid-sentence")
	ok(snuff.contains("名字") and snuff.contains("没有路可走"), "snuff: the names have nowhere to go")
	ok(snuff.contains("城还睡着"), "snuff: the city is still asleep")
	ok(_docs.contains("还火（`give`）") and _docs.contains("守炉（`keep`）") and _docs.contains("熄火（第一章，`snuff`）"),
			"docs explains all three endings by name")
	eq(ChapterText.ending_summary_of("give").split("：")[0], "还火", "give is called 还火")
	eq(ChapterText.ending_summary_of("keep").split("：")[0], "守炉", "keep is called 守炉")
	eq(ChapterText.ending_summary_of("snuff").split("：")[0], "熄火", "snuff is called 熄火")


func test_events_and_core_voices_cover_the_built_content() -> void:
	for key in ["boss_gate", "boss_slain", "toxin", "parry"]:
		ok(ChapterText.event_line(key) != "", "level01 event line %s exists" % key)
	for ability in [AbilityIds.HEAT_FORGE, AbilityIds.HOOKSHOT_TETHER, AbilityIds.EMBER_STEP]:
		ok(ChapterText.CORE_VOICE.has(ability), "core voice exists for %s" % ability)
		ok(String(ChapterText.CORE_VOICE[ability]).contains("："), "core voice names its trade")


func test_acts_group_the_fourteen_chapters() -> void:
	eq(ChapterText.ACTS.size(), 4, "four acts")
	var counts := {}
	for act in ChapterText.ACTS:
		counts[StringName(act["id"])] = 0
		ok(String(act["name"]) != "", "act %s has a name" % act["id"])
	for id in ChapterText.order():
		var act := ChapterText.act_of(id)
		ok(not act.is_empty(), "%s belongs to a known act" % id)
		if not act.is_empty():
			counts[StringName(act["id"])] = int(counts[StringName(act["id"])]) + 1
	eq(int(counts[&"awake"]), 3, "醒 = chapters 1-3")
	eq(int(counts[&"debt"]), 4, "账 = chapters 4-7")
	eq(int(counts[&"cast"]), 4, "铸 = chapters 8-11")
	eq(int(counts[&"forge"]), 3, "炉 = chapters 12-14")


# --- v3 canon 回归门 --------------------------------------------------------------

func _prose_of(id: String) -> String:
	var parts: Array[String] = [ChapterText.wake_of(id), ChapterText.objective_of(id),
			ChapterText.recap_of(id)]
	for caption in ChapterText.exit_captions_of(id):
		parts.append(String(caption))
	for stele in ChapterText.steles_of(id):
		parts.append(String(stele.get("title", "")))
		parts.append(String(stele.get("text", "")))
	parts.append(ChapterText.boss_intro_of(id))
	return " ".join(parts)


func test_no_forbidden_words_in_player_text() -> void:
	var prose := " ".join(ChapterText.all_prose())
	for word in FORBIDDEN:
		ok(not prose.contains(word), "prose does not use the retired wording '%s'" % word)


## 时间线只有一条：一百年前炉心熄灭 → 火种放上炉座当灯芯 → 又烧了一百年 → 如今快灭。
func test_fire_seed_timeline_is_unique() -> void:
	var c1 := _prose_of("level01")
	ok(c1.contains("一百年前炉心熄了"), "chapter 1 pins the furnace going out a hundred years ago")
	ok(c1.contains("最后一口火封进火种") and c1.contains("放上炉座当灯芯"),
			"chapter 1: the last fire was sealed into the fire seed and burned on the stand as a wick")
	ok(ChapterText.wake_of("level01").contains("火种快灭"),
			"chapter 1 wake says the fire is about to go out")
	ok(ChapterText.objective_of("level01").contains("续火"),
			"chapter 1 objective is to feed the fire at the stand")
	var c3 := _prose_of("level03")
	ok(c3.contains("炉座那盏") and c3.contains("暗了"),
			"chapter 4 says the lamp on the stand is dim")
	ok(not c3.contains("圣殿的灯还亮着"), "chapter 4 does not claim the stand lamp still burns")
	var c4 := _prose_of("level04")
	ok(c4.contains("前一百年") and c4.contains("后一百年") and c4.contains("撑灯"),
			"chapter 5 pins the two centuries: names first, then the fire seed as a wick")


## 第一章：续火是把火种放上炉座再收回剑里，不是结局；石板松开通向第二章。
func test_chapter1_relight_and_hand_off() -> void:
	var exit_caps := " ".join(ChapterText.exit_captions_of("level01"))
	ok(exit_caps.contains("火种续上了火") and exit_caps.contains("收回剑里"),
			"chapter 1 exit: the fire seed is relit and taken back into the sword")
	ok(exit_caps.contains("钟声"), "chapter 1 exit points down to the bell")
	ok(ChapterText.exit_label_of("level01") == "", "chapter 1 has no door; the stand is the exit")
	ok(ChapterText.event_line("boss_gate").contains("炉座"), "the executioner guards the stand")
	ok(ChapterText.event_line("boss_slain").contains("火种"), "the fallen executioner points at the fire seed")


## 钟舌线：守炉人熔了钟舌铸成火种，也拆了哈伦的剑；ch8/ch9 目标拆开，碑文回答谁干的。
func test_bell_tongue_chain_and_split_objectives() -> void:
	var ch8 := ChapterText.objective_of("level06")
	var ch9 := ChapterText.objective_of("level07")
	ok(ch8.contains("哈伦") and ch8.contains("门闩"),
			"chapter 8 objective asks why Harlan's sword became the door bar")
	ok(ch9.contains("熔钟舌"), "chapter 9 objective is to find where the tongue was melted")
	ok(ch8 != ch9, "the two objectives are not nearly the same sentence")
	ok(_prose_of("level06").contains("守炉人拆了他的剑"),
			"the graveyard stele answers who took Harlan's sword")
	ok(_prose_of("level07").contains("守炉人熔了钟舌"),
			"the bell tower recap answers who melted the tongue")
	ok(ChapterText.cast_of("守炉人").contains("熔了") and ChapterText.cast_of("守炉人").contains("钟舌"),
			"the cast entry says the keepers melted the tongue")
	ok(not ChapterText.cast_of("守炉人").contains("哈伦"),
			"the cast entry shown from the prologue does not name Harlan")
	ok(_prose_of("level07").contains("伊尔"), "the bell tower says the voice on your back is Yir")


## 代价必须在选择之前说清，并且在多处预埋：还火的人，自己也要进炉。
func test_ending_cost_is_seeded_before_the_choice() -> void:
	ok(" ".join(StoryFlow.for_edge("level06")["epilogue"]).contains("自己也要进炉"),
			"the graveyard-to-bell bridge seeds 'returning the fire costs you'")
	ok(_prose_of("level08").contains("还火的人") and _prose_of("level08").contains("进炉"),
			"chapter 11 also seeds the cost")
	var pre_ending := " ".join(StoryFlow.SPECIALS["pre_ending"]["lines"])
	ok(pre_ending.contains("还火") and pre_ending.contains("守炉") and pre_ending.contains("散成铁"),
			"the bridge into the final chapter states both costs")
	ok(_prose_of("level10").contains("还火：") and _prose_of("level10").contains("守炉："),
			"the final chapter's stele states both choices")
	ok(ChapterText.objective_of("level10").contains("选择"), "the final objective is the choice")


## 称呼与门名统一。
func test_terminology_and_door_names_are_clean() -> void:
	var prose := " ".join(ChapterText.all_prose())
	ok(ChapterText.term_of("锈核").contains("手艺"), "锈核 is explained as a dead person's craft")
	ok(ChapterText.term_of("火种").contains("钥匙"), "the fire seed is explained as the key")
	ok(ChapterText.exit_label_of("level09") == "城墙外", "the wall gate leads out, not into the furnace door")
	ok(ChapterText.exit_label_of("level09b") == "炉心门", "the cliff door is called 炉心门")
	ok(ChapterText.exit_label_of("level10") == "炉心门", "the forge door is called 炉心门")
	ok(_prose_of("level10").contains("让城睡下"), "'把锈还给铁' is glossed as letting the city sleep")
	ok(_prose_of("level07b").contains("当年的钥匙") or _prose_of("level07b").contains("火种就是钥匙"),
			"the bell foundry says what the key is")
	ok(prose.contains("火种") and prose.contains("守炉人"), "the two core nouns are used in player text")
	ok(ChapterText.cast_of("伊尔").contains("封进火种"), "the cast entry says Yir sealed herself into the fire seed")


## 路线：每一章的去向都说得出原因。
func test_route_reasons_and_secondary_motives() -> void:
	var c2 := " ".join(ChapterText.exit_captions_of("level02"))
	ok(c2.contains("回声停了") and c2.contains("真钟还在钟楼响"),
			"chapter 2 exit explains: echo stops, the real bell keeps ringing")
	var c2b := " ".join(ChapterText.exit_captions_of("level02b"))
	ok(c2b.contains("斜坡") and c2b.contains("圣殿的暗门"),
			"chapter 3 exit explains the slope up and the only road (the cathedral's hidden door)")
	ok(_prose_of("level04b").contains("名字还困在火里") and _prose_of("level04b").contains("火一还"),
			"the choir says why the fire must be returned")
	ok(_prose_of("level09b").contains("守的是门"), "the grey guards guard a door, not the city")
	ok(_prose_of("level09b").contains("早就想让人去问"), "the grey guards want the question asked")
	ok(_prose_of("level09b").contains("这火该不该还"), "the last grey guard states the question")
	ok(_prose_of("level10").contains("没想清楚"), "the nightmare guards the door against the unsure")
	ok(not " ".join(ChapterText.exit_captions_of("level06")).contains("熔"),
			"chapter 8 exit does not spoil the melted tongue")
	ok(_prose_of("level06").contains("不肯进炉的战马"), "chapter 8 seeds the horse")
	ok(_prose_of("level07").contains("马蹄"), "chapter 9 keeps the horse thread")
	ok(_prose_of("level07").contains("钟还在响"), "the bell phrase agrees the real bell still rings")


func test_no_design_terms_and_compact_is_only_an_oath() -> void:
	var prose := " ".join(ChapterText.all_prose())
	for word in ["第一幕", "第二幕", "幕", "债"]:
		ok(not prose.contains(word), "player text does not leak the design term '%s'" % word)
	ok(ChapterText.CAST.has("守炉人"), "the organisation is 守炉人 in the cast")
	ok(not ChapterText.CAST.has("炉约"), "炉约 is not a person/organisation in the cast")
	ok(ChapterText.term_of("炉约").contains("誓"), "the glossary says 炉约 is an oath")
	ok(ChapterText.term_of("守炉人").contains("炉约"), "the glossary ties 守炉人 to the oath")
	for bad in ["炉约造", "炉约把", "炉约看见", "炉约让", "炉约在"]:
		ok(not prose.contains(bad), "炉约 is not used as an actor ('%s')" % bad)


func test_journal_reveal_tables_cover_everyone_and_hide_late_names() -> void:
	var first := ""
	for who in ChapterText.CAST:
		ok(ChapterText.CAST_FIRST_CHAPTER.has(String(who)), "cast reveal table has %s" % who)
		first = ChapterText.cast_first_chapter(String(who))
		ok(first == "" or GameContext.LEVEL_ORDER.has(first),
				"%s first chapter is blank or a real level" % who)
	for term in ChapterText.TERMS:
		ok(ChapterText.TERM_FIRST_CHAPTER.has(String(term)), "term reveal table has %s" % term)
		first = ChapterText.term_first_chapter(String(term))
		ok(first == "" or GameContext.LEVEL_ORDER.has(first),
				"%s first chapter is blank or a real level" % term)
	var none := ChapterText.revealed_cast(-1)
	ok(none.has("余烬骑士") and none.has("伊尔"), "no progress still names the knight and Yir")
	for hidden in ["灰卫", "哈伦", "薇尔", "梦魇"]:
		ok(not ChapterText.revealed_cast(0).has(hidden), "chapter 1 does not list %s" % hidden)
	ok(not ChapterText.revealed_terms(0).has("锈核"), "chapter 1 glossary hides 锈核")
	eq(ChapterText.revealed_cast(GameContext.LEVEL_ORDER.size() - 1).size(), ChapterText.CAST.size(),
			"the last chapter reveals the whole cast")
	ok(ChapterText.revealed_terms(ChapterText.order().find("level05")).has("锈核"),
			"the workshop chapter reveals 锈核")
