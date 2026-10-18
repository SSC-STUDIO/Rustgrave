extends Node2D
## 竞技场场景（垂直切片）：一块封闭场地 + 玩家 + 定时刷怪 + 竞技场 HUD。
## 自己不结算胜负：击杀上报 ArenaRun，死亡/时间到由 ArenaRun 收口。

const PlayerScene := preload("res://scenes/player/Player.tscn")
const CameraScene := preload("res://scenes/camera/GameCamera.tscn")
const HudScene := preload("res://scenes/ui/HUD.tscn")
const PlatformScene := preload("res://scenes/world/Platform.tscn")
const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")

var _player: Player
var _enemies: Array[Dictionary] = []
var _wave_timer := 1.0
var _wave_index := 0


func _enter_tree() -> void:
	add_to_group("game_world")


func _ready() -> void:
	_build_arena()
	_player = PlayerScene.instantiate() as Player
	_player.position = ArenaCatalog.PLAYER_SPAWN
	add_child(_player)
	var cam: GameCamera = CameraScene.instantiate()
	add_child(cam)
	cam.limit_left = 0
	cam.limit_right = 900
	cam.limit_top = 0
	cam.limit_bottom = 360
	cam.global_position = _player.global_position + Vector2(0.0, -18.0)
	var hud: CanvasLayer = HudScene.instantiate()
	GameContext.ui_host(self).add_child(hud)
	ArenaRun.begin()


func _process(delta: float) -> void:
	if not ArenaRun.running():
		return
	_prune_enemies()
	_wave_timer -= delta
	if _wave_timer <= 0.0:
		_wave_timer = ArenaCatalog.WAVE_INTERVAL
		if _enemies.size() < ArenaCatalog.MAX_ALIVE:
			_spawn_wave()


func _prune_enemies() -> void:
	var alive: Array[Dictionary] = []
	for entry in _enemies:
		var enemy: Node = entry.get("node")
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			alive.append(entry)
		else:
			ArenaRun.add_kill(int(entry.get("score", 10)))
	_enemies = alive


func _spawn_wave() -> void:
	var row: Dictionary = ArenaCatalog.enemy_for_wave(_wave_index)
	_wave_index += 1
	var scene_path := String(row.get("scene", ""))
	if not ResourceLoader.exists(scene_path):
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var enemy: Node2D = packed.instantiate() as Node2D
	if enemy == null:
		return
	var x := ArenaCatalog.SPAWN_X + float((_wave_index % 3) * 24)
	enemy.position = Vector2(x, 320.0)
	add_child(enemy)
	_enemies.append({"node": enemy, "score": int(row.get("score", 10))})


func _build_arena() -> void:
	_wall(Vector2(-40.0, 0.0), Vector2(40.0, 400.0))
	_wall(Vector2(900.0, 0.0), Vector2(40.0, 400.0))
	_platform(Vector2(0.0, 320.0), Vector2(900.0, 80.0), "ground")
	_platform(Vector2(160.0, 232.0), Vector2(120.0, 16.0), "floating")
	_platform(Vector2(600.0, 232.0), Vector2(140.0, 16.0), "floating")
	# 背景：竞技场自己的暗色大厅，不依赖章节视差。
	var bg := ColorRect.new()
	bg.name = "ArenaBackdrop"
	bg.size = Vector2(900.0, 360.0)
	bg.color = Color("#171019")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -20
	add_child(bg)


func _platform(pos: Vector2, size: Vector2, skin: String) -> void:
	var plat: SolidPlatform = PlatformScene.instantiate() as SolidPlatform
	plat.position = pos
	plat.size = size
	plat.skin = skin
	add_child(plat)


func _wall(pos: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.position = pos
	wall.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = size * 0.5
	wall.add_child(shape)
	add_child(wall)
