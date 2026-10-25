extends Node
## SaveData autoload: persist player + world state to user://rustgrave_save.cfg.
## Pure data — works identically in headless runs. Call save_game(node, player)
## from an Ember Nest; load_game() reads the file back into the dictionary.
##
## World persistence: any node in the "persistent" group exports a snapshot via
## get_persistent_state() and restores it via apply_persistent_state(). The
## save stores that data keyed by a scene-relative path (with a resolver for
## older absolute `/root/...` keys) so a renamed root still remaps.

const CharacterOriginScript := preload("res://scripts/data/character_origin.gd")
const OriginCatalogScript := preload("res://scripts/data/origin_catalog.gd")
const TrialRunScript := preload("res://scripts/autoload/trial_run.gd")
const ArenaRunScript := preload("res://scripts/autoload/arena_run.gd")

## v1 = 10-chapter campaign (no profile block). v2 adds the profile block
## (character_id + extras). v3 adds the progression/appearance block used by the
## v3 character system (ember rank/xp, attribute points, two skill slots, skin +
## skin rune) — every one of them degrades to a default, so v1/v2 saves keep
## loading. Loading an older save keeps
## every old field and fills the new ones with defaults — no migration step needed.
const SAVE_VERSION := 3
## Fresh campaign foot point. Matches Level01Static.DEFAULT_SPAWN so a new
## save never starts at world zero, which the opening reads as "not yet placed".
const NEW_GAME_SPAWN := Vector2(96, 320)

const DEFAULT_EQUIPMENT := {
	"weapon": "broken_sword",
	"armor": "broken_armor",
	"trinket": "broken_pendant",
	"bag": []
}

var save_path := "user://rustgrave_save.cfg"

## Currently loaded save dictionary (empty until load_game / save_game).
## Structure:
##   meta      = { version, scene, saved_at }
##   player    = { hp, max_hp, toxin, max_toxin, pos (Vector2), facing }
##   inventory = { pouch: [core ids], sockets: [core ids or ""] }
##   equipment = { weapon: id, armor: id, trinket: id, bag: [id, ...] }
##   profile   = { character_id, extras, ember_rank, ember_xp, attribute_points,
##                 skill_1, skill_2, skin_id, skin_rune }   # save v3
##   world     = { "Props/Door": {...}, ... }  # scene-relative; old /root keys still resolve
##   atmosphere = { time_of_day (0–1), weather }
var data: Dictionary = {}

## One-shot spawn override consumed by a level right after it instantiates the
## player. Set by respawn flow so the player appears at the last Ember Nest.
var pending_spawn: Vector2 = Vector2.INF
## True from death→fade until the new level finishes try_wake. Survives
## consume_pending_spawn(), unlike pending_spawn itself.
var entering_from_checkpoint: bool = false
## Transient UI notice; never serialized into the campaign file.
var checkpoint_notice_pending := false

## Absolute node paths of one-shot interactables that died (picked up cores,
## used filter gears, melted gates). Persisted even though their nodes are
## freed from the tree, and replayed to remove them on every reload.
var consumed: PackedStringArray = []

## Ember Nests lit so far; the last one is the respawn point. Stored as scene
## paths so levels can recompute the spawn even before replaying world state.
var lit_nests: PackedStringArray = []

## One-shot story beats already shown (wake, first toxin, first parry…).
var flags: PackedStringArray = []
## Empty until a finished ending: "snuff" at the remnant, "give" / "keep" at the forge door.
## Chapter-1 rekindle is a promise to continue, not an ending.
var ending: String = ""
## True until the new-game opening finishes. Older saves omit the key; only a
## pristine zero-coordinate initializer is repaired forward.
var opening_pending: bool = false
## Save v2 profile block. Owned by the character/weapon lines through this file and
## the LoadoutBridge; campaign code only reads `character_id` for spawn/visual selection.
## `extras` keeps unknown keys verbatim so a newer build can add data without another
## schema bump (unlock tables, per-character progress, ...).
var character_id: String = ""
var extras: Dictionary = {}

## Save v3 progression/appearance block (character system v3).
## 余烬阶位 1..10；经验只增；属性点由升阶奖励、消费在以后的面板里。
var ember_rank: int = 1
var ember_xp: int = 0
var attribute_points: int = 0
## 两个主动技能槽（技能 id，"" = 空）。
var skill_1: String = ""
var skill_2: String = ""
## 外观：皮肤 id + 皮肤刻印 id（"" = 无）。
var skin_id: String = ""
var skin_rune: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 试炼模式（TrialRun，契约 §2/§5）中战役档案只读：读档拒绝、写入函数 no-op、
## 旗标/消耗/余烬巢等内存状态也不改。TrialRun 只写自己的 user://rustgrave_trials.cfg。
func _trial_active() -> bool:
	return TrialRunScript.blocks_campaign_save() or ArenaRunScript.blocks_campaign_save()


func set_character(id: String) -> void:
	character_id = id
	if data.has("profile"):
		data["profile"]["character_id"] = id


func get_extra(key: String, default_value: Variant = null) -> Variant:
	return extras.get(key, default_value)


func set_extra(key: String, value: Variant) -> void:
	extras[key] = value
	if data.has("profile"):
		var p: Dictionary = data["profile"]
		var ex: Dictionary = p.get("extras", {})
		ex[key] = value
		p["extras"] = ex
		data["profile"] = p


## 当前 profile 的完整快照（测试 / 存档都只认这一份结构）。
func profile_snapshot() -> Dictionary:
	return {
		"character_id": character_id,
		"extras": extras.duplicate(true),
		"ember_rank": ember_rank,
		"ember_xp": ember_xp,
		"attribute_points": attribute_points,
		"skill_1": skill_1,
		"skill_2": skill_2,
		"skin_id": skin_id,
		"skin_rune": skin_rune,
	}


func _write_profile_to_cfg(cfg: ConfigFile) -> void:
	cfg.set_value("profile", "character_id", character_id)
	cfg.set_value("profile", "extras", extras.duplicate(true))
	cfg.set_value("profile", "ember_rank", ember_rank)
	cfg.set_value("profile", "ember_xp", ember_xp)
	cfg.set_value("profile", "attribute_points", attribute_points)
	cfg.set_value("profile", "skill_1", skill_1)
	cfg.set_value("profile", "skill_2", skill_2)
	cfg.set_value("profile", "skin_id", skin_id)
	cfg.set_value("profile", "skin_rune", skin_rune)


func _read_profile_from_cfg(cfg: ConfigFile) -> void:
	character_id = String(cfg.get_value("profile", "character_id", ""))
	var raw_extras: Variant = cfg.get_value("profile", "extras", {})
	extras = raw_extras.duplicate(true) if raw_extras is Dictionary else {}
	ember_rank = clampi(int(cfg.get_value("profile", "ember_rank", 1)), 1, 10)
	ember_xp = maxi(0, int(cfg.get_value("profile", "ember_xp", 0)))
	attribute_points = maxi(0, int(cfg.get_value("profile", "attribute_points", 0)))
	skill_1 = String(cfg.get_value("profile", "skill_1", ""))
	skill_2 = String(cfg.get_value("profile", "skill_2", ""))
	skin_id = String(cfg.get_value("profile", "skin_id", ""))
	skin_rune = String(cfg.get_value("profile", "skin_rune", ""))
	data["profile"] = profile_snapshot()


func set_ember_state(rank: int, xp: int, points: int) -> void:
	ember_rank = clampi(rank, 1, 10)
	ember_xp = maxi(0, xp)
	attribute_points = maxi(0, points)
	if data.has("profile"):
		data["profile"] = profile_snapshot()


func set_skill_slot(index: int, skill_id: String) -> void:
	if index == 0:
		skill_1 = skill_id
	elif index == 1:
		skill_2 = skill_id
	if data.has("profile"):
		data["profile"] = profile_snapshot()


func set_skin(id: String, rune: String = "") -> void:
	skin_id = id
	skin_rune = rune
	if data.has("profile"):
		data["profile"] = profile_snapshot()


## Flush only the profile block onto the existing save (character select, weapon
## unlock). No-op before the first checkpoint so a fresh run keeps no half-save.
func persist_profile() -> bool:
	if _trial_active():
		return false
	var cfg := _load_cfg()
	if cfg == null:
		return false
	_write_profile_to_cfg(cfg)
	data["profile"] = profile_snapshot()
	return _write_cfg(cfg)


func has_save() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(_backup_path())

func get_current_origin() -> StringName:
	if data != null and data.has("player") and data["player"] is Dictionary:
		var orig = data["player"].get("origin", "")
		if orig != null and String(orig).strip_edges() != "":
			return StringName(String(orig).strip_edges())
	var tree := get_tree()
	if tree != null:
		var players := tree.get_nodes_in_group("player")
		if not players.is_empty():
			var p = players[0]
			if p is Player and (p as Player).stats != null:
				var oid := (p as Player).stats.get_origin_id()
				if oid != &"":
					return oid
			elif "origin" in p and String(p.origin).strip_edges() != "":
				return StringName(String(p.origin).strip_edges())
	if FileAccess.file_exists(save_path):
		var cfg := _load_cfg()
		if cfg != null and cfg.has_section_key("player", "origin"):
			var disk_origin: String = String(cfg.get_value("player", "origin", "")).strip_edges()
			if disk_origin != "":
				return StringName(disk_origin)
	return &""


## Initialize a brand new game session with selected character origin and starting loadout.
## Writes the new file first. A failed write leaves the previous session and clock untouched.
func init_new_game(origin_id: Variant = &"ember_vanguard", loadout: Dictionary = {}) -> bool:
	var o_sym := StringName(str(origin_id)) if origin_id != null else &"ember_vanguard"
	var o_str := String(o_sym).strip_edges()
	if o_str == "":
		o_sym = &"ember_vanguard"
		o_str = "ember_vanguard"

	var w_val = loadout.get("weapon", "broken_sword")
	var a_val = loadout.get("armor", "broken_armor")
	var t_val = loadout.get("trinket", "broken_pendant")
	var bag_val = loadout.get("bag", [])

	var w_str := _item_to_id(w_val)
	if w_str == "":
		w_str = "broken_sword"
	var a_str := _item_to_id(a_val)
	if a_str == "":
		a_str = "broken_armor"
	var t_str := _item_to_id(t_val)
	if t_str == "":
		t_str = "broken_pendant"

	var clean_bag: Array = []
	if bag_val is Array:
		for b in bag_val:
			var bid := _item_to_id(b)
			if bid != "":
				clean_bag.append(bid)

	var preview: Dictionary = OriginCatalogScript.calculate_preview_stats(o_sym, w_str, a_str, t_str)
	var max_hp: int = int(preview.get("max_hp", 5))
	var saved_at := Time.get_datetime_string_from_system()
	var atmosphere := {
		"time_of_day": WorldClock.DEFAULT_TIME,
		"weather": "haze",
		"zone": "outdoors",
		"wind_heading": -1.0,
	}
	var fresh_profile := {
		"character_id": "",
		"extras": {},
		"ember_rank": 1,
		"ember_xp": 0,
		"attribute_points": 0,
		"skill_1": "",
		"skill_2": "",
		"skin_id": "",
		"skin_rune": "",
	}
	var next_data := {
		"meta": {
			"version": SAVE_VERSION,
			"scene": GameContext.WORLD_PATH,
			"saved_at": saved_at,
			"ending": "",
		},
		"player": {
			"origin": o_str,
			"hp": max_hp,
			"max_hp": max_hp,
			"toxin": 0.0,
			"max_toxin": 100.0,
			"pos": NEW_GAME_SPAWN,
			"facing": 1,
			"pouch": [],
			"sockets": [],
		},
		"equipment": {
			"weapon": w_str,
			"armor": a_str,
			"trinket": t_str,
			"bag": clean_bag,
		},
		"profile": fresh_profile,
		"world": {},
		"atmosphere": atmosphere,
	}

	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)
	cfg.set_value("meta", "scene", GameContext.WORLD_PATH)
	cfg.set_value("meta", "saved_at", saved_at)
	cfg.set_value("meta", "ending", "")
	for key in fresh_profile:
		cfg.set_value("profile", key, fresh_profile[key])

	cfg.set_value("player", "origin", o_str)
	cfg.set_value("player", "hp", max_hp)
	cfg.set_value("player", "max_hp", max_hp)
	cfg.set_value("player", "toxin", 0.0)
	cfg.set_value("player", "max_toxin", 100.0)
	cfg.set_value("player", "pos_x", NEW_GAME_SPAWN.x)
	cfg.set_value("player", "pos_y", NEW_GAME_SPAWN.y)
	cfg.set_value("player", "facing", 1)
	cfg.set_value("player", "pouch", [])
	cfg.set_value("player", "sockets", [])

	cfg.set_value("equipment", "weapon", w_str)
	cfg.set_value("equipment", "armor", a_str)
	cfg.set_value("equipment", "trinket", t_str)
	cfg.set_value("equipment", "bag", clean_bag)

	cfg.set_value("consumed", "paths", [])
	cfg.set_value("lit_nests", "paths", [])
	cfg.set_value("story", "flags", [])
	cfg.set_value("story", "opening_pending", true)

	cfg.set_value("atmosphere", "time_of_day", float(atmosphere["time_of_day"]))
	cfg.set_value("atmosphere", "weather", String(atmosphere["weather"]))
	cfg.set_value("atmosphere", "zone", String(atmosphere["zone"]))
	cfg.set_value("atmosphere", "wind_heading", float(atmosphere["wind_heading"]))

	if not _write_cfg(cfg):
		push_warning("SaveData: new game could not be saved; previous progress kept")
		return false

	data = next_data
	consumed.clear()
	lit_nests.clear()
	flags.clear()
	ending = ""
	opening_pending = true
	character_id = ""
	extras.clear()
	ember_rank = 1
	ember_xp = 0
	attribute_points = 0
	skill_1 = ""
	skill_2 = ""
	skin_id = ""
	skin_rune = ""
	pending_spawn = Vector2.INF
	entering_from_checkpoint = false
	WorldClock.reset()
	GameEvents.game_saved.emit()
	return true


## `spawn_override`: where the knight should stand when this save is loaded —
## used by level exits, whose save names the *next* scene while the knight is
## still standing in the old one.
func save_game(scene_path: String, player: Node, spawn_override: Vector2 = Vector2.INF) -> bool:
	if _trial_active():
		return false
	var player_state := _collect_player(player)
	if spawn_override != Vector2.INF:
		player_state["pos"] = spawn_override
	var inv_state := _collect_inventory(player)
	player_state["pouch"] = inv_state["pouch"]
	player_state["sockets"] = inv_state["sockets"]
	var equip_state := _collect_equipment(player)
	var world := _collect_world()
	var cfg := ConfigFile.new()
	data = {
		"meta": {
			"version": SAVE_VERSION,
			"scene": scene_path,
			"saved_at": Time.get_datetime_string_from_system(),
		},
		"player": player_state,
		"equipment": equip_state,
		"profile": profile_snapshot(),
		"world": world,
	}
	cfg.set_value("meta", "version", SAVE_VERSION)
	cfg.set_value("meta", "scene", scene_path)
	cfg.set_value("meta", "saved_at", data["meta"]["saved_at"])
	_write_profile_to_cfg(cfg)
	var ps: Dictionary = player_state
	var origin_str: String = String(ps.get("origin", "")).strip_edges()
	if origin_str != "":
		cfg.set_value("player", "origin", origin_str)
	cfg.set_value("player", "hp", ps.get("hp", 0))
	cfg.set_value("player", "max_hp", ps.get("max_hp", 1))
	cfg.set_value("player", "toxin", ps.get("toxin", 0.0))
	cfg.set_value("player", "max_toxin", ps.get("max_toxin", 100.0))
	cfg.set_value("player", "pos_x", (ps.get("pos", Vector2.ZERO) as Vector2).x)
	cfg.set_value("player", "pos_y", (ps.get("pos", Vector2.ZERO) as Vector2).y)
	cfg.set_value("player", "facing", ps.get("facing", 1))
	var pouch_ids: Array = []
	for core in ps.get("pouch", []):
		pouch_ids.append(core)
	cfg.set_value("player", "pouch", pouch_ids)
	var socket_ids: Array = []
	for core in ps.get("sockets", []):
		socket_ids.append(core)
	cfg.set_value("player", "sockets", socket_ids)
	var w_val: Variant = equip_state.get("weapon", "broken_sword")
	cfg.set_value("equipment", "weapon", "" if w_val == null else String(w_val))
	var a_val: Variant = equip_state.get("armor", "broken_armor")
	cfg.set_value("equipment", "armor", "" if a_val == null else String(a_val))
	var t_val: Variant = equip_state.get("trinket", "broken_pendant")
	cfg.set_value("equipment", "trinket", "" if t_val == null else String(t_val))
	var bag_ids: Array = []
	for id_val in equip_state.get("bag", []):
		var id_str := String(id_val).strip_edges()
		if id_str != "":
			bag_ids.append(id_str)
	cfg.set_value("equipment", "bag", bag_ids)
	for key in world:
		cfg.set_value("world", key, world[key])
	cfg.set_value("consumed", "paths", Array(consumed))
	cfg.set_value("lit_nests", "paths", Array(lit_nests))
	cfg.set_value("story", "flags", Array(flags))
	cfg.set_value("story", "opening_pending", opening_pending)
	cfg.set_value("meta", "ending", ending)
	var atmosphere := WorldClock.snapshot()
	data["atmosphere"] = atmosphere
	cfg.set_value("atmosphere", "time_of_day", float(atmosphere.get("time_of_day", WorldClock.DEFAULT_TIME)))
	cfg.set_value("atmosphere", "weather", String(atmosphere.get("weather", "haze")))
	cfg.set_value("atmosphere", "zone", String(atmosphere.get("zone", "outdoors")))
	cfg.set_value("atmosphere", "wind_heading", float(atmosphere.get("wind_heading", -1.0)))
	if not _write_cfg(cfg):
		push_warning("SaveData: failed to save to %s" % save_path)
		return false
	GameEvents.game_saved.emit()
	return true

func load_game() -> bool:
	if _trial_active():
		return false
	var cfg := _load_cfg()
	if cfg == null:
		data = {}
		return false
	data = {}
	data["meta"] = {
		"version": cfg.get_value("meta", "version", 1),
		"scene": cfg.get_value("meta", "scene", ""),
		"saved_at": cfg.get_value("meta", "saved_at", ""),
	}
	# Save v2/v3 profile block (character + progression + appearance).
	_read_profile_from_cfg(cfg)
	var player_dict: Dictionary = {
		"hp": cfg.get_value("player", "hp", 0),
		"max_hp": cfg.get_value("player", "max_hp", 5),
		"toxin": cfg.get_value("player", "toxin", 0.0),
		"max_toxin": cfg.get_value("player", "max_toxin", 100.0),
		"pos": Vector2(cfg.get_value("player", "pos_x", 0.0), cfg.get_value("player", "pos_y", 0.0)),
		"facing": cfg.get_value("player", "facing", 1),
		"pouch": cfg.get_value("player", "pouch", []),
		"sockets": cfg.get_value("player", "sockets", []),
	}
	if cfg.has_section_key("player", "origin"):
		player_dict["origin"] = String(cfg.get_value("player", "origin", ""))
	data["player"] = player_dict
	if cfg.has_section("equipment"):
		var raw_bag: Variant = cfg.get_value("equipment", "bag", [])
		var clean_bag: Array = []
		if raw_bag is Array:
			for item_id in raw_bag:
				if item_id is String or item_id is StringName:
					var s := String(item_id).strip_edges()
					if s != "":
						clean_bag.append(s)
		data["equipment"] = {
			"weapon": String(cfg.get_value("equipment", "weapon", "broken_sword")),
			"armor": String(cfg.get_value("equipment", "armor", "broken_armor")),
			"trinket": String(cfg.get_value("equipment", "trinket", "broken_pendant")),
			"bag": clean_bag,
		}
	else:
		data["equipment"] = DEFAULT_EQUIPMENT.duplicate(true)
	data["world"] = {}
	if cfg.has_section("world"):
		for key in cfg.get_section_keys("world"):
			data["world"][key] = cfg.get_value("world", key)
	consumed.clear()
	for p in cfg.get_value("consumed", "paths", []):
		consumed.append(String(p))
	lit_nests.clear()
	for p in cfg.get_value("lit_nests", "paths", []):
		lit_nests.append(String(p))
	flags.clear()
	for f in cfg.get_value("story", "flags", []):
		flags.append(String(f))
	ending = String(cfg.get_value("meta", "ending", ""))
	opening_pending = bool(cfg.get_value("story", "opening_pending", false))
	_repair_unstarted_save(cfg)
	var atmosphere := {
		"time_of_day": float(cfg.get_value("atmosphere", "time_of_day", WorldClock.DEFAULT_TIME)),
		"weather": String(cfg.get_value("atmosphere", "weather", "haze")),
		"zone": String(cfg.get_value("atmosphere", "zone", "outdoors")),
		"wind_heading": float(cfg.get_value("atmosphere", "wind_heading", -1.0)),
	}
	data["atmosphere"] = atmosphere
	WorldClock.apply_snapshot(atmosphere)
	return true


## Repair only the obsolete pristine identity initializer, never a progressed save.
## Its zero coordinate was written before the first world frame was ever entered.
func _repair_unstarted_save(cfg: ConfigFile) -> void:
	if cfg.has_section_key("story", "opening_pending"):
		return
	var player: Dictionary = data.get("player", {})
	if data.get("meta", {}).get("scene", "") != GameContext.WORLD_PATH \
			or player.get("pos", Vector2.INF) != Vector2.ZERO:
		return
	if not OriginCatalogScript.has_origin(player.get("origin", "")) \
			or not cfg.has_section("equipment"):
		return
	if not flags.is_empty() or not consumed.is_empty() or not lit_nests.is_empty() \
			or ending != "" or not (data["world"] as Dictionary).is_empty():
		return
	if not player.get("pouch", []).is_empty() \
			or int(player.get("hp", 0)) != int(player.get("max_hp", 5)) \
			or not is_zero_approx(float(player.get("toxin", 0.0))) \
			or not data.get("equipment", {}).get("bag", []).is_empty():
		return
	for core_id in player.get("sockets", []):
		if String(core_id) != "":
			return
	data["player"]["pos"] = NEW_GAME_SPAWN
	opening_pending = true
	cfg.set_value("player", "pos_x", NEW_GAME_SPAWN.x)
	cfg.set_value("player", "pos_y", NEW_GAME_SPAWN.y)
	cfg.set_value("story", "opening_pending", true)
	_write_cfg(cfg)


func delete_save() -> void:
	if _trial_active():
		return
	_remove_if_exists(save_path)
	_remove_if_exists(_backup_path())
	_remove_if_exists(_tmp_path())
	data = {}
	consumed.clear()
	lit_nests.clear()
	flags.clear()
	ending = ""
	opening_pending = false
	character_id = ""
	extras.clear()
	pending_spawn = Vector2.INF
	entering_from_checkpoint = false
	WorldClock.reset()


## Record that a one-shot interactable at `path` has been consumed (picked up,
## used, melted). Survives node free because it's a plain path list.
func mark_consumed(path: String) -> void:
	if _trial_active():
		return
	path = _normalize_saved_path(path)
	if path == "":
		return
	if not consumed.has(path):
		consumed.append(path)


func is_consumed(path: String) -> bool:
	path = _normalize_saved_path(path)
	if consumed.has(path):
		return true
	for p in consumed:
		if _normalize_saved_path(String(p)) == path:
			return true
	return false


## Remove from the freshly-built scene every one-shot node that was consumed.
func apply_consumed(node: Node) -> void:
	if _trial_active():
		return
	if node == null or not is_instance_valid(node):
		return
	for p in consumed.duplicate():
		var target := resolve_saved_node(node, String(p))
		if target == null or not is_instance_valid(target):
			continue
		# A required core must never vanish with the save not owning it (soft-lock).
		if target is CorePickup and (target as CorePickup).core != null \
				and release_unowned_core(String(p), (target as CorePickup).core.id):
			continue
		target.queue_free()


func register_lit_nest(path: String) -> void:
	if _trial_active():
		return
	path = _normalize_saved_path(path)
	if path == "":
		return
	var leaf := path.get_file()
	var i := lit_nests.size() - 1
	while i >= 0:
		var existing := String(lit_nests[i])
		if existing == path or (leaf != "" and existing.get_file() == leaf):
			lit_nests.remove_at(i)
		i -= 1
	lit_nests.append(path)


func last_lit_nest() -> String:
	return lit_nests[lit_nests.size() - 1] if not lit_nests.is_empty() else ""


func mark_flag(id: String) -> void:
	if _trial_active():
		return
	if not flags.has(id):
		flags.append(id)
	# 契约 §5：第七章通关 / 任一结局给试炼入口上锁解除（trial_unlocked）。
	if id == "level07_done" or id == "game_complete":
		if not flags.has("trial_unlocked"):
			flags.append("trial_unlocked")


func has_flag(id: String) -> bool:
	# A practice scene must build its defeated Boss again. The stored campaign
	# flags remain intact and all writes remain blocked by the existing trial lock.
	if TrialRunScript.forces_boss_spawn() and id == String(TrialRunScript.stage().get("death_flag", "")):
		return false
	return flags.has(id)


## Write flags + ending onto an existing save without needing a live player.
## Used after Boss kill so a nest-respawn load_game() cannot revive the Executioner.
## Also flushes consumed / lit_nests so a story write cannot drop later pickups.
##
## The flush is a *progression* write: it also carries the live knight's cores and the
## persistent world nodes (looted scrap, opened doors). Writing `consumed` alone used to
## record a picked-up core as gone while the pouch on disk still lacked it, so a death
## before the next nest lost the core for good (and with it the grapple route).
func persist_story(player: Node = null) -> void:
	if _trial_active():
		return
	persist_progress(player)


## Save-at-pickup: write cores, consumed one-shots, world nodes, nests and flags onto the
## existing save without moving the respawn point, HP or the saved scene. No-op without a
## save (before the first nest a death reloads a fresh level and every pickup returns).
func persist_progress(player: Node = null) -> bool:
	if _trial_active():
		return false
	var cfg := _load_cfg()
	if cfg == null:
		return false
	if player == null:
		player = _live_player()
	if player is Player and is_instance_valid(player):
		var inv := _collect_inventory(player)
		cfg.set_value("player", "pouch", inv["pouch"])
		cfg.set_value("player", "sockets", inv["sockets"])
		if data.has("player"):
			(data["player"] as Dictionary)["pouch"] = inv["pouch"]
			(data["player"] as Dictionary)["sockets"] = inv["sockets"]
		var equip_state := _collect_equipment(player)
		var w_val: Variant = equip_state.get("weapon", "broken_sword")
		cfg.set_value("equipment", "weapon", "" if w_val == null else String(w_val))
		var a_val: Variant = equip_state.get("armor", "broken_armor")
		cfg.set_value("equipment", "armor", "" if a_val == null else String(a_val))
		var t_val: Variant = equip_state.get("trinket", "broken_pendant")
		cfg.set_value("equipment", "trinket", "" if t_val == null else String(t_val))
		var bag_ids: Array = []
		for id_val in equip_state.get("bag", []):
			var id_str := String(id_val).strip_edges()
			if id_str != "":
				bag_ids.append(id_str)
		cfg.set_value("equipment", "bag", bag_ids)
		if data.has("equipment"):
			data["equipment"] = equip_state
		var world := _collect_world()
		for key in world:
			cfg.set_value("world", key, world[key])
			if data.has("world"):
				(data["world"] as Dictionary)[key] = world[key]
	cfg.set_value("story", "flags", Array(flags))
	cfg.set_value("story", "opening_pending", opening_pending)
	cfg.set_value("meta", "ending", ending)
	cfg.set_value("consumed", "paths", Array(consumed))
	cfg.set_value("lit_nests", "paths", Array(lit_nests))
	return _write_cfg(cfg)


func _live_player() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("player")


## Ownership check against the *loaded save* (pouch or sockets). Cores are never
## destroyed — sockets swap back into the pouch — so a consumed core pickup whose core
## the save does not own is a lost core, and must come back into the world.
func save_owns_core(core_id: StringName) -> bool:
	var p: Dictionary = data.get("player", {})
	for key in ["pouch", "sockets"]:
		for id_str in p.get(key, []):
			if StringName(String(id_str)) == core_id:
				return true
	return false


## Save-compat repair for files written before persist_progress existed: un-consume
## core pickups the save no longer owns. Returns how many paths were released.
func release_unowned_core(path: String, core_id: StringName) -> bool:
	if not data.has("player") or save_owns_core(core_id):
		return false
	var key := _normalize_saved_path(path)
	var released := false
	var i := consumed.size() - 1
	while i >= 0:
		var c := String(consumed[i])
		if c == key or c == path or _normalize_saved_path(c) == key:
			consumed.remove_at(i)
			released = true
		i -= 1
	return released


func peek_ending() -> String:
	if ending != "":
		return ending
	var cfg := _load_cfg()
	if cfg == null:
		return ""
	return String(cfg.get_value("meta", "ending", ""))

## Pull a player node's live state into the data dict.
func _collect_player(player: Node) -> Dictionary:
	if player == null:
		return {}
	var hp := player.get_node_or_null("Health") as Health
	var tox := player.get_node_or_null("ToxinMeter") as ToxinMeter
	var state: Dictionary = {}
	var cur_origin: String = ""
	if player is Player and (player as Player).stats != null:
		cur_origin = String((player as Player).stats.get_origin_id()).strip_edges()
	elif "origin" in player and player.origin != null:
		cur_origin = String(player.origin).strip_edges()
	if cur_origin == "" and data != null and data.has("player") and data["player"] is Dictionary:
		cur_origin = String(data["player"].get("origin", "")).strip_edges()
	if cur_origin != "":
		state["origin"] = cur_origin
	state["hp"] = hp.current if hp else 0
	state["max_hp"] = hp.max_hp if hp else 5
	state["toxin"] = tox.toxin if tox else 0.0
	state["max_toxin"] = tox.max_toxin if tox else 100.0
	state["pos"] = player.global_position
	state["facing"] = 1
	if player is Player:
		state["facing"] = (player as Player).controller.facing
	return state


func _collect_inventory(player: Node) -> Dictionary:
	if player is Player:
		var inv := (player as Player).inventory
		var pouch_ids: Array = []
		for core in inv.pouch:
			if core is RustCore:
				pouch_ids.append(String((core as RustCore).id))
		var socket_ids: Array = []
		for core in inv.sockets:
			socket_ids.append(String((core as RustCore).id) if core is RustCore else "")
		return {"pouch": pouch_ids, "sockets": socket_ids}
	return {"pouch": [], "sockets": []}


func _collect_equipment(player: Node) -> Dictionary:
	var result := DEFAULT_EQUIPMENT.duplicate(true)
	if player == null:
		return result
	var eq: EquipmentInventory = null
	if player is Player:
		eq = (player as Player).equipment_inventory
		if eq == null:
			eq = (player as Player).equipment
	if eq == null:
		if "equipment_inventory" in player and player.equipment_inventory != null:
			eq = player.equipment_inventory
		elif "equipment" in player and player.equipment != null:
			eq = player.equipment
		elif player.has_node("EquipmentInventory"):
			eq = player.get_node("EquipmentInventory") as EquipmentInventory
	if eq != null:
		if eq.has_method("serialize"):
			return eq.serialize()
		result["weapon"] = _item_to_id(eq.get_equipped(EquipmentInventory.SLOT_WEAPON))
		result["armor"] = _item_to_id(eq.get_equipped(EquipmentInventory.SLOT_ARMOR))
		result["trinket"] = _item_to_id(eq.get_equipped(EquipmentInventory.SLOT_TRINKET))
		var bag_ids: Array = []
		for it in eq.bag:
			var item_id := _item_to_id(it)
			if item_id != "":
				bag_ids.append(item_id)
		result["bag"] = bag_ids
	return result


func _item_to_id(item: Variant) -> String:
	if item == null:
		return ""
	if item is String or item is StringName:
		return String(item)
	if "id" in item:
		return String(item.id)
	return ""


## Persist player equipment to save file independently.
func save_equipment(player: Node = null) -> bool:
	if _trial_active():
		return false
	if player == null:
		var tree := get_tree()
		if tree != null:
			var players := tree.get_nodes_in_group("player")
			if not players.is_empty():
				player = players[0]
	if player == null:
		return false
	var equip_state := _collect_equipment(player)
	if data == null:
		data = {}
	data["equipment"] = equip_state
	var cfg := _load_cfg()
	if cfg == null:
		cfg = ConfigFile.new()
		cfg.set_value("meta", "version", SAVE_VERSION)
		cfg.set_value("meta", "saved_at", Time.get_datetime_string_from_system())
	var w_val: Variant = equip_state.get("weapon", "broken_sword")
	cfg.set_value("equipment", "weapon", "" if w_val == null else String(w_val))
	var a_val: Variant = equip_state.get("armor", "broken_armor")
	cfg.set_value("equipment", "armor", "" if a_val == null else String(a_val))
	var t_val: Variant = equip_state.get("trinket", "broken_pendant")
	cfg.set_value("equipment", "trinket", "" if t_val == null else String(t_val))
	var bag_ids: Array = []
	for id_val in equip_state.get("bag", []):
		var id_str := String(id_val).strip_edges()
		if id_str != "":
			bag_ids.append(id_str)
	cfg.set_value("equipment", "bag", bag_ids)
	cfg.set_value("consumed", "paths", Array(consumed))
	cfg.set_value("lit_nests", "paths", Array(lit_nests))
	return _write_cfg(cfg)


func _collect_world() -> Dictionary:
	var world: Dictionary = {}
	for node in get_tree().get_nodes_in_group("persistent"):
		if not node.has_method("get_persistent_state"):
			continue
		var state: Dictionary = node.get_persistent_state()
		var key := persist_path(node)
		if key != "" and not state.is_empty():
			world[key] = state
	return world


## After a respawn, replay stored world state onto the freshly-built scene.
func apply_world(node: Node) -> void:
	if _trial_active():
		return
	if data.is_empty() or not data.has("world"):
		return
	if node == null or not is_instance_valid(node):
		return
	for key in data["world"]:
		var target := resolve_saved_node(node, String(key))
		if target == null or not target.has_method("apply_persistent_state"):
			continue
		target.apply_persistent_state(data["world"][key])


## Relight every recorded Ember Nest even when the world snapshot key is stale.
func apply_lit_nests(node: Node) -> void:
	if _trial_active():
		return
	if node == null or not is_instance_valid(node):
		return
	for p in lit_nests:
		var nest := resolve_saved_node(node, String(p))
		if nest != null and nest.has_method("apply_persistent_state"):
			nest.apply_persistent_state({"lit": true})


## Populate a freshly-instantiated player from the stored save.
func apply_player(player: Node) -> void:
	if _trial_active():
		return
	if player == null or data.is_empty():
		return
	if not data.has("player") and not data.has("equipment"):
		return

	# 1. Apply origin first so base stats are established before equipment calculations
	var o := get_current_origin()
	if player is Player:
		(player as Player).origin = o
		if (player as Player).stats != null:
			if o != &"":
				(player as Player).stats.apply_origin(o)
			else:
				(player as Player).stats.apply_origin(&"")
	elif "origin" in player:
		player.origin = o
		if "stats" in player and player.stats != null and player.stats.has_method("apply_origin"):
			player.stats.apply_origin(o)

	# 外观：读档/重生时把皮肤与刻印重新挂上（player._ready 也读，这里覆盖"同场景读档"）。
	if player is Player:
		(player as Player).apply_skin(StringName(skin_id))
		(player as Player).equip_rune(StringName(skin_rune))

	# 2. Restore equipment so character stats & max HP bonuses update before health clamping
	var eq: EquipmentInventory = null
	if player is Player:
		eq = (player as Player).equipment_inventory
		if eq == null:
			eq = (player as Player).equipment
	if eq == null and player != null:
		if "equipment_inventory" in player and player.equipment_inventory != null:
			eq = player.equipment_inventory
		elif "equipment" in player and player.equipment != null:
			eq = player.equipment
		elif player.has_node("EquipmentInventory"):
			eq = player.get_node("EquipmentInventory") as EquipmentInventory

	if eq != null:
		var equip_data: Dictionary = data.get("equipment", DEFAULT_EQUIPMENT)
		if equip_data.is_empty():
			equip_data = DEFAULT_EQUIPMENT
		if eq.has_method("deserialize"):
			eq.deserialize(equip_data)
		else:
			eq.equipped[EquipmentInventory.SLOT_WEAPON] = EquipmentCatalog.for_id(StringName(equip_data.get("weapon", "")))
			eq.equipped[EquipmentInventory.SLOT_ARMOR] = EquipmentCatalog.for_id(StringName(equip_data.get("armor", "")))
			eq.equipped[EquipmentInventory.SLOT_TRINKET] = EquipmentCatalog.for_id(StringName(equip_data.get("trinket", "")))
			eq.bag.clear()
			for b in equip_data.get("bag", []):
				var it = EquipmentCatalog.for_id(StringName(b))
				if it != null and eq.bag.size() < EquipmentInventory.MAX_BAG_CAPACITY:
					eq.bag.append(it)
			eq.equipment_changed.emit()
			if eq.has_signal("bag_changed"):
				eq.bag_changed.emit()

	# 2. Restore health & toxin
	if data.has("player"):
		var p: Dictionary = data["player"]
		var hp := player.get_node_or_null("Health") as Health
		if hp:
			if player is Player and (player as Player).stats != null:
				hp.max_hp = (player as Player).stats.get_effective_max_hp()
			else:
				hp.max_hp = int(p.get("max_hp", hp.max_hp))
			if entering_from_checkpoint:
				hp.current = hp.max_hp
			else:
				hp.current = clampi(int(p.get("hp", hp.max_hp)), 0, hp.max_hp)
			hp.changed.emit(hp.current, hp.max_hp)
		var tox := player.get_node_or_null("ToxinMeter") as ToxinMeter
		if tox:
			if entering_from_checkpoint:
				tox.toxin = 0.0
			else:
				tox.toxin = clampf(float(p.get("toxin", 0.0)), 0.0, tox.max_toxin)
			GameEvents.toxin_changed.emit(tox.toxin, tox.max_toxin)
		entering_from_checkpoint = false
		if player is Player:
			var face := int(p.get("facing", 1))
			if face == 0:
				face = 1
			(player as Player).controller.facing = face
			(player as Player).visual.scale.x = float(face)
			var inv := (player as Player).inventory
			inv.pouch.clear()
			inv.sockets.clear()
			for i in inv.socket_count:
				inv.sockets.append(null)
			for id_str in p.get("pouch", []):
				var core := AbilityCatalog.for_id(StringName(id_str))
				if core:
					inv.pouch.append(core)
			var sockets: Array = p.get("sockets", [])
			for i in mini(sockets.size(), inv.socket_count):
				var id_str: String = sockets[i]
				if id_str == "":
					continue
				var core := AbilityCatalog.for_id(StringName(id_str))
				if core:
					inv.sockets[i] = core
			inv.sockets_changed.emit()
			inv.pouch_changed.emit()


## Record the scene we should boot into and the spawn point, then reload there.
func respawn(scene_path: String, spawn: Vector2) -> void:
	if _trial_active():
		return
	pending_spawn = spawn
	entering_from_checkpoint = true
	checkpoint_notice_pending = true
	Director.fade_to(scene_path)


func consume_pending_spawn() -> Vector2:
	var v := pending_spawn
	pending_spawn = Vector2.INF
	return v


func has_pending_spawn() -> bool:
	return pending_spawn != Vector2.INF


## Scene-relative path so a renamed root or test host still remaps on load.
func persist_path(node: Node) -> String:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return ""
	return _normalize_saved_path(String(node.get_path()))


func resolve_saved_node(root: Node, saved_path: String) -> Node:
	if root == null or not is_instance_valid(root) or saved_path == "":
		return null
	saved_path = saved_path.strip_edges()
	# Level namespace: "level02:Props/Door" only resolves inside level02, and a
	# bare Level01 path never resolves inside another level.
	var expected := _level_prefix_for(root)
	var colon := saved_path.find(":")
	if colon > 0 and not saved_path.begins_with("/"):
		if saved_path.substr(0, colon + 1) != expected:
			return null
		saved_path = saved_path.substr(colon + 1)
	elif expected != "":
		return null
	if saved_path == ".":
		return root
	# Walk by each `/` name. Do not feed the raw string to get_node — test
	# hosts (and some Godot NodePaths) put `.` in a node name; the parser
	# treats `.` as "current", so `/root/.../save_test.test_foo/...` misses.
	var parts := _path_parts(saved_path)
	var found := _walk_parts(root, parts)
	if found != null:
		return found
	if root.is_inside_tree():
		found = _walk_parts(root.get_tree().root, parts)
		if found != null:
			return found
	for i in range(parts.size()):
		found = _walk_parts(root, parts.slice(i, parts.size()))
		if found != null:
			return found
	if parts.is_empty():
		return null
	var leaf := String(parts[parts.size() - 1])
	var hits: Array[Node] = []
	_collect_named(root, leaf, hits)
	return hits[0] if hits.size() == 1 else null


func _path_parts(path: String) -> PackedStringArray:
	var parts: PackedStringArray = []
	var skipped_viewport := false
	for p in path.split("/"):
		if p == "" or p == ".":
			continue
		if not skipped_viewport and p == "root":
			skipped_viewport = true
			continue
		skipped_viewport = true
		parts.append(p)
	return parts


func _walk_parts(from: Node, parts: PackedStringArray) -> Node:
	if from == null or not is_instance_valid(from):
		return null
	var node := from
	for part in parts:
		if part == "..":
			node = node.get_parent()
			if node == null:
				return null
			continue
		node = _child_named(node, String(part))
		if node == null:
			return null
	return node


func _child_named(parent: Node, child_name: String) -> Node:
	for child in parent.get_children():
		if String(child.name) == child_name:
			return child
	return null


func _normalize_saved_path(path: String) -> String:
	if path == "" or path == ".":
		return path
	if not is_inside_tree():
		return path
	var scene := GameContext.world_root()
	if scene == null or not scene.is_inside_tree():
		scene = get_tree().current_scene
	if scene == null or not scene.is_inside_tree():
		return path
	var root := String(scene.get_path())
	if path == root:
		return "."
	if path.begins_with(root + "/"):
		return _level_prefix_for(scene) + path.substr(root.length() + 1)
	return path


## "level02:" for levels registered after Level01, "" otherwise (Level01 keeps
## the bare paths older saves already contain).
func _level_prefix_for(scene: Node) -> String:
	if scene == null or not is_instance_valid(scene):
		return ""
	var id := GameContext.level_id(String(scene.scene_file_path))
	return id + ":" if id != "" else ""


## Scene recorded by the last save, or `fallback` when it is not a known level.
func saved_scene(fallback: String = GameContext.WORLD_PATH) -> String:
	var meta: Dictionary = data.get("meta", {})
	var scene := String(meta.get("scene", ""))
	return scene if GameContext.is_world_scene(scene) else fallback


func _collect_named(node: Node, leaf: String, hits: Array[Node]) -> void:
	if String(node.name) == leaf:
		hits.append(node)
	for child in node.get_children():
		_collect_named(child, leaf, hits)


func _backup_path() -> String:
	return save_path + ".bak"


func _tmp_path() -> String:
	return save_path + ".tmp"


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _cfg_is_usable(cfg: ConfigFile) -> bool:
	return cfg.has_section("player") or cfg.has_section("meta") or cfg.has_section("equipment")


func _load_cfg() -> ConfigFile:
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(save_path) and cfg.load(save_path) == OK and _cfg_is_usable(cfg):
		return cfg
	var bak := _backup_path()
	var bak_cfg := ConfigFile.new()
	if FileAccess.file_exists(bak) and bak_cfg.load(bak) == OK and _cfg_is_usable(bak_cfg):
		bak_cfg.save(save_path)
		return bak_cfg
	return null


func _write_cfg(cfg: ConfigFile) -> bool:
	# 兜底：试炼会话中任何路径都不许把战役档写盘。
	if _trial_active():
		return false
	var tmp := _tmp_path()
	var err := cfg.save(tmp)
	if err != OK:
		return false
	var had_save := FileAccess.file_exists(save_path)
	if had_save:
		# Never remove the only good copy if its recovery copy cannot be made.
		if DirAccess.copy_absolute(save_path, _backup_path()) != OK:
			_remove_if_exists(tmp)
			return false
		if DirAccess.remove_absolute(save_path) != OK:
			_remove_if_exists(tmp)
			return false
	err = DirAccess.rename_absolute(tmp, save_path)
	if err != OK:
		if had_save:
			DirAccess.copy_absolute(_backup_path(), save_path)
		_remove_if_exists(tmp)
	return err == OK
