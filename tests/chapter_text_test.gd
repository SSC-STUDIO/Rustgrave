extends TestCase
## ChapterText 是战役剧情的唯一文本源（v4「焚名轮回 · 第四十九号柴薪骗局」版）：
## 14 节点齐备（8 主线 + 5 违抗裂隙支线 + 1 隐藏真结局终章）、章号/标题唯一、
## 零新章静态碑文（去站桩化）、与 docs/story.md 严格同步，且完整覆盖四大结局与人物真相翻转。

const DOC_PATH := "res://docs/story.md"
const EXPECTED_TERMS: Array[String] = [
	"炉约", "炉心", "火种", "守炉人", "锈核", "余烬巢", "真名残片",
]
const EXPECTED_CAST: Array[String] = [
	"余烬骑士", "伊尔", "刽子手", "守炉人", "灰卫", "哈伦", "薇尔", "梦魇",
]
const FORBIDDEN_META: Array[String] = [
	"第一幕", "第二幕", "程序员", "代码", "键盘", "屏幕", "开发者",
	"陵墓", "塞进剑", "断头者", "守芯者", "插座", "提前离场结局",
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


func test_every_chapter_is_complete_and_matches_level_order() -> void:
	eq(ChapterText.order(), GameContext.LEVEL_ORDER, "registry order follows GameContext.LEVEL_ORDER")
	eq(ChapterText.order().size(), 14, "fourteen stage nodes")
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
		eq(ChapterText.steles_of(id).size(), 0, "%s has zero static steles in v4 live-voice mode" % id)
		if id in ["stage07", "stage08_true"]:
			eq(ChapterText.exit_captions_of(id).size(), 0, "%s resolves through ending cinematics" % id)
		else:
			ok(ChapterText.exit_captions_of(id).size() >= 1, "%s has door captions" % id)


func test_display_numbers_names_and_titles_are_unique() -> void:
	var numbers := {}
	var places := {}
	var titles := {}
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
		ok(title.begins_with("锈墓・"), "%s title is a Rustgrave title" % id)
		ok(title.contains(" — "), "%s title has the chapter-card separator" % id)
		eq(ChapterText.subtitle_of(id), "锈墓・" + number, "%s subtitle is the numbered line" % id)
		eq(ChapterText.title_of(id), "%s — %s" % [ChapterText.subtitle_of(id), place],
				"%s title is subtitle + place name" % id)
	eq(numbers["壹"], "stage01")
	eq(numbers["裂·壹"], "branch01")
	eq(numbers["捌"], "stage07")
	eq(numbers["终"], "stage08_true")


func test_text_budgets_keep_lines_readable() -> void:
	for id in ChapterText.order():
		var wake := ChapterText.wake_of(id)
		ok(wake.length() <= 30, "%s wake is <=30 chars (%d)" % [id, wake.length()])
		var objective := ChapterText.objective_of(id)
		ok(objective.length() <= 16, "%s objective is <=16 chars (%d)" % [id, objective.length()])
		var recap := ChapterText.recap_of(id)
		ok(recap.length() <= 40, "%s recap is <=40 chars (%d)" % [id, recap.length()])
		for caption in ChapterText.exit_captions_of(id):
			ok(String(caption).length() <= 32, "%s exit caption stays short: %s" % [id, caption])


func test_docs_story_anchors_glossary_and_cast_match_registry() -> void:
	ok(_docs != "", "docs/story.md is readable")
	for id in ChapterText.order():
		ok(_docs.contains("`%s`" % id), "docs/story.md pins node %s" % id)
		ok(_docs.contains(ChapterText.title_of(id)), "docs/story.md pins title of %s" % id)
		ok(_docs.contains(ChapterText.objective_of(id)), "docs/story.md pins objective of %s" % id)
		ok(_docs.contains(ChapterText.wake_of(id)), "docs/story.md pins wake of %s" % id)
	eq(ChapterText.TERMS.size(), 7, "glossary covers seven terms")
	for term in EXPECTED_TERMS:
		ok(ChapterText.TERMS.has(term), "%s is a defined term" % term)
		var plain := ChapterText.term_of(term)
		ok(plain.length() >= 8 and plain.length() <= 60, "%s explanation stays concise" % term)
		ok(_docs.contains("**%s**：%s" % [term, plain]), "docs glossary matches %s" % term)
	eq(ChapterText.CAST.size(), 8, "eight cast entries")
	for who in EXPECTED_CAST:
		ok(ChapterText.CAST.has(who), "%s is in the cast" % who)
		ok(_docs.contains("**%s**：%s" % [who, ChapterText.cast_of(who)]), "docs cast matches %s" % who)


func test_cast_truth_flips_when_fragments_are_collected() -> void:
	eq(ChapterText.cast_of_with_flags("伊尔", PackedStringArray()), ChapterText.cast_of("伊尔"))
	var flipped := ChapterText.cast_of_with_flags("伊尔", PackedStringArray(["truth_3"]))
	ok(flipped != ChapterText.cast_of("伊尔") and flipped.contains("司炉回声"),
			"truth_3 flips Yir's journal entry to expose the synthesized echo")
	var knight_truth := ChapterText.cast_of_with_flags("余烬骑士", PackedStringArray(["truth_1"]))
	ok(knight_truth.contains("第四十九号收火偶"), "truth_1 flips knight's journal entry")
	var horse_truth := ChapterText.cast_of_with_flags("梦魇", PackedStringArray(["truth_5"]))
	ok(horse_truth.contains("拦住"), "truth_5 flips Nightmare's journal entry")


func test_split_speaker_and_title_lines() -> void:
	var yir := ChapterText.split_speaker("伊尔：醒醒。")
	eq(yir[0], "伊尔")
	eq(yir[1], "醒醒。")
	var echo := ChapterText.split_speaker("司炉回声：第四十九号偏离动线。")
	eq(echo[0], "司炉回声")
	var doubt := ChapterText.split_speaker("伊尔？：别往下翻了。")
	eq(doubt[0], "伊尔？")
	var true_yir := ChapterText.split_speaker("真伊尔：握紧你的真名！")
	eq(true_yir[0], "真伊尔")
	var plain := ChapterText.split_speaker("炉约二百年：前一百年烧剑。")
	eq(plain[0], "")
	ok(ChapterText.TITLE_LINES.size() >= 3)
	for line in ChapterText.TITLE_LINES:
		ok(String(line).length() <= 18, "title line stays <=18 chars: %s" % line)
		ok(not String(line).contains("："), "title lines are statements, not dialogue")


func test_opening_four_endings_and_acts() -> void:
	var lines := ChapterText.opening_lines()
	eq(lines.size(), 7, "OPENING retains 7 concise compatibility beats")
	for line in lines:
		ok(String(line).length() <= 22, "opening beat <=22 chars: %s" % line)
	for kind in ["give", "keep", "snuff", "true_break"]:
		var elines := ChapterText.ending_lines_of(kind)
		ok(elines.size() >= 4, "%s ending has >=4 lines" % kind)
		ok(ChapterText.ending_summary_of(kind) != "", "%s ending has summary" % kind)
		ok(String(elines[elines.size() - 1]).contains("结局"), "%s ending closes with ending stamp" % kind)
	eq(ChapterText.ACTS.size(), 4, "four acts: 醒 / 疑 / 铸 / 破")
	var counts := {}
	for act in ChapterText.ACTS:
		counts[StringName(act["id"])] = 0
	for id in ChapterText.order():
		var act := ChapterText.act_of(id)
		counts[StringName(act["id"])] = int(counts[StringName(act["id"])]) + 1
	eq(int(counts[&"awake"]), 3)
	eq(int(counts[&"doubt"]), 4)
	eq(int(counts[&"cast"]), 4)
	eq(int(counts[&"break"]), 3)


func test_no_forbidden_words_and_journal_reveals_are_valid() -> void:
	var prose := " ".join(ChapterText.all_prose())
	for word in FORBIDDEN_META:
		ok(not prose.contains(word), "prose does not use forbidden word '%s'" % word)
	for ability in [AbilityIds.HEAT_FORGE, AbilityIds.HOOKSHOT_TETHER, AbilityIds.EMBER_STEP]:
		ok(ChapterText.CORE_VOICE.has(ability), "core voice exists for %s" % ability)
	for who in ChapterText.CAST:
		var first := ChapterText.cast_first_chapter(String(who))
		ok(first == "" or GameContext.LEVEL_ORDER.has(first), "%s first chapter is valid" % who)
	for term in ChapterText.TERMS:
		var first := ChapterText.term_first_chapter(String(term))
		ok(first == "" or GameContext.LEVEL_ORDER.has(first), "%s first chapter is valid" % term)
	eq(ChapterText.revealed_cast(GameContext.LEVEL_ORDER.size() - 1).size(), ChapterText.CAST.size())
	ok(ChapterText.revealed_terms(ChapterText.order().find("stage02")).has("锈核"))
	ok(ChapterText.revealed_terms(ChapterText.order().find("branch01")).has("真名残片"))
