class_name EquipmentCatalog
extends RefCounted
## Static registry and factory for all equipment items and set synergy definitions.
## All returned items are fresh EquipmentItem resource instances.

const SET_BROKEN_KNIGHT := &"broken_knight"

## Authoritative definitions of equipment set synergies and their threshold bonuses.
const SET_DEFINITIONS: Dictionary = {
	SET_BROKEN_KNIGHT: {
		"name": "破损骑士",
		"description": "昔日折戟沉沙的骑士遗物，残破甲胄间凝聚着未灭的战意。",
		"thresholds": [
			{
				"pieces": 2,
				"defense": 1,
				"max_hp": 1,
				"name": "残破战意",
				"description": "残破战意 (2件套): 防御 +1，生命上限 +1"
			},
			{
				"pieces": 3,
				"attack": 1,
				"toxin_resist": 0.10,
				"name": "灰烬誓约",
				"description": "灰烬誓约 (3件套): 攻击 +1，毒素抗性 +10%"
			}
		]
	}
}


# ===========================================================================
# Core Factory Methods
# ===========================================================================

## Starter weapon: Broken Knight Sword.
static func broken_sword() -> EquipmentItem:
	var item := EquipmentItem.new(
		&"broken_sword",
		"破损骑士剑",
		EquipmentItem.SLOT_WEAPON,
		SET_BROKEN_KNIGHT,
		"剑身布满锈痕与崩口的断剑。虽已残破，但依稀可见昔日精湛的锻造工艺。"
	)
	item.attack = 1
	return item


## Starter armor: Broken Knight Armor.
static func broken_armor() -> EquipmentItem:
	var item := EquipmentItem.new(
		&"broken_armor",
		"破损板甲",
		EquipmentItem.SLOT_ARMOR,
		SET_BROKEN_KNIGHT,
		"布满凹痕与暗红锈斑的骑士胸甲，内衬虽已腐朽，仍可抵御部分直击。"
	)
	item.defense = 1
	item.max_hp = 1
	return item


## Starter trinket: Broken Knight Pendant.
static func broken_pendant() -> EquipmentItem:
	var item := EquipmentItem.new(
		&"broken_pendant",
		"破损挂坠",
		EquipmentItem.SLOT_TRINKET,
		SET_BROKEN_KNIGHT,
		"挂着微温灰烬石的破损吊坠，微弱的余烬波动能过滤部分渗入的毒雾。"
	)
	item.toxin_resist = 0.05
	return item


## Upgraded weapon: Iron Blade.
static func iron_blade() -> EquipmentItem:
	var item := EquipmentItem.new(
		&"iron_blade",
		"铁斩刃",
		EquipmentItem.SLOT_WEAPON,
		&"",
		"由坚硬熟铁锤炼打磨的重直刃，刃锋沉重凌厉，劈斩更具破坏力。"
	)
	item.attack = 2
	return item


## Upgraded armor: Iron Carapace.
static func iron_carapace() -> EquipmentItem:
	var item := EquipmentItem.new(
		&"iron_carapace",
		"生铁甲壳",
		EquipmentItem.SLOT_ARMOR,
		&"",
		"多层铸铁铆接成型的护体胸甲，防护坚固，可抵挡更强烈的冲击。"
	)
	item.defense = 2
	item.max_hp = 2
	return item


## Upgraded trinket: Toxic Ward.
static func toxic_ward() -> EquipmentItem:
	var item := EquipmentItem.new(
		&"toxic_ward",
		"滤毒符印",
		EquipmentItem.SLOT_TRINKET,
		&"",
		"凝结高纯度净化滤芯的炼金符印，大幅降低毒素侵蚀速度并加速体内排毒。"
	)
	item.toxin_resist = 0.15
	item.toxin_decay = 0.5
	return item


## Backward-compatibility / E2E test item: Bone Charm.
static func bone_charm() -> EquipmentItem:
	var item := EquipmentItem.new(
		&"bone_charm",
		"白骨护身符",
		EquipmentItem.SLOT_TRINKET,
		&"",
		"刻有祈愿铭文的异兽遗骨，微幅提升配戴者的生命与机敏行动力。"
	)
	item.max_hp = 1
	item.speed_mult = 0.05
	return item


# ===========================================================================
# Lookup & Registry
# ===========================================================================

## Rehydrates an EquipmentItem from its ID. Returns null safely if the ID is unknown
## or invalid, ensuring legacy saves and missing keys degrade gracefully without errors.
static func for_id(p_id: Variant) -> EquipmentItem:
	if p_id == null:
		return null
	var id_sym := StringName(str(p_id))
	match id_sym:
		&"broken_sword":
			return broken_sword()
		&"broken_armor":
			return broken_armor()
		&"broken_pendant":
			return broken_pendant()
		&"iron_blade":
			return iron_blade()
		&"iron_carapace":
			return iron_carapace()
		&"toxic_ward":
			return toxic_ward()
		&"bone_charm":
			return bone_charm()
	return null


## Returns true if the catalog contains a factory for the specified item ID.
static func has_id(p_id: Variant) -> bool:
	return for_id(p_id) != null


## Returns all registered item IDs.
static func get_all_registered_ids() -> Array[StringName]:
	return [
		&"broken_sword",
		&"broken_armor",
		&"broken_pendant",
		&"iron_blade",
		&"iron_carapace",
		&"toxic_ward",
		&"bone_charm"
	]


## Returns the default starter gear dictionary for new games or legacy save fallback.
static func get_starter_loadout() -> Dictionary:
	return {
		EquipmentItem.SLOT_WEAPON: broken_sword(),
		EquipmentItem.SLOT_ARMOR: broken_armor(),
		EquipmentItem.SLOT_TRINKET: broken_pendant()
	}


## Returns the default starter gear IDs for save file initialization.
static func get_starter_ids() -> Dictionary:
	return {
		EquipmentItem.SLOT_WEAPON: &"broken_sword",
		EquipmentItem.SLOT_ARMOR: &"broken_armor",
		EquipmentItem.SLOT_TRINKET: &"broken_pendant"
	}


# ===========================================================================
# Set Synergy Calculation
# ===========================================================================

## Returns bonus dictionary for a specific set at a given piece count.
static func get_set_bonuses(set_id: Variant, piece_count: int) -> Dictionary:
	if set_id == null:
		return {}
	var s_id := StringName(str(set_id))
	if not SET_DEFINITIONS.has(s_id):
		return {}
	var set_def: Dictionary = SET_DEFINITIONS[s_id]
	var thresholds: Array = set_def.get("thresholds", [])
	for entry in thresholds:
		if entry is Dictionary and int(entry.get("pieces", 0)) == piece_count:
			return {
				"set_id": s_id,
				"pieces": piece_count,
				"defense": int(entry.get("defense", 0)),
				"max_hp": int(entry.get("max_hp", 0)),
				"attack": int(entry.get("attack", 0)),
				"toxin_resist": float(entry.get("toxin_resist", 0.0)),
				"toxin_decay": float(entry.get("toxin_decay", 0.0)),
				"speed_mult": float(entry.get("speed_mult", 0.0)),
				"name": String(entry.get("name", "")),
				"description": String(entry.get("description", ""))
			}
	return {}


## Computes all active set synergies for a collection of equipped items.
## Returns Array[Dictionary] formatted for direct consumption by CharacterStats.recalculate()
## and EquipmentInventory.get_set_synergies().
static func calculate_set_synergies(equipped_items: Array) -> Array[Dictionary]:
	var synergies: Array[Dictionary] = []
	var set_counts: Dictionary = {}

	# Tally set items
	for item in equipped_items:
		if item == null:
			continue
		var s_id: StringName = &""
		if item is EquipmentItem:
			s_id = item.set_id
		elif item is Dictionary and item.has("set_id"):
			s_id = StringName(item["set_id"])
		elif item is Object and "set_id" in item:
			s_id = StringName(item.get("set_id"))

		if s_id != &"":
			set_counts[s_id] = int(set_counts.get(s_id, 0)) + 1

	# Match against set definitions
	for s_id in set_counts:
		if not SET_DEFINITIONS.has(s_id):
			continue
		var count: int = set_counts[s_id]
		var set_def: Dictionary = SET_DEFINITIONS[s_id]
		var thresholds: Array = set_def.get("thresholds", [])
		for entry in thresholds:
			if not (entry is Dictionary):
				continue
			var threshold_pieces: int = int(entry.get("pieces", 0))
			if count >= threshold_pieces:
				var syn: Dictionary = {
					"set_id": s_id,
					"pieces": threshold_pieces,
					"defense": int(entry.get("defense", 0)),
					"max_hp": int(entry.get("max_hp", 0)),
					"attack": int(entry.get("attack", 0)),
					"toxin_resist": float(entry.get("toxin_resist", 0.0)),
					"toxin_decay": float(entry.get("toxin_decay", 0.0)),
					"speed_mult": float(entry.get("speed_mult", 0.0)),
					"name": String(entry.get("name", "")),
					"description": String(entry.get("description", ""))
				}
				synergies.append(syn)

	return synergies
