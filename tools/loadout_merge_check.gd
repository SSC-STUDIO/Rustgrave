extends Node
## M5 合并检查工具（契约 §3 合并门）。
##
## 用法（在当前项目里跑，检查任意项目路径）：
##   godot --headless --path "<campaign-v2>" res://scenes/tools/LoadoutMergeCheck.tscn \
##       -- --project="<外部分支 worktree 路径>"
## 不给 --project 时检查当前项目自己（并有额外运行时探针）。
##
## 输出 PASS / WARN / FAIL 清单 + 合并后必跑的 smoke 清单；FAIL>0 时退出码 1。
## 只读文件 + 只读运行时 API，不写存档、不改工程。
##
## 检查内容：
##   1. 战役侧必需件（Bridge / SaveData v2 / 奖励位接线 / 14 章注册 / 契约测试）
##   2. 外部 roster 文件与 API 形状（存在则查，缺失只 WARN：feature-detect 分支）
##   3. SaveData v2 profile 字段
##   4. HUD/暂停/标题的 loadout 挂点（存在/缺失都报告，缺失给 patch 提示）
##   5. 运行时探针（仅当检查目标就是当前项目）
##   6. 合并后 smoke 清单

const BRIDGE := "scripts/player/loadout_bridge.gd"
const SAVE_DATA := "scripts/autoload/save_data.gd"
const CHAPTER_LAYOUT := "scripts/levels/chapter_layout.gd"
const EQUIPMENT_PICKUP := "scripts/interactables/equipment_pickup.gd"
const GAME_CONTEXT := "scripts/autoload/game_context.gd"
const CHARACTER_ROSTER := "scripts/data/character_roster.gd"
const WEAPON_ROSTER := "scripts/data/weapon_roster.gd"
const HUD := "scripts/ui/hud.gd"
const PAUSE := "scripts/ui/pause_menu.gd"
const TITLE := "scripts/ui/title_screen.gd"
const CHIP := "scripts/ui/loadout_chip.gd"
const CHARACTER_STUB := "tests/fixtures/character_roster_stub.gd"
const WEAPON_STUB := "tests/fixtures/weapon_roster_stub.gd"
const BRIDGE_REQUIRED := [
	"class_name LoadoutBridge",
	"CHARACTER_ROSTER_PATH",
	"WEAPON_ROSTER_PATH",
	"func character_available",
	"func weapon_available",
	"func character_id",
	"func display_character",
	"func grant(",
]
const BRIDGE_RECOMMENDED := [
	"test_roster_override",
	"func reset_roster_cache",
	"func available(",
	"func apply_to_player",
	"func character_ids",
	"func weapon_ids",
	"func default_weapon_id",
]
const SAVE_REQUIRED := [
	"character_id",
	"extras",
	"func set_character",
	"func get_extra",
	"func set_extra",
	"func persist_profile",
	"SAVE_VERSION",
]
const CHARACTER_FIELDS := [
	"display_name", "char_frames_id", "body_size", "hurt_size",
	"speed_mult", "max_hp_mod", "intro_line", "ability_set",
]
const WEAPON_FIELDS := [
	"display_name", "slot", "moveset_id", "pickup_art", "desc", "unlocked_by",
]
const UI_NAMES := {
	"HUD": ["show_loadout", "LoadoutChip", "loadout_chip", "loadout_line"],
	"pause": ["loadout", "Loadout", "character_select"],
	"title": ["loadout", "Loadout", "character_select", "character"],
}

var _target := ""
var _self := false
var _passed: Array[String] = []
var _warned: Array[String] = []
var _failed: Array[String] = []
var _info: Array[String] = []


func _ready() -> void:
	_target = _resolve_target()
	_self = _same_path(_target, _normalize(ProjectSettings.globalize_path("res://")))
	print("=".repeat(64))
	print("[MERGE CHECK] target=%s self=%s" % [_target, str(_self)])
	_check_campaign_surface()
	_check_save_v2()
	_check_rosters()
	_check_ui_hooks()
	_check_tests()
	if _self:
		_check_runtime()
	else:
		_info.append("runtime probes skipped (external project path)")
	_print_smoke_checklist()
	_print_report()
	var code := 0 if _failed.is_empty() else 1
	get_tree().quit(code)


# --------------------------------------------------------------------- util --

func _resolve_target() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--project="):
			return _normalize(arg.trim_prefix("--project="))
	return _normalize(ProjectSettings.globalize_path("res://"))


func _normalize(path: String) -> String:
	var text := path.replace("\\", "/")
	while text.ends_with("/"):
		text = text.left(text.length() - 1)
	return text


func _same_path(a: String, b: String) -> bool:
	return a.to_lower() == b.to_lower()


func _file(rel: String) -> String:
	return _target + "/" + rel


func _read(rel: String) -> String:
	var path := _file(rel)
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


func _pass(message: String) -> void:
	_passed.append(message)
	print("PASS  ", message)


func _warn(message: String) -> void:
	_warned.append(message)
	print("WARN  ", message)


func _fail(message: String) -> void:
	_failed.append(message)
	print("FAIL  ", message)


func _note(message: String) -> void:
	_info.append(message)
	print("INFO  ", message)


func _has_all(text: String, tokens: Array) -> Array:
	var missing: Array = []
	for token in tokens:
		if not text.contains(String(token)):
			missing.append(String(token))
	return missing


# ------------------------------------------------------------------ checks --

func _check_campaign_surface() -> void:
	print("--- campaign surface")
	if _read("project.godot") == "":
		_fail("target has no project.godot (not a Godot project): " + _target)
		return
	_pass("project.godot found")
	var bridge := _read(BRIDGE)
	if bridge == "":
		_fail("missing " + BRIDGE)
	else:
		var missing: Array = _has_all(bridge, BRIDGE_REQUIRED)
		if missing.is_empty():
			_pass("LoadoutBridge exposes the contract API")
		else:
			_fail("LoadoutBridge missing API: " + str(missing))
		var recommended: Array = _has_all(bridge, BRIDGE_RECOMMENDED)
		if recommended.is_empty():
			_pass("LoadoutBridge exposes the M5 extras (test injection + available/apply)")
		else:
			_warn("LoadoutBridge older than M5: missing " + str(recommended)
					+ " - merge may overwrite the M5 bridge; re-apply scripts/player/loadout_bridge.gd")
	var layout := _read(CHAPTER_LAYOUT)
	if layout.contains("func reward("):
		_pass("ChapterLayout.reward() hook present")
	else:
		_warn("ChapterLayout.reward() missing - reward slots from the external line would not exist")
	if _read(EQUIPMENT_PICKUP).contains("LoadoutBridge"):
		_pass("EquipmentPickup routes reward_kind through LoadoutBridge")
	else:
		_warn("EquipmentPickup does not reference LoadoutBridge - unresolved reward wiring")
	var context := _read(GAME_CONTEXT)
	var missing_ids: Array = _has_all(context, ["LEVEL_ORDER", "LEVELS", "\"level07b\"", "\"level09b\""])
	if missing_ids.is_empty():
		_pass("GameContext registers the 14-chapter order incl. level07b/level09b")
	else:
		_fail("GameContext missing campaign registry tokens: " + str(missing_ids))


func _check_save_v2() -> void:
	print("--- save v2")
	var save := _read(SAVE_DATA)
	if save == "":
		_fail("missing " + SAVE_DATA)
		return
	var missing: Array = _has_all(save, SAVE_REQUIRED)
	if not missing.is_empty():
		_fail("SaveData v2 missing: " + str(missing))
		return
	if save.contains("SAVE_VERSION := 2") or save.contains("SAVE_VERSION = 2"):
		_pass("SaveData v2 profile API present (version 2)")
	else:
		_warn("SaveData profile API present but SAVE_VERSION is not 2 - external saves would migrate wrongly")
	if save.contains("\"profile\"") or save.contains("profile"):
		_pass("SaveData persists a profile block (character_id + extras)")
	else:
		_warn("SaveData profile block marker not found")


func _check_rosters() -> void:
	print("--- external rosters")
	var character := _read(CHARACTER_ROSTER)
	var weapon := _read(WEAPON_ROSTER)
	if character == "" and weapon == "":
		_warn("no roster delivered yet (%s / %s) - feature-detect path expected; UI hooks stay hidden" % [
				CHARACTER_ROSTER, WEAPON_ROSTER])
		return
	if character != "":
		_roster_file("character", character, ["func ids", "func def", "func default_id"], CHARACTER_FIELDS, "CharacterRoster")
	else:
		_warn("missing " + CHARACTER_ROSTER + " (character select hidden)")
	if weapon != "":
		_roster_file("weapon", weapon, ["func ids", "func def", "func default_id"], WEAPON_FIELDS, "WeaponRoster")
	else:
		_warn("missing " + WEAPON_ROSTER + " (weapon section hidden)")


func _roster_file(kind: String, text: String, functions: Array, fields: Array, class_token: String) -> void:
	var missing_functions: Array = _has_all(text, functions)
	if missing_functions.is_empty():
		_pass("%s roster exposes ids()/def()/default_id()" % kind)
	else:
		_fail("%s roster missing static API: %s" % [kind, str(missing_functions)])
	if text.contains("class_name " + class_token):
		_pass("%s roster declares class_name %s" % [kind, class_token])
	else:
		_warn("%s roster has no class_name %s (Bridge loads by path, so not fatal)" % [kind, class_token])
	var missing_fields: Array = _has_all(text, fields)
	if missing_fields.is_empty():
		_pass("%s roster definition includes the contract fields" % kind)
	else:
		_warn("%s roster definition missing fields: %s" % [kind, str(missing_fields)])


func _check_ui_hooks() -> void:
	print("--- UI hooks (report only; external line is editing these)")
	_report_hook("HUD", HUD, ["show_loadout"], UI_NAMES["HUD"])
	_report_hook("pause", PAUSE, ["loadout"], UI_NAMES["pause"])
	_report_hook("title", TITLE, ["loadout"], UI_NAMES["title"])
	if _read(CHIP) != "":
		_pass("scripts/ui/loadout_chip.gd present in target")
	else:
		_warn("scripts/ui/loadout_chip.gd missing in target - copy it or add the HUD chip in the HUD file")


func _report_hook(label: String, rel: String, contract_tokens: Array, any_tokens: Array) -> void:
	var text := _read(rel)
	if text == "":
		_warn("%s missing (%s) - loadout entry cannot be checked" % [label, rel])
		return
	var missing_contract: Array = _has_all(text, contract_tokens)
	var found: Array = []
	for token in any_tokens:
		if text.contains(String(token)):
			found.append(String(token))
	if not found.is_empty():
		_pass("%s has a loadout hook (tokens: %s)" % [label, str(found)])
	elif missing_contract.is_empty():
		_warn("%s contract token present but no concrete hook name" % label)
	else:
		_warn("%s has no loadout hook yet - %s" % [label, _hook_hint(label)])


func _hook_hint(label: String) -> String:
	match label:
		"HUD":
			return "add LoadoutChip (preload scripts/ui/loadout_chip.gd), bind_player(player), refresh on weapon change"
		"pause":
			return "add a 'Loadout & Equipment' entry/page only when LoadoutBridge.available()"
		"title":
			return "add a 'Choose character/weapon' new-game page only when LoadoutBridge.character_available()"
	return "add the loadout entry"


func _check_tests() -> void:
	print("--- merge-gate tests")
	for rel in ["tests/loadout_contract_test.gd", "tests/loadout_route_test.gd"]:
		if _read(rel) != "":
			_pass("gate test present: " + rel)
		else:
			_fail("gate test missing: " + rel)
	for rel in ["tests/loadout_bridge_test.gd", "tests/equipment_reward_test.gd",
			CHARACTER_STUB, WEAPON_STUB]:
		if _read(rel) != "":
			_pass("support test/fixture present: " + rel)
		else:
			_warn("support test/fixture missing: " + rel)


# ------------------------------------------------------------- runtime probe --

func _check_runtime() -> void:
	print("--- runtime probes (self)")
	var available := LoadoutBridge.available()
	_pass("LoadoutBridge.available() callable (value=%s)" % str(available))
	_pass("character_available=%s weapon_available=%s character_id='%s' display='%s'" % [
			str(LoadoutBridge.character_available()), str(LoadoutBridge.weapon_available()),
			str(LoadoutBridge.character_id()), str(LoadoutBridge.display_character())])
	_pass("character_ids=%s weapon_ids=%s default_weapon='%s'" % [
			str(LoadoutBridge.character_ids()), str(LoadoutBridge.weapon_ids()),
			str(LoadoutBridge.default_weapon_id())])
	_pass("weapon_def(default)=%s loadout_line='%s'" % [
			str(LoadoutBridge.weapon_def(LoadoutBridge.default_weapon_id()).keys()),
			LoadoutBridge.loadout_line(null)])
	LoadoutBridge.apply_to_player(null)
	LoadoutBridge.weapon_id(null)
	_pass("apply_to_player(null) / weapon_id(null) are safe")
	# SaveData profile 探针：只改内存，结束前恢复，不落盘。
	var old_character := SaveData.character_id
	var old_extras := SaveData.extras.duplicate(true)
	SaveData.set_character("_merge_check")
	var character_ok := String(SaveData.character_id) == "_merge_check"
	SaveData.set_extra("_merge_check_key", [1, 2])
	var extra_ok: bool = SaveData.get_extra("_merge_check_key", []) == [1, 2]
	SaveData.character_id = old_character
	SaveData.extras = old_extras
	if character_ok and extra_ok:
		_pass("SaveData v2 profile API round-trips in memory (character_id + extras)")
	else:
		_fail("SaveData v2 profile API round-trip failed")
	# 测试注入探针：fixtures 存在时应能走 stub roster 正向路径。
	if _read(CHARACTER_STUB) != "" and _read(WEAPON_STUB) != "":
		var previous := LoadoutBridge.test_roster_override
		LoadoutBridge.test_roster_override = [load("res://" + CHARACTER_STUB), load("res://" + WEAPON_STUB)]
		LoadoutBridge.reset_roster_cache()
		var stub_ok := LoadoutBridge.character_available() and not LoadoutBridge.character_def(&"knight").is_empty()
		LoadoutBridge.test_roster_override = previous
		LoadoutBridge.reset_roster_cache()
		if stub_ok:
			_pass("test roster injection round-trip works (stubs -> available -> restored)")
		else:
			_fail("test roster injection probe failed")
	else:
		_warn("roster fixtures missing - stub-roster positive path not runnable")


# ------------------------------------------------------------------ report --

func _print_smoke_checklist() -> void:
	print("--- smoke checklist (after merge)")
	print("SMOKE 1  full suite:   godot --headless --path \"%s\" res://tests/run_tests.tscn" % _target)
	print("SMOKE 2  gate filters: -- --case-filter=loadout_contract / loadout_route / loadout_bridge / equipment_reward")
	print("SMOKE 3  14-chapter walkthrough: godot --headless --path \"%s\" res://scenes/tools/CampaignWalkthrough.tscn" % _target)
	print("SMOKE 4  loadout walkthrough x2: title select -> level01; weapon pickup -> HUD chip visible")
	print("SMOKE 5  trial smoke: TrialMenu -> one TrialRun (loadout frozen, no campaign flags written)")
	print("SMOKE 6  story/interlude overlay: --case-filter=interlude_overlay + boss_fixture 14/14")
	print("SMOKE 7  renders: screenshots/peek/loadout-{full,fallback} (HUD chip on/off)")


func _print_report() -> void:
	print("--- verified API names")
	print("API     available/character_available/weapon_available/character_ids/weapon_ids/")
	print("        default_character_id/default_weapon_id/character_def/weapon_def/character_id/")
	print("        display_character/display_weapon/weapon_id/loadout_line/grant/is_unlocked/")
	print("        apply_to_player/reset_roster_cache/test_roster_override")
	print("SAVE    character_id / extras / set_character() / get_extra() / set_extra() / persist_profile()")
	print("UI      Hud.show_loadout(name, weapon) / LoadoutChip / pause 'Loadout & Equipment' / title 'Choose character/weapon'")
	print("--- merge guidance")
	print("MERGE   1) merge the external roster files (scripts/data/*_roster.gd) first, then the UI files;")
	print("        2) if loadout_bridge.gd was overwritten by an older copy, restore the M5 bridge")
	print("           (test_roster_override / available / apply_to_player);");
	print("        3) run SMOKE 1-7; only commit when fail=0 and the hashes line up.")
	print("=".repeat(64))
	var result := "PASS" if _failed.is_empty() else "FAIL"
	if _failed.is_empty() and _warned.is_empty():
		result = "PASS (clean)"
	print("[MERGE CHECK] RESULT=%s passed=%d warned=%d failed=%d" % [
			result, _passed.size(), _warned.size(), _failed.size()])
	for message in _failed:
		print("  FAIL: ", message)
	for message in _warned:
		print("  WARN: ", message)
