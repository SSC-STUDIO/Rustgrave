extends TestCase
## Tester diagnostic: why do origin stat bonuses vanish after apply_player()?

const SaveDataScript := preload("res://scripts/autoload/save_data.gd")
const PLAYER := preload("res://scenes/player/Player.tscn")


func test_diagnose_origin_bonus_loss() -> void:
	var sd := SaveDataScript.new()
	add_child(sd)
	await get_tree().process_frame
	sd.data = {
		"player": {"hp": 6, "max_hp": 6, "origin": "ember_vanguard"},
		"equipment": {"weapon": "broken_sword", "armor": "broken_armor",
				"trinket": "broken_pendant", "bag": []}
	}
	var player: Node = PLAYER.instantiate()
	add_child(player)
	await flush(4)
	var stats = player.stats
	print("--- BEFORE apply_player ---")
	_dump(stats)
	sd.apply_player(player)
	print("--- AFTER apply_player ---")
	_dump(stats)
	# Now re-apply origin manually and see if it fixes it.
	stats.apply_origin(&"ember_vanguard")
	print("--- AFTER manual apply_origin ---")
	_dump(stats)
	player.queue_free()
	sd.queue_free()


func _dump(stats) -> void:
	print("origin_id=%s" % String(stats.get_origin_id()))
	print("max_hp_bonus=%d atk_bonus=%d def_reduction=%d" % [
			stats.get_max_hp_bonus(), stats.get_attack_bonus(), stats.get_defense_reduction()])
	print("effective_max_hp=%d" % stats.get_effective_max_hp())
	var mods: Dictionary = stats.get_origin_stat_modifiers()
	print("origin modifiers: %s" % str(mods))
