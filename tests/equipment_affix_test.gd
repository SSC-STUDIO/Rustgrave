extends TestCase
## 装备词缀/稀有度：确定性掉落、旧装备零改动、词缀进 CharacterStats。

const Affix := preload("res://scripts/data/affix_catalog.gd")
const Loot := preload("res://scripts/data/loot_tables.gd")


func test_rarity_affix_counts_and_names() -> void:
	eq(Affix.affix_count(Affix.RARITY_COMMON), 0)
	eq(Affix.affix_count(Affix.RARITY_RARE), 1)
	eq(Affix.affix_count(Affix.RARITY_EPIC), 2)
	eq(Affix.rarity_name(Affix.RARITY_RARE), "稀有")
	ok(not Affix.is_rarity(&"mythic"))


func test_affixes_are_deterministic_per_item_id() -> void:
	var a := Affix.affixes_for(&"iron_blade", Affix.RARITY_EPIC)
	var b := Affix.affixes_for(&"iron_blade", Affix.RARITY_EPIC)
	eq(a.size(), 2)
	eq(a, b, "同一件装备永远同一套词缀")
	var rare := Affix.affixes_for(&"iron_blade", Affix.RARITY_RARE)
	eq(rare.size(), 1, "稀有 1 条")
	var common := Affix.affixes_for(&"iron_blade", Affix.RARITY_COMMON)
	eq(common.size(), 0, "普通无词缀")


func test_affix_values_match_rarity_and_aggregate() -> void:
	var epic := Affix.affixes_for(&"iron_blade", Affix.RARITY_EPIC)
	var total := Affix.total(epic)
	var sum_atk := 0
	var sum_def := 0
	var sum_hp := 0
	for affix in epic:
		eq(String(affix["id"]) != "", true)
		var stat := StringName(affix["stat"])
		match stat:
			&"attack":
				sum_atk += int(affix["value"])
			&"defense":
				sum_def += int(affix["value"])
			&"max_hp":
				sum_hp += int(affix["value"])
	eq(int(total["attack"]), sum_atk)
	eq(int(total["defense"]), sum_def)
	eq(int(total["max_hp"]), sum_hp)
	var lines := Affix.lines_for(epic)
	eq(lines.size(), epic.size())
	ok(lines[0].contains("·"))


func test_legacy_items_are_untouched() -> void:
	var blade := EquipmentCatalog.for_id(&"broken_sword")
	ok(blade != null)
	eq(blade.attack, 1)
	eq(blade.rarity, Affix.RARITY_COMMON)
	eq(blade.affixes.size(), 0)
	eq(EquipmentCatalog.for_id(&"nope"), null)


func test_generated_ids_parse_and_rebuild_deterministically() -> void:
	var id := Loot.generated_id(&"iron_blade", Affix.RARITY_EPIC)
	ok(Loot.is_generated(id))
	var parsed := Loot.parse_id(id)
	eq(StringName(parsed.get("base", &"")), &"iron_blade")
	eq(StringName(parsed.get("rarity", &"")), Affix.RARITY_EPIC)
	var item := EquipmentCatalog.for_id(id)
	ok(item is EquipmentItem)
	if item is EquipmentItem:
		eq(item.id, StringName(id), "生成装备保留生成 id")
		eq(item.attack, 2, "基座属性还在")
		eq(item.affixes.size(), 2)
		ok(String(item.display_name).begins_with("史诗·"), "史诗前缀")
	var again := EquipmentCatalog.for_id(id)
	eq(again.to_dict(), item.to_dict(), "读档重建完全一致")
	eq(Loot.parse_id("gen:iron_blade:mythic"), {}, "非法稀有度不解析")
	eq(Loot.parse_id("gen:nope:rare"), {}, "未知基座不解析")


func test_roll_is_deterministic_and_uses_pools() -> void:
	var a := Loot.roll_id(EquipmentItem.SLOT_WEAPON, "level03", 7)
	var b := Loot.roll_id(EquipmentItem.SLOT_WEAPON, "level03", 7)
	eq(a, b, "同章节同种子必出同一件")
	ok(Loot.is_generated(a))
	var item := Loot.roll_item(EquipmentItem.SLOT_ARMOR, "level05", 3)
	ok(item != null)
	if item != null:
		eq(item.slot_type, EquipmentItem.SLOT_ARMOR, "按槽位掉落")
		ok(item.affixes.size() <= 2)
	var src := Loot.roll_for_source("level07", &"boss", 11)
	ok(src != null)
	if src != null:
		eq(src.slot_type, EquipmentItem.SLOT_WEAPON, "Boss 武器掉落")


func test_character_stats_aggregate_affix_bonuses() -> void:
	var stats := CharacterStats.new()
	add_child(stats)
	await flush(1)
	var item := Loot.make(&"iron_blade", Affix.RARITY_EPIC)
	var base_attack: int = item.attack
	var affix_total := Affix.total(item.affixes)
	stats.recalculate([item], {})
	eq(stats.bonus_attack, base_attack + int(affix_total.get("attack", 0)))
	eq(stats.bonus_defense, int(affix_total.get("defense", 0)))
	eq(stats.bonus_max_hp, int(affix_total.get("max_hp", 0)))
	almost(stats.bonus_toxin_resist, float(affix_total.get("toxin_resist", 0.0)), 0.0001)
	almost(stats.bonus_speed_mult, float(affix_total.get("speed_mult", 0.0)), 0.0001)
	# 卸下后归零
	stats.recalculate([], {})
	eq(stats.bonus_attack, 0)
	eq(stats.bonus_defense, 0)
	stats.queue_free()


func test_affix_lines_show_in_tooltip() -> void:
	var item := Loot.make(&"iron_carapace", Affix.RARITY_RARE)
	var lines := item.get_stat_lines()
	var has_affix_line := false
	for line in lines:
		if String(line).begins_with("· "):
			has_affix_line = true
	ok(has_affix_line, "词缀出现在装备说明行里")
