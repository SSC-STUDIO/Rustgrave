class_name EquipmentInventory
extends Node
## Manages Player equipment slots (weapon, armor, trinket) and bag container.
## Emits signals on modification and detects active set synergies.

signal equipment_changed()
signal bag_changed()

const SLOT_WEAPON: StringName = &"weapon"
const SLOT_ARMOR: StringName = &"armor"
const SLOT_TRINKET: StringName = &"trinket"
const SLOTS: Array[StringName] = [SLOT_WEAPON, SLOT_ARMOR, SLOT_TRINKET]

const MAX_BAG_CAPACITY: int = 16
const CATALOG_PATH: String = "res://scripts/data/equipment_catalog.gd"

## Current equipped items per slot.
var equipped: Dictionary = {
	SLOT_WEAPON: null,
	SLOT_ARMOR: null,
	SLOT_TRINKET: null
}

## Inventory bag storing unequipped items (max capacity: 16).
var bag: Array = []


func _ready() -> void:
	pass


## Equip an item into a designated slot.
## Returns true on success, false if rejected.
func equip_item(item: Variant, slot: StringName) -> bool:
	if item == null:
		return false
	if not equipped.has(slot):
		return false

	var resolved_item: Variant = _resolve_item(item)
	if resolved_item == null:
		return false

	var item_slot: StringName = _get_item_slot(resolved_item)
	if item_slot != slot:
		return false

	var prev: Variant = equipped[slot]
	if prev != null:
		if bag.size() >= MAX_BAG_CAPACITY:
			return false
		bag.append(prev)
		bag_changed.emit()

	equipped[slot] = resolved_item
	equipment_changed.emit()
	return true


## Unequip an item from a slot into the bag.
## Returns false if slot empty or bag is full (capacity 16).
func unequip_slot(slot: StringName) -> bool:
	if not equipped.has(slot) or equipped[slot] == null:
		return false
	if bag.size() >= MAX_BAG_CAPACITY:
		return false

	var item: Variant = equipped[slot]
	equipped[slot] = null
	bag.append(item)
	equipment_changed.emit()
	bag_changed.emit()
	return true


## Atomic swap between equipped slot and bag item at bag_index.
## If slot was empty, moves candidate into slot.
func swap_item(slot: StringName, bag_index: int) -> bool:
	if not equipped.has(slot):
		return false
	if bag_index < 0 or bag_index >= bag.size():
		return false

	var candidate: Variant = bag[bag_index]
	if candidate == null:
		return false

	var candidate_slot: StringName = _get_item_slot(candidate)
	if candidate_slot != slot:
		return false

	var old_item: Variant = equipped[slot]
	equipped[slot] = candidate
	if old_item != null:
		bag[bag_index] = old_item
	else:
		bag.remove_at(bag_index)

	equipment_changed.emit()
	bag_changed.emit()
	return true


## Add an item or item ID to the bag.
## Rejects if bag is at MAX_BAG_CAPACITY (16) or item is invalid.
func add_to_bag(item: Variant) -> bool:
	if item == null or bag.size() >= MAX_BAG_CAPACITY:
		return false

	var resolved: Variant = _resolve_item(item)
	if resolved == null:
		return false

	bag.append(resolved)
	bag_changed.emit()
	return true


## Remove and return an item from the bag at bag_index.
func remove_from_bag(bag_index: int) -> Variant:
	if bag_index < 0 or bag_index >= bag.size():
		return null
	var item: Variant = bag[bag_index]
	bag.remove_at(bag_index)
	bag_changed.emit()
	return item


## Return the item currently equipped in slot, or null.
func get_equipped(slot: StringName) -> Variant:
	return equipped.get(slot, null)


## Return all currently equipped items as an Array.
func get_equipped_items() -> Array:
	var items: Array = []
	for slot in SLOTS:
		var it: Variant = equipped.get(slot)
		if it != null:
			items.append(it)
	return items


## Alias for get_equipped_items() matching dispatch prompt.
func get_all_equipped() -> Array:
	return get_equipped_items()


## Calculate all active set synergy bonuses from equipped items.
func get_set_synergies() -> Array[Dictionary]:
	if ResourceLoader.exists(CATALOG_PATH):
		var catalog: GDScript = load(CATALOG_PATH)
		if catalog != null and catalog.has_method("calculate_set_synergies"):
			return catalog.call("calculate_set_synergies", get_equipped_items())

	# Fallback calculation if catalog is not accessible
	var synergies: Array[Dictionary] = []
	var counts: Dictionary = {}

	for slot in equipped:
		var it: Variant = equipped[slot]
		if it != null and ("set_id" in it or "set" in it):
			var s_id: Variant = it.get("set_id") if "set_id" in it else it.get("set")
			if s_id != null and s_id != &"":
				counts[s_id] = counts.get(s_id, 0) + 1

	for s_id in counts:
		var c: int = counts[s_id]
		if s_id == &"broken_knight":
			if c >= 2:
				synergies.append({"set_id": &"broken_knight", "pieces": 2, "defense": 1, "max_hp": 1})
			if c >= 3:
				synergies.append({"set_id": &"broken_knight", "pieces": 3, "attack": 1, "toxin_resist": 0.1})

	return synergies


## Alias for get_set_synergies() matching dispatch prompt.
func get_active_set_bonuses() -> Array[Dictionary]:
	return get_set_synergies()


## Check if all slots and bag are completely unequipped.
func is_completely_unequipped() -> bool:
	for slot in SLOTS:
		if equipped[slot] != null:
			return false
	return bag.is_empty()


## Initialize starter Broken Knight set.
func initialize_starter_kit(force: bool = false) -> bool:
	if not force and not is_completely_unequipped():
		return false

	var sword: Variant = _resolve_item(&"broken_sword")
	var armor: Variant = _resolve_item(&"broken_armor")
	var pendant: Variant = _resolve_item(&"broken_pendant")

	if sword != null:
		equipped[SLOT_WEAPON] = sword
	if armor != null:
		equipped[SLOT_ARMOR] = armor
	if pendant != null:
		equipped[SLOT_TRINKET] = pendant

	equipment_changed.emit()
	return true


## Serialize equipped items and bag for SaveData ConfigFile.
func serialize() -> Dictionary:
	var data := {
		"weapon": _item_to_id(equipped[SLOT_WEAPON]),
		"armor": _item_to_id(equipped[SLOT_ARMOR]),
		"trinket": _item_to_id(equipped[SLOT_TRINKET]),
		"bag": []
	}
	for it in bag:
		var id_str := _item_to_id(it)
		if id_str != "":
			data["bag"].append(id_str)
	return data


## Restore equipment and bag from SaveData dictionary.
func deserialize(data: Dictionary) -> void:
	if data == null:
		data = {}
	equipped[SLOT_WEAPON] = _resolve_item(data.get("weapon", ""))
	equipped[SLOT_ARMOR] = _resolve_item(data.get("armor", ""))
	equipped[SLOT_TRINKET] = _resolve_item(data.get("trinket", ""))
	bag.clear()
	var raw_bag: Variant = data.get("bag", [])
	if raw_bag is Array:
		for id_val in raw_bag:
			var item: Variant = _resolve_item(id_val)
			if item != null and bag.size() < MAX_BAG_CAPACITY:
				bag.append(item)
	equipment_changed.emit()
	bag_changed.emit()


# ---------------------------------------------------------------------------
# Internal Helpers
# ---------------------------------------------------------------------------

func _resolve_item(source: Variant) -> Variant:
	if source == null:
		return null
	if source is String or source is StringName:
		var id_str := String(source).strip_edges()
		if id_str == "":
			return null
		if ResourceLoader.exists(CATALOG_PATH):
			var catalog: GDScript = load(CATALOG_PATH)
			if catalog != null and catalog.has_method("for_id"):
				return catalog.call("for_id", StringName(id_str))
		return EquipmentCatalog.for_id(StringName(id_str))
	return source


func _get_item_slot(item: Variant) -> StringName:
	if item == null:
		return &""
	if "slot_type" in item:
		return StringName(item.get("slot_type"))
	if "slot" in item:
		return StringName(item.get("slot"))
	return &""


func _item_to_id(item: Variant) -> String:
	if item == null:
		return ""
	if item is String or item is StringName:
		return String(item)
	if "id" in item:
		return String(item.get("id"))
	return ""
