extends Node2D
## 3v3 场馆。胜负、波次和复活由 ArenaRun 管；这里只搭地图、出生单位、放行镜头。
## 赛前单位冻结（玩家 cutscene_locked）。Enter 由 ArenaRun 接。正式 HUD 之后替换条带。

const PlayerScene := preload("res://scenes/player/Player.tscn")
const CameraScene := preload("res://scenes/camera/GameCamera.tscn")
const HudScene := preload("res://scenes/ui/HUD.tscn")
const PlatformScene := preload("res://scenes/world/Platform.tscn")
const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")
const UnitScript := preload("res://scripts/arena/arena_unit.gd")
const MinionScript := preload("res://scripts/arena/arena_minion.gd")
const HeroScript := preload("res://scripts/arena/arena_hero.gd")
const TowerScript := preload("res://scripts/arena/arena_tower.gd")
const CrystalScript := preload("res://scripts/arena/arena_crystal.gd")
const FountainScript := preload("res://scripts/arena/arena_fountain.gd")
const StageScript := preload("res://scripts/levels/arena_stage.gd")
const ShadowScript := preload("res://scripts/arena/arena_shadow.gd")
const DestructiblePropScene := preload("res://scenes/interactables/DestructibleProp.tscn")

## 观礼矮墙顶（arena_stage.WALL_TOP = 226）的装饰可破坏物脚点，左右镜像。
## 226 在纵深带（DEPTH_BACK 252 .. DEPTH_FRONT 328）之外：ArenaRun.active 时
## Hurtbox 的深度过滤按脚底深度差否决——近战差 26 > 容差 16 永远够不到；
## 弹丸容差 30，只有贴着后缘 4px 内起手的流弹理论上够得着，实战中打不到墙顶。
const SPECTATOR_WEST_FEET := Vector2(620, 226)
const SPECTATOR_EAST_FEET := Vector2(3220, 226)

var _player: Player
var _cam: GameCamera
var _focus: Node2D
var camera_driver := true
var _player_heal := 0.0
var _sweep := 0.0
var _arena_ui: Node = null
var _unrest_pool := 0.0


func _enter_tree() -> void:
	add_to_group("game_world")
	y_sort_enabled = true


func _ready() -> void:
	ArenaRun.begin()
	_build_map()
	_spawn_spectator_props()
	_spawn_fountains()
	_spawn_structures()
	_spawn_elite()
	_spawn_heroes()
	_spawn_player()
	_spawn_camera()
	_spawn_hud()
	if not ArenaRun.phase_changed.is_connected(_on_phase):
		ArenaRun.phase_changed.connect(_on_phase)
	if not ArenaRun.match_restarted.is_connected(_on_restart):
		ArenaRun.match_restarted.connect(_on_restart)
	_on_phase(ArenaRun.phase())
	ArenaRun.sync_player_growth()
	_mount_arena_ui()


func _exit_tree() -> void:
	if _arena_ui != null and is_instance_valid(_arena_ui):
		var ui: Node = _arena_ui
		_arena_ui = null
		ui.queue_free()
	if ArenaRun.phase_changed.is_connected(_on_phase):
		ArenaRun.phase_changed.disconnect(_on_phase)
	if ArenaRun.match_restarted.is_connected(_on_restart):
		ArenaRun.match_restarted.disconnect(_on_restart)
	# 中途离开不能把还在走的计时结算成胜利。
	if ArenaRun.active() and ArenaRun.phase() != ArenaCatalog.PHASE_RESULT:
		ArenaRun.abandon()


func _process(delta: float) -> void:
	_drive_camera(delta)
	_heal_player(delta)
	_tick_unrest(delta)
	var wave := ArenaRun.take_wave()
	if not wave.is_empty():
		_spawn_wave(wave)


func set_camera_driver(enabled: bool) -> void:
	camera_driver = enabled
	if not enabled and _cam != null:
		_cam.release()


func camera() -> GameCamera:
	return _cam


func _on_phase(next: String) -> void:
	if next == ArenaCatalog.PHASE_COUNTDOWN or next == ArenaCatalog.PHASE_PLAYING:
		_refresh_unit_stats()
	var locked := next != ArenaCatalog.PHASE_PLAYING
	if _player != null and is_instance_valid(_player):
		_player.cutscene_locked = locked
	if _cam == null:
		return
	if not camera_driver:
		return
	if next == ArenaCatalog.PHASE_PLAYING:
		_cam.release()
	elif next == ArenaCatalog.PHASE_LOBBY or next == ArenaCatalog.PHASE_COUNTDOWN:
		_sweep = 0.0
		if _focus != null:
			_focus.global_position = Vector2(480, 180)
			_cam.focus(_focus, 1.0, 1.2)


func _on_restart() -> void:
	_clear_bolts()
	var nodes: Array = get_tree().get_nodes_in_group("arena_unit")
	for node in nodes:
		if not is_instance_valid(node):
			continue
		if String(node.get("unit_kind")) == "minion":
			node.queue_free()
		elif node.has_method("reset_for_match"):
			node.call("reset_for_match")
	if _player != null and is_instance_valid(_player):
		_player.arena_respawn(ArenaCatalog.PLAYER_SPAWN)
	ArenaRun.sync_player_growth()


func _drive_camera(delta: float) -> void:
	if not camera_driver or _focus == null or _cam == null:
		return
	var next := ArenaRun.phase()
	if next != ArenaCatalog.PHASE_LOBBY and next != ArenaCatalog.PHASE_COUNTDOWN:
		return
	_sweep = minf(1.0, _sweep + delta * 0.12)
	var x := lerpf(480.0, 3360.0, _sweep)
	_focus.global_position = Vector2(x, 180.0)


func _heal_player(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or _player.health == null:
		return
	if _player.health.current <= 0:
		return
	if not ArenaRun.allows_combat():
		return
	var well := ArenaCatalog.fountain_for(ArenaCatalog.TEAM_PLAYER)
	if not ArenaCatalog.near_fountain(_player.global_position, well):
		return
	_player_heal += ArenaCatalog.FOUNTAIN_HEAL * delta
	var n := int(_player_heal)
	if n > 0:
		_player_heal -= float(n)
		_player.health.heal(n)


func _spawn_wave(wave: Dictionary) -> void:
	var index := int(wave.get("index", 1))
	var raw_kinds: Variant = wave.get("kinds", [])
	if raw_kinds is not Array:
		return
	var slot := 0
	for kind_v in raw_kinds:
		var kind := String(kind_v)
		_spawn_minion(ArenaCatalog.TEAM_PLAYER, kind, index, slot)
		_spawn_minion(ArenaCatalog.TEAM_ENEMY, kind, index, slot)
		slot += 1


func _spawn_minion(team: String, kind: String, wave_index: int, slot: int) -> void:
	if _minion_count(team) >= ArenaCatalog.MINION_CAP:
		return
	var blue := team == ArenaCatalog.TEAM_PLAYER
	var side := 0 if blue else 1
	var lane := ArenaCatalog.lane_slot(slot, wave_index, side)
	var x := ArenaCatalog.BLUE_MINION_X + float(slot) * 18.0
	if not blue:
		x = ArenaCatalog.RED_MINION_X - float(slot) * 18.0
	var label := "骸骨"
	if kind == "ranged":
		label = "火颅"
	elif kind == "siege":
		label = "碎铁犬"
	var unit: Node = MinionScript.new()
	var cfg := {
		"id": "minion_%s_%d_%d" % [team, wave_index, slot],
		"team": team,
		"kind": "minion",
		"role": kind,
		"label": label,
		"dir": 1.0 if blue else -1.0,
		"slot": lane,
		"wave": wave_index,
		"pos": Vector2(x, ArenaCatalog.lane_y(lane)),
	}
	unit.call("configure", cfg)
	add_child(unit)


func _tick_unrest(delta: float) -> void:
	if not ArenaRun.running():
		return
	var board: Dictionary = ArenaRun.scoreboard()
	if float(board.get("elapsed", 0.0)) < ArenaCatalog.UNREST_AT:
		return
	_unrest_pool += delta
	while _unrest_pool >= ArenaCatalog.UNREST_STEP:
		_unrest_pool -= ArenaCatalog.UNREST_STEP
		_chip_exposed_towers()


func _chip_exposed_towers() -> void:
	for node in get_tree().get_nodes_in_group("arena_unit"):
		if not is_instance_valid(node):
			continue
		if String(node.get("unit_kind")) != "tower":
			continue
		var side := String(node.get("team"))
		var index := int(node.get("structure_index"))
		if not ArenaRun.structure_vulnerable(side, index):
			continue
		ArenaRun.apply_structure_damage(side, index, 1, "")


func _minion_count(team: String) -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("arena_unit"):
		if not is_instance_valid(node):
			continue
		if String(node.get("unit_kind")) != "minion":
			continue
		if String(node.get("team")) != team or not bool(node.get("alive")):
			continue
		n += 1
	return n


func _spawn_player() -> void:
	_player = PlayerScene.instantiate() as Player
	_player.position = ArenaCatalog.PLAYER_SPAWN
	_player.z_index = 0
	_player.add_to_group("arena_plane")
	add_child(_player)
	var shadow: Node2D = ShadowScript.new()
	shadow.name = "ArenaShadow"
	_player.add_child(shadow)
	_player.move_child(shadow, 0)


func _spawn_camera() -> void:
	_focus = Node2D.new()
	_focus.name = "CameraFocus"
	_focus.position = Vector2(480, 180)
	add_child(_focus)
	_cam = CameraScene.instantiate() as GameCamera
	_cam.name = "GameCamera"
	add_child(_cam)
	_cam.limit_left = 0
	_cam.limit_right = int(ArenaCatalog.LANE_RIGHT)
	_cam.limit_top = 0
	_cam.limit_bottom = int(ArenaCatalog.VIEW_H)
	_cam.global_position = Vector2(480, 180)


func _spawn_hud() -> void:
	var hud: CanvasLayer = HudScene.instantiate() as CanvasLayer
	if hud == null:
		return
	GameContext.ui_host(self).add_child(hud)


func _mount_arena_ui() -> void:
	var hud_script := preload("res://scripts/ui/arena_hud.gd") as GDScript
	var ui: Node = hud_script.new()
	ui.name = "ArenaInterface"
	_arena_ui = ui
	GameContext.ui_host(self).add_child(ui)


## M3 装饰性可破坏物：坐在后台观礼矮墙顶（y=226），在纵深带之外。
## persist=false——场馆是临时对局，打碎不写战役档；collision_layer 清零——
## 纯摆设，不挡路、不参与碰撞与战斗判定（不进 arena_unit / arena_plane 组）。
## 对局里它们够不到也打不中谁；爆破罐/余烬窖这类有战场副作用的一律不放。
func _spawn_spectator_props() -> void:
	for spec in [["SpectatorUrnWest", &"rust_urn", SPECTATOR_WEST_FEET],
			["SpectatorHeapEast", &"scrap_heap", SPECTATOR_EAST_FEET]]:
		var prop := DestructiblePropScene.instantiate() as DestructibleProp
		if prop == null:
			continue
		prop.name = String(spec[0])
		prop.position = spec[2] as Vector2
		prop.prop_id = spec[1] as StringName
		prop.persist = false
		add_child(prop)
		# _ready 把 collision_layer 置 1（战役里它要挡路）；场馆里压回 0。
		prop.collision_layer = 0


func _spawn_fountains() -> void:
	_spawn_fountain(ArenaCatalog.TEAM_PLAYER, ArenaCatalog.BLUE_FOUNTAIN)
	_spawn_fountain(ArenaCatalog.TEAM_ENEMY, ArenaCatalog.RED_FOUNTAIN)


func _spawn_fountain(team: String, pos: Vector2) -> void:
	var well: Node = FountainScript.new()
	well.call("configure", {"team": team, "pos": pos})
	add_child(well)


func _spawn_structures() -> void:
	_spawn_tower(ArenaCatalog.TEAM_PLAYER, 0, ArenaCatalog.BLUE_OUTER)
	_spawn_tower(ArenaCatalog.TEAM_PLAYER, 1, ArenaCatalog.BLUE_INNER)
	_spawn_crystal(ArenaCatalog.TEAM_PLAYER, ArenaCatalog.BLUE_CRYSTAL)
	_spawn_tower(ArenaCatalog.TEAM_ENEMY, 0, ArenaCatalog.RED_OUTER)
	_spawn_tower(ArenaCatalog.TEAM_ENEMY, 1, ArenaCatalog.RED_INNER)
	_spawn_crystal(ArenaCatalog.TEAM_ENEMY, ArenaCatalog.RED_CRYSTAL)


func _spawn_tower(team: String, index: int, pos: Vector2) -> void:
	var tower: Node = TowerScript.new()
	tower.call("configure", {
		"id": "tower_%s_%d" % [team, index],
		"team": team,
		"kind": "tower",
		"role": "tower",
		"index": index,
		"label": ArenaCatalog.structure_label(index),
		"dir": 1.0 if team == ArenaCatalog.TEAM_PLAYER else -1.0,
		"pos": pos,
	})
	add_child(tower)


func _spawn_crystal(team: String, pos: Vector2) -> void:
	var crystal: Node = CrystalScript.new()
	crystal.call("configure", {
		"id": "crystal_%s" % team,
		"team": team,
		"kind": "crystal",
		"role": "crystal",
		"index": 2,
		"label": "水晶",
		"dir": 1.0 if team == ArenaCatalog.TEAM_PLAYER else -1.0,
		"pos": pos,
	})
	add_child(crystal)


func _spawn_elite() -> void:
	var elite: Node = UnitScript.new()
	elite.call("configure", {
		"id": "elite",
		"team": ArenaCatalog.TEAM_NEUTRAL,
		"kind": "elite",
		"role": "elite",
		"label": "炉火精英",
		"pos": Vector2(ArenaCatalog.ELITE_POS.x, ArenaCatalog.DEPTH_MID),
	})
	add_child(elite)


func _spawn_heroes() -> void:
	for raw in ArenaCatalog.HERO_ROSTER:
		if raw is not Dictionary:
			continue
		var hero: Dictionary = raw
		var team := String(hero.get("team", ArenaCatalog.TEAM_ENEMY))
		var body: Node = HeroScript.new()
		var pos_v: Variant = hero.get("pos", ArenaCatalog.PLAYER_SPAWN)
		var pos := ArenaCatalog.PLAYER_SPAWN
		if pos_v is Vector2:
			pos = pos_v as Vector2
		var slot := int(hero.get("slot", 0))
		pos.y = ArenaCatalog.lane_y(slot)
		body.call("configure", {
			"id": String(hero.get("id", "")),
			"team": team,
			"kind": "hero",
			"role": "hero",
			"label": String(hero.get("label", "")),
			"skin": String(hero.get("skin", "")),
			"ranged": bool(hero.get("ranged", false)),
			"slot": slot,
			"dir": 1.0 if team == ArenaCatalog.TEAM_PLAYER else -1.0,
			"pos": pos,
		})
		add_child(body)


func _build_map() -> void:
	var bg := ColorRect.new()
	bg.name = "ArenaBackdrop"
	bg.position = Vector2.ZERO
	bg.size = Vector2(ArenaCatalog.LANE_LENGTH, ArenaCatalog.VIEW_H)
	bg.color = Color("#120e14")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -40
	add_child(bg)
	var stage: Node = StageScript.new()
	stage.call("build", self)
	# 碰撞仍是一整条厚板，给大厅里的重力站立用。对局里平面运动不再靠它。
	# 外观由纵深地面取代，所以把平台画的那层藏掉。
	_platform(Vector2(-8, ArenaCatalog.GROUND_Y), Vector2(ArenaCatalog.LANE_LENGTH + 16.0, 48))
	_wall(Vector2(-48, 0), Vector2(48, 400))
	_wall(Vector2(ArenaCatalog.LANE_RIGHT, 0), Vector2(48, 400))


func _platform(pos: Vector2, size: Vector2) -> void:
	var plat: SolidPlatform = PlatformScene.instantiate() as SolidPlatform
	plat.position = pos
	plat.size = size
	plat.skin = "ground"
	add_child(plat)
	plat.visible = false


func _clear_bolts() -> void:
	for node in get_tree().get_nodes_in_group("arena_bolt"):
		if is_instance_valid(node):
			node.queue_free()


func _refresh_unit_stats() -> void:
	for node in get_tree().get_nodes_in_group("arena_unit"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node.has_method("refresh_combat_stats"):
			node.call("refresh_combat_stats")


func _wall(pos: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.position = pos
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = size * 0.5
	wall.add_child(shape)
	add_child(wall)
