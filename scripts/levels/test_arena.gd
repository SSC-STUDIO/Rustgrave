extends Node2D
## Scrapyard test chamber: movement, parry, toxin, plate-door, cores, Heat Forge gate.

const PLAYER := preload("res://scenes/player/Player.tscn")
const CAMERA := preload("res://scenes/camera/GameCamera.tscn")
const HUD := preload("res://scenes/ui/HUD.tscn")
const PLATFORM := preload("res://scenes/world/Platform.tscn")
const GEAR := preload("res://scenes/world/GearPlatform.tscn")
const SPITTER := preload("res://scenes/enemies/SpitterEnemy.tscn")
const PLATE := preload("res://scenes/interactables/PressurePlate.tscn")
const DOOR := preload("res://scenes/interactables/Door.tscn")
const SCRAP := preload("res://scenes/interactables/ScrapPile.tscn")
const TOXIN := preload("res://scenes/interactables/ToxinPool.tscn")
const FILTER := preload("res://scenes/interactables/FilterGear.tscn")
const SHRINE := preload("res://scenes/interactables/PurificationShrine.tscn")
const SOCKET := preload("res://scenes/interactables/SocketStation.tscn")
const GATE := preload("res://scenes/interactables/RustyGate.tscn")


func _enter_tree() -> void:
	add_to_group("game_world")


func _ready() -> void:
	_build_backdrop()
	_build_collision()
	_build_props()
	_spawn_actors()


func _build_backdrop() -> void:
	var sky := ColorRect.new()
	sky.size = Vector2(1600, 400)
	sky.color = Palette.VOID
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sky.z_index = -20
	add_child(sky)
	for i in 8:
		var girder := ColorRect.new()
		girder.size = Vector2(8, 280)
		girder.position = Vector2(80 + i * 190, 20)
		girder.color = Palette.SHADOW
		girder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		girder.z_index = -12
		add_child(girder)
	for i in 5:
		var lamp := ColorRect.new()
		lamp.size = Vector2(6, 4)
		lamp.position = Vector2(140 + i * 280, 36)
		lamp.color = Palette.TOXIC
		lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lamp.z_index = -8
		add_child(lamp)


func _build_collision() -> void:
	_plat(Vector2(0, 320), Vector2(400, 80), Palette.RUST_DARK)
	_plat(Vector2(Level01EastWing.PIT_X0, Level01EastWing.PIT_FLOOR_Y), Level01EastWing.PIT_FLOOR_SIZE, Palette.RUST_SHADOW)
	_plat(Level01EastWing.PIT_CLIMB_LEFT_POS, Level01EastWing.PIT_CLIMB_LEFT_SIZE, Palette.RUST_MID)
	_plat(Level01EastWing.PIT_CLIMB_RIGHT_POS, Level01EastWing.PIT_CLIMB_RIGHT_SIZE, Palette.RUST_MID)
	_plat(Vector2(512, 320), Vector2(1088, 80), Palette.RUST_DARK)
	_plat(Vector2(-16, 0), Vector2(16, 400), Palette.SHADOW)
	_plat(Vector2(1600, 0), Vector2(16, 400), Palette.SHADOW)
	_plat(Vector2(56, 256), Vector2(72, 16), Palette.IRON)
	_plat(Vector2(160, 200), Vector2(64, 16), Palette.IRON)
	_plat(Vector2(48, 144), Vector2(56, 16), Palette.IRON)
	_plat(Vector2(268, 248), Vector2(88, 16), Palette.IRON)
	_plat(Vector2(420, 236), Vector2(72, 16), Palette.IRON)
	_plat(Vector2(620, 248), Vector2(96, 16), Palette.IRON)
	_plat(Vector2(760, 184), Vector2(104, 16), Palette.RUST_MID)
	_plat(Vector2(920, 248), Vector2(72, 16), Palette.IRON)
	var gear: GearPlatform = GEAR.instantiate()
	gear.setup(Vector2(600, 200), 22.0)
	add_child(gear)
	_sign(Vector2(60, 300), "余烬骑士")
	_sign(Vector2(410, 300), "腐液")
	_sign(Vector2(760, 160), "弹反练习")
	_sign(Vector2(1020, 292), "压力板")
	_sign(Vector2(1190, 270), "废料 / 插座")
	_sign(Vector2(1368, 232), "锈门")


func _build_props() -> void:
	var toxin: ToxinPool = TOXIN.instantiate()
	toxin.position = Vector2(400, 336)
	add_child(toxin)
	toxin.configure(Vector2(112, 32))

	var filter: FilterGear = FILTER.instantiate()
	filter.position = Vector2(352, 308)
	add_child(filter)

	var plate: PressurePlate = PLATE.instantiate()
	plate.position = Vector2(1040, 314)
	add_child(plate)

	var door: ArenaDoor = DOOR.instantiate()
	door.position = Vector2(1144, 256)
	add_child(door)
	plate.activated.connect(door.open_door)

	var scrap: ScrapPile = SCRAP.instantiate()
	scrap.position = Vector2(1220, 302)
	add_child(scrap)

	var socket: SocketStation = SOCKET.instantiate()
	socket.position = Vector2(1296, 296)
	add_child(socket)

	var gate: RustyGate = GATE.instantiate()
	gate.position = Vector2(1384, 256)
	add_child(gate)

	var shrine: PurificationShrine = SHRINE.instantiate()
	shrine.position = Vector2(1488, 288)
	add_child(shrine)


func _spawn_actors() -> void:
	var player: Player = PLAYER.instantiate()
	player.position = Vector2(96, 320)
	add_child(player)

	var enemy: SpitterEnemy = SPITTER.instantiate()
	enemy.position = Vector2(812, 184)
	add_child(enemy)

	var cam: GameCamera = CAMERA.instantiate()
	add_child(cam)
	cam.global_position = player.global_position + Vector2(0, -18)

	var hud: CanvasLayer = HUD.instantiate()
	GameContext.ui_host(self).add_child(hud)

	GameEvents.announcement.emit("锈墓试验场 — 用斩击的判定帧把渣弹打回去")


func _plat(pos: Vector2, size: Vector2, color: Color) -> void:
	var p: SolidPlatform = PLATFORM.instantiate()
	p.setup(pos, size, color)
	add_child(p)


func _sign(pos: Vector2, text: String) -> void:
	var lab := Label.new()
	lab.text = text
	lab.position = pos
	lab.add_theme_font_size_override("font_size", 8)
	lab.add_theme_color_override("font_color", Palette.PALE)
	add_child(lab)
