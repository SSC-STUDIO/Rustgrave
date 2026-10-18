class_name OriginCatalog
extends RefCounted
## Static catalog and calculation registry for playable character origins.
## Defines the 3 starting archetypes, their lore, preset gear, and preview math.

const ORIGIN_EMBER_VANGUARD := &"ember_vanguard"
const ORIGIN_SCRAP_SCAVENGER := &"scrap_scavenger"
const ORIGIN_RUST_AUTOMATON := &"rust_automaton"

const ALLOWED_TRINKETS: Array[StringName] = [
	&"broken_pendant",
	&"bone_amulet",
	&"toxic_filter_talisman"
]


# ===========================================================================
# Origin Definitions
# ===========================================================================

## Ember Vanguard (余烬重骑): Max HP +1, Defense +1.
## Sturdy defense, sustained attrition, and heavy knight protection.
static func ember_vanguard() -> CharacterOrigin:
	return CharacterOrigin.new(
		ORIGIN_EMBER_VANGUARD,
		"余烬重骑",
		"身负厚重残铠的守望骑士，余烬火种在胸膛低语，赋予其抵御一切冲击的磐石体魄。",
		"稳固防御与高生存",
		{
			"max_hp": 1,
			"defense": 1,
			"attack": 0,
			"toxin_resist": 0.0,
			"toxin_decay": 0.0,
			"speed_mult": 0.0
		},
		&"broken_sword",
		&"broken_armor",
		ALLOWED_TRINKETS.duplicate(),
		&"passive_ember_bulwark",
		"完美弹反后 2 秒内防御 +1。"
	)


## Scrap Scavenger (废料剑客): Attack +1, Speed Mult +10% (+0.10).
## High mobility, rapid evasion, and sharp scrap blades.
static func scrap_scavenger() -> CharacterOrigin:
	return CharacterOrigin.new(
		ORIGIN_SCRAP_SCAVENGER,
		"废料剑客",
		"游走于齿轮遗迹与钢铁废墟间的拾荒刺客，以轻盈敏捷的步法与锋利拼凑的残刃穿梭于死线。",
		"敏捷规避与高机动斩击",
		{
			"max_hp": 0,
			"defense": 0,
			"attack": 1,
			"toxin_resist": 0.0,
			"toxin_decay": 0.0,
			"speed_mult": 0.10
		},
		&"scavenger_blade",
		&"scavenger_rags",
		ALLOWED_TRINKETS.duplicate(),
		&"passive_scavenger_instinct",
		"拾取锈核或装备时回复 1 点生命（20 秒冷却）。"
	)


## Rust Automaton (锈械学者): Toxin Resist +20% (+0.20), Toxin Decay +50% (+0.50).
## Corrosive fluid immunity, alchemy filtration, and mire combat specialization.
static func rust_automaton() -> CharacterOrigin:
	return CharacterOrigin.new(
		ORIGIN_RUST_AUTOMATON,
		"锈械学者",
		"将机械义肢与炼金滤腺深植体内的古代学者，即便身处浓度致命的腐蚀酸池亦能从容穿行。",
		"腐液耐受与毒池战斗特化",
		{
			"max_hp": 0,
			"defense": 0,
			"attack": 0,
			"toxin_resist": 0.20,
			"toxin_decay": 0.50,
			"speed_mult": 0.0
		},
		&"scholar_probe",
		&"scholar_cowl",
		ALLOWED_TRINKETS.duplicate(),
		&"passive_filter_convert",
		"毒素满溢的伤害每两次只结算一次，并排掉 10% 毒素。"
	)


# ===========================================================================
# Registry & Query Methods
# ===========================================================================

## Returns an array containing instances of all 3 defined character origins.
static func get_all_origins() -> Array[CharacterOrigin]:
	return [
		ember_vanguard(),
		scrap_scavenger(),
		rust_automaton()
	]


## Returns the list of all valid origin IDs.
static func get_all_origin_ids() -> Array[StringName]:
	return [
		ORIGIN_EMBER_VANGUARD,
		ORIGIN_SCRAP_SCAVENGER,
		ORIGIN_RUST_AUTOMATON
	]


## Returns the universal starting trinket pool.
static func get_trinket_pool() -> Array[StringName]:
	return ALLOWED_TRINKETS.duplicate()


## Rehydrates a CharacterOrigin by ID. Returns null safely if ID is unknown.
static func get_origin(p_id: Variant) -> CharacterOrigin:
	if p_id == null:
		return null
	var id_sym := StringName(str(p_id))
	match id_sym:
		ORIGIN_EMBER_VANGUARD:
			return ember_vanguard()
		ORIGIN_SCRAP_SCAVENGER:
			return scrap_scavenger()
		ORIGIN_RUST_AUTOMATON:
			return rust_automaton()
	return null


## Returns true if the catalog contains the specified origin ID.
static func has_origin(p_id: Variant) -> bool:
	return get_origin(p_id) != null


## Resolves starter loadout EquipmentItems for a given origin and chosen trinket.
static func get_starter_loadout(origin_id: Variant, trinket_id: Variant = &"") -> Dictionary:
	var origin := get_origin(origin_id)
	var weapon_id: StringName = origin.default_weapon if origin != null else &"broken_sword"
	var armor_id: StringName = origin.default_armor if origin != null else &"broken_armor"
	var resolved_trinket_id: StringName = StringName(str(trinket_id))
	if resolved_trinket_id == &"" or not ALLOWED_TRINKETS.has(resolved_trinket_id):
		resolved_trinket_id = ALLOWED_TRINKETS[0]

	return {
		EquipmentItem.SLOT_WEAPON: EquipmentCatalog.for_id(weapon_id),
		EquipmentItem.SLOT_ARMOR: EquipmentCatalog.for_id(armor_id),
		EquipmentItem.SLOT_TRINKET: EquipmentCatalog.for_id(resolved_trinket_id)
	}


# ===========================================================================
# Live Dynamic Stat Preview (WYSIWYG Parity with CharacterStats)
# ===========================================================================

## Calculates composite effective 6 stats (max_hp, attack, defense, toxin_resist,
## toxin_decay, speed_mult) with exact mathematical parity to CharacterStats.
## Evaluates base attributes, origin modifiers, item values, set synergies (e.g. Broken Knight),
## and enforces strict boundary clamping ([0.0, 0.8] for resist, [0.1, 3.0] for speed, floors >= 0/1).
static func calculate_preview_stats(
	origin_id: Variant,
	weapon_id: Variant,
	armor_id: Variant,
	trinket_id: Variant
) -> Dictionary:
	# 1. Base defaults (mirroring CharacterStats baseline constants)
	var base_hp: int = CharacterStats.BASE_MAX_HP # 5
	var base_atk: int = CharacterStats.BASE_ATTACK # 0
	var base_def: int = CharacterStats.BASE_DEFENSE # 0
	var base_res: float = CharacterStats.BASE_TOXIN_RESIST # 0.0
	var base_dec: float = CharacterStats.BASE_TOXIN_DECAY # 0.0
	var base_spd: float = CharacterStats.BASE_SPEED_MULT # 1.0

	# 2. Origin stat modifiers
	var orig_hp: int = 0
	var orig_atk: int = 0
	var orig_def: int = 0
	var orig_res: float = 0.0
	var orig_dec: float = 0.0
	var orig_spd: float = 0.0

	var origin := get_origin(origin_id)
	if origin != null:
		orig_hp = int(origin.stat_modifiers.get("max_hp", 0))
		orig_atk = int(origin.stat_modifiers.get("attack", 0))
		orig_def = int(origin.stat_modifiers.get("defense", 0))
		orig_res = float(origin.stat_modifiers.get("toxin_resist", 0.0))
		orig_dec = float(origin.stat_modifiers.get("toxin_decay", 0.0))
		orig_spd = float(origin.stat_modifiers.get("speed_mult", 0.0))

	# 3. Equipped items
	var weapon: EquipmentItem = EquipmentCatalog.for_id(weapon_id) if weapon_id != null and str(weapon_id) != "" else null
	var armor: EquipmentItem = EquipmentCatalog.for_id(armor_id) if armor_id != null and str(armor_id) != "" else null
	var trinket: EquipmentItem = EquipmentCatalog.for_id(trinket_id) if trinket_id != null and str(trinket_id) != "" else null

	var equip_hp: int = 0
	var equip_atk: int = 0
	var equip_def: int = 0
	var equip_res: float = 0.0
	var equip_dec: float = 0.0
	var equip_spd: float = 0.0

	var equipped_list: Array = []
	for item in [weapon, armor, trinket]:
		if item != null:
			equipped_list.append(item)
			equip_hp += item.max_hp
			equip_atk += item.attack
			equip_def += item.defense
			equip_res += item.toxin_resist
			equip_dec += item.toxin_decay
			equip_spd += item.speed_mult

	# 4. Set synergies
	var synergies: Array[Dictionary] = EquipmentCatalog.calculate_set_synergies(equipped_list)
	var syn_hp: int = 0
	var syn_atk: int = 0
	var syn_def: int = 0
	var syn_res: float = 0.0
	var syn_dec: float = 0.0
	var syn_spd: float = 0.0

	for syn in synergies:
		syn_hp += int(syn.get("max_hp", 0))
		syn_atk += int(syn.get("attack", 0))
		syn_def += int(syn.get("defense", 0))
		syn_res += float(syn.get("toxin_resist", 0.0))
		syn_dec += float(syn.get("toxin_decay", 0.0))
		syn_spd += float(syn.get("speed_mult", 0.0))

	# 5. Composite effective values with strict boundary clamping
	var effective_hp: int = maxi(1, base_hp + orig_hp + equip_hp + syn_hp)
	var effective_atk: int = maxi(0, base_atk + orig_atk + equip_atk + syn_atk)
	var effective_def: int = maxi(0, base_def + orig_def + equip_def + syn_def)
	var effective_res: float = clampf(base_res + orig_res + equip_res + syn_res, CharacterStats.TOXIN_RESIST_MIN, CharacterStats.TOXIN_RESIST_MAX)
	var effective_dec: float = maxf(0.0, base_dec + orig_dec + equip_dec + syn_dec)
	var effective_spd: float = clampf(base_spd + orig_spd + equip_spd + syn_spd, CharacterStats.SPEED_MULT_MIN, CharacterStats.SPEED_MULT_MAX)

	return {
		"max_hp": effective_hp,
		"attack": effective_atk,
		"defense": effective_def,
		"toxin_resist": effective_res,
		"toxin_decay": effective_dec,
		"speed_mult": effective_spd,
		"synergies": synergies
	}
