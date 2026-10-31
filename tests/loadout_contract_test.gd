extends TestCase
## 角色/武器接应契约（契约 §3.1/§3.3）——正向路径。
##
## 外部 roster 还没交付，所以这里用 tests/fixtures 的 roster 替身走一遍**存在**
## 的完整路径：ids/def/default_id/字段类型/显示名/存档 profile round-trip/
## extras 解锁表/未知 id 回退/奖励发放。真实 roster 到位后，feature-detect 分支
## 会验证真实文件；没有真实 roster 时本套测试照样全绿（fallback 由
## loadout_bridge_test.gd 覆盖）。
##
## 只读桥：不动 SaveData 语义、不写 scripts/data/、不动 HUD/暂停/标题。

const SAVE_PATH := "user://test_loadout_contract.cfg"
const CHARACTER_STUB := "res://tests/fixtures/character_roster_stub.gd"
const WEAPON_STUB := "res://tests/fixtures/weapon_roster_stub.gd"
const CHIP_PATH := "res://scripts/ui/loadout_chip.gd"
const CHARACTER_FIELDS: Array = [
	"display_name", "char_frames_id", "body_size", "hurt_size",
	"speed_mult", "max_hp_mod", "intro_line", "ability_set",
]
const WEAPON_FIELDS: Array = [
	"display_name", "slot", "moveset_id", "pickup_art", "desc", "unlocked_by",
]


func setup() -> void:
	SaveData.save_path = SAVE_PATH
	SaveData.delete_save()
	SaveData.flags.clear()
	LoadoutBridge.test_roster_override = []
	LoadoutBridge.reset_roster_cache()


func teardown() -> void:
	LoadoutBridge.test_roster_override = []
	LoadoutBridge.reset_roster_cache()
	SaveData.delete_save()
	SaveData.save_path = "user://rustgrave_save.cfg"
	SaveData.flags.clear()
	Director.abort()


func _use_stub_rosters() -> void:
	LoadoutBridge.test_roster_override = [load(CHARACTER_STUB), load(WEAPON_STUB)]
	LoadoutBridge.reset_roster_cache()


## ---------------------------------------------------------------- positive --

func test_stub_roster_positive_contract() -> void:
	_use_stub_rosters()
	ok(LoadoutBridge.available(), "stub rosters make the loadout system available")
	ok(LoadoutBridge.character_available(), "character roster is callable")
	ok(LoadoutBridge.weapon_available(), "weapon roster is callable")
	eq(LoadoutBridge.default_character_id(), &"knight", "default character comes from the roster")
	eq(LoadoutBridge.default_weapon_id(), &"iron_blade", "default weapon comes from the roster")
	var char_ids := LoadoutBridge.character_ids()
	ok(char_ids.size() >= 2, "roster exposes 2+ characters (%d)" % char_ids.size())
	ok(char_ids.has(&"knight") and char_ids.has(&"gothic_hero"), "known character ids are listed")
	var weapon_ids := LoadoutBridge.weapon_ids()
	ok(weapon_ids.size() >= 2, "roster exposes 2+ weapons (%d)" % weapon_ids.size())
	ok(weapon_ids.has(&"bell_hammer"), "known weapon ids are listed")
	for id in char_ids:
		var def := LoadoutBridge.character_def(id)
		ok(not def.is_empty(), "character %s has a definition" % id)
		for field in CHARACTER_FIELDS:
			ok(def.has(field), "character %s has field %s" % [id, field])
		ok(def.get("display_name") is String and String(def.get("display_name")) != "",
				"character %s has a display name" % id)
		ok(def.get("char_frames_id") is StringName, "character %s frames id is StringName" % id)
		ok(def.get("body_size") is Vector2, "character %s body_size is Vector2" % id)
		ok(def.get("hurt_size") is Vector2, "character %s hurt_size is Vector2" % id)
		ok(def.get("speed_mult") is float, "character %s speed_mult is float" % id)
		ok(def.get("max_hp_mod") is int, "character %s max_hp_mod is int" % id)
		ok(def.get("intro_line") is String, "character %s intro_line is String" % id)
		var abilities: Variant = def.get("ability_set")
		ok(abilities is Array, "character %s ability_set is an Array" % id)
		if abilities is Array:
			for ability in abilities:
				ok(ability is StringName, "character %s ability is StringName (%s)" % [id, str(ability)])
	for id in weapon_ids:
		var def := LoadoutBridge.weapon_def(id)
		ok(not def.is_empty(), "weapon %s has a definition" % id)
		for field in WEAPON_FIELDS:
			ok(def.has(field), "weapon %s has field %s" % [id, field])
		eq(def.get("slot"), &"weapon", "weapon %s targets the weapon slot" % id)
		ok(def.get("moveset_id") is StringName, "weapon %s moveset is StringName" % id)
		ok(def.get("pickup_art") is String, "weapon %s pickup art is a path" % id)
	eq(LoadoutBridge.character_id(), &"knight", "no save -> roster default character")
	eq(LoadoutBridge.display_character(), String(LoadoutBridge.character_def(&"knight")["display_name"]),
			"display name matches the roster")
	var knight_def := LoadoutBridge.character_def(&"knight")
	var hero_def := LoadoutBridge.character_def(&"gothic_hero")
	ok((knight_def.get("ability_set") as Array).is_empty(), "knight is the bare-ability baseline")
	ok((hero_def.get("ability_set") as Array).has(&"hookshot"), "gothic hero carries hookshot")
	ok(LoadoutBridge.loadout_line(null).contains(String(knight_def["display_name"])),
			"loadout line starts with the character name")
	eq(LoadoutBridge.weapon_id(null), &"", "no equipped weapon -> empty weapon id")
	eq(LoadoutBridge.weapon_def(&"iron_blade").get("display_name"), "锈铁长刃", "weapon display name")
	eq(LoadoutBridge.weapon_def(&"no_such_weapon"), {}, "unknown weapon id -> empty definition")


func test_unknown_ids_fall_back_without_crashing() -> void:
	_use_stub_rosters()
	SaveData.set_character("missing_hero")
	eq(LoadoutBridge.character_id(), &"knight", "unknown saved character falls back to the default")
	eq(LoadoutBridge.display_character(), "余烬骑士", "display name follows the fallback")
	eq(LoadoutBridge.character_def(&"missing_hero"), {}, "explicit unknown id stays honest (no fake def)")
	# 奖励文案靠这个空字典说“遗落的偶”，不会冒用默认角色名。
	eq(LoadoutBridge.weapon_def(&"missing_blade"), {}, "unknown weapon stays honest")
	eq(LoadoutBridge.display_weapon(null), "", "no equipment -> no weapon label")
	ok(not LoadoutBridge.grant("character", "missing_hero", null), "unknown character cannot be unlocked")
	ok(not LoadoutBridge.grant("weapon", "missing_blade", null), "unknown weapon cannot be unlocked")


## ------------------------------------------------------------ persistence --

func test_profile_round_trip_keeps_story_flags_and_extras() -> void:
	_use_stub_rosters()
	var arena := Node2D.new()
	arena.name = "ContractArena"
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)
	SaveData.mark_flag("story_bell_found")
	ok(SaveData.save_game(String(GameContext.LEVELS["stage03"]), player), "fixture save is written")
	SaveData.set_character("gothic_hero")
	SaveData.set_extra(LoadoutBridge.EXTRAS_CHARACTERS, ["gothic_hero"])
	SaveData.set_extra(LoadoutBridge.EXTRAS_WEAPONS, ["bell_hammer"])
	SaveData.set_extra("unknown_future_key", {"v": 7})
	ok(SaveData.persist_profile(), "profile flush lands on the existing save")
	ok(SaveData.load_game(), "save reloads")
	eq(SaveData.character_id, "gothic_hero", "character_id survives the round-trip")
	eq(SaveData.get_extra(LoadoutBridge.EXTRAS_CHARACTERS, []), ["gothic_hero"], "character extras survive")
	eq(SaveData.get_extra(LoadoutBridge.EXTRAS_WEAPONS, []), ["bell_hammer"], "weapon extras survive")
	eq(SaveData.get_extra("unknown_future_key", {}), {"v": 7}, "unknown extras keys are kept verbatim")
	ok(SaveData.has_flag("story_bell_found"), "story flags are not clobbered by a profile flush")
	eq(LoadoutBridge.character_id(), &"gothic_hero", "bridge reads the saved character")
	eq(LoadoutBridge.display_character(), "哥特骑手", "bridge displays the saved character")
	ok(LoadoutBridge.is_unlocked("character", "gothic_hero"), "saved character reads as unlocked")
	arena.free()
	await flush(1)


func test_grant_unlocks_real_roster_ids_once_and_persists() -> void:
	_use_stub_rosters()
	ok(LoadoutBridge.grant("character", "gothic_hero", null), "real character reward is granted")
	ok(LoadoutBridge.is_unlocked("character", "gothic_hero"), "character shows as unlocked")
	ok(LoadoutBridge.grant("character", "gothic_hero", null), "duplicate grant is harmless")
	eq(SaveData.get_extra(LoadoutBridge.EXTRAS_CHARACTERS, []), ["gothic_hero"], "unlock list has no duplicate")
	ok(LoadoutBridge.grant("weapon", "bell_hammer", null), "real weapon reward is granted")
	ok(LoadoutBridge.is_unlocked("weapon", "bell_hammer"), "weapon shows as unlocked")
	eq(SaveData.get_extra(LoadoutBridge.EXTRAS_WEAPONS, []), ["bell_hammer"], "weapon unlock list written")
	# 有存档时，解锁表随 persist_profile 落盘。
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)
	ok(SaveData.save_game(String(GameContext.LEVELS["stage04"]), player), "fixture save is written")
	SaveData.persist_profile()
	SaveData.load_game()
	ok(LoadoutBridge.is_unlocked("character", "gothic_hero"), "character unlock survives reload")
	ok(LoadoutBridge.is_unlocked("weapon", "bell_hammer"), "weapon unlock survives reload")
	arena.free()
	await flush(1)


## ---------------------------------------------------------------- surface --

func test_bridge_contract_surface_and_hud_chip() -> void:
	_use_stub_rosters()
	ok(LoadoutBridge.available(), "contract §3.1 available() reports the system")
	var chip := (load(CHIP_PATH) as GDScript).new() as Control
	add_child(chip)
	await flush(1)
	ok(chip.visible, "HUD chip shows a line when a roster exists")
	ok(str(chip.call("current_line")).contains("余烬骑士"), "HUD chip shows the character name")
	# 无 roster：整件隐藏，HUD 不用自己判断。
	LoadoutBridge.test_roster_override = []
	LoadoutBridge.reset_roster_cache()
	chip.call("refresh")
	ok(not chip.visible, "HUD chip hides itself when the roster is missing")
	# apply_to_player 在 roster 存在/缺失、玩家有效/为 null 时都安全。
	LoadoutBridge.apply_to_player(null)
	var arena := Node2D.new()
	add_child(arena)
	build_floor(arena)
	var player: Player = await spawn_player(arena)
	LoadoutBridge.apply_to_player(player)
	_use_stub_rosters()
	LoadoutBridge.apply_to_player(player)
	ok(true, "apply_to_player is a safe no-op without an external entry point")
	chip.queue_free()
	arena.free()
	await flush(1)


## ----------------------------------------------------------- feature-detect --

func test_real_roster_feature_detect() -> void:
	LoadoutBridge.test_roster_override = []
	LoadoutBridge.reset_roster_cache()
	var has_character := ResourceLoader.exists(LoadoutBridge.CHARACTER_ROSTER_PATH)
	var has_weapon := ResourceLoader.exists(LoadoutBridge.WEAPON_ROSTER_PATH)
	if not has_character or not has_weapon:
		print("[LOADOUT CONTRACT] real roster not delivered yet (character=%s weapon=%s) — positive path covered by stubs" % [
				str(has_character), str(has_weapon)])
		ok(not LoadoutBridge.character_available(), "missing character roster -> unavailable, not a crash")
		ok(not LoadoutBridge.weapon_available(), "missing weapon roster -> unavailable, not a crash")
		eq(LoadoutBridge.display_character(), "", "missing roster -> empty display name")
		eq(LoadoutBridge.character_id(), &"", "missing roster -> campaign knight fallback")
		return
	# 真实 roster：至少验证契约形状（更细的字段由外部线的测试/走查覆盖）。
	ok(LoadoutBridge.character_available(), "real character roster is callable")
	var ids: Array = LoadoutBridge._ids(LoadoutBridge.character_roster())
	ok(not ids.is_empty(), "real character roster exposes ids")
	var default_id := LoadoutBridge.default_character_id()
	ok(default_id != &"", "real character roster exposes a default id")
	ok(ids.has(default_id), "real default id is one of the ids")
	for id in ids:
		var def := LoadoutBridge.character_def(id)
		ok(not def.is_empty(), "real character %s has a definition" % id)
		for field in CHARACTER_FIELDS:
			ok(def.has(field), "real character %s has field %s" % [id, field])
	if LoadoutBridge.weapon_available():
		var wids: Array = LoadoutBridge._ids(LoadoutBridge.weapon_roster())
		ok(not wids.is_empty(), "real weapon roster exposes ids")
		var wdef := LoadoutBridge.weapon_def(LoadoutBridge.default_weapon_id())
		for field in WEAPON_FIELDS:
			ok(wdef.has(field), "real weapon default has field %s" % field)
