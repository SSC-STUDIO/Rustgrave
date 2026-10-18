extends TestCase
## 角色/武器接应契约：roster 缺失时 LoadoutBridge 必须安全回退，奖励位不能死锁。
## roster 由外部 agent 提供；测试对"存在/不存在"两种状态都成立（feature-detect）。

const PATH := "user://test_loadout_bridge.cfg"


func setup() -> void:
	SaveData.save_path = PATH
	SaveData.delete_save()
	SaveData.flags.clear()


func teardown() -> void:
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	SaveData.flags.clear()


func test_bridge_reports_roster_availability_without_crashing() -> void:
	var has_character_roster := ResourceLoader.exists(LoadoutBridge.CHARACTER_ROSTER_PATH)
	var has_weapon_roster := ResourceLoader.exists(LoadoutBridge.WEAPON_ROSTER_PATH)
	if not has_character_roster:
		ok(not LoadoutBridge.character_available(), "no roster file -> character system unavailable")
	if not has_weapon_roster:
		ok(not LoadoutBridge.weapon_available(), "no roster file -> weapon system unavailable")
	# 即使 roster 存在，读取也必须安全返回字符串/字典而不是崩。
	ok(LoadoutBridge.display_character() is String)
	ok(LoadoutBridge.display_weapon(null) is String)
	ok(LoadoutBridge.loadout_line(null) is String)


func test_missing_roster_keeps_single_character_defaults() -> void:
	if LoadoutBridge.character_available():
		ok(true, "roster present; fallback branch not applicable")
		return
	eq(LoadoutBridge.default_character_id(), &"", "no roster -> no default character id")
	eq(LoadoutBridge.character_id(), &"", "current character falls back to the campaign knight")
	eq(LoadoutBridge.display_character(), "", "no display name to show")
	eq(LoadoutBridge.weapon_def(&"iron_blade"), {}, "no weapon roster -> empty definition")
	loadout_reward_refuses_without_roster()


func loadout_reward_refuses_without_roster() -> void:
	ok(not LoadoutBridge.grant("character", "gothic_hero", null), "character reward refused without roster")
	ok(not LoadoutBridge.grant("weapon", "iron_blade", null), "weapon reward refused without roster")
	eq(SaveData.get_extra(LoadoutBridge.EXTRAS_CHARACTERS, []), [], "no unlock written on refusal")
	eq(SaveData.get_extra(LoadoutBridge.EXTRAS_WEAPONS, []), [], "no weapon unlock written on refusal")


func test_unknown_reward_kind_never_writes_profile() -> void:
	ok(not LoadoutBridge.grant("mystery", "thing", null), "unknown kind is refused")
	eq(SaveData.character_id, "", "profile untouched")
	eq(SaveData.extras.size(), 0, "extras untouched")
