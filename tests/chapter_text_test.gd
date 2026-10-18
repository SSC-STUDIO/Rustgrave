extends TestCase
## ChapterText 是战役剧情的唯一文本源：14 章齐备、章号/标题唯一、每条文本都在预算内，
## 和 docs/story.md 的「文本锚点」「术语表」逐条同步（改故事漏改一边就红），
## 并锁住 M1R4 canon：开场动机+代价、第一章机关与守灯 continuity、钟舌线、结局名字/死法/
## 守火代价、术语统一、靠门问与选的先后（盲测可读性的最终回归门）。

const DOC_PATH := "res://docs/story.md"
const EXPECTED_TERMS: Array[String] = [
	"炉约", "炉心", "锈墓", "锈", "净化偶", "锈核", "残芯", "名字", "腐液", "余烬巢", "灰卫",
]
const EXPECTED_CAST: Array[String] = [
	"净化偶", "伊尔", "刽子手", "守炉人", "灰卫", "哈伦", "薇尔", "梦魇",
]
const LORE_NOUNS: Array[String] = [
	"炉约", "锈", "净化偶", "锈核", "残芯", "腐液", "余烬巢", "灰卫",
	"伊尔", "刽子手", "哈伦", "薇尔", "梦魇", "守炉人",
	"空钟", "绞盘守渠人", "无声唱诗班", "铸钟人", "炉风先驱",
]
## M1R4 禁词：旧称呼、设计/元语言、旧术语与不统一的门名。
const FORBIDDEN: Array[String] = [
	"骑士", "陵墓", "塞进剑", "你这把剑", "你这一把", "收索", "断头者", "守芯者",
	"顺渣上城", "点亮炉心", "欠伊尔一次回答", "不是灯芯",
	"第一幕", "第二幕", "幕", "债",
	"借他们的手艺往前", "钟不响",
	"插座", "封核", "提前离场结局", "炉心大门", "炉心之门",
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
		ok(EXPECTED_TERMS.has(String(term)), "%s is not an accidental extra term" % term)
		var plain := ChapterText.term_of(String(term))
		ok(plain.length() >= 8, "%s gets a real plain-language explanation" % term)
		ok(plain.length() <= 60, "%s explanation stays short (%d)" % [term, plain.length()])


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


func test_openings_explain_terms_give_motive_and_cost() -> void:
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
	# 专名首现就地解释。
	ok(all.contains("炉约") and all.contains("誓"), "炉约 is explained as the oath")
	ok(all.contains("守炉人") and all.contains("立誓"), "守炉人 is explained as the people who swore")
	ok(all.contains("净化偶") and all.contains("人偶"), "净化偶 is explained as a puppet")
	ok(all.contains("炉心") and all.contains("炉膛"), "炉心 is explained as the furnace")
	ok(all.contains("残芯") and all.contains("封成"), "残芯 is explained as the sealed fire")
	# 评审 E/F 硬伤：动机与代价必须在开场。
	ok(String(opening["saved"]).contains("只求你带她问一次"),
			"the opening states her motive: she only asks to be taken to ask once")
	ok(String(opening["cost"]).contains("还火的人") and String(opening["cost"]).contains("散成铁"),
			"the opening states the cost: returning the fire scatters you into iron")
	ok(String(opening["echo"]).contains("回声") and String(opening["echo"]).contains("封进核之前"),
			"the opening marks Yir's voice as an echo from before she sealed herself")
	ok(String(opening["situation"]).contains("核里还有人"), "the core holds someone")
	ok(String(opening["question"]).contains("这火该不该还"), "the question is stated verbatim")
	ok(ChapterText.FIRST_CORE_LINE.contains("锈核") and ChapterText.FIRST_CORE_LINE.contains("剑槽"),
			"the first skill core explains 锈核 and 剑槽 in plain words")


func test_endings_resolve_names_death_and_keep_cost() -> void:
	for kind in ["give", "keep", "snuff"]:
		var lines := ChapterText.ending_lines_of(kind)
		ok(lines.size() >= 2, "%s ending has a sequence" % kind)
		ok(ChapterText.ending_summary_of(kind) != "", "%s ending has a summary" % kind)
		ok(String(lines[lines.size() - 1]).contains("完"), "%s ending closes the campaign" % kind)
	var give := " ".join(ChapterText.ending_lines_of("give"))
	var keep := " ".join(ChapterText.ending_lines_of("keep"))
	var snuff := " ".join(ChapterText.ending_lines_of("snuff"))
	ok(give.contains("门开了"), "give starts after the door opens (ask happens before the door)")
	ok(give.contains("名字都归火"), "give says what happens to the names")
	ok(give.contains("核连着你的性命") and give.contains("散成铁"),
			"give connects 'returning the fire' to 'you scatter': the core is tied to your life")
	ok(give.contains("城终于睡下"), "give puts the city to sleep")
	ok(give.contains("听不真") and give.contains("够了") and give.contains("别还"),
			"give's answer stays ambiguous")
	ok(keep.contains("城一直半醒"), "keep: the city stays half-awake")
	ok(keep.contains("铁里的名字还困着"), "keep: the names remain trapped")
	ok(keep.contains("你走不了"), "keep: you can never leave")
	ok(keep.contains("伊尔的声音还在"), "keep keeps Yir's voice")
	ok(snuff.contains("没问到") and snuff.contains("城还睡着"), "snuff is explicit")
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


# --- M1R4 canon 回归门 ------------------------------------------------------------

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


func test_remnant_core_timeline_is_unique() -> void:
	var c1 := _prose_of("level01")
	ok(c1.contains("一百年前炉心熄灭"), "chapter 1 pins the furnace going out a hundred years ago")
	ok(c1.contains("封进残芯") and c1.contains("放上炉座当灯芯") and c1.contains("又点了一百年"),
			"chapter 1: the last fire was sealed into the core and burned on the stand as a wick")
	ok(ChapterText.wake_of("level01").contains("从座上取下"),
			"chapter 1 wake says Yir took the core down from the stand")
	ok(not c1.contains("炉座空了一百年"), "the stand has not been empty for a century")
	ok(_prose_of("level03").contains("炉座那盏") and _prose_of("level03").contains("一百年"),
			"chapter 4 keeps the stand-wick century")
	var c5 := _prose_of("level04")
	ok(c5.contains("后一百年") and c5.contains("残芯") and c5.contains("撑灯"),
			"chapter 5 says the last century burned the remnant core to keep the lamp")


## 评审硬伤 2：第一章的机关（点过才能带走）与「另一盏守灯」continuity。
func test_chapter1_mechanism_and_lamp_continuity() -> void:
	var exit_caps := " ".join(ChapterText.exit_captions_of("level01"))
	ok(exit_caps.contains("炉座认点过的核") and exit_caps.contains("点过的核才能带走"),
			"chapter 1 states the mechanism: only a core lit on the stand can be taken")
	var c4 := _prose_of("level03")
	ok(c4.contains("守灯"), "chapter 4 names the separate guardian lamp")
	ok(c4.contains("另点") and c4.contains("炉座那盏"),
			"chapter 4 distinguishes the guardian lamp from the stand lamp")
	ok(_prose_of("level03").contains("已经暗了") or c4.contains("已经暗了"),
			"the stand lamp is dim once the core is taken")
	ok(not c4.contains("圣殿的灯还亮着") or c4.contains("守灯"),
			"chapter 4 no longer claims the stand lamp still burns")


## 评审硬伤 3：钟舌线挂回主目标，ch8/ch9 目标拆开，碑文回答谁熔了钟舌。
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
			"the bell tower stele answers who melted the tongue")
	ok(ChapterText.cast_of("守炉人").contains("熔了") and ChapterText.cast_of("守炉人").contains("钟舌"),
			"the cast entry says the keepers melted the tongue")


## 评审硬伤 4：结局补名字下场/你的死法/守火真实代价；代价提前预埋。
func test_ending_cost_is_seeded_and_keep_has_real_cost() -> void:
	ok(" ".join(StoryFlow.for_edge("level06")["epilogue"]).contains("自己也要进炉"),
			"the bell bridge seeds 'returning the fire costs you'")
	ok(_prose_of("level08").contains("还火的人") and _prose_of("level08").contains("进炉"),
			"chapter 11 also seeds the cost")
	var give := " ".join(ChapterText.ending_lines_of("give"))
	ok(give.contains("核连着你的性命"), "give explains why the sword joining the fire kills you")
	ok(give.contains("名字都归火"), "give says the names return to the fire")
	var keep := " ".join(ChapterText.ending_lines_of("keep"))
	ok(keep.contains("永留") or keep.contains("走不了"), "keep has a real cost: you never leave")
	ok(keep.contains("半醒") and keep.contains("困着"), "keep costs the city and the names")


## 评审硬伤 5：清术语与元文本（插座→剑槽、封核→封进核、门名统一、把锈还给铁白话）。
func test_terminology_and_meta_language_are_clean() -> void:
	var prose := " ".join(ChapterText.all_prose())
	for banned in ["插座", "封核", "提前离场结局"]:
		ok(not prose.contains(banned), "no retired meta/term '%s' in player text" % banned)
	ok(prose.contains("剑槽"), "the socket is called 剑槽 in player text")
	ok(TERMS_has("锈核") and ChapterText.term_of("锈核").contains("剑槽"), "锈核 is seated in the 剑槽")
	ok(ChapterText.exit_label_of("level09") == "炉心门", "the last door is called 炉心门")
	ok(ChapterText.exit_label_of("level09b") == "炉心门", "the cliff door is called 炉心门")
	ok(ChapterText.exit_label_of("level10") == "炉心门", "the forge door is called 炉心门")
	ok(_prose_of("level10").contains("让城睡下"), "'把锈还给铁' is glossed as letting the city sleep")
	ok(_prose_of("level07b").contains("当年守炉人"), "the key was cast by the keepers long ago")
	# 「封进核」的说法在首现处给白话（她把自己封进核之前）。
	ok(ChapterText.opening_lines().has(String(ChapterText.OPENING["echo"])),
			"pre-sealing is stated in the opening")
	ok(String(ChapterText.OPENING["echo"]).contains("封进核之前"),
			"pre-sealing uses the unified wording")
	ok(ChapterText.cast_of("伊尔").contains("封进核之前"), "the cast entry uses the unified wording")


func TERMS_has(term: String) -> bool:
	return ChapterText.TERMS.has(term)


## D2 + D14：路线与「先问火、门才开，进去再选」。
func test_d_chain_breaks_are_answered() -> void:
	var under := " ".join(StoryFlow.for_edge("level02")["epilogue"])
	ok(under.contains("渠顶旧街") and under.contains("圣殿地窖") and under.contains("暗门"),
			"the undercroft bridge says: no direct road, old street to the cathedral crypt")
	var c14 := _prose_of("level10")
	ok(c14.contains("先问火一句") and c14.contains("门才开"),
			"chapter 14: ask the fire first, then the door opens")
	ok(ChapterText.objective_of("level10").contains("问火"),
			"the final objective is to ask the fire before choosing")
	var specials := " ".join(StoryFlow.SPECIALS["pre_ending"]["lines"])
	ok(specials.contains("先在门外问火") and specials.contains("门才会开"),
			"the pre-ending bridge states the order: ask, then the door opens")
	ok(" ".join(ChapterText.ending_lines_of("give")).contains("门开了"),
			"the ending starts after the door has opened")


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


func test_no_design_terms_and_compact_is_only_an_oath() -> void:
	var prose := " ".join(ChapterText.all_prose())
	for word in ["第一幕", "第二幕", "幕", "债"]:
		ok(not prose.contains(word), "player text does not leak the design term '%s'" % word)
	ok(ChapterText.CAST.has("守炉人"), "the organisation is 守炉人 in the cast")
	ok(not ChapterText.CAST.has("炉约"), "炉约 is not a person/organisation in the cast")
	ok(ChapterText.term_of("炉约").contains("守炉人"),
			"the glossary says the people who swore are called 守炉人")
	for bad in ["炉约造", "炉约把", "炉约看见", "炉约让", "炉约在"]:
		ok(not prose.contains(bad), "炉约 is not used as an actor ('%s')" % bad)


func test_route_reasons_and_secondary_motives() -> void:
	var c2 := " ".join(ChapterText.exit_captions_of("level02"))
	ok(c2.contains("渠在城上") and c2.contains("炉心在城下"),
			"chapter 2 exit explains the space: canal above, furnace below")
	ok(_prose_of("level02b").contains("斜坡") and _prose_of("level02b").contains("退"),
			"chapter 3 explains the slag slope back up")
	ok(_prose_of("level04b").contains("名字还在火里") and _prose_of("level04b").contains("散"),
			"the choir says why the fire must be returned")
	ok(_prose_of("level09b").contains("守的是门"), "the grey guards guard a door, not the city")
	ok(_prose_of("level09b").contains("早想让人去问"), "the grey guards want the question asked")
	ok(_prose_of("level10").contains("最后一句回答"), "the nightmare guards the final answer")
	ok(not " ".join(ChapterText.exit_captions_of("level06")).contains("熔"),
			"chapter 8 exit does not spoil the melted tongue")
	ok(_prose_of("level06").contains("不肯进炉的战马"), "chapter 8 seeds the horse")
	ok(_prose_of("level07").contains("马蹄"), "chapter 9 keeps the horse thread")
	ok(_prose_of("level07").contains("钟还在响"), "the bell phrase agrees the real bell still rings")
