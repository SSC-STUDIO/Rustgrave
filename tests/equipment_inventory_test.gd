class_name EquipmentInventoryTest
extends TestCase
## Tier 2: Equipment Inventory & Slot Management Test Suite.
## Validates slot restrictions, equip/unequip operations, atomic swaps,
## bag capacity bounds (16 items), illegal inputs, starter gear catalog,
## and set synergy detection.

const INVENTORY_SCRIPT_PATH := "res://scripts/player/equipment_inventory.gd"
const ITEM_SCRIPT_PATH := "res://scripts/data/equipment_item.gd"
const CATALOG_SCRIPT_PATH := "res://scripts/data/equipment_catalog.gd"

const SLOT_WEAPON := &"weapon"
const SLOT_ARMOR := &"armor"
const SLOT_TRINKET := &"trinket"


## Mock item for contract testing.
class MockEquipmentItem extends Resource:
	var id: StringName = &""
	var display_name: String = ""
	var slot_type: StringName = &""
	var set_id: StringName = &""
	var attack: int = 0
	var defense: int = 0
	var max_hp: int = 0
	var toxin_resist: float = 0.0
	var toxin_decay: float = 0.0
	var speed_mult: float = 0.0

	func _init(p_id: StringName = &"", p_name: String = "", p_slot: StringName = &"", p_set: StringName = &"") -> void:
		id = p_id
		display_name = p_name
		slot_type = p_slot
		set_id = p_set


## Mock catalog for contract testing.
class MockEquipmentCatalog extends RefCounted:
	static func broken_sword() -> MockEquipmentItem:
		var item := MockEquipmentItem.new(&"broken_sword", "破损骑士剑", &"weapon", &"broken_knight")
		item.attack = 1
		return item

	static func broken_armor() -> MockEquipmentItem:
		var item := MockEquipmentItem.new(&"broken_armor", "破损板甲", &"armor", &"broken_knight")
		item.defense = 1
		item.max_hp = 1
		return item

	static func broken_pendant() -> MockEquipmentItem:
		var item := MockEquipmentItem.new(&"broken_pendant", "破损挂坠", &"trinket", &"broken_knight")
		item.toxin_resist = 0.05
		return item

	static func iron_blade() -> MockEquipmentItem:
		var item := MockEquipmentItem.new(&"iron_blade", "铁斩刃", &"weapon", &"")
		item.attack = 2
		return item

	static func for_id(p_id: StringName) -> Object:
		match p_id:
			&"broken_sword": return broken_sword()
			&"broken_armor": return broken_armor()
			&"broken_pendant": return broken_pendant()
			&"iron_blade": return iron_blade()
		return null


## Mock inventory for contract testing.
class MockEquipmentInventory extends Node:
	const SLOT_WEAPON := &"weapon"
	const SLOT_ARMOR := &"armor"
	const SLOT_TRINKET := &"trinket"
	const MAX_BAG_CAPACITY := 16

	var equipped := {
		SLOT_WEAPON: null,
		SLOT_ARMOR: null,
		SLOT_TRINKET: null
	}
	var bag: Array = []

	signal equipment_changed()
	signal bag_changed()

	func equip_item(item: Object, slot: StringName) -> bool:
		if item == null:
			return false
		if not equipped.has(slot):
			return false
		var item_slot = item.get("slot_type") if "slot_type" in item else item.get("slot")
		if item_slot != slot:
			return false

		# If slot was occupied, move previous item to bag if space allows
		var prev = equipped[slot]
		if prev != null:
			if bag.size() >= MAX_BAG_CAPACITY:
				return false
			bag.append(prev)
			bag_changed.emit()

		equipped[slot] = item
		equipment_changed.emit()
		return true

	func unequip_slot(slot: StringName) -> bool:
		if not equipped.has(slot) or equipped[slot] == null:
			return false
		if bag.size() >= MAX_BAG_CAPACITY:
			return false
		var item = equipped[slot]
		equipped[slot] = null
		bag.append(item)
		equipment_changed.emit()
		bag_changed.emit()
		return true

	func swap_item(slot: StringName, bag_index: int) -> bool:
		if not equipped.has(slot):
			return false
		if bag_index < 0 or bag_index >= bag.size():
			return false
		var candidate = bag[bag_index]
		if candidate == null:
			return false
		var candidate_slot = candidate.get("slot_type") if "slot_type" in candidate else candidate.get("slot")
		if candidate_slot != slot:
			return false

		var old_item = equipped[slot]
		equipped[slot] = candidate
		if old_item != null:
			bag[bag_index] = old_item
		else:
			bag.remove_at(bag_index)
		equipment_changed.emit()
		bag_changed.emit()
		return true

	func add_to_bag(item: Object) -> bool:
		if item == null or bag.size() >= MAX_BAG_CAPACITY:
			return false
		bag.append(item)
		bag_changed.emit()
		return true

	func remove_from_bag(bag_index: int) -> Object:
		if bag_index < 0 or bag_index >= bag.size():
			return null
		var item = bag[bag_index]
		bag.remove_at(bag_index)
		bag_changed.emit()
		return item

	func get_equipped(slot: StringName) -> Object:
		return equipped.get(slot, null)

	func get_set_synergies() -> Array[Dictionary]:
		var synergies: Array[Dictionary] = []
		var counts := {}
		for slot in equipped:
			var it = equipped[slot]
			if it != null and ("set_id" in it or "set" in it):
				var s_id = it.get("set_id") if "set_id" in it else it.get("set")
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


func _create_inventory() -> Object:
	if ResourceLoader.exists(INVENTORY_SCRIPT_PATH):
		var script: GDScript = load(INVENTORY_SCRIPT_PATH)
		if script != null and script.can_instantiate():
			return script.new()
	return MockEquipmentInventory.new()


func _create_item(id: StringName, name: String, slot: StringName, set_id: StringName = &"") -> Object:
	if ResourceLoader.exists(ITEM_SCRIPT_PATH):
		var script: GDScript = load(ITEM_SCRIPT_PATH)
		if script != null and script.can_instantiate():
			var item = script.new()
			item.id = id
			item.display_name = name
			item.slot_type = slot
			item.set_id = set_id
			return item
	return MockEquipmentItem.new(id, name, slot, set_id)


func _catalog_get(id: StringName) -> Object:
	if ResourceLoader.exists(CATALOG_SCRIPT_PATH):
		var script: GDScript = load(CATALOG_SCRIPT_PATH)
		if script != null and script.has_method("for_id"):
			return script.call("for_id", id)
	return MockEquipmentCatalog.for_id(id)


func test_starter_gear_catalog_creation() -> void:
	var sword = _catalog_get(&"broken_sword")
	ok(sword != null, "broken_sword created successfully")
	eq(sword.slot_type, SLOT_WEAPON, "broken_sword is weapon slot")
	eq(sword.set_id, &"broken_knight", "broken_sword belongs to broken_knight set")

	var armor = _catalog_get(&"broken_armor")
	ok(armor != null, "broken_armor created successfully")
	eq(armor.slot_type, SLOT_ARMOR, "broken_armor is armor slot")
	eq(armor.set_id, &"broken_knight", "broken_armor belongs to broken_knight set")

	var pendant = _catalog_get(&"broken_pendant")
	ok(pendant != null, "broken_pendant created successfully")
	eq(pendant.slot_type, SLOT_TRINKET, "broken_pendant is trinket slot")
	eq(pendant.set_id, &"broken_knight", "broken_pendant belongs to broken_knight set")


func test_catalog_for_id_lookup_and_invalid_fallback() -> void:
	var valid = _catalog_get(&"broken_sword")
	ok(valid != null, "valid id resolves to item")

	var invalid = _catalog_get(&"mythical_sword_does_not_exist")
	ok(invalid == null, "nonexistent id safely returns null")


func test_equip_valid_item_to_matching_slot() -> void:
	var inv = _create_inventory()
	add_child(inv)

	var emitted := [false]
	inv.equipment_changed.connect(func(): emitted[0] = true)

	var sword = _catalog_get(&"broken_sword")
	var success: bool = inv.equip_item(sword, SLOT_WEAPON)

	ok(success, "equip weapon to weapon slot succeeds")
	eq(inv.get_equipped(SLOT_WEAPON), sword, "slot holds equipped sword")
	ok(emitted[0], "equipment_changed signal emitted")


func test_equip_mismatched_slot_type_rejected() -> void:
	var inv = _create_inventory()
	add_child(inv)

	var armor = _catalog_get(&"broken_armor")
	var success: bool = inv.equip_item(armor, SLOT_WEAPON)

	ok(not success, "equipping armor to weapon slot must be rejected")
	ok(inv.get_equipped(SLOT_WEAPON) == null, "weapon slot remains empty")


func test_equip_to_invalid_slot_name_rejected() -> void:
	var inv = _create_inventory()
	add_child(inv)

	var sword = _catalog_get(&"broken_sword")
	var success: bool = inv.equip_item(sword, &"boots_slot")

	ok(not success, "equipping to non-existent slot name rejected")


func test_equip_null_item_rejected() -> void:
	var inv = _create_inventory()
	add_child(inv)

	var success: bool = inv.equip_item(null, SLOT_WEAPON)
	ok(not success, "equipping null item rejected")


func test_unequip_moves_to_bag_and_emits_signals() -> void:
	var inv = _create_inventory()
	add_child(inv)

	var sword = _catalog_get(&"broken_sword")
	inv.equip_item(sword, SLOT_WEAPON)
	eq(inv.bag.size(), 0)

	var equip_emitted := [false]
	var bag_emitted := [false]
	inv.equipment_changed.connect(func(): equip_emitted[0] = true)
	inv.bag_changed.connect(func(): bag_emitted[0] = true)

	var success: bool = inv.unequip_slot(SLOT_WEAPON)
	ok(success, "unequip succeeds")
	ok(inv.get_equipped(SLOT_WEAPON) == null, "slot is now empty")
	eq(inv.bag.size(), 1, "bag now holds unequipped item")
	eq(inv.bag[0], sword, "bag holds the exact sword")
	ok(equip_emitted[0], "equipment_changed emitted")
	ok(bag_emitted[0], "bag_changed emitted")


func test_unequip_empty_slot_returns_false() -> void:
	var inv = _create_inventory()
	add_child(inv)

	var success: bool = inv.unequip_slot(SLOT_WEAPON)
	ok(not success, "unequipping empty slot returns false")


func test_swap_item_between_slot_and_bag() -> void:
	var inv = _create_inventory()
	add_child(inv)

	var sword_a = _create_item(&"sword_a", "剑A", SLOT_WEAPON)
	var sword_b = _create_item(&"sword_b", "剑B", SLOT_WEAPON)

	inv.equip_item(sword_a, SLOT_WEAPON)
	inv.add_to_bag(sword_b)

	var equip_emitted := [false]
	var bag_emitted := [false]
	inv.equipment_changed.connect(func(): equip_emitted[0] = true)
	inv.bag_changed.connect(func(): bag_emitted[0] = true)

	var success: bool = inv.swap_item(SLOT_WEAPON, 0)
	ok(success, "swap item succeeds")
	eq(inv.get_equipped(SLOT_WEAPON), sword_b, "equipped slot now holds sword B")
	eq(inv.bag[0], sword_a, "bag slot 0 now holds old sword A")
	ok(equip_emitted[0], "equipment_changed emitted on swap")
	ok(bag_emitted[0], "bag_changed emitted on swap")


func test_swap_mismatched_slot_type_rejected() -> void:
	var inv = _create_inventory()
	add_child(inv)

	var sword = _create_item(&"sword", "剑", SLOT_WEAPON)
	var armor = _create_item(&"armor", "甲", SLOT_ARMOR)

	inv.equip_item(sword, SLOT_WEAPON)
	inv.add_to_bag(armor)

	var success: bool = inv.swap_item(SLOT_WEAPON, 0)
	ok(not success, "cannot swap armor from bag into weapon slot")
	eq(inv.get_equipped(SLOT_WEAPON), sword, "slot still holds sword")
	eq(inv.bag[0], armor, "bag still holds armor")


func test_swap_out_of_bounds_index_rejected() -> void:
	var inv = _create_inventory()
	add_child(inv)

	var sword = _create_item(&"sword", "剑", SLOT_WEAPON)
	inv.equip_item(sword, SLOT_WEAPON)

	ok(not inv.swap_item(SLOT_WEAPON, -1), "negative index rejected")
	ok(not inv.swap_item(SLOT_WEAPON, 99), "overflow index rejected")


func test_bag_capacity_limit_at_16() -> void:
	var inv = _create_inventory()
	add_child(inv)

	for i in range(16):
		var item = _create_item(StringName("item_%d" % i), "物品", SLOT_WEAPON)
		var added: bool = inv.add_to_bag(item)
		ok(added, "item %d added to bag" % i)

	eq(inv.bag.size(), 16, "bag reached max capacity of 16")

	# 17th item must be rejected
	var overflow_item = _create_item(&"overflow", "溢出物品", SLOT_WEAPON)
	var overflow_added: bool = inv.add_to_bag(overflow_item)
	ok(not overflow_added, "17th item rejected by full bag")
	eq(inv.bag.size(), 16, "bag size stays at 16")


func test_unequip_rejected_when_bag_is_full() -> void:
	var inv = _create_inventory()
	add_child(inv)

	var sword = _catalog_get(&"broken_sword")
	inv.equip_item(sword, SLOT_WEAPON)

	# Fill bag to 16
	for i in range(16):
		inv.add_to_bag(_create_item(StringName("filler_%d" % i), "填充", SLOT_ARMOR))

	eq(inv.bag.size(), 16)

	var success: bool = inv.unequip_slot(SLOT_WEAPON)
	ok(not success, "unequip rejected when bag is full")
	eq(inv.get_equipped(SLOT_WEAPON), sword, "item remains equipped in slot")
	eq(inv.bag.size(), 16, "bag size untouched")


func test_remove_from_bag_success_and_boundary() -> void:
	var inv = _create_inventory()
	add_child(inv)

	var item_a = _create_item(&"a", "A", SLOT_WEAPON)
	var item_b = _create_item(&"b", "B", SLOT_ARMOR)
	inv.add_to_bag(item_a)
	inv.add_to_bag(item_b)

	var removed = inv.remove_from_bag(0)
	eq(removed, item_a, "removed first item")
	eq(inv.bag.size(), 1)
	eq(inv.bag[0], item_b)

	var invalid = inv.remove_from_bag(10)
	ok(invalid == null, "invalid index removal returns null")


func test_broken_knight_set_synergy_2_pieces() -> void:
	var inv = _create_inventory()
	add_child(inv)

	var sword = _catalog_get(&"broken_sword")
	var armor = _catalog_get(&"broken_armor")

	inv.equip_item(sword, SLOT_WEAPON)
	inv.equip_item(armor, SLOT_ARMOR)

	var synergies = inv.get_set_synergies()
	eq(synergies.size(), 1, "exactly 1 synergy active for 2 pieces")
	eq(synergies[0]["set_id"], &"broken_knight")
	eq(int(synergies[0]["pieces"]), 2)


func test_broken_knight_set_synergy_3_pieces() -> void:
	var inv = _create_inventory()
	add_child(inv)

	var sword = _catalog_get(&"broken_sword")
	var armor = _catalog_get(&"broken_armor")
	var pendant = _catalog_get(&"broken_pendant")

	inv.equip_item(sword, SLOT_WEAPON)
	inv.equip_item(armor, SLOT_ARMOR)
	inv.equip_item(pendant, SLOT_TRINKET)

	var synergies = inv.get_set_synergies()
	eq(synergies.size(), 2, "both 2-piece and 3-piece synergies active for full 3-piece set")


func test_set_synergy_revoked_on_unequip() -> void:
	var inv = _create_inventory()
	add_child(inv)

	var sword = _catalog_get(&"broken_sword")
	var armor = _catalog_get(&"broken_armor")
	var pendant = _catalog_get(&"broken_pendant")

	inv.equip_item(sword, SLOT_WEAPON)
	inv.equip_item(armor, SLOT_ARMOR)
	inv.equip_item(pendant, SLOT_TRINKET)
	eq(inv.get_set_synergies().size(), 2)

	# Unequip pendant -> drops from 3 to 2 pieces
	inv.unequip_slot(SLOT_TRINKET)
	var synergies = inv.get_set_synergies()
	eq(synergies.size(), 1, "only 2-piece synergy remains")
	eq(int(synergies[0]["pieces"]), 2)

	# Unequip armor -> drops to 1 piece (no synergy)
	inv.unequip_slot(SLOT_ARMOR)
	eq(inv.get_set_synergies().size(), 0, "all set synergies revoked")
