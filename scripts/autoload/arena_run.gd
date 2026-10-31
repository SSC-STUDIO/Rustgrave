extends Node
## 3v3 推线对局（Autoload ArenaRun）。
## 阶段 IDLE / LOBBY / COUNTDOWN / PLAYING / RESULT。不写战役档。
## 对外接口见 docs/arena-mode.md「UI 接口」。标题仍调用 start()。

signal match_finished(result: Dictionary)
signal phase_changed(phase: String)
signal kill_feed(entry: Dictionary)
signal tower_destroyed(team: String, index: int)
signal match_restarted
signal blessing_granted(team: String)

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")
const MobaRunScript := preload("res://scripts/moba/moba_run.gd")

static var auto_begin := false
static var shop_ignore_range := false

static var _node: Node = null
static var _active := false
static var _finished := false
static var _phase := ArenaCatalog.PHASE_IDLE
static var _difficulty := ArenaCatalog.DEFAULT_DIFFICULTY
static var _score := 0
static var _score_pad := 0
static var _kills := 0
static var _blue_kills := 0
static var _red_kills := 0
static var _time_left := ArenaCatalog.DURATION
static var _elapsed := 0.0
static var _countdown := ArenaCatalog.COUNTDOWN_SECONDS
static var _last_result: Dictionary = {}
static var _records_path := ArenaCatalog.RECORDS_PATH
static var _roster: Dictionary = {}
static var _structures: Array = []
static var _tags: Array = []
static var _wave_index := 0
static var _wave_wait := ArenaCatalog.FIRST_WAVE_DELAY
static var _queued_wave: Dictionary = {}
static var _bless_player := 0.0
static var _bless_enemy := 0.0
static var _elite_alive := true
static var _elite_left := 0.0
static var _press_until := -1.0
static var _shop_hp := 0
static var _shop_attack := 0
static var _shop_speed := 0.0
static var _strip: CanvasLayer = null
static var _strip_label: Label = null
## 正式界面挂上后为 true，临时文字条藏掉，Enter 不再由这里开战/离场。
static var ui_attached := false
static var _ui_owner: Node = null
static var _compat_seq := 0


func _ready() -> void:
	_node = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not GameEvents.player_died.is_connected(_on_player_died):
		GameEvents.player_died.connect(_on_player_died)
	if not GameEvents.hit.is_connected(_on_hit):
		GameEvents.hit.connect(_on_hit)


func _exit_tree() -> void:
	if _node == self:
		_node = null
	if GameEvents.player_died.is_connected(_on_player_died):
		GameEvents.player_died.disconnect(_on_player_died)
	if GameEvents.hit.is_connected(_on_hit):
		GameEvents.hit.disconnect(_on_hit)


func _process(delta: float) -> void:
	if not _active or _clock_frozen():
		return
	if _phase == ArenaCatalog.PHASE_COUNTDOWN:
		_countdown = maxf(0.0, _countdown - delta)
		if _countdown <= 0.0:
			_enter_playing()
		_refresh_strip()
		return
	if _phase != ArenaCatalog.PHASE_PLAYING:
		return
	_elapsed += delta
	_time_left = maxf(0.0, _time_left - delta)
	if _queued_wave.is_empty():
		_wave_wait -= delta
		if _wave_wait <= 0.0:
			_wave_index += 1
			_queue_wave()
			_wave_wait = ArenaCatalog.WAVE_INTERVAL
	_tick_respawns(delta)
	_tick_blessings(delta)
	_tick_elite(delta)
	_revive_due()
	if _time_left <= 0.0 and _phase == ArenaCatalog.PHASE_PLAYING:
		var outcome := ArenaCatalog.timeout_outcome(
				towers_destroyed_by(ArenaCatalog.TEAM_PLAYER),
				towers_destroyed_by(ArenaCatalog.TEAM_ENEMY),
				_blue_kills, _red_kills)
		finish_match(outcome, "timeout")
	_refresh_strip()


func _unhandled_input(event: InputEvent) -> void:
	# 正式界面自己接 Enter / Esc，避免和大厅、结算菜单抢键。
	if ui_attached:
		return
	if not _active or _clock_frozen():
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var code := key.keycode
	if code == KEY_NONE:
		code = key.physical_keycode
	if code != KEY_ENTER and code != KEY_KP_ENTER:
		return
	if _phase == ArenaCatalog.PHASE_LOBBY:
		begin_match()
	elif _phase == ArenaCatalog.PHASE_RESULT:
		exit_to_title()
	else:
		return
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()


func _on_player_died() -> void:
	if not _active:
		return
	if _phase == ArenaCatalog.PHASE_LOBBY:
		_mark_hero_down("player")
		if _roster.has("player"):
			var held: Dictionary = _roster["player"]
			held["respawn"] = 0.0
		return
	if _phase != ArenaCatalog.PHASE_PLAYING and _phase != ArenaCatalog.PHASE_COUNTDOWN:
		return
	if _phase != ArenaCatalog.PHASE_PLAYING:
		_mark_hero_down("player")
		return
	var killer := _latest_tag("player")
	report_death({
		"killer_id": killer,
		"victim_id": "player",
		"victim_team": ArenaCatalog.TEAM_PLAYER,
		"victim_kind": "hero",
		"victim_label": "余烬骑士",
		"xp": int(ArenaCatalog.unit_stat("hero").get("xp", 28)),
		"ember": int(ArenaCatalog.unit_stat("hero").get("ember", 16)),
	})


func _on_hit(attacker: Node, target: Node, _amount: int) -> void:
	if not running():
		return
	if target != null and (target is Player or target.is_in_group("player")):
		note_tag("player", attacker_id(attacker))


# --------------------------------------------------------------- lifecycle --

static func start() -> bool:
	if _node == null or not is_instance_valid(_node):
		return false
	if MobaRunScript.active():
		return false
	# Keep the established title/recap entry API while retiring the 2.5D mode.
	# Do not seed its roster, timer, lobby or presentation viewport.
	abandon()
	return MobaRunScript.start()


static func activate_for_test() -> void:
	_boot()
	if auto_begin:
		_enter_playing()
	else:
		_set_phase(ArenaCatalog.PHASE_LOBBY)
	_ensure_strip()
	_refresh_strip()


static func begin() -> void:
	if not _active:
		_boot()
		_set_phase(ArenaCatalog.PHASE_LOBBY)
	_ensure_strip()
	_refresh_strip()


static func begin_match() -> void:
	if not _active:
		return
	if _phase != ArenaCatalog.PHASE_LOBBY:
		return
	_countdown = ArenaCatalog.COUNTDOWN_SECONDS
	_set_phase(ArenaCatalog.PHASE_COUNTDOWN)


static func restart_match() -> void:
	var diff := _difficulty
	_boot()
	_difficulty = diff
	_active = true
	_set_phase(ArenaCatalog.PHASE_LOBBY)
	_emit("match_restarted")
	begin_match()


static func active() -> bool:
	return _active


static func running() -> bool:
	return _active and _phase == ArenaCatalog.PHASE_PLAYING and not _finished


static func allows_combat() -> bool:
	return running() and not _clock_frozen()


static func phase() -> String:
	return _phase


static func difficulty_id() -> String:
	return _difficulty


static func set_difficulty(id: String) -> bool:
	if not ArenaCatalog.DIFFICULTY_ORDER.has(id):
		return false
	if _active and _phase != ArenaCatalog.PHASE_LOBBY and _phase != ArenaCatalog.PHASE_IDLE:
		return false
	_difficulty = id
	_refresh_strip()
	return true


static func score() -> int:
	return _score


static func add_kill(points: int = 0) -> void:
	if not running():
		return
	_compat_seq += 1
	report_death({
		"killer_id": "player",
		"victim_id": "compat_%d" % _compat_seq,
		"victim_team": ArenaCatalog.TEAM_ENEMY,
		"victim_kind": "minion",
		"victim_label": "目标",
		"xp": 0,
		"ember": 0,
	})
	_score_pad += maxi(0, points)
	_sync_score(false)


static func time_left() -> float:
	if not _active:
		return ArenaCatalog.DURATION
	return _time_left


static func countdown_left() -> float:
	return _countdown


static func last_result() -> Dictionary:
	return _last_result.duplicate(true)


static func match_result() -> Dictionary:
	return _last_result.duplicate(true)


static func finish(win: bool) -> void:
	finish_match("win" if win else "loss", "finish")


static func finish_match(outcome: String, reason: String) -> void:
	if not _active or _phase == ArenaCatalog.PHASE_RESULT or _phase == ArenaCatalog.PHASE_IDLE:
		return
	_finished = true
	var win_bonus := outcome == "win"
	_sync_score(win_bonus)
	var result := _build_result(outcome, reason)
	var is_new := _write_records(result)
	result["new_record"] = is_new
	_last_result = result.duplicate(true)
	_set_phase(ArenaCatalog.PHASE_RESULT)
	_refresh_strip()
	_emit_result(result)


static func abandon() -> void:
	_clear_player_blessing()
	var was := _active or _phase != ArenaCatalog.PHASE_IDLE
	_active = false
	_finished = false
	_score = 0
	_score_pad = 0
	_kills = 0
	_blue_kills = 0
	_red_kills = 0
	_time_left = ArenaCatalog.DURATION
	_elapsed = 0.0
	_countdown = ArenaCatalog.COUNTDOWN_SECONDS
	_last_result = {}
	_roster = {}
	_structures = []
	_tags = []
	_queued_wave = {}
	_wave_index = 0
	_bless_player = 0.0
	_bless_enemy = 0.0
	_elite_alive = true
	_elite_left = 0.0
	_press_until = -1.0
	_shop_hp = 0
	_shop_attack = 0
	_shop_speed = 0.0
	_clear_screens()
	if was:
		_set_phase(ArenaCatalog.PHASE_IDLE)


static func blocks_campaign_save() -> bool:
	return _active or MobaRunScript.active()


static func exit_to_title() -> void:
	var was := _active
	if _phase == ArenaCatalog.PHASE_RESULT:
		_active = false
		_finished = true
		_clear_screens()
		_set_phase(ArenaCatalog.PHASE_IDLE)
	else:
		abandon()
	if was and _node != null and is_instance_valid(_node):
		Director.fade_to(ArenaCatalog.TITLE_SCENE, 0.5)


# -------------------------------------------------------------------- query --

static func scoreboard() -> Dictionary:
	var blue_crystal := _struct(ArenaCatalog.TEAM_PLAYER, 2)
	var red_crystal := _struct(ArenaCatalog.TEAM_ENEMY, 2)
	return {
		"phase": _phase,
		"difficulty": _difficulty,
		"time_left": time_left(),
		"elapsed": _elapsed,
		"countdown": _countdown,
		"blue": {
			"kills": _blue_kills,
			"towers": towers_destroyed_by(ArenaCatalog.TEAM_PLAYER),
			"crystal_hp": int(blue_crystal.get("hp", 0)),
			"crystal_max": int(blue_crystal.get("max_hp", 0)),
			"blessing": _bless_player,
		},
		"red": {
			"kills": _red_kills,
			"towers": towers_destroyed_by(ArenaCatalog.TEAM_ENEMY),
			"crystal_hp": int(red_crystal.get("hp", 0)),
			"crystal_max": int(red_crystal.get("max_hp", 0)),
			"blessing": _bless_enemy,
		},
		"heroes": _hero_rows(),
	}


static func tower_status() -> Array:
	var out: Array = []
	for raw in _structures:
		if raw is not Dictionary:
			continue
		var row: Dictionary = raw
		var team := String(row.get("team", ""))
		var index := int(row.get("index", 0))
		var alive := bool(row.get("alive", false))
		out.append({
			"team": team,
			"index": index,
			"kind": String(row.get("kind", ArenaCatalog.structure_kind(index))),
			"label": ArenaCatalog.structure_label(index),
			"hp": int(row.get("hp", 0)),
			"max_hp": int(row.get("max_hp", 0)),
			"alive": alive,
			"exposed": structure_vulnerable(team, index) or (alive and index <= 0),
			"x": float(row.get("x", 0.0)),
			"y": float(row.get("y", 0.0)),
		})
	return out


static func minimap_data() -> Dictionary:
	var units: Array = []
	var tree := GameContext.tree()
	if tree != null and _active:
		var knight := tree.get_first_node_in_group("player")
		if knight is Node2D:
			var body := knight as Node2D
			var alive := true
			if knight is Player and (knight as Player).health != null:
				alive = (knight as Player).health.current > 0
			var depth := body.global_position.y
			if knight.has_method(&"arena_depth"):
				depth = float(knight.call(&"arena_depth"))
			units.append({
				"id": "player",
				"team": ArenaCatalog.TEAM_PLAYER,
				"kind": "hero",
				"x": body.global_position.x,
				"y": body.global_position.y,
				"depth": depth,
				"alive": alive,
			})
		for node in tree.get_nodes_in_group("arena_unit"):
			if node != null and node.has_method("minimap_entry"):
				units.append(node.call("minimap_entry"))
	return {
		"lane_left": ArenaCatalog.LANE_LEFT,
		"lane_right": ArenaCatalog.LANE_RIGHT,
		"ground_y": ArenaCatalog.GROUND_Y,
		"depth_back": ArenaCatalog.DEPTH_BACK,
		"depth_front": ArenaCatalog.DEPTH_FRONT,
		"depth_mid": ArenaCatalog.DEPTH_MID,
		"altar": {
			"x": ArenaCatalog.ALTAR_RECT.position.x,
			"y": ArenaCatalog.ALTAR_RECT.position.y,
			"w": ArenaCatalog.ALTAR_RECT.size.x,
			"h": ArenaCatalog.ALTAR_RECT.size.y,
		},
		"units": units,
		"structures": tower_status(),
	}


static func respawn_time_left(unit: Variant = null) -> float:
	var id := _id_of(unit)
	if id == "":
		id = "player"
	var row := _row(id)
	return float(row.get("respawn", 0.0))


static func player_level() -> int:
	return level_of("player")


static func player_xp() -> int:
	return int(_row("player").get("xp", 0))


static func player_ember() -> int:
	return int(_row("player").get("ember", 0))


static func level_of(id: String) -> int:
	return maxi(1, int(_row(id).get("level", 1)))


static func blessing_time_left(team: String) -> float:
	if team == ArenaCatalog.TEAM_ENEMY:
		return _bless_enemy
	if team == ArenaCatalog.TEAM_PLAYER:
		return _bless_player
	return 0.0


static func blessing_multiplier(team: String) -> float:
	if blessing_time_left(team) > 0.0:
		return ArenaCatalog.BLESSING_DAMAGE
	return 1.0


static func player_pressing_hero() -> bool:
	return _press_until >= 0.0 and _elapsed <= _press_until


static func shop_items() -> Array:
	var out: Array = []
	for raw in ArenaCatalog.SHOP:
		if raw is Dictionary:
			out.append((raw as Dictionary).duplicate(true))
	return out


static func buy(item_id: String) -> Dictionary:
	var ember := player_ember()
	if _phase != ArenaCatalog.PHASE_PLAYING:
		return {"ok": false, "reason": "phase", "ember": ember, "item": item_id}
	var item := ArenaCatalog.shop_item(item_id)
	if item.is_empty():
		return {"ok": false, "reason": "unknown", "ember": ember, "item": item_id}
	var cost := int(item.get("cost", 0))
	if ember < cost:
		return {"ok": false, "reason": "ember", "ember": ember, "item": item_id}
	if not shop_ignore_range and not _player_in_fountain():
		return {"ok": false, "reason": "range", "ember": ember, "item": item_id}
	_give_ember("player", -cost)
	_shop_attack += int(item.get("attack", 0))
	_shop_hp += int(item.get("hp", 0))
	_shop_speed += float(item.get("speed", 0.0))
	sync_player_growth()
	return {"ok": true, "reason": "", "ember": player_ember(), "item": item_id}


static func grant_ember(id: String, amount: int) -> void:
	_give_ember(id, amount)


static func take_wave() -> Dictionary:
	if _queued_wave.is_empty():
		return {}
	var out := _queued_wave.duplicate(true)
	_queued_wave = {}
	return out


static func objective_x(team: String) -> float:
	if team == ArenaCatalog.TEAM_NEUTRAL:
		return ArenaCatalog.ELITE_POS.x
	var foe := ArenaCatalog.TEAM_ENEMY if team == ArenaCatalog.TEAM_PLAYER else ArenaCatalog.TEAM_PLAYER
	if structure_alive(foe, 0):
		return ArenaCatalog.structure_anchor(foe, 0).x
	if structure_alive(foe, 1):
		return ArenaCatalog.structure_anchor(foe, 1).x
	return ArenaCatalog.structure_anchor(foe, 2).x


static func structure_alive(team: String, index: int) -> bool:
	var row := _struct(team, index)
	return bool(row.get("alive", false)) and int(row.get("hp", 0)) > 0


static func structure_vulnerable(team: String, index: int) -> bool:
	var outer := structure_alive(team, 0)
	var inner := structure_alive(team, 1)
	var self_alive := true
	if index >= 0:
		self_alive = structure_alive(team, index)
	return ArenaCatalog.exposed(index, outer, inner, self_alive)


static func towers_destroyed_by(side: String) -> int:
	var foe := ArenaCatalog.TEAM_ENEMY if side == ArenaCatalog.TEAM_PLAYER else ArenaCatalog.TEAM_PLAYER
	var n := 0
	if not structure_alive(foe, 0) and not _struct(foe, 0).is_empty():
		n += 1
	if not structure_alive(foe, 1) and not _struct(foe, 1).is_empty():
		n += 1
	return n


# -------------------------------------------------------------------- world --

static func register_combatant(info: Dictionary) -> void:
	var id := String(info.get("id", ""))
	if id == "":
		return
	if not _roster.has(id):
		_roster[id] = _blank_row(id)
	var row: Dictionary = _roster[id]
	row["team"] = String(info.get("team", row.get("team", "")))
	row["kind"] = String(info.get("kind", row.get("kind", "minion")))
	row["label"] = String(info.get("label", row.get("label", id)))
	row["is_player"] = bool(info.get("is_player", row.get("is_player", false)))


static func report_death(info: Dictionary) -> void:
	if not running():
		return
	var victim_id := String(info.get("victim_id", ""))
	var victim_team := String(info.get("victim_team", ""))
	var victim_kind := String(info.get("victim_kind", ""))
	var killer_id := String(info.get("killer_id", ""))
	var xp := int(info.get("xp", 0))
	var ember := int(info.get("ember", 0))
	if victim_team == "" and victim_id != "":
		victim_team = String(_row(victim_id).get("team", ""))
	var killer_team := _team_of(killer_id)
	if victim_kind == "hero":
		_mark_hero_down(victim_id)
	elif victim_kind == "elite":
		_elite_alive = false
		_elite_left = ArenaCatalog.ELITE_RESPAWN
		if killer_team != "":
			grant_blessing(killer_team)
	if victim_kind == "hero" or victim_kind == "minion" or victim_kind == "elite":
		if killer_team == ArenaCatalog.TEAM_PLAYER:
			_blue_kills += 1
		elif killer_team == ArenaCatalog.TEAM_ENEMY:
			_red_kills += 1
	if killer_id != "" and _is_hero_id(killer_id):
		var killer: Dictionary = _row(killer_id)
		if not killer.is_empty():
			killer["kills"] = int(killer.get("kills", 0)) + 1
			if victim_kind == "minion":
				killer["last_hits"] = int(killer.get("last_hits", 0)) + 1
			_give_xp(killer_id, xp)
			_give_ember(killer_id, ember)
	_give_assists(victim_id, killer_id, killer_team, xp)
	var victim_label := String(info.get("victim_label", _row(victim_id).get("label", victim_id)))
	var killer_label := String(_row(killer_id).get("label", killer_id))
	if victim_kind == "minion" and victim_id != "" and not victim_id.begins_with("compat_"):
		_roster.erase(victim_id)
	_sync_score(false)
	var entry := {
		"killer_id": killer_id,
		"killer_label": killer_label,
		"killer_team": killer_team,
		"victim_id": victim_id,
		"victim_label": victim_label,
		"victim_team": victim_team,
		"kind": victim_kind,
	}
	_emit_feed(entry)


static func note_tag(victim_id: String, attacker: String) -> void:
	if victim_id == "" or attacker == "" or victim_id == attacker:
		return
	_tags.append({"v": victim_id, "a": attacker, "t": _elapsed})
	if _tags.size() > 48:
		_tags.pop_front()
	if victim_id != "player" and _is_hero_id(victim_id) and attacker == "player":
		_press_until = _elapsed + 1.5


static func note_structure_state(team: String, index: int, hp: int, killer_id: String) -> void:
	var row := _struct(team, index)
	if row.is_empty():
		return
	row["hp"] = maxi(0, hp)
	if hp <= 0:
		_break_structure(team, index, killer_id)
	else:
		row["alive"] = true


static func apply_structure_damage(team: String, index: int, amount: int, killer_id: String = "") -> int:
	if not running():
		return 0
	if not structure_vulnerable(team, index):
		return 0
	var row := _struct(team, index)
	if row.is_empty():
		return 0
	var hp := int(row.get("hp", 0))
	var dealt := mini(hp, maxi(0, amount))
	hp -= dealt
	row["hp"] = hp
	if hp <= 0:
		_break_structure(team, index, killer_id)
	_mirror_structure(team, index, int(row.get("hp", 0)))
	return dealt


static func attacker_id(node: Node) -> String:
	var cursor: Node = node
	var guard := 0
	var saw_player_box := false
	while cursor != null and guard < 8:
		if cursor is Player or cursor.is_in_group("player"):
			return "player"
		if "owner_id" in cursor:
			var oid := String(cursor.get("owner_id"))
			if oid != "":
				return oid
		if "unit_id" in cursor:
			var uid := String(cursor.get("unit_id"))
			if uid != "":
				return uid
		if cursor is Hitbox and (cursor as Hitbox).team == &"player":
			saw_player_box = true
		cursor = cursor.get_parent()
		guard += 1
	if saw_player_box:
		return "player"
	return ""


static func grant_blessing(team: String) -> void:
	if team == ArenaCatalog.TEAM_PLAYER:
		_bless_player = ArenaCatalog.BLESSING_TIME
		var knight := _find_player()
		if knight != null and knight.stats != null:
			knight.stats.remove_modifier(&"arena_blessing")
			knight.stats.add_modifier(&"arena_blessing", {"attack": 1}, 0.0)
	elif team == ArenaCatalog.TEAM_ENEMY:
		_bless_enemy = ArenaCatalog.BLESSING_TIME
	else:
		return
	_emit_blessing(team)


static func sync_player_growth() -> void:
	var knight := _find_player()
	if knight == null or knight.stats == null or knight.health == null:
		return
	var lv := level_of("player")
	var bonus_hp := ArenaCatalog.hero_hp(lv) - 5 + _shop_hp
	var bonus_atk := maxi(0, ArenaCatalog.hero_damage(lv) - 1 + _shop_attack)
	var before := knight.health.max_hp
	knight.stats.add_modifier(&"arena_growth", {
		"max_hp": bonus_hp,
		"attack": bonus_atk,
	}, 0.0)
	if knight.controller != null:
		knight.controller.max_speed = 108.0 + _shop_speed
	var after := knight.health.max_hp
	if after > before and knight.health.current > 0:
		knight.health.heal(after - before)


# ------------------------------------------------------------------ records --

static func use_file(path: String) -> void:
	_records_path = path


static func use_default_file() -> void:
	_records_path = ArenaCatalog.RECORDS_PATH


static func read_records() -> Dictionary:
	if not FileAccess.file_exists(_records_path):
		return ArenaCatalog.empty_records()
	var cfg := ConfigFile.new()
	if cfg.load(_records_path) != OK:
		return ArenaCatalog.empty_records()
	var raw := {
		"best_score": int(cfg.get_value("meta", "best_score", 0)),
		"best_kills": int(cfg.get_value("meta", "best_kills", 0)),
		"runs": int(cfg.get_value("meta", "runs", 0)),
		"wins": int(cfg.get_value("meta", "wins", 0)),
		"losses": int(cfg.get_value("meta", "losses", 0)),
		"draws": int(cfg.get_value("meta", "draws", 0)),
		"fastest_win": float(cfg.get_value("meta", "fastest_win", 0.0)),
	}
	return ArenaCatalog.migrate_records(raw)


static func _write_records(result: Dictionary) -> bool:
	var records := read_records()
	var prev_score := int(records.get("best_score", 0))
	var prev_kills := int(records.get("best_kills", 0))
	var prev_fast := float(records.get("fastest_win", 0.0))
	var improved := false
	var outcome := String(result.get("outcome", ""))
	var elapsed := float(result.get("elapsed", 0.0))
	var sc := int(result.get("score", 0))
	var pk := int(result.get("kills", 0))
	records["runs"] = int(records.get("runs", 0)) + 1
	if outcome == "win":
		records["wins"] = int(records.get("wins", 0)) + 1
		if elapsed > 0.05 and (prev_fast <= 0.0 or elapsed < prev_fast):
			records["fastest_win"] = elapsed
			improved = true
	elif outcome == "loss":
		records["losses"] = int(records.get("losses", 0)) + 1
	else:
		records["draws"] = int(records.get("draws", 0)) + 1
	if sc > prev_score:
		records["best_score"] = sc
		improved = true
	else:
		records["best_score"] = prev_score
	if pk > prev_kills:
		records["best_kills"] = pk
		improved = true
	else:
		records["best_kills"] = prev_kills
	records["version"] = ArenaCatalog.RECORDS_VERSION
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", ArenaCatalog.RECORDS_VERSION)
	cfg.set_value("meta", "best_score", int(records["best_score"]))
	cfg.set_value("meta", "best_kills", int(records["best_kills"]))
	cfg.set_value("meta", "runs", int(records["runs"]))
	cfg.set_value("meta", "wins", int(records["wins"]))
	cfg.set_value("meta", "losses", int(records["losses"]))
	cfg.set_value("meta", "draws", int(records["draws"]))
	cfg.set_value("meta", "fastest_win", float(records["fastest_win"]))
	cfg.save(_records_path)
	return improved


# ---------------------------------------------------------------------- hud --

static func strip() -> CanvasLayer:
	return _strip


static func strip_text() -> String:
	if _strip_label == null or not is_instance_valid(_strip_label):
		return ""
	return _strip_label.text


static func _ensure_strip() -> void:
	if _strip != null and is_instance_valid(_strip):
		return
	if _node == null or not _node.is_inside_tree():
		return
	var host := GameContext.ui_host()
	if host == null:
		host = _node.get_tree().root
	_strip = CanvasLayer.new()
	_strip.name = "ArenaHud"
	_strip.layer = 14
	_strip.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(_strip)
	PresentationMetrics.bind_layer(_strip)
	WorldClock.isolate_ui_layer(_strip)
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.extras_theme()
	_strip.add_child(root)
	var plate := UiKit.panel(&"HudPlate")
	plate.name = "Plate"
	plate.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	plate.offset_left = -440
	plate.offset_top = 8
	plate.offset_right = -8
	plate.offset_bottom = 52
	plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(plate)
	_strip_label = UiKit.label("", &"TinyStrongLabel", HORIZONTAL_ALIGNMENT_RIGHT)
	_strip_label.name = "Text"
	_strip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_strip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(_strip_label)


static func set_ui_attached(on: bool, owner: Node = null) -> void:
	if on:
		ui_attached = true
		_ui_owner = owner
		_refresh_strip()
		return
	if owner != null and _ui_owner != null and owner != _ui_owner:
		return
	ui_attached = false
	_ui_owner = null
	_refresh_strip()


static func _refresh_strip() -> void:
	if _strip_label == null or not is_instance_valid(_strip_label):
		return
	if ui_attached:
		_strip_label.text = ""
		if _strip != null and is_instance_valid(_strip):
			_strip.visible = false
		return
	if _strip != null and is_instance_valid(_strip):
		_strip.visible = true
	if _phase == ArenaCatalog.PHASE_LOBBY:
		_strip_label.text = "按 Enter 开战"
	elif _phase == ArenaCatalog.PHASE_COUNTDOWN:
		_strip_label.text = "开战 %d" % maxi(1, int(ceil(_countdown)))
	elif _phase == ArenaCatalog.PHASE_RESULT:
		_strip_label.text = "%s  ·  Enter 返回标题" % ArenaCatalog.result_summary(_last_result)
	elif _phase == ArenaCatalog.PHASE_PLAYING:
		_strip_label.text = "灰卫 %d塔 %d杀 · 锈誓 %d塔 %d杀 · %s" % [
			towers_destroyed_by(ArenaCatalog.TEAM_PLAYER), _blue_kills,
			towers_destroyed_by(ArenaCatalog.TEAM_ENEMY), _red_kills,
			ArenaCatalog.format_time(_time_left),
		]
	else:
		_strip_label.text = ""


static func _clear_screens() -> void:
	if _strip != null and is_instance_valid(_strip):
		_strip.queue_free()
	_strip = null
	_strip_label = null
	if _node != null and _node.is_inside_tree():
		var host := GameContext.ui_host()
		if host != null:
			var old := host.get_node_or_null("ArenaResult")
			if old != null:
				old.queue_free()


# -------------------------------------------------------------------- internals

static func _clear_player_blessing() -> void:
	var knight := _find_player()
	if knight != null and knight.stats != null:
		knight.stats.remove_modifier(&"arena_blessing")


static func _boot() -> void:
	_clear_player_blessing()
	_active = true
	_finished = false
	_score = 0
	_score_pad = 0
	_kills = 0
	_blue_kills = 0
	_red_kills = 0
	_time_left = ArenaCatalog.DURATION
	_elapsed = 0.0
	_countdown = ArenaCatalog.COUNTDOWN_SECONDS
	_last_result = {}
	_roster = {}
	_tags = []
	_queued_wave = {}
	_wave_index = 0
	_wave_wait = ArenaCatalog.FIRST_WAVE_DELAY
	_bless_player = 0.0
	_bless_enemy = 0.0
	_elite_alive = true
	_elite_left = 0.0
	_press_until = -1.0
	_shop_hp = 0
	_shop_attack = 0
	_shop_speed = 0.0
	_seed_roster()
	_structures = _make_structures()
	_sync_score(false)


static func _enter_playing() -> void:
	_finished = false
	_time_left = ArenaCatalog.DURATION
	_elapsed = 0.0
	_wave_index = 0
	_wave_wait = ArenaCatalog.FIRST_WAVE_DELAY
	_queued_wave = {}
	_set_phase(ArenaCatalog.PHASE_PLAYING)
	sync_player_growth()
	_revive_due()


static func _seed_roster() -> void:
	_roster["player"] = _blank_row("player")
	var player_row: Dictionary = _roster["player"]
	player_row["team"] = ArenaCatalog.TEAM_PLAYER
	player_row["kind"] = "hero"
	player_row["label"] = "余烬骑士"
	player_row["is_player"] = true
	for raw in ArenaCatalog.HERO_ROSTER:
		if raw is not Dictionary:
			continue
		var hero: Dictionary = raw
		var id := String(hero.get("id", ""))
		if id == "":
			continue
		_roster[id] = _blank_row(id)
		var row: Dictionary = _roster[id]
		row["team"] = String(hero.get("team", ""))
		row["kind"] = "hero"
		row["label"] = String(hero.get("label", id))
		row["is_player"] = false


static func _blank_row(id: String) -> Dictionary:
	return {
		"id": id,
		"team": "",
		"kind": "minion",
		"label": id,
		"is_player": false,
		"kills": 0,
		"deaths": 0,
		"assists": 0,
		"last_hits": 0,
		"towers": 0,
		"level": 1,
		"xp": 0,
		"ember": 0,
		"alive": true,
		"respawn": 0.0,
	}


static func _make_structures() -> Array:
	var out: Array = []
	for team in [ArenaCatalog.TEAM_PLAYER, ArenaCatalog.TEAM_ENEMY]:
		for index in [0, 1, 2]:
			var role := "crystal" if index == 2 else "tower"
			var stat := ArenaCatalog.unit_stat(role)
			var hp := int(stat.get("hp", 1))
			var anchor := ArenaCatalog.structure_anchor(team, index)
			out.append({
				"team": team,
				"index": index,
				"kind": ArenaCatalog.structure_kind(index),
				"hp": hp,
				"max_hp": hp,
				"alive": true,
				"x": anchor.x,
				"y": anchor.y,
			})
	return out


static func _queue_wave() -> void:
	var kinds: Array = []
	var packed: PackedStringArray = ArenaCatalog.wave_kinds(_wave_index)
	for kind in packed:
		kinds.append(String(kind))
	_queued_wave = {"index": _wave_index, "kinds": kinds}


static func _tick_respawns(delta: float) -> void:
	var ids: Array = _roster.keys()
	for id_v in ids:
		var id := String(id_v)
		var row: Dictionary = _roster[id]
		var left := float(row.get("respawn", 0.0))
		if left > 0.0:
			row["respawn"] = maxf(0.0, left - delta)


static func _tick_blessings(delta: float) -> void:
	if _bless_player > 0.0:
		_bless_player = maxf(0.0, _bless_player - delta)
		if _bless_player <= 0.0:
			var knight := _find_player()
			if knight != null and knight.stats != null:
				knight.stats.remove_modifier(&"arena_blessing")
	if _bless_enemy > 0.0:
		_bless_enemy = maxf(0.0, _bless_enemy - delta)


static func _tick_elite(delta: float) -> void:
	if not _elite_alive:
		_elite_left = maxf(0.0, _elite_left - delta)
		if _elite_left <= 0.0:
			_elite_alive = true
	if not _elite_alive:
		return
	var node := _find_unit("elite")
	if node != null and not bool(node.get("alive")):
		node.call("arena_revive", ArenaCatalog.ELITE_POS)


static func _revive_due() -> void:
	var ids: Array = _roster.keys()
	for id_v in ids:
		var id := String(id_v)
		var row: Dictionary = _roster[id]
		if bool(row.get("alive", true)):
			continue
		if float(row.get("respawn", 0.0)) > 0.0:
			continue
		if String(row.get("kind", "")) != "hero" and not bool(row.get("is_player", false)):
			continue
		row["alive"] = true
		row["respawn"] = 0.0
		var team := String(row.get("team", ArenaCatalog.TEAM_PLAYER))
		var at := ArenaCatalog.fountain_for(team)
		if id == "player" or bool(row.get("is_player", false)):
			var knight := _find_player()
			if knight != null and knight.has_method("arena_respawn"):
				knight.arena_respawn(at)
			continue
		var node := _find_unit(id)
		if node == null:
			continue
		var slot := int(node.get("slot"))
		var face := 1.0 if team == ArenaCatalog.TEAM_PLAYER else -1.0
		at.x += float(slot) * 12.0 * face
		if node.has_method("arena_revive"):
			node.call("arena_revive", at)


static func _mark_hero_down(id: String) -> void:
	if id == "":
		return
	if not _roster.has(id):
		_roster[id] = _blank_row(id)
		var created: Dictionary = _roster[id]
		created["kind"] = "hero"
		if id == "player":
			created["team"] = ArenaCatalog.TEAM_PLAYER
			created["label"] = "余烬骑士"
			created["is_player"] = true
	var row: Dictionary = _roster[id]
	if not bool(row.get("alive", true)) and float(row.get("respawn", 0.0)) > 0.0:
		return
	row["kind"] = "hero"
	row["alive"] = false
	row["deaths"] = int(row.get("deaths", 0)) + 1
	var lv := int(row.get("level", 1))
	row["respawn"] = ArenaCatalog.respawn_seconds(lv, _difficulty)


static func _break_structure(team: String, index: int, killer_id: String) -> void:
	var row := _struct(team, index)
	if row.is_empty() or not bool(row.get("alive", false)):
		return
	row["alive"] = false
	row["hp"] = 0
	_emit_tower(team, index)
	if _is_hero_id(killer_id):
		var stat := ArenaCatalog.unit_stat("crystal" if index >= 2 else "tower")
		var killer: Dictionary = _row(killer_id)
		if not killer.is_empty():
			killer["towers"] = int(killer.get("towers", 0)) + 1
			_give_xp(killer_id, int(stat.get("xp", 0)))
			_give_ember(killer_id, int(stat.get("ember", 0)))
	_sync_score(false)
	if index >= 2 and _phase == ArenaCatalog.PHASE_PLAYING:
		var outcome := "win" if team == ArenaCatalog.TEAM_ENEMY else "loss"
		finish_match(outcome, "crystal")


static func _mirror_structure(team: String, index: int, hp: int) -> void:
	var tree := GameContext.tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("arena_unit"):
		if String(node.get("team")) != team:
			continue
		if int(node.get("structure_index")) != index:
			continue
		if node.has_method("mirror_hp"):
			node.call("mirror_hp", hp)
		return


static func _give_xp(id: String, amount: int) -> void:
	if amount == 0 or not _is_hero_id(id):
		return
	var row: Dictionary = _row(id)
	if row.is_empty():
		return
	if amount < 0:
		return
	row["xp"] = int(row.get("xp", 0)) + amount
	var guard := 0
	while guard < ArenaCatalog.MAX_LEVEL:
		guard += 1
		var lv := int(row.get("level", 1))
		var need := ArenaCatalog.xp_needed(lv)
		if need <= 0 or int(row.get("xp", 0)) < need:
			break
		row["xp"] = int(row.get("xp", 0)) - need
		row["level"] = lv + 1
	var node := _find_unit(id)
	if node != null and node.has_method("apply_growth"):
		node.call("apply_growth", int(row.get("level", 1)))
	if id == "player":
		sync_player_growth()


static func _give_ember(id: String, amount: int) -> void:
	if amount == 0 or id == "":
		return
	var row: Dictionary = _row(id)
	if row.is_empty():
		return
	row["ember"] = maxi(0, int(row.get("ember", 0)) + amount)


static func _give_assists(victim_id: String, killer_id: String, killer_team: String, xp: int) -> void:
	if killer_team == "" or victim_id == "":
		return
	var seen: Dictionary = {}
	for raw in _tags:
		if raw is not Dictionary:
			continue
		var tag: Dictionary = raw
		if String(tag.get("v", "")) != victim_id:
			continue
		if _elapsed - float(tag.get("t", 0.0)) > ArenaCatalog.ASSIST_WINDOW:
			continue
		var aid := String(tag.get("a", ""))
		if aid == "" or aid == killer_id or seen.has(aid):
			continue
		if _team_of(aid) != killer_team or not _is_hero_id(aid):
			continue
		seen[aid] = true
		var row: Dictionary = _row(aid)
		if row.is_empty():
			continue
		row["assists"] = int(row.get("assists", 0)) + 1
		if xp > 1:
			_give_xp(aid, maxi(1, int(xp / 2.0)))


static func _latest_tag(victim_id: String) -> String:
	var best_t := -1.0
	var best := ""
	for raw in _tags:
		if raw is not Dictionary:
			continue
		var tag: Dictionary = raw
		if String(tag.get("v", "")) != victim_id:
			continue
		var at := float(tag.get("t", 0.0))
		if at >= best_t:
			best_t = at
			best = String(tag.get("a", ""))
	return best


static func _is_hero_id(id: String) -> bool:
	if id == "":
		return false
	var row := _row(id)
	if row.is_empty():
		return false
	return String(row.get("kind", "")) == "hero" or bool(row.get("is_player", false))


static func _team_of(id: String) -> String:
	if id == "player":
		return ArenaCatalog.TEAM_PLAYER
	return String(_row(id).get("team", ""))


static func _row(id: String) -> Dictionary:
	if id != "" and _roster.has(id):
		return _roster[id]
	return {}


static func _struct(team: String, index: int) -> Dictionary:
	for raw in _structures:
		if raw is not Dictionary:
			continue
		var row: Dictionary = raw
		if String(row.get("team", "")) == team and int(row.get("index", -1)) == index:
			return row
	return {}


static func _hero_rows() -> Array:
	var out: Array = []
	var ids: Array = _roster.keys()
	ids.sort()
	for id_v in ids:
		var id := String(id_v)
		var row: Dictionary = _roster[id]
		if String(row.get("kind", "")) != "hero" and not bool(row.get("is_player", false)):
			continue
		out.append(row.duplicate(true))
	return out


static func _build_result(outcome: String, reason: String) -> Dictionary:
	var heroes: Array = _hero_rows()
	var mvp := _pick_mvp(heroes)
	var player_row := _row("player")
	return {
		"outcome": outcome,
		"win": outcome == "win",
		"draw": outcome == "draw",
		"reason": reason,
		"duration": _elapsed,
		"elapsed": _elapsed,
		"time_left": _time_left,
		"score": _score,
		"kills": int(player_row.get("kills", _kills)),
		"blue_kills": _blue_kills,
		"red_kills": _red_kills,
		"blue_towers": towers_destroyed_by(ArenaCatalog.TEAM_PLAYER),
		"red_towers": towers_destroyed_by(ArenaCatalog.TEAM_ENEMY),
		"player": player_row.duplicate(true),
		"heroes": heroes,
		"mvp": mvp,
		"new_record": false,
		"difficulty": _difficulty,
	}


static func _pick_mvp(heroes: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -1
	for raw in heroes:
		if raw is not Dictionary:
			continue
		var row: Dictionary = raw
		var value := int(row.get("kills", 0)) * 3 + int(row.get("assists", 0)) + int(row.get("towers", 0))
		if value > best_score:
			best_score = value
			best = {
				"id": String(row.get("id", "")),
				"label": String(row.get("label", "")),
				"team": String(row.get("team", "")),
				"kills": int(row.get("kills", 0)),
				"assists": int(row.get("assists", 0)),
				"towers": int(row.get("towers", 0)),
			}
	return best


static func _sync_score(win_bonus: bool) -> void:
	var bonus := 100 if win_bonus else 0
	_kills = int(_row("player").get("kills", 0))
	_score = _kills * 10 + towers_destroyed_by(ArenaCatalog.TEAM_PLAYER) * 25 + bonus + _score_pad


static func _player_in_fountain() -> bool:
	var knight := _find_player()
	if knight == null:
		return false
	return ArenaCatalog.near_fountain(knight.global_position, ArenaCatalog.fountain_for(ArenaCatalog.TEAM_PLAYER))


static func _find_player() -> Player:
	var tree := GameContext.tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("player") as Player


static func _find_unit(id: String) -> Node:
	var tree := GameContext.tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("arena_unit"):
		if String(node.get("unit_id")) == id:
			return node
	return null


static func _id_of(unit: Variant) -> String:
	if unit == null:
		return "player"
	if unit is String:
		return String(unit)
	if unit is Node:
		var node := unit as Node
		if node.is_in_group("player"):
			return "player"
		if "unit_id" in node:
			return String(node.get("unit_id"))
	return ""


static func _clock_frozen() -> bool:
	var tree := GameContext.tree()
	if tree != null and tree.paused:
		return true
	return Director.is_suspended()


static func _set_phase(next: String) -> void:
	if _phase == next:
		return
	_phase = next
	if _node != null and is_instance_valid(_node):
		_node.emit_signal("phase_changed", next)
	_refresh_strip()


static func _emit(sig: String) -> void:
	if _node != null and is_instance_valid(_node):
		_node.emit_signal(sig)


static func _emit_result(result: Dictionary) -> void:
	if _node != null and is_instance_valid(_node):
		_node.emit_signal("match_finished", result)


static func _emit_feed(entry: Dictionary) -> void:
	if _node != null and is_instance_valid(_node):
		_node.emit_signal("kill_feed", entry)


static func _emit_tower(team: String, index: int) -> void:
	if _node != null and is_instance_valid(_node):
		_node.emit_signal("tower_destroyed", team, index)


static func _emit_blessing(team: String) -> void:
	if _node != null and is_instance_valid(_node):
		_node.emit_signal("blessing_granted", team)
