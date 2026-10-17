extends Node
## SaveData autoload: persist player + world state to user://rustgrave_save.cfg.
## Pure data — works identically in headless runs. Call save_game(node, player)
## from an Ember Nest; load_game() reads the file back into the dictionary.
##
## World persistence: any node in the "persistent" group exports a snapshot via
## get_persistent_state() and restores it via apply_persistent_state(). The
## save stores that data keyed by a scene-relative path (with a resolver for
## older absolute `/root/...` keys) so a renamed root still remaps.

const SAVE_VERSION := 1

var save_path := "user://rustgrave_save.cfg"

## Currently loaded save dictionary (empty until load_game / save_game).
## Structure:
##   meta      = { version, scene, saved_at }
##   player    = { hp, max_hp, toxin, max_toxin, pos (Vector2), facing }
##   inventory = { pouch: [core ids], sockets: [core ids or ""] }
##   world     = { "Props/Door": {...}, ... }  # scene-relative; old /root keys still resolve
##   atmosphere = { time_of_day (0–1), weather }
var data: Dictionary = {}

## One-shot spawn override consumed by a level right after it instantiates the
## player. Set by respawn flow so the player appears at the last Ember Nest.
var pending_spawn: Vector2 = Vector2.INF
## True from death→fade until the new level finishes try_wake. Survives
## consume_pending_spawn(), unlike pending_spawn itself.
var entering_from_checkpoint: bool = false

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func has_save() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(_backup_path())

## `spawn_override`: where the knight should stand when this save is loaded —
## used by level exits, whose save names the *next* scene while the knight is
## still standing in the old one.
func save_game(scene_path: String, player: Node, spawn_override: Vector2 = Vector2.INF) -> bool:
	var player_state := _collect_player(player)
	if spawn_override != Vector2.INF:
		player_state["pos"] = spawn_override
	var inv_state := _collect_inventory(player)
	player_state["pouch"] = inv_state["pouch"]
	player_state["sockets"] = inv_state["sockets"]
	var world := _collect_world()
	var cfg := ConfigFile.new()
	data = {
		"meta": {
			"version": SAVE_VERSION,
			"scene": scene_path,
			"saved_at": Time.get_datetime_string_from_system(),
		},
		"player": player_state,
		"world": world,
	}
	cfg.set_value("meta", "version", SAVE_VERSION)
	cfg.set_value("meta", "scene", scene_path)
	cfg.set_value("meta", "saved_at", data["meta"]["saved_at"])
	var ps: Dictionary = player_state
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
	for key in world:
		cfg.set_value("world", key, world[key])
	cfg.set_value("consumed", "paths", Array(consumed))
	cfg.set_value("lit_nests", "paths", Array(lit_nests))
	cfg.set_value("story", "flags", Array(flags))
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
	data["player"] = {
		"hp": cfg.get_value("player", "hp", 0),
		"max_hp": cfg.get_value("player", "max_hp", 5),
		"toxin": cfg.get_value("player", "toxin", 0.0),
		"max_toxin": cfg.get_value("player", "max_toxin", 100.0),
		"pos": Vector2(cfg.get_value("player", "pos_x", 0.0), cfg.get_value("player", "pos_y", 0.0)),
		"facing": cfg.get_value("player", "facing", 1),
		"pouch": cfg.get_value("player", "pouch", []),
		"sockets": cfg.get_value("player", "sockets", []),
	}
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
	var atmosphere := {
		"time_of_day": float(cfg.get_value("atmosphere", "time_of_day", WorldClock.DEFAULT_TIME)),
		"weather": String(cfg.get_value("atmosphere", "weather", "haze")),
		"zone": String(cfg.get_value("atmosphere", "zone", "outdoors")),
		"wind_heading": float(cfg.get_value("atmosphere", "wind_heading", -1.0)),
	}
	data["atmosphere"] = atmosphere
	WorldClock.apply_snapshot(atmosphere)
	return true


func delete_save() -> void:
	_remove_if_exists(save_path)
	_remove_if_exists(_backup_path())
	_remove_if_exists(_tmp_path())
	data = {}
	consumed.clear()
	lit_nests.clear()
	flags.clear()
	ending = ""
	pending_spawn = Vector2.INF
	entering_from_checkpoint = false
	WorldClock.reset()


## Record that a one-shot interactable at `path` has been consumed (picked up,
## used, melted). Survives node free because it's a plain path list.
func mark_consumed(path: String) -> void:
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
	if node == null or not is_instance_valid(node):
		return
	for p in consumed:
		var target := resolve_saved_node(node, String(p))
		if target != null and is_instance_valid(target):
			target.queue_free()


func register_lit_nest(path: String) -> void:
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
	if not flags.has(id):
		flags.append(id)


func has_flag(id: String) -> bool:
	return flags.has(id)


## Write flags + ending onto an existing save without needing a live player.
## Used after Boss kill so a nest-respawn load_game() cannot revive the Executioner.
## Also flushes consumed / lit_nests so a story write cannot drop later pickups.
func persist_story() -> void:
	var cfg := _load_cfg()
	if cfg == null:
		return
	cfg.set_value("story", "flags", Array(flags))
	cfg.set_value("meta", "ending", ending)
	cfg.set_value("consumed", "paths", Array(consumed))
	cfg.set_value("lit_nests", "paths", Array(lit_nests))
	_write_cfg(cfg)


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
	if node == null or not is_instance_valid(node):
		return
	for p in lit_nests:
		var nest := resolve_saved_node(node, String(p))
		if nest != null and nest.has_method("apply_persistent_state"):
			nest.apply_persistent_state({"lit": true})


## Populate a freshly-instantiated player from the stored save.
func apply_player(player: Node) -> void:
	if player == null or data.is_empty() or not data.has("player"):
		return
	var p: Dictionary = data["player"]
	var hp := player.get_node_or_null("Health") as Health
	if hp:
		hp.max_hp = int(p.get("max_hp", hp.max_hp))
		hp.current = clampi(int(p.get("hp", hp.max_hp)), 0, hp.max_hp)
		hp.changed.emit(hp.current, hp.max_hp)
	var tox := player.get_node_or_null("ToxinMeter") as ToxinMeter
	if tox:
		tox.toxin = clampf(float(p.get("toxin", 0.0)), 0.0, tox.max_toxin)
		GameEvents.toxin_changed.emit(tox.toxin, tox.max_toxin)
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
	pending_spawn = spawn
	entering_from_checkpoint = true
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
	return cfg.has_section("player") or cfg.has_section("meta")


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
	var tmp := _tmp_path()
	var err := cfg.save(tmp)
	if err != OK:
		return false
	if FileAccess.file_exists(save_path):
		DirAccess.copy_absolute(save_path, _backup_path())
		DirAccess.remove_absolute(save_path)
	err = DirAccess.rename_absolute(tmp, save_path)
	if err != OK:
		err = cfg.save(save_path)
		_remove_if_exists(tmp)
	return err == OK
