class_name M2AdversarialStressTest
extends TestCase
## Adversarial Stress Test Suite for Milestone 2:
## Slot & Inventory Boundaries, Negative/OOB Index Safety, Full-Bag Rejection,
## Cross-Slot Interception, and Null Safety.

const INVENTORY_SCRIPT := preload("res://scripts/player/equipment_inventory.gd")
const ITEM_SCRIPT := preload("res://scripts/data/equipment_item.gd")
const CATALOG_SCRIPT := preload("res://scripts/data/equipment_catalog.gd")
const PLAYER_SCENE := preload("res://scenes/player/Player.tscn")

const SLOT_WEAPON := &"weapon"
const SLOT_ARMOR := &"armor"
const SLOT_TRINKET := &"trinket"


func _create_test_item(id: StringName, slot: StringName, set_id: StringName = &"") -> EquipmentItem:
	var item := EquipmentItem.new()
	item.id = id
	item.display_name = String(id)
	item.slot_type = slot
	item.set_id = set_id
	return item


## Stress Test 1: Unequip operations when bag is full (16 items)
## Must be rejected and equipped state strictly preserved.
func test_stress_unequip_when_bag_full() -> void:
	var inv: EquipmentInventory = INVENTORY_SCRIPT.new()
	add_child(inv)

	var sword := _create_test_item(&"stress_sword", SLOT_WEAPON)
	var armor := _create_test_item(&"stress_armor", SLOT_ARMOR)
	var trinket := _create_test_item(&"stress_trinket", SLOT_TRINKET)

	ok(inv.equip_item(sword, SLOT_WEAPON), "equip weapon")
	ok(inv.equip_item(armor, SLOT_ARMOR), "equip armor")
	ok(inv.equip_item(trinket, SLOT_TRINKET), "equip trinket")

	# Fill bag to exact maximum capacity (16 items)
	for i in range(16):
		var filler := _create_test_item(StringName("filler_%d" % i), SLOT_WEAPON)
		var added: bool = inv.add_to_bag(filler)
		ok(added, "filler item %d added to bag" % i)

	eq(inv.bag.size(), 16, "bag is at full capacity (16)")

	# Track signals to ensure no false notifications on rejected operations
	var equip_changed_count := 0
	var bag_changed_count := 0
	inv.equipment_changed.connect(func(): equip_changed_count += 1)
	inv.bag_changed.connect(func(): bag_changed_count += 1)

	# 1. Attempt unequip weapon when bag is full
	var unequip_weapon_res: bool = inv.unequip_slot(SLOT_WEAPON)
	ok(not unequip_weapon_res, "unequip weapon must be rejected when bag is full")
	eq(inv.get_equipped(SLOT_WEAPON), sword, "weapon remains equipped")
	eq(inv.bag.size(), 16, "bag size remains 16")

	# 2. Attempt unequip armor when bag is full
	var unequip_armor_res: bool = inv.unequip_slot(SLOT_ARMOR)
	ok(not unequip_armor_res, "unequip armor must be rejected when bag is full")
	eq(inv.get_equipped(SLOT_ARMOR), armor, "armor remains equipped")
	eq(inv.bag.size(), 16, "bag size remains 16")

	# 3. Attempt unequip trinket when bag is full
	var unequip_trinket_res: bool = inv.unequip_slot(SLOT_TRINKET)
	ok(not unequip_trinket_res, "unequip trinket must be rejected when bag is full")
	eq(inv.get_equipped(SLOT_TRINKET), trinket, "trinket remains equipped")
	eq(inv.bag.size(), 16, "bag size remains 16")

	# 4. Attempt to equip a replacement weapon while slot is occupied and bag is full
	var new_sword := _create_test_item(&"new_sword", SLOT_WEAPON)
	var equip_replacement_res: bool = inv.equip_item(new_sword, SLOT_WEAPON)
	ok(not equip_replacement_res, "equipping replacement into occupied slot must fail when bag cannot hold displaced item")
	eq(inv.get_equipped(SLOT_WEAPON), sword, "original sword remains safely equipped")
	eq(inv.bag.size(), 16, "bag size remains 16")

	eq(equip_changed_count, 0, "no equipment_changed signals emitted during rejected unequip/replace")
	eq(bag_changed_count, 0, "no bag_changed signals emitted during rejected unequip/replace")

	# 5. Free 1 bag slot (size = 15) and verify unequip now succeeds exactly once
	var removed_filler = inv.remove_from_bag(0)
	ok(removed_filler != null, "successfully removed 1 item from bag")
	eq(inv.bag.size(), 15, "bag now has 1 slot available")

	var unequip_weapon_now: bool = inv.unequip_slot(SLOT_WEAPON)
	ok(unequip_weapon_now, "unequipping weapon succeeds now that bag has space")
	ok(inv.get_equipped(SLOT_WEAPON) == null, "weapon slot is now empty")
	eq(inv.bag.size(), 16, "bag is full again (16)")

	# Subsequent unequip of armor must be rejected again because bag is full again
	var unequip_armor_again: bool = inv.unequip_slot(SLOT_ARMOR)
	ok(not unequip_armor_again, "unequip armor must be rejected again as bag is full")
	eq(inv.get_equipped(SLOT_ARMOR), armor, "armor remains equipped")


## Stress Test 2: Cross-slot equipment attempts
## Putting incompatible item types into slots must be strictly rejected.
func test_stress_cross_slot_equipment() -> void:
	var inv: EquipmentInventory = INVENTORY_SCRIPT.new()
	add_child(inv)

	var weapon := _create_test_item(&"blade", SLOT_WEAPON)
	var armor := _create_test_item(&"cuirass", SLOT_ARMOR)
	var trinket := _create_test_item(&"ring", SLOT_TRINKET)

	# Direct cross-slot equips
	ok(not inv.equip_item(armor, SLOT_WEAPON), "reject armor into weapon slot")
	ok(not inv.equip_item(trinket, SLOT_WEAPON), "reject trinket into weapon slot")
	ok(not inv.equip_item(weapon, SLOT_ARMOR), "reject weapon into armor slot")
	ok(not inv.equip_item(trinket, SLOT_ARMOR), "reject trinket into armor slot")
	ok(not inv.equip_item(weapon, SLOT_TRINKET), "reject weapon into trinket slot")
	ok(not inv.equip_item(armor, SLOT_TRINKET), "reject armor into trinket slot")

	# Nonexistent slot names
	ok(not inv.equip_item(weapon, &"helmet"), "reject weapon into helmet slot")
	ok(not inv.equip_item(armor, &"boots"), "reject armor into boots slot")
	ok(not inv.equip_item(trinket, &""), "reject trinket into empty slot name")
	ok(not inv.equip_item(weapon, &"unknown_slot_xyz"), "reject arbitrary slot name")

	# Cross-slot swap attempts
	ok(inv.equip_item(weapon, SLOT_WEAPON), "equip weapon")
	ok(inv.add_to_bag(armor), "add armor to bag")
	ok(inv.add_to_bag(trinket), "add trinket to bag")

	# Bag index 0 is armor, index 1 is trinket
	ok(not inv.swap_item(SLOT_WEAPON, 0), "reject swapping armor from bag into weapon slot")
	eq(inv.get_equipped(SLOT_WEAPON), weapon, "weapon slot unchanged after failed swap")
	eq(inv.bag[0], armor, "bag slot 0 unchanged after failed swap")

	ok(not inv.swap_item(SLOT_WEAPON, 1), "reject swapping trinket from bag into weapon slot")
	eq(inv.get_equipped(SLOT_WEAPON), weapon, "weapon slot unchanged")
	eq(inv.bag[1], trinket, "bag slot 1 unchanged")

	# Cross-slot equip by string ID
	ok(not inv.equip_item(&"broken_armor", SLOT_WEAPON), "reject broken_armor ID into weapon slot")
	ok(not inv.equip_item(&"broken_sword", SLOT_ARMOR), "reject broken_sword ID into armor slot")
	ok(not inv.equip_item(&"broken_pendant", SLOT_WEAPON), "reject broken_pendant ID into weapon slot")


## Stress Test 3: Swapping items at negative or out-of-bound bag indices
## Must safely fail without crash or state mutation.
func test_stress_swap_out_of_bounds_and_negative_indices() -> void:
	var inv: EquipmentInventory = INVENTORY_SCRIPT.new()
	add_child(inv)

	var weapon := _create_test_item(&"w1", SLOT_WEAPON)
	inv.equip_item(weapon, SLOT_WEAPON)

	# 1. Swapping on empty bag
	eq(inv.bag.size(), 0)
	ok(not inv.swap_item(SLOT_WEAPON, 0), "empty bag swap at index 0 returns false")
	ok(not inv.swap_item(SLOT_WEAPON, -1), "empty bag swap at index -1 returns false")
	ok(not inv.swap_item(SLOT_WEAPON, 1), "empty bag swap at index 1 returns false")
	ok(not inv.swap_item(SLOT_WEAPON, 9999), "empty bag swap at large index returns false")
	ok(not inv.swap_item(SLOT_WEAPON, -9999), "empty bag swap at large negative index returns false")

	# 2. Add 2 items to bag
	var w2 := _create_test_item(&"w2", SLOT_WEAPON)
	var w3 := _create_test_item(&"w3", SLOT_WEAPON)
	inv.add_to_bag(w2)
	inv.add_to_bag(w3)
	eq(inv.bag.size(), 2)

	# Test extreme out of bounds and negative boundaries
	var oob_indices := [-100000, -100, -2, -1, 2, 3, 10, 100, 999999]
	for idx in oob_indices:
		ok(not inv.swap_item(SLOT_WEAPON, idx), "swap at index %d safely rejected" % idx)
		var removed_val = inv.remove_from_bag(idx)
		ok(removed_val == null, "remove_from_bag at index %d safely returns null" % idx)

	# Verify state was not mutated by invalid swap attempts
	eq(inv.get_equipped(SLOT_WEAPON), weapon, "equipped weapon remains intact")
	eq(inv.bag.size(), 2, "bag size remains 2")
	eq(inv.bag[0], w2, "bag[0] untouched")
	eq(inv.bag[1], w3, "bag[1] untouched")

	# 3. Swap with invalid slot name
	ok(not inv.swap_item(&"invalid_slot", 0), "swap with invalid slot returns false")
	ok(not inv.swap_item(&"", 0), "swap with empty slot name returns false")

	# 4. Valid swap succeeds
	ok(inv.swap_item(SLOT_WEAPON, 0), "valid swap succeeds")
	eq(inv.get_equipped(SLOT_WEAPON), w2, "equipped is now w2")
	eq(inv.bag[0], weapon, "bag[0] is now old weapon")


## Stress Test 4: Null item handling in equip_item and add_to_bag
## Must safely return false without engine error or crash.
func test_stress_null_and_corrupted_items() -> void:
	var inv: EquipmentInventory = INVENTORY_SCRIPT.new()
	add_child(inv)

	# equip_item with null
	ok(not inv.equip_item(null, SLOT_WEAPON), "equip_item(null, weapon) safely returns false")
	ok(not inv.equip_item(null, SLOT_ARMOR), "equip_item(null, armor) safely returns false")
	ok(not inv.equip_item(null, SLOT_TRINKET), "equip_item(null, trinket) safely returns false")
	ok(not inv.equip_item(null, &""), "equip_item(null, empty) safely returns false")
	ok(not inv.equip_item(null, &"unknown"), "equip_item(null, unknown) safely returns false")

	# equip_item with invalid strings
	ok(not inv.equip_item("", SLOT_WEAPON), "equip_item('', weapon) safely returns false")
	ok(not inv.equip_item("   ", SLOT_WEAPON), "equip_item('   ', weapon) safely returns false")
	ok(not inv.equip_item(&"totally_fake_item_id_404", SLOT_WEAPON), "equip_item(fake_id, weapon) safely returns false")

	# add_to_bag with null
	ok(not inv.add_to_bag(null), "add_to_bag(null) safely returns false")
	ok(not inv.add_to_bag(""), "add_to_bag('') safely returns false")
	ok(not inv.add_to_bag("   "), "add_to_bag('   ') safely returns false")
	ok(not inv.add_to_bag(&"totally_fake_item_id_404"), "add_to_bag(fake_id) safely returns false")

	# Verify inventory is completely empty and uncorrupted
	eq(inv.bag.size(), 0, "bag remains completely empty")
	ok(inv.get_equipped(SLOT_WEAPON) == null, "weapon slot remains null")
	ok(inv.get_equipped(SLOT_ARMOR) == null, "armor slot remains null")
	ok(inv.get_equipped(SLOT_TRINKET) == null, "trinket slot remains null")
	ok(inv.is_completely_unequipped(), "is_completely_unequipped is true")


## Stress Test 5: Live Player and Stats node resilience under adversarial inputs
## Verifies that invalid equipment attempts never corrupt CharacterStats.
func test_stress_player_stats_resilience_under_adversarial_inputs() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	add_child(player)
	await flush(2)

	var inv: EquipmentInventory = player.equipment
	var stats: CharacterStats = player.stats

	ok(inv != null, "player has EquipmentInventory")
	ok(stats != null, "player has CharacterStats")

	var initial_atk := stats.get_attack_bonus()
	var initial_def := stats.get_defense_reduction()
	var initial_hp_bonus := stats.get_max_hp_bonus()

	# Fire barrage of illegal calls on player inventory
	for i in range(20):
		inv.equip_item(null, SLOT_WEAPON)
		inv.equip_item(&"bogus_item", SLOT_ARMOR)
		inv.equip_item(null, &"fake_slot")
		inv.unequip_slot(&"fake_slot")
		inv.swap_item(SLOT_WEAPON, -1)
		inv.swap_item(SLOT_WEAPON, 999)
		inv.add_to_bag(null)
		inv.remove_from_bag(-5)
		inv.remove_from_bag(50)

	# Verify stats did not change or desync
	eq(stats.get_attack_bonus(), initial_atk, "attack bonus unchanged after illegal barrage")
	eq(stats.get_defense_reduction(), initial_def, "defense reduction unchanged after illegal barrage")
	eq(stats.get_max_hp_bonus(), initial_hp_bonus, "max hp bonus unchanged after illegal barrage")

	# Now perform legitimate equip and verify stats update cleanly
	var sword: EquipmentItem = CATALOG_SCRIPT.broken_sword()
	ok(inv.equip_item(sword, SLOT_WEAPON), "equip legitimate broken sword")
	eq(stats.get_attack_bonus(), initial_atk + sword.attack, "stats recalculated correctly on legitimate equip")

	player.queue_free()


## Stress Test 6: Deterministic fuzzing sequence
## Performs 100 randomized actions and verifies system invariants hold after every action.
func test_stress_fuzzing_invariant_checker() -> void:
	var inv: EquipmentInventory = INVENTORY_SCRIPT.new()
	add_child(inv)

	var items: Array[EquipmentItem] = [
		_create_test_item(&"fuzz_w1", SLOT_WEAPON),
		_create_test_item(&"fuzz_w2", SLOT_WEAPON),
		_create_test_item(&"fuzz_a1", SLOT_ARMOR),
		_create_test_item(&"fuzz_a2", SLOT_ARMOR),
		_create_test_item(&"fuzz_t1", SLOT_TRINKET),
		_create_test_item(&"fuzz_t2", SLOT_TRINKET)
	]

	# Pseudo-random seed for determinism
	var seed_val: int = 42

	for step in range(100):
		seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
		var action_type := seed_val % 6
		var item_idx := (seed_val / 6) % items.size()
		var slot_idx := (seed_val / 36) % 3
		var slot_name: StringName = [SLOT_WEAPON, SLOT_ARMOR, SLOT_TRINKET][slot_idx]
		var item := items[item_idx]

		match action_type:
			0: # Equip item
				inv.equip_item(item, slot_name)
			1: # Unequip slot
				inv.unequip_slot(slot_name)
			2: # Add to bag
				inv.add_to_bag(item)
			3: # Swap item with bag index (could be valid or OOB)
				var bag_idx := (seed_val % 25) - 4 # range [-4, 20]
				inv.swap_item(slot_name, bag_idx)
			4: # Remove from bag (could be valid or OOB)
				var bag_idx := (seed_val % 25) - 4
				inv.remove_from_bag(bag_idx)
			5: # Illegal calls (nulls or invalid slot names)
				inv.equip_item(null, slot_name)
				inv.equip_item(item, &"bad_slot")
				inv.add_to_bag(null)

		# INVARIANT CHECKS:
		# 1. Bag capacity must never exceed 16
		ok(inv.bag.size() <= 16, "invariant: bag size %d <= 16 at step %d" % [inv.bag.size(), step])

		# 2. Slots must hold correct type or null
		for s in [SLOT_WEAPON, SLOT_ARMOR, SLOT_TRINKET]:
			var eq_item = inv.get_equipped(s)
			if eq_item != null:
				eq(eq_item.slot_type, s, "invariant: equipped item in %s matches slot type at step %d" % [s, step])

		# 3. Bag elements must all be non-null EquipmentItem
		for b_idx in range(inv.bag.size()):
			var b_item = inv.bag[b_idx]
			ok(b_item != null, "invariant: bag[%d] is not null at step %d" % [b_idx, step])
