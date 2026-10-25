extends TestCase
## 辅助选项的默认值必须等于改动前的战斗：1.0 不改伤害、不改弹反、不改毒素。


func teardown() -> void:
	for key in [&"assist_incoming", &"assist_parry", &"assist_toxin", &"subtitle_speed", &"text_scale", &"vsync"]:
		Settings._extra.erase(key)
	Settings.using_gamepad = false


func test_defaults_leave_combat_alone() -> void:
	eq(float(Settings.value(&"assist_incoming", 1.0)), 1.0)
	eq(float(Settings.value(&"assist_parry", 1.0)), 1.0)
	eq(float(Settings.value(&"assist_toxin", 1.0)), 1.0)
	eq(float(Settings.value(&"subtitle_speed", 1.0)), 1.0)
	eq(float(Settings.value(&"text_scale", 1.0)), 1.0)
	var hp := Health.new()
	add_child(hp)
	hp.max_hp = 10
	hp.current = 10
	ok(hp.take_damage(3))
	eq(hp.current, 7, "a health node that is not the player ignores the assist scale")
	var melee := MeleeCombat.new()
	add_child(melee)
	Settings.set_value(&"assist_parry", 1.5, false)
	ok(not melee.is_parry_window(), "idle is never a parry, even with a wider window")


func test_gamepad_glyphs_follow_the_last_device() -> void:
	Settings.using_gamepad = false
	ok(KeyLabels.label(&"jump") != "A", "keyboard prompts stay on the bound key")
	Settings.using_gamepad = true
	eq(KeyLabels.label(&"jump"), "A")
	eq(KeyLabels.label(&"attack"), "X")
	eq(KeyLabels.label(&"world_map"), "Select")
	ok(InputMap.has_action(&"world_map"), "map hotkey is installed")
