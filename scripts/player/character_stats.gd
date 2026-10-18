class_name CharacterStats
extends Node
## Lightweight numerical model managing base attributes, equipment bonuses,
## temporary modifiers, and computed effective attributes for the Player.

const CharacterOriginScript := preload("res://scripts/data/character_origin.gd")
const OriginCatalogScript := preload("res://scripts/data/origin_catalog.gd")
const AffixCatalogScript := preload("res://scripts/data/affix_catalog.gd")

signal stats_changed()

const BASE_MAX_HP: int = 5
const BASE_ATTACK: int = 0
const BASE_DEFENSE: int = 0
const BASE_TOXIN_RESIST: float = 0.0
const BASE_TOXIN_DECAY: float = 0.0
const BASE_SPEED_MULT: float = 1.0

const TOXIN_RESIST_MIN: float = 0.0
const TOXIN_RESIST_MAX: float = 0.8
const SPEED_MULT_MIN: float = 0.1
const SPEED_MULT_MAX: float = 3.0

@export var base_max_hp: int = BASE_MAX_HP:
	set(v):
		base_max_hp = v
		_recompute()

@export var base_attack: int = BASE_ATTACK:
	set(v):
		base_attack = v
		_recompute()

@export var base_defense: int = BASE_DEFENSE:
	set(v):
		base_defense = v
		_recompute()

@export var base_toxin_resist: float = BASE_TOXIN_RESIST:
	set(v):
		base_toxin_resist = v
		_recompute()

@export var base_toxin_decay: float = BASE_TOXIN_DECAY:
	set(v):
		base_toxin_decay = v
		_recompute()

@export var base_speed_mult: float = BASE_SPEED_MULT:
	set(v):
		base_speed_mult = v
		_recompute()

# Bonus attributes from equipment and synergies
var bonus_max_hp: int = 0:
	set(v):
		bonus_max_hp = v
		equip_max_hp = v
		_recompute()

var bonus_attack: int = 0:
	set(v):
		bonus_attack = v
		equip_attack = v
		_recompute()

var bonus_defense: int = 0:
	set(v):
		bonus_defense = v
		equip_defense = v
		_recompute()

var bonus_toxin_resist: float = 0.0:
	set(v):
		bonus_toxin_resist = v
		equip_toxin_resist = v
		_recompute()

var bonus_toxin_decay: float = 0.0:
	set(v):
		bonus_toxin_decay = v
		equip_toxin_decay = v
		_recompute()

var bonus_speed_mult: float = 0.0:
	set(v):
		bonus_speed_mult = v
		equip_speed_mult = v
		_recompute()

# Equipment bonuses mirror
var equip_max_hp: int = 0
var equip_attack: int = 0
var equip_defense: int = 0
var equip_toxin_resist: float = 0.0
var equip_toxin_decay: float = 0.0
var equip_speed_mult: float = 0.0

# Origin tracking
var origin_id: StringName = &""
var origin_max_hp: int = 0
var origin_attack: int = 0
var origin_defense: int = 0
var origin_toxin_resist: float = 0.0
var origin_toxin_decay: float = 0.0
var origin_speed_mult: float = 0.0

# Temporary modifiers: id -> { "stats": Dictionary, "duration": float, "time_left": float }
var _modifiers: Dictionary = {}

# Cached effective stats
var _effective_max_hp: int = BASE_MAX_HP
var _effective_attack: int = BASE_ATTACK
var _effective_defense: int = BASE_DEFENSE
var _effective_toxin_resist: float = BASE_TOXIN_RESIST
var _effective_toxin_decay: float = BASE_TOXIN_DECAY
var _effective_speed_mult: float = BASE_SPEED_MULT


func _init() -> void:
	_recompute(false)


func _ready() -> void:
	_recompute(false)


func _process(delta: float) -> void:
	if _modifiers.is_empty():
		return
	var expired: Array[StringName] = []
	for id in _modifiers:
		var mod: Dictionary = _modifiers[id]
		var duration: float = float(mod.get("duration", 0.0))
		if duration > 0.0:
			var left: float = float(mod.get("time_left", duration)) - delta
			if left <= 0.0:
				expired.append(id)
			else:
				mod["time_left"] = left
	if not expired.is_empty():
		for id in expired:
			_modifiers.erase(id)
		_recompute()


# ---------------------------------------------------------------------------
# Public Contract (PROJECT.md Specification)
# ---------------------------------------------------------------------------

func get_attack_bonus() -> int:
	return _effective_attack


func get_defense_reduction() -> int:
	return _effective_defense


func get_max_hp_bonus() -> int:
	return _effective_max_hp - base_max_hp


func get_total_max_hp() -> int:
	return _effective_max_hp


func get_effective_max_hp() -> int:
	return _effective_max_hp


func get_toxin_resistance() -> float:
	return _effective_toxin_resist


func get_toxin_decay_bonus() -> float:
	return _effective_toxin_decay


func get_speed_multiplier() -> float:
	return _effective_speed_mult


func get_origin_id() -> StringName:
	return origin_id


func get_origin_stat_modifiers() -> Dictionary:
	return {
		"max_hp": origin_max_hp,
		"attack": origin_attack,
		"defense": origin_defense,
		"toxin_resist": origin_toxin_resist,
		"toxin_decay": origin_toxin_decay,
		"speed_mult": origin_speed_mult
	}


## Applies a character origin by ID or CharacterOrigin instance.
## Passing empty string or null resets origin modifiers back to 0.
func apply_origin(p_origin: Variant) -> void:
	if p_origin == null or str(p_origin) == "":
		origin_id = &""
		origin_max_hp = 0
		origin_attack = 0
		origin_defense = 0
		origin_toxin_resist = 0.0
		origin_toxin_decay = 0.0
		origin_speed_mult = 0.0
		_recompute(true)
		return

	var origin = null
	if is_instance_of(p_origin, CharacterOriginScript):
		origin = p_origin
	else:
		var sym := StringName(str(p_origin))
		origin = OriginCatalogScript.get_origin(sym)

	if origin == null:
		origin_id = StringName(str(p_origin))
		origin_max_hp = 0
		origin_attack = 0
		origin_defense = 0
		origin_toxin_resist = 0.0
		origin_toxin_decay = 0.0
		origin_speed_mult = 0.0
	else:
		origin_id = origin.id
		var mods: Dictionary = origin.stat_modifiers
		origin_max_hp = int(mods.get("max_hp", 0))
		origin_attack = int(mods.get("attack", 0))
		origin_defense = int(mods.get("defense", 0))
		origin_toxin_resist = float(mods.get("toxin_resist", 0.0))
		origin_toxin_decay = float(mods.get("toxin_decay", 0.0))
		origin_speed_mult = float(mods.get("speed_mult", 0.0))

	_recompute(true)


## Recalculate all equipment bonuses and trigger stats recomputation.
## Accepts Array of EquipmentItem / Dictionary and Dictionary/Array of set bonuses.
func recalculate(equipped_items: Array, set_bonuses: Variant = {}) -> void:
	var total_hp := 0
	var total_atk := 0
	var total_def := 0
	var total_res := 0.0
	var total_dec := 0.0
	var total_spd := 0.0

	for item in equipped_items:
		if item == null:
			continue
		total_hp += _extract_int(item, [&"max_hp_bonus", &"hp_bonus", &"max_hp", &"hp"])
		total_atk += _extract_int(item, [&"attack_bonus", &"attack", &"atk"])
		total_def += _extract_int(item, [&"defense_bonus", &"defense", &"def"])
		total_res += _extract_float(item, [&"toxin_resist", &"toxin_resistance", &"resist"])
		total_dec += _extract_float(item, [&"toxin_decay", &"toxin_decay_bonus", &"decay"])
		total_spd += _extract_speed(item)
		# 词缀（v3）：每件装备自带 0–2 条，聚合成同一组 bonus。
		var raw_affixes: Variant = null
		if item is Dictionary:
			raw_affixes = (item as Dictionary).get("affixes", null)
		elif item is Object:
			raw_affixes = (item as Object).get(&"affixes")
		if raw_affixes is Array and not (raw_affixes as Array).is_empty():
			var affix_bonus: Dictionary = AffixCatalogScript.total(raw_affixes)
			total_hp += int(affix_bonus.get("max_hp", 0))
			total_atk += int(affix_bonus.get("attack", 0))
			total_def += int(affix_bonus.get("defense", 0))
			total_res += float(affix_bonus.get("toxin_resist", 0.0))
			total_dec += float(affix_bonus.get("toxin_decay", 0.0))
			total_spd += float(affix_bonus.get("speed_mult", 0.0))

	if set_bonuses is Dictionary:
		total_hp += _extract_int(set_bonuses, [&"max_hp_bonus", &"hp_bonus", &"max_hp", &"hp"])
		total_atk += _extract_int(set_bonuses, [&"attack_bonus", &"attack", &"atk"])
		total_def += _extract_int(set_bonuses, [&"defense_bonus", &"defense", &"def"])
		total_res += _extract_float(set_bonuses, [&"toxin_resist", &"toxin_resistance", &"resist"])
		total_dec += _extract_float(set_bonuses, [&"toxin_decay", &"toxin_decay_bonus", &"decay"])
		total_spd += _extract_speed(set_bonuses)
	elif set_bonuses is Array:
		for sb in set_bonuses:
			if sb is Dictionary:
				total_hp += _extract_int(sb, [&"max_hp_bonus", &"hp_bonus", &"max_hp", &"hp"])
				total_atk += _extract_int(sb, [&"attack_bonus", &"attack", &"atk"])
				total_def += _extract_int(sb, [&"defense_bonus", &"defense", &"def"])
				total_res += _extract_float(sb, [&"toxin_resist", &"toxin_resistance", &"resist"])
				total_dec += _extract_float(sb, [&"toxin_decay", &"toxin_decay_bonus", &"decay"])
				total_spd += _extract_speed(sb)

	bonus_max_hp = total_hp
	bonus_attack = total_atk
	bonus_defense = total_def
	bonus_toxin_resist = total_res
	bonus_toxin_decay = total_dec
	bonus_speed_mult = total_spd
	_recompute(true)


func recompute() -> void:
	_recompute(true)


# ---------------------------------------------------------------------------
# Temporary Modifiers Management
# ---------------------------------------------------------------------------

func add_modifier(id: StringName, stats: Dictionary, duration: float = 0.0) -> void:
	_modifiers[id] = {
		"stats": stats.duplicate(true),
		"duration": duration,
		"time_left": duration
	}
	_recompute()


func remove_modifier(id: StringName) -> bool:
	if _modifiers.has(id):
		_modifiers.erase(id)
		_recompute()
		return true
	return false


func has_modifier(id: StringName) -> bool:
	return _modifiers.has(id)


func clear_modifiers() -> void:
	if not _modifiers.is_empty():
		_modifiers.clear()
		_recompute()


# ---------------------------------------------------------------------------
# Internal Helpers & Computation
# ---------------------------------------------------------------------------

func _recompute(p_emit_signal: bool = true) -> void:
	var mod_max_hp: int = 0
	var mod_attack: int = 0
	var mod_defense: int = 0
	var mod_toxin_resist: float = 0.0
	var mod_toxin_decay: float = 0.0
	var mod_speed_mult: float = 0.0

	for id in _modifiers:
		var st: Dictionary = _modifiers[id].get("stats", {})
		mod_max_hp += _extract_int(st, [&"max_hp_bonus", &"hp_bonus", &"max_hp", &"hp"])
		mod_attack += _extract_int(st, [&"attack_bonus", &"attack", &"atk"])
		mod_defense += _extract_int(st, [&"defense_bonus", &"defense", &"def"])
		mod_toxin_resist += _extract_float(st, [&"toxin_resist", &"toxin_resistance", &"resist"])
		mod_toxin_decay += _extract_float(st, [&"toxin_decay", &"toxin_decay_bonus", &"decay"])
		mod_speed_mult += _extract_speed(st)

	_effective_max_hp = maxi(1, base_max_hp + origin_max_hp + bonus_max_hp + mod_max_hp)
	_effective_attack = maxi(0, base_attack + origin_attack + bonus_attack + mod_attack)
	_effective_defense = maxi(0, base_defense + origin_defense + bonus_defense + mod_defense)
	_effective_toxin_resist = clampf(base_toxin_resist + origin_toxin_resist + bonus_toxin_resist + mod_toxin_resist, TOXIN_RESIST_MIN, TOXIN_RESIST_MAX)
	_effective_toxin_decay = maxf(0.0, base_toxin_decay + origin_toxin_decay + bonus_toxin_decay + mod_toxin_decay)
	_effective_speed_mult = clampf(base_speed_mult + origin_speed_mult + bonus_speed_mult + mod_speed_mult, SPEED_MULT_MIN, SPEED_MULT_MAX)

	if p_emit_signal:
		stats_changed.emit()


func _extract_int(source: Variant, keys: Array[StringName]) -> int:
	if source == null:
		return 0
	for key in keys:
		if source is Dictionary and source.has(key):
			return int(source[key])
		elif source is Object and key in source:
			return int(source.get(key))
	return 0


func _extract_float(source: Variant, keys: Array[StringName]) -> float:
	if source == null:
		return 0.0
	for key in keys:
		if source is Dictionary and source.has(key):
			return float(source[key])
		elif source is Object and key in source:
			return float(source.get(key))
	return 0.0


func _extract_speed(source: Variant) -> float:
	if source == null:
		return 0.0
	for key in [&"speed_mult", &"speed_bonus", &"speed"]:
		if source is Dictionary and source.has(key):
			return float(source[key])
		elif source is Object and key in source:
			return float(source.get(key))
	return 0.0
