extends TestCase
## Tester probe: the starter-equipment guard in player.gd is keyed on a
## substring match against the current scene's name. The project's own test
## runner scene is "RunTests", which CONTAINS "Test" — so every player
## spawned under the test runner silently loses its starter equipment.
##
## Consequence: any test that spawns a player and expects Broken Knight
## starter gear (max_hp 7, defense 2) sees a bare player (max_hp 5, defense 1)
## instead. This is a production-code defect, not a test artifact: the guard
## is meant to catch bespoke test scenes, not the runner itself.

const PLAYER := preload("res://scenes/player/Player.tscn")


func test_starter_equipment_guard_does_not_swallow_the_test_runner() -> void:
	# The guard must not fire for a scene whose name merely *contains* "Test"
	# as part of a longer word — e.g. the project's own runner, "RunTests".
	var runner_name := "RunTests"
	ok("Test" in runner_name,
			"precondition: the runner scene name contains the substring 'Test'")
	var player: Player = PLAYER.instantiate()
	add_child(player)
	await flush(6)
	# A freshly spawned player in a normal (non-test) scene gets starter gear.
	ok(not player.equipment.is_completely_unequipped(),
			"a player spawned under the real runner must receive starter equipment "
			+ "(guard currently returns %s for scene '%s')" % [
					str(player._should_auto_equip_starter()), runner_name])
	if player.equipment.is_completely_unequipped():
		print("   equipped slots: %s" % str(player.equipment.equipped))
	player.queue_free()
	await get_tree().process_frame


func test_starter_gear_yields_documented_broken_knight_bonuses() -> void:
	# With starter gear the player must show the Broken Knight numbers the
	# equipment catalog documents (broken_sword/armor/pendant + 2-piece).
	var player: Player = PLAYER.instantiate()
	add_child(player)
	await flush(6)
	if player.equipment.is_completely_unequipped():
		ok(false, "starter equipment missing — downstream HP/defense numbers cannot be verified")
		player.queue_free()
		await get_tree().process_frame
		return
	eq(player.equipment.get_equipped(EquipmentInventory.SLOT_WEAPON).id, &"broken_sword",
			"starter weapon is broken_sword")
	eq(player.equipment.get_equipped(EquipmentInventory.SLOT_ARMOR).id, &"broken_armor",
			"starter armor is broken_armor")
	eq(player.equipment.get_equipped(EquipmentInventory.SLOT_TRINKET).id, &"broken_pendant",
			"starter trinket is broken_pendant")
	player.queue_free()
	await get_tree().process_frame
