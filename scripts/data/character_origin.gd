class_name CharacterOrigin
extends Resource
## Resource definition for playable character origins (combat archetypes).
## Encapsulates identification, lore, combat focus, stat modifiers, and starting loadout IDs.

@export var id: StringName = &""
@export var title: String = ""
@export var lore: String = ""
@export var combat_focus: String = ""
@export var stat_modifiers: Dictionary = {}
@export var default_weapon: StringName = &""
@export var default_armor: StringName = &""
@export var allowed_trinkets: Array[StringName] = []


func _init(
	p_id: StringName = &"",
	p_title: String = "",
	p_lore: String = "",
	p_combat_focus: String = "",
	p_stat_modifiers: Dictionary = {},
	p_default_weapon: StringName = &"",
	p_default_armor: StringName = &"",
	p_allowed_trinkets: Array[StringName] = []
) -> void:
	id = p_id
	title = p_title
	lore = p_lore
	combat_focus = p_combat_focus
	stat_modifiers = p_stat_modifiers.duplicate(true)
	default_weapon = p_default_weapon
	default_armor = p_default_armor
	allowed_trinkets = p_allowed_trinkets.duplicate()


## Returns true if the origin has a valid identifier and non-empty title.
func is_valid() -> bool:
	return id != &"" and not title.is_empty()


## Safe lookup for a specific stat modifier value, returning default_val if absent.
func get_stat_modifier(stat_key: StringName, default_val: Variant = 0) -> Variant:
	if stat_modifiers.has(stat_key):
		return stat_modifiers[stat_key]
	var str_key := String(stat_key)
	if stat_modifiers.has(str_key):
		return stat_modifiers[str_key]
	return default_val


## Checks whether the specified trinket ID is present in this origin's allowed trinket pool.
func allows_trinket(trinket_id: StringName) -> bool:
	return allowed_trinkets.has(trinket_id)


## Serializes this origin configuration into a Dictionary representation.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"title": title,
		"lore": lore,
		"combat_focus": combat_focus,
		"stat_modifiers": stat_modifiers.duplicate(true),
		"default_weapon": default_weapon,
		"default_armor": default_armor,
		"allowed_trinkets": allowed_trinkets.duplicate()
	}
