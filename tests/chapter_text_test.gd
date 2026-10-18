extends TestCase
## ChapterText 是战役剧情的唯一文本源：14 章齐备、章号/标题唯一、每条文本都在预算内，
## 和 docs/story.md 的「文本锚点」「术语表」逐条同步（改故事漏改一边就红），
## 并锁住 M1R3 canon：残芯时间线唯一、首现术语就地解释、伊尔动作有「封核前」标记、
## 炉约只作誓约/账本、钥匙行动落地、梦魇有来历、结局平衡（盲测可读性的回归门）。

const DOC_PATH := "res://docs/story.md"
const EXPECTED_TERMS: Array[String] = [
	"炉约", "炉心", "锈墓", "锈", "净化偶", "锈核", "残芯", "名字", "腐液", "余烬巢", "灰卫",
]
const EXPECTED_CAST: Array[String] = [
	"净化偶", "伊尔", "刽子手", "守炉人", "灰卫", "哈伦", "薇尔", "梦魇",
]
## 出现在剧情文本里、必须能在 docs（术语表/人物/章节表）里找到定义的专名候选。
const LORE_NOUNS: Array[String] = [
	"炉约", "锈", "净化偶", "锈核", "残芯", "腐液", "余烬巢", "灰卫",
	"伊尔", "刽子手", "哈伦", "薇尔", "梦魇", "守炉人",
	"空钟", "绞盘守渠人", "无声唱诗班", "铸钟人", "炉风先驱",
]
## M1R3 禁词：旧稿里没定义/误导的称呼、设计术语与错因果。
const FORBIDDEN: Array[String] = [
	"骑士", "陵墓", "塞进剑", "你这把剑", "你这一把", "收索", "断头者", "守芯者",
	"顺渣上城", "点亮炉心", "欠伊尔一次回答", "不是灯芯",
	"第一幕", "第二幕", "幕", "债",
	"借他们的手艺往前", "钟不响",
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


## 取 docs 里某个二级标题（按关键字匹配，标题编号变了也不怕）到下一个二级标题之间的行。
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
	var names := {}
	var titles := {}
	var ids_by_number := {}
	for id in ChapterText.order():
		var number := ChapterText.number_of(id)
		var name := ChapterText.name_of(id)
		var title := ChapterText.title_of(id)
		ok(not numbers.has(number), "display number %s is used once" % number)
		ok(not names.has(name), "place name %s is used once" % name)
		ok(not titles.has(title), "title %s is used once" % title)
		numbers[number] = id
		names[name] = id
		titles[title] = id
		ids_by_number[number] = id
		ok(title.begins_with("锈墓・"), "%s title is a Rustgrave title" % id)
		ok(title.contains(" — "), "%s title has the chapter-card separator" % id)
		eq(ChapterText.subtitle_of(id), "锈墓・" + number, "%s subtitle is the numbered line" % id)
		eq(ChapterText.title_of(id), "%s — %s" % [ChapterText.subtitle_of(id), name],
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
		eq(ChapterText.exit_captions_of(id).size() <= 2, true,
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

## docs/story.md「文本锚点」表：| id | 章号 | 地名 | 目标 | 醒来句 | 前情提要 |
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


func _glossary_rows() -> Dictionary:
	var out := {}
	for raw in _section("术语表"):
		var line := String(raw).strip_edges()
		if not line.begins_with("|"):
			continue
		var cells := line.split("|")
		if cells.size() < 4:
			continue
		var term := String(cells[1]).strip_edges()
		if term == "术语" or term.begins_with("---"):
			continue
		out[term] = String(cells[2]).strip_edges()
	return out


func test_docs_glossary_matches_registry() -> void:
	var glossary := _glossary_rows()
	eq(ChapterText.TERMS.size(), 11, "glossary covers eleven terms")
	eq(glossary.size(), 11, "docs glossary lists eleven terms")
	for term in EXPECTED_TERMS:
		ok(ChapterText.TERMS.has(term), "%s is a defined term" % term)
		ok(glossary.has(term), "docs explains %s" % term)
		eq(ChapterText.term_of(term), String(glossary.get(term, "")),
				"%s explanation is identical in docs and registry" % term)
	for term in ChapterText.TERMS:
		ok(EXPECTED_TERMS.has(String(term)),
				"%s is not an accidental extra term" % term)
		var plain := ChapterText.term_of(String(term))
		ok(plain.length() >= 8, "%s gets a real plain-language explanation" % term)
		ok(plain.length() <= 60, "%s explanation stays short (%d)" % [term, plain.length()])


## 剧本文本里出现的专名必须能在 docs / 注册表里找到定义，不许冒出老玩家才懂的名字。
func test_glossary_leaves_no_undefined_proper_noun() -> void:
	ok(_docs != "", "docs/story.md is readable")
	var defined := {}
	for term in ChapterText.TERMS:
		defined[String(term)] = true
	for name in ChapterText.CAST:
		defined[String(name)] = true
	for raw in _section("人物"):
		var line := String(raw).strip_edges()
		if not line.begins_with("|"):
			continue
		var cells := line.split("|")
		if cells.size() < 3:
			continue
		var name := String(cells[1]).strip_edges()
		if name == "人物" or name.begins_with("---"):
			continue
		defined[name] = true
	for raw in _docs.split("\n"):
		var line := String(raw).strip_edges()
		if not line.begins_with("|"):
			continue
		var cells := line.split("|")
		if cells.size() >= 9 and String(cells[2]).strip_edges().begins_with("level"):
			var boss := String(cells[5]).strip_edges()
			boss = boss.split("（")[0].strip_edges()
			if boss != "" and boss != "—":
				defined[boss] = true
		if cells.size() >= 8 and String(cells[1]).strip_edges().begins_with("level"):
			defined[String(cells[3]).strip_edges()] = true
	for noun in LORE_NOUNS:
		ok(defined.has(noun), "proper noun %s is defined in docs/story.md" % noun)
	for verbatim in ["炉约", "净化偶", "锈核", "残芯", "名字", "腐液", "余烬巢", "灰卫"]:
		ok(ChapterText.TERMS.has(verbatim), "%s is a glossary term, not jargon" % verbatim)


# --- 开场 / 结局 / 事件 ---------------------------------------------------------

func _opening_text() -> String:
	return " ".join(ChapterText.opening_lines())


func test_openings_explain_proper_nouns_on_first_use() -> void:
	var lines := ChapterText.opening_lines()
	eq(lines.size(), 16, "the opening has sixteen beats")
	var opening: Dictionary = ChapterText.OPENING
	for key in opening:
		var hits := 0
		for line in lines:
			if String(line) == String(opening[key]):
				hits += 1
		eq(hits, 1, "opening beat %s is said exactly once" % key)
	for line in lines:
		ok(String(line).length() <= 22, "opening line is a pin, not a paragraph: %s" % line)
	var all := _opening_text()
	# 评审：6 专名 5 个首现无解释——开场必须逐个就地解释。
	ok(all.contains("炉约") and all.contains("誓"), "炉约 is explained as the oath")
	ok(all.contains("守炉人") and all.contains("立誓"), "守炉人 is explained as the people who swore")
	ok(all.contains("净化偶") and all.contains("人偶"), "净化偶 is explained as a rust-scraping puppet")
	ok(all.contains("炉心") and all.contains("炉膛"), "炉心 is explained as the great furnace")
	ok(all.contains("残芯") and all.contains("封成"), "残芯 is explained as the sealed last fire")
	ok(all.contains("锈核") == false, "the skill core is introduced at the first pick-up, not in the opening")
	# 处境与回聲、名字、目标、阻碍照旧。
	ok(String(opening["situation"]).contains("核里还有人"), "the sword's core is what holds someone")
	ok(String(opening["echo"]).contains("封进核之前"), "Yir's actions are marked as pre-sealing")
	ok(String(opening["names"]).contains("烧进铁里"), "names are burned into the iron")
	ok(String(opening["question"]).contains("这火该不该还"), "the question is stated verbatim")
	ok(String(opening["obstacle"]).contains("刽子手") and String(opening["obstacle"]).contains("炉座"),
			"the obstacle guards the furnace stand")
	# 锈核首现（第一次捡核）也带白话。
	ok(ChapterText.FIRST_CORE_LINE.contains("锈核") and ChapterText.FIRST_CORE_LINE.contains("职称")
			and ChapterText.FIRST_CORE_LINE.contains("手艺"),
			"the first skill core explains itself in plain words")


func test_endings_are_balanced_and_distinct() -> void:
	for kind in ["give", "keep", "snuff"]:
		var lines := ChapterText.ending_lines_of(kind)
		ok(lines.size() >= 2, "%s ending has a sequence" % kind)
		ok(ChapterText.ending_summary_of(kind) != "", "%s ending has a summary" % kind)
		ok(String(lines[lines.size() - 1]).contains("完"), "%s ending closes the campaign" % kind)
	var give := " ".join(ChapterText.ending_lines_of("give"))
	var keep := " ".join(ChapterText.ending_lines_of("keep"))
	var snuff := " ".join(ChapterText.ending_lines_of("snuff"))
	# 平衡：give 的回应听不真，不是「正确答案」的背书；keep 的火没有回答。
	ok(give.contains("听不真") and give.contains("够了") and give.contains("别还"),
			"give's answer is ambiguous — the fire is not endorsing a right choice")
	ok(give.contains("城终于睡下") and give.contains("伊尔归火"), "give resolves the city and Yir")
	ok(keep.contains("火没有回答") and keep.contains("城还醒着"),
			"keep: no answer, the city stays awake")
	ok(keep.contains("伊尔的声音还在"), "keep keeps Yir's voice")
	ok(snuff.contains("没问到") and snuff.contains("城还睡着"), "snuff is explicit")
	ok(ChapterText.ending_summary_of("snuff").contains("提前离场"),
			"snuff is labelled an early-exit ending")
	ok(ChapterText.event_line("boss_slain").contains("提前离场"),
			"the first-chapter prompt labels snuff as an early-exit ending")
	ok(_docs.contains("送剑（`give`）") and _docs.contains("守火（`keep`）"),
			"docs explains both endings by name")


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
	for act_id in counts:
		ok(int(counts[act_id]) >= 3, "act %s groups at least three chapters" % act_id)


# --- M1R3 canon 回归门 ------------------------------------------------------------

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


## 评审硬伤1：残芯这一百年的时间线只能有一条，三处文本互相印证。
func test_remnant_core_timeline_is_unique() -> void:
	var c1 := _prose_of("level01")
	ok(c1.contains("一百年前炉心熄灭"), "chapter 1 pins the furnace going out a hundred years ago")
	ok(c1.contains("封进残芯"), "chapter 1: the last fire was sealed into the remnant core")
	ok(c1.contains("放上炉座当灯芯") and c1.contains("又点了一百年"),
			"chapter 1: the keepers put it on the stand as a wick and burned it another century")
	ok(ChapterText.wake_of("level01").contains("从座上取下"),
			"chapter 1 wake says Yir took the core down from the stand")
	ok(not c1.contains("炉座空了一百年"), "the stand has not been empty for a century")
	ok(c1.contains("残芯") and not c1.contains("后一百年烧剑"), "chapter 1 does not contradict itself")
	ok(_prose_of("level03").contains("炉座上的残芯") and _prose_of("level03").contains("又亮了一百年"),
			"chapter 4 says the lamp on the stand burned another hundred years")
	var c5 := _prose_of("level04")
	ok(c5.contains("后一百年") and c5.contains("残芯") and c5.contains("撑灯"),
			"chapter 5 says the last century burned the remnant core to keep the lamp")
	ok(not c5.contains("后一百年烧一枚核"), "chapter 5 does not use the vague 'a core'")
	# 全篇不再出现第二套时间线说法。
	var all := " ".join(ChapterText.all_prose())
	ok(not all.contains("炉座空了一百年"), "no text claims the stand was empty for a century")


## 评审硬伤2/3：玩家文本不出现设计术语；炉约只作誓约/账本，组织叫守炉人。
func test_no_design_terms_and_compact_is_only_an_oath() -> void:
	var prose := " ".join(ChapterText.all_prose())
	for word in ["第一幕", "第二幕", "幕", "债"]:
		ok(not prose.contains(word), "player text does not leak the design term '%s'" % word)
	ok(ChapterText.CAST.has("守炉人"), "the organisation is 守炉人 in the cast")
	ok(not ChapterText.CAST.has("炉约"), "炉约 is not a person/organisation in the cast")
	ok(ChapterText.term_of("炉约").contains("守炉人"),
			"the glossary says the people who swore are called 守炉人")
	ok(prose.contains("炉约二百年") or prose.contains("炉约的账") or prose.contains("炉约的末条")
			or prose.contains("炉约的最后一条") or prose.contains("炉约纪事")
			or prose.contains("炉约："),
			"炉约 still appears as the oath / ledger")
	for bad in ["炉约造", "炉约把", "炉约看见", "炉约让", "炉约在"]:
		ok(not prose.contains(bad), "炉约 is not used as an actor ('%s')" % bad)
	ok(c1_has("level04", "不想让守炉人看见"), "the torn page is hidden from the 守炉人")


func c1_has(id: String, needle: String) -> bool:
	return _prose_of(id).contains(needle)


## 评审硬伤4：伊尔的动作都发生在封核之前；玩家听到的是回声。
func test_yir_actions_are_marked_as_pre_sealing() -> void:
	var opening := _opening_text()
	ok(opening.contains("回声") and opening.contains("封进核之前"),
			"the opening says the voice is an echo from before she sealed herself")
		
	var markers := {
		"level04": "封核之前",
		"level04b": "封核之前",
		"level08": "封核之前",
	}
	for id in markers:
		ok(_prose_of(id).contains(String(markers[id])),
				"%s marks Yir's action as before the sealing" % id)
	ok(ChapterText.cast_of("伊尔").contains("封核前"), "the cast entry marks her actions as pre-sealing")


## 评审硬伤5：钥匙要落到行动上（门认核不认人），并梦魇有来历。
func test_key_action_and_nightmare_seed() -> void:
	ok(_prose_of("level07b").contains("门认核不认人"), "the foundry says the door knows the core")
	ok(_prose_of("level07b").contains("钥匙"), "the foundry says the core is the key")
	ok(" ".join(ChapterText.exit_captions_of("level09")).contains("门认核不认人"),
			"chapter 12 turns the key into an action at the door")
	var c8 := _prose_of("level06")
	ok(c8.contains("不肯进炉的战马") and c8.contains("没舍得杀"),
			"chapter 8 seeds the horse that refused the furnace and why it lives")
	ok(_prose_of("level07").contains("马蹄"), "chapter 9 keeps the horse thread alive")
	for id in ["level09", "level09b", "level10"]:
		ok(_prose_of(id).contains("马"), "%s still names the horse" % id)


## 评审硬伤6：终章代价提前预埋，give/keep 不读作对错题。
func test_ending_cost_is_seeded_before_the_finale() -> void:
	ok(" ".join(StoryFlow.for_edge("level06")["epilogue"]).contains("自己也要进炉"),
			"the bell-tower bridge seeds 'returning the fire costs you'")
	ok(_prose_of("level08").contains("还火的人") and _prose_of("level08").contains("进炉"),
			"chapter 11 also seeds the cost of returning the fire")
	var give := " ".join(ChapterText.ending_lines_of("give"))
	var keep := " ".join(ChapterText.ending_lines_of("keep"))
	ok(give.contains("听不真") and keep.contains("火没有回答"),
			"neither ending is framed as the correct answer")
	ok(not give.contains("还吧"), "give does not clearly endorse returning the fire")


## 评审点9：其他文字一致性。
func test_consistency_cleanups() -> void:
	var prose := " ".join(ChapterText.all_prose())
	ok(ChapterText.OPENING["situation"].contains("核里还有人"),
			"the situation line matches the core-in-the-sword canon")
	ok(_prose_of("level07").contains("钟还在响，链不停"),
			"the bell tower phrase agrees that the real bell still rings")
	ok(ChapterText.wake_of("level07b").contains("守炉人") and ChapterText.wake_of("level07b").contains("铸钥匙"),
			"the key is cast by the 守炉人, not a nameless 'they'")
	ok(not prose.contains("借他们的手艺往前"), "the old vague debt line is gone")
	ok(_prose_of("level06").contains("剑走了，她留下"), "薇尔 is described as left behind, not 'alone'")


## 盲测人物题：只读注册表也能复述 8 个人/一方势力是谁。
func test_character_roster_is_self_contained() -> void:
	eq(ChapterText.CAST.size(), 8, "eight cast entries")
	var expected_sorted := EXPECTED_CAST.duplicate()
	expected_sorted.sort()
	eq(ChapterText.cast_names(), expected_sorted, "the cast roster is stable")
	for name in EXPECTED_CAST:
		var role := ChapterText.cast_of(name)
		ok(role.length() >= 10, "%s gets a one-line identity" % name)
		ok(role.length() <= 60, "%s identity stays one line (%d)" % [name, role.length()])


func test_route_reasons_and_secondary_motives() -> void:
	var c2 := " ".join(ChapterText.exit_captions_of("level02"))
	ok(c2.contains("渠在城上") and c2.contains("炉心在城下") and c2.contains("要下去，得先上去"),
			"chapter 2 exit explains the space: canal above, furnace below")
	ok(_prose_of("level02b").contains("斜坡") and _prose_of("level02b").contains("退"),
			"chapter 3 explains the slag slope back up")
	ok(_prose_of("level04").contains("伊尔封核前撕走") or _prose_of("level04").contains("封核之前"),
			"the cathedral explains who tore out the page")
	ok(_prose_of("level04b").contains("名字还在火里") and _prose_of("level04b").contains("散"),
			"the choir says why the fire must be returned")
	ok(_prose_of("level09b").contains("守的是门"), "the grey guards guard a door, not the city")
	ok(_prose_of("level09b").contains("早想让人去问"), "the grey guards want the question asked")
	ok(_prose_of("level10").contains("最后一句回答"), "the nightmare guards the final answer")
	ok(not " ".join(ChapterText.exit_captions_of("level06")).contains("熔"),
			"chapter 8 exit does not spoil the melted tongue")
	ok(ChapterText.objective_of("level06").contains("查钟舌"), "chapter 8 objective is to check the tongue")
