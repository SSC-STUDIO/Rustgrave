extends Object
## 掉落表：根据章节/来源/种子确定性地产出一件"生成装备"。
##
## 生成装备的存档 id 形如 `gen:<基座 id>:<稀有度>`；词缀由 AffixCatalog 按 id 确定性
## 生成，所以**存档只存 id**，读档时 EquipmentCatalog.for_id() 重新造出同一件东西。

const Affix := preload("res://scripts/data/affix_catalog.gd")
const EquipmentCatalogScript := preload("res://scripts/data/equipment_catalog.gd")

const PREFIX := "gen:"
const RARITY_WEIGHTS := {
	Affix.RARITY_COMMON: 60,
	Affix.RARITY_RARE: 30,
	Affix.RARITY_EPIC: 10,
}
const BASE_POOLS := {
	EquipmentItem.SLOT_WEAPON: [&"iron_blade", &"scavenger_blade", &"scholar_probe", &"broken_sword"],
	EquipmentItem.SLOT_ARMOR: [&"iron_carapace", &"scavenger_rags", &"scholar_cowl", &"broken_armor"],
	EquipmentItem.SLOT_TRINKET: [&"toxic_ward", &"bone_charm", &"toxic_filter_talisman",
			&"bone_amulet", &"broken_pendant"],
}


static func is_generated(id: Variant) -> bool:
	return String(id).begins_with(PREFIX)


static func generated_id(base_id: StringName, rarity: StringName) -> String:
	return "%s%s:%s" % [PREFIX, String(base_id), String(rarity)]


## "gen:iron_blade:rare" -> {base: "iron_blade", rarity: "rare"}；非法返回 {}。
static func parse_id(id: Variant) -> Dictionary:
	var raw := String(id)
	if not raw.begins_with(PREFIX):
		return {}
	var body := raw.substr(PREFIX.length())
	var split := body.rfind(":")
	if split <= 0:
		return {}
	var base := StringName(body.substr(0, split))
	var rarity := StringName(body.substr(split + 1))
	if not Affix.is_rarity(rarity):
		return {}
	if not EquipmentCatalogScript.has_id(base) or String(base).begins_with(PREFIX):
		return {}
	return {"base": base, "rarity": rarity}


static func make_from_id(id: Variant) -> EquipmentItem:
	var parsed := parse_id(id)
	if parsed.is_empty():
		return null
	return make(StringName(parsed["base"]), StringName(parsed["rarity"]))


## 用基座 + 稀有度造一件生成装备（确定性词缀）。
static func make(base_id: StringName, rarity: StringName) -> EquipmentItem:
	var item := EquipmentCatalogScript.for_id(base_id)
	if item == null:
		return null
	var safe_rarity := rarity if Affix.is_rarity(rarity) else Affix.RARITY_COMMON
	item.id = StringName(generated_id(base_id, safe_rarity))
	item.set("rarity", safe_rarity)
	item.set("affixes", Affix.affixes_for(base_id, safe_rarity))
	if safe_rarity != Affix.RARITY_COMMON:
		item.display_name = "%s·%s" % [Affix.rarity_name(safe_rarity), item.display_name]
	return item


## 确定性抽一件：同一个 (slot, level_id, seed) 永远相同。
static func roll_id(slot: StringName, level_id: String, seed: int) -> String:
	var pool: Array = BASE_POOLS.get(slot, [])
	if pool.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(slot) ^ hash(level_id) * 31 ^ seed
	var base := StringName(pool[rng.randi_range(0, pool.size() - 1)])
	var total_weight := 0
	for rarity in RARITY_WEIGHTS:
		total_weight += int(RARITY_WEIGHTS[rarity])
	var pick := rng.randi_range(1, maxi(1, total_weight))
	var chosen: StringName = Affix.RARITY_COMMON
	var acc := 0
	for rarity in RARITY_WEIGHTS:
		acc += int(RARITY_WEIGHTS[rarity])
		if pick <= acc:
			chosen = StringName(rarity)
			break
	return generated_id(base, chosen)


static func roll_item(slot: StringName, level_id: String, seed: int) -> EquipmentItem:
	return make_from_id(roll_id(slot, level_id, seed))


## 章节出货口：Boss/宝箱/可破坏道具都能用它，稀有度权重已内置。
static func roll_for_source(level_id: String, source: StringName, seed: int) -> EquipmentItem:
	var slot: StringName = EquipmentItem.SLOT_WEAPON
	match source:
		&"armor_cache", &"boss_armor":
			slot = EquipmentItem.SLOT_ARMOR
		&"trinket_cache", &"boss_trinket":
			slot = EquipmentItem.SLOT_TRINKET
		&"boss_weapon", &"boss":
			slot = EquipmentItem.SLOT_WEAPON
		_:
			var slots: Array = [
				EquipmentItem.SLOT_WEAPON, EquipmentItem.SLOT_ARMOR, EquipmentItem.SLOT_TRINKET]
			slot = StringName(slots[absi(hash(level_id) + hash(source)) % slots.size()])
	return roll_item(slot, level_id, seed)
