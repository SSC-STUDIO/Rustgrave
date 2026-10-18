class_name EquipmentItem
extends Resource
## Data model for equippable weapon, armor, and trinket items.
## Compatible with EquipmentInventory slot management, CharacterStats calculation,
## and SaveData serialization.

const SLOT_WEAPON: StringName = &"weapon"
const SLOT_ARMOR: StringName = &"armor"
const SLOT_TRINKET: StringName = &"trinket"
const VALID_SLOTS: Array[StringName] = [SLOT_WEAPON, SLOT_ARMOR, SLOT_TRINKET]

@export_group("Identification")
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var slot_type: StringName = &""
@export var set_id: StringName = &""
@export var icon: Texture2D = null
## v3：稀有度（common/rare/epic）与词缀列表（见 affix_catalog.gd）。
@export var rarity: StringName = &"common"
@export var affixes: Array[Dictionary] = []

@export_group("Combat Attributes")
@export var attack: int = 0
@export var defense: int = 0
@export var max_hp: int = 0

@export_group("Resilience & Mobility")
@export var toxin_resist: float = 0.0
@export var toxin_decay: float = 0.0
@export var speed_mult: float = 0.0


func _init(
	p_id: StringName = &"",
	p_display_name: String = "",
	p_slot_type: StringName = &"",
	p_set_id: StringName = &"",
	p_description: String = ""
) -> void:
	if p_id != &"":
		id = p_id
	if p_display_name != "":
		display_name = p_display_name
	if p_slot_type != &"":
		slot_type = p_slot_type
	if p_set_id != &"":
		set_id = p_set_id
	if p_description != "":
		description = p_description


## Returns true if the item has a valid identifier and recognized slot type.
func is_valid() -> bool:
	return id != &"" and slot_type in VALID_SLOTS


## Checks if this item can be placed in the specified equipment slot.
func matches_slot(target_slot: StringName) -> bool:
	return slot_type == target_slot


## Returns true if this item belongs to a gear set.
func has_set() -> bool:
	return set_id != &""


## Creates an independent duplicate of this equipment item.
func duplicate_item() -> Resource:
	var script: GDScript = get_script() as GDScript
	var copy: Resource = script.new(id, display_name, slot_type, set_id, description)
	copy.set("attack", attack)
	copy.set("defense", defense)
	copy.set("max_hp", max_hp)
	copy.set("toxin_resist", toxin_resist)
	copy.set("toxin_decay", toxin_decay)
	copy.set("speed_mult", speed_mult)
	copy.set("icon", icon)
	copy.set("rarity", rarity)
	copy.set("affixes", affixes.duplicate(true))
	return copy


## Returns a Dictionary representation of the item bonuses.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"slot_type": slot_type,
		"set_id": set_id,
		"attack": attack,
		"defense": defense,
		"max_hp": max_hp,
		"toxin_resist": toxin_resist,
		"toxin_decay": toxin_decay,
		"speed_mult": speed_mult,
		"rarity": rarity,
		"affixes": affixes.duplicate(true),
	}


## Returns an array of formatted tooltip lines for UI presentation.
func get_stat_lines() -> Array[String]:
	var lines: Array[String] = []
	if attack != 0:
		lines.append("攻击力 %+d" % attack)
	if defense != 0:
		lines.append("防御力 %+d" % defense)
	if max_hp != 0:
		lines.append("生命上限 %+d" % max_hp)
	if not is_zero_approx(toxin_resist):
		lines.append("毒素抗性 %+.0f%%" % (toxin_resist * 100.0))
	if not is_zero_approx(toxin_decay):
		lines.append("毒素消散 %+.1f/s" % toxin_decay)
	if not is_zero_approx(speed_mult):
		lines.append("移动速度 %+.0f%%" % (speed_mult * 100.0))
	if not affixes.is_empty():
		var Affix := preload("res://scripts/data/affix_catalog.gd")
		for line in Affix.lines_for(affixes):
			lines.append("· " + line)
	return lines
