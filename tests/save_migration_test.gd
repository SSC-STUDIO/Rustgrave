extends TestCase
## Save v3: v1（10 章旧档）与 v2（profile 块）都必须能直接继续；v3 新增的
## 余烬阶位/经验/属性点/技能槽/皮肤槽缺省时用默认值补齐，写入后能原样读回；
## persist_profile 只动 profile，不碰战役进度。

const PATH := "user://test_save_migration.cfg"


func setup() -> void:
	SaveData.save_path = PATH
	SaveData.delete_save()
	SaveData.flags.clear()


func teardown() -> void:
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	SaveData.flags.clear()


func _write_v1_save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 1)
	cfg.set_value("meta", "scene", GameContext.LEGACY_LEVELS["level03"])
	cfg.set_value("meta", "saved_at", "2026-10-17 12:00:00")
	cfg.set_value("player", "hp", 3)
	cfg.set_value("player", "max_hp", 5)
	cfg.set_value("player", "toxin", 12.0)
	cfg.set_value("player", "max_toxin", 100.0)
	cfg.set_value("player", "pos_x", 640.0)
	cfg.set_value("player", "pos_y", 300.0)
	cfg.set_value("player", "facing", -1)
	cfg.set_value("player", "pouch", ["ember_core"])
	cfg.set_value("player", "sockets", ["heat_forge"])
	cfg.set_value("equipment", "weapon", "iron_blade")
	cfg.set_value("equipment", "armor", "broken_armor")
	cfg.set_value("equipment", "trinket", "broken_pendant")
	cfg.set_value("equipment", "bag", ["rust_ring"])
	cfg.set_value("story", "flags", ["wake", "level02_done"])
	cfg.set_value("meta", "ending", "")
	cfg.set_value("consumed", "paths", ["level03:Props/Loot"])
	cfg.set_value("lit_nests", "paths", ["level03:Props/EmberNestStart"])
	cfg.set_value("atmosphere", "time_of_day", 0.35)
	cfg.set_value("atmosphere", "weather", "rain")
	cfg.set_value("atmosphere", "zone", "outdoors")
	cfg.set_value("atmosphere", "wind_heading", -1.0)
	eq(cfg.save(PATH), OK, "v1 save fixture written")


func test_save_version_is_three() -> void:
	eq(SaveData.SAVE_VERSION, 3, "save schema bumped for the v3 character profile")


func test_v1_save_loads_with_default_profile_and_keeps_every_old_field() -> void:
	_write_v1_save()
	ok(SaveData.load_game(), "v1 save loads")
	eq(int((SaveData.data["meta"] as Dictionary)["version"]), 1, "old version is reported, not rewritten")
	eq(SaveData.saved_scene(), GameContext.LEGACY_LEVELS["level03"], "old scene survives")
	eq(SaveData.character_id, "", "missing profile block -> empty character id (default character)")
	eq(SaveData.extras.size(), 0, "missing extras -> empty")
	eq(SaveData.ember_rank, 1, "missing rank -> rank 1")
	eq(SaveData.ember_xp, 0, "missing xp -> 0")
	eq(SaveData.attribute_points, 0, "missing attribute points -> 0")
	eq(SaveData.skill_1, "", "missing skill slots -> empty")
	eq(SaveData.skin_id, "", "missing skin -> default look")
	eq(SaveData.skin_rune, "", "missing skin rune -> none")
	ok(SaveData.has_flag("wake") and SaveData.has_flag("level02_done"), "story flags survive")
	eq(SaveData.flags.size(), 2)
	var player: Dictionary = SaveData.data["player"]
	eq(int(player["hp"]), 3)
	eq((player["pos"] as Vector2), Vector2(640, 300))
	eq((player["sockets"] as Array).size(), 1)
	var equipment: Dictionary = SaveData.data["equipment"]
	eq(String(equipment["weapon"]), "iron_blade", "equipped weapon survives migration")
	eq(String(equipment["trinket"]), "broken_pendant")
	eq((equipment["bag"] as Array).size(), 1)
	eq(SaveData.consumed.size(), 1)
	eq(SaveData.lit_nests.size(), 1)


func test_profile_round_trips_and_unknown_extras_survive() -> void:
	_write_v1_save()
	ok(SaveData.load_game())
	SaveData.set_character("gothic_hero")
	SaveData.set_extra("unlocked_characters", ["gothic_hero", "cemetery_hero"])
	SaveData.set_extra("unlocked_weapons", ["iron_blade"])
	SaveData.set_extra("future_key", {"nested": true})
	ok(SaveData.persist_profile(), "profile flushes onto the existing save")
	# 新进程式重载：清内存再读。
	SaveData.character_id = ""
	SaveData.extras.clear()
	ok(SaveData.load_game())
	eq(SaveData.character_id, "gothic_hero", "character id round-trips")
	eq(SaveData.get_extra("unlocked_characters", []), ["gothic_hero", "cemetery_hero"])
	eq(SaveData.get_extra("unlocked_weapons", []), ["iron_blade"])
	var future: Variant = SaveData.get_extra("future_key", null)
	ok(future is Dictionary and bool((future as Dictionary).get("nested", false)),
			"unknown extras keys are preserved verbatim")
	ok(SaveData.has_flag("wake"), "persist_profile does not touch story flags")


func test_v2_save_gets_v3_defaults_without_losing_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", 2)
	cfg.set_value("player", "hp", 4)
	cfg.set_value("player", "max_hp", 5)
	cfg.set_value("profile", "character_id", "gothic_hero")
	cfg.set_value("profile", "extras", {"future_key": 7})
	eq(cfg.save(PATH), OK)
	ok(SaveData.load_game())
	eq(int((SaveData.data["meta"] as Dictionary)["version"]), 2, "v2 version is reported")
	eq(SaveData.character_id, "gothic_hero", "v2 profile block survives")
	eq(SaveData.get_extra("future_key", null), 7)
	eq(SaveData.ember_rank, 1, "v2 save gets v3 rank default")
	eq(SaveData.skill_1, "", "v2 save gets v3 skill default")


func test_v3_progression_and_appearance_round_trip() -> void:
	_write_v1_save()
	ok(SaveData.load_game())
	SaveData.set_ember_state(4, 812, 3)
	SaveData.set_skill_slot(0, "ember_burst")
	SaveData.set_skill_slot(1, "hollow_guard")
	SaveData.set_skin("skin_ash_runner", "rune_ember_grip")
	ok(SaveData.persist_profile())
	SaveData.ember_rank = 1
	SaveData.ember_xp = 0
	SaveData.attribute_points = 0
	SaveData.skill_1 = ""
	SaveData.skill_2 = ""
	SaveData.skin_id = ""
	SaveData.skin_rune = ""
	ok(SaveData.load_game())
	eq(SaveData.ember_rank, 4)
	eq(SaveData.ember_xp, 812)
	eq(SaveData.attribute_points, 3)
	eq(SaveData.skill_1, "ember_burst")
	eq(SaveData.skill_2, "hollow_guard")
	eq(SaveData.skin_id, "skin_ash_runner")
	eq(SaveData.skin_rune, "rune_ember_grip")
	eq(int((SaveData.data["profile"] as Dictionary).get("ember_rank", 0)), 4,
			"内存里的 profile 快照同步")
	ok(SaveData.has_flag("wake"), "profile writes do not touch story flags")


func test_persist_profile_is_noop_without_a_save() -> void:
	SaveData.delete_save()
	SaveData.set_character("gothic_hero")
	ok(not SaveData.persist_profile(), "no save yet -> nothing written")
	ok(not SaveData.has_save(), "still no save on disk")
	SaveData.set_character("")
