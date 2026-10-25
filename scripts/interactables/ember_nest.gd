class_name EmberNest
extends Interactable
## Ember Nest: a weighted checkpoint. Interacting saves the game and sets this
## nest as the respawn point (the knight is fully restored here on death).

const SCENE_PATH := "res://scenes/levels/Level01_Static.tscn"
const BASE_PATH := "res://assets/env/ember_nest.png"
const COALS_PATH := "res://assets/env/ember_nest_coals.png"
const FLAME_PATH := "res://assets/fx/shrine_flame.png"
const SPARK_PATH := "res://assets/ui/ember_motes.png"
const FLAME_FRAMES := 8
const SPARK_FRAMES := 8
const LIT_FPS := 12.0
const LIT_MOD := Color(1.0, 0.92, 0.62, 1.0)
const LIGHT_COLOR := Color(1.0, 0.70, 0.36)
const HALO_PATH := "res://assets/env/glow_soft.png"
## 锈铁火盆 48×36（tools/gen_ember_nest.py），脚埋进草皮两像素。
const BASE_SIZE := Vector2(48, 36)
const BASE_OFFSET := Vector2(-16, -20)
## 盆井中心 = BASE_OFFSET + 贴图里的 (WELL_CX, WELL_CY)；炭火铺在这里。
const BOWL := Vector2(6, -12)
## 火根：16×24 火焰以底边中心为原点立在灰井里（-14），火舌烧到 -38，出盆口。
## 以前以 BOWL 为中心画，整团火盖住盆身还垂到三脚架上，像泼在盆上的黄漆；
## 雨天按中心缩小时还会缩成一团悬在盆口上。底边锚定后缩放、倾斜都以火根为轴。
const FLAME_BASE := Vector2(6, -14)
const FLAME_SIZE := Vector2(16, 24)

var _lit: bool = false
var _flame: Sprite2D
var _coals: Sprite2D
var _sparks: Node2D
var _light: WorldLight
var _beam: Sprite2D
var _halo: Sprite2D
var _frame_t := 0.0
var _spark_t := 0.35
var _headless := false


func _ready() -> void:
	super._ready()
	add_to_group("persistent")
	add_to_group("ember_nests")
	prompt = "E 点燃余烬巢"
	# 以前是 rubble_c 压成 18×22，在 80px 骑士旁边只是一颗石子。
	ensure_sprite(BASE_PATH, BASE_SIZE, BASE_OFFSET, Palette.RUST_DARK)
	_headless = DisplayServer.get_name() == "headless"
	_ensure_coals()
	_ensure_flame()
	_ensure_light()
	_ensure_halo()
	_ensure_beam()
	_apply_flame_state()
	if not WorldClock.phase_changed.is_connected(_on_atmosphere):
		WorldClock.phase_changed.connect(_on_atmosphere)
	if not WorldClock.weather_changed.is_connected(_on_weather):
		WorldClock.weather_changed.connect(_on_weather)


func _ensure_flame() -> void:
	if _flame != null or not ResourceLoader.exists(FLAME_PATH):
		return
	var tex := DensityTextures.load_texture(FLAME_PATH)
	if tex == null:
		return
	var spr := Sprite2D.new()
	spr.name = "Flame"
	spr.texture = tex
	spr.hframes = FLAME_FRAMES
	spr.vframes = 1
	spr.centered = false
	spr.offset = Vector2(-FLAME_SIZE.x * 0.5, -FLAME_SIZE.y)
	spr.position = FLAME_BASE
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.z_index = 2
	add_child(spr)
	_flame = spr
	var sparks := Node2D.new()
	sparks.name = "Sparks"
	sparks.position = FLAME_BASE + Vector2(0, -FLAME_SIZE.y * 0.5)
	sparks.z_index = 3
	add_child(sparks)
	_sparks = sparks


## 点燃后盆底透出的炭火（加法混合），冷盆时隐藏。
func _ensure_coals() -> void:
	if _coals != null or not ResourceLoader.exists(COALS_PATH):
		return
	var tex := DensityTextures.load_texture(COALS_PATH)
	if tex == null:
		return
	var spr := Sprite2D.new()
	spr.name = "Coals"
	spr.texture = tex
	spr.centered = false
	spr.position = BASE_OFFSET
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.z_index = 1
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	spr.material = mat
	spr.visible = false
	add_child(spr)
	_coals = spr


func _exit_tree() -> void:
	if WorldClock.phase_changed.is_connected(_on_atmosphere):
		WorldClock.phase_changed.disconnect(_on_atmosphere)
	if WorldClock.weather_changed.is_connected(_on_weather):
		WorldClock.weather_changed.disconnect(_on_weather)
	Sfx.set_nest_steam(get_instance_id(), 0.0)


func _on_atmosphere(_phase: int) -> void:
	_sync_light(999.0)
	_apply_rain_look()


func _on_weather(_weather: int) -> void:
	_sync_light(999.0)
	_apply_rain_look()


func _process(delta: float) -> void:
	if _lit:
		_sync_light(delta)
		_lean_flame()
		_apply_rain_look()
	if _flame == null or not _lit:
		return
	_frame_t += delta
	var step := 1.0 / LIT_FPS
	while _frame_t >= step:
		_frame_t -= step
		_flame.frame = (_flame.frame + 1) % FLAME_FRAMES
	if _headless or _sparks == null:
		return
	_spark_t += delta
	if _spark_t >= 0.40:
		_spark_t = 0.0
		_spawn_spark()


func _spawn_spark() -> void:
	if not _lit or not ResourceLoader.exists(SPARK_PATH):
		return
	if _sparks.get_child_count() >= 3:
		return
	var sheet := DensityTextures.load_texture(SPARK_PATH)
	if sheet == null:
		return
	_sparks.add_child(NestSpark.new(sheet, WorldClock.rain_opacity() >= 0.35))


func _ensure_light() -> void:
	if _light != null:
		return
	var light := WorldLight.new()
	light.name = "NestLight"
	light.position = FLAME_BASE + Vector2(0, -8)
	light.color = LIGHT_COLOR
	light.follow = &"nest"
	light.flicker = true
	add_child(light)
	_light = light


func _ensure_halo() -> void:
	if _halo != null:
		return
	var spr := Sprite2D.new()
	spr.name = "Halo"
	if ResourceLoader.exists(HALO_PATH):
		spr.texture = DensityTextures.load_texture(HALO_PATH)
	spr.centered = true
	spr.position = FLAME_BASE + Vector2(0, -10)
	spr.z_index = 0
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	spr.material = mat
	spr.visible = false
	spr.modulate = Color(1.0, 0.62, 0.28, 0.0)
	add_child(spr)
	_halo = spr


func _sync_halo() -> void:
	if _halo == null:
		return
	_halo.visible = _lit
	if not _lit:
		_halo.modulate.a = 0.0
		return
	var k := clampf(WorldClock.nest_light_energy() / 2.60, 0.12, 1.0)
	var soak := WorldClock.rain_opacity()
	# 抱紧盆口：48px 光晕放到 1.8x 会读成一块灰色 UI 方块。
	_halo.scale = Vector2(0.92, 0.78) * (0.85 + 0.25 * k) * lerpf(1.0, 0.55, soak)
	_halo.modulate = Color(1.0, 0.62, 0.28, (0.22 + 0.18 * k) * lerpf(1.0, 0.35, soak))


func _sync_light(delta: float) -> void:
	if _light == null:
		return
	_light.lit = _lit
	if _flame != null:
		_light.set_flame_frame(_flame.frame)
	_light.apply(delta > 10.0)


func _ensure_beam() -> void:
	if _beam != null:
		return
	var beam := Sprite2D.new()
	beam.name = "WarmShaft"
	beam.centered = true
	beam.position = FLAME_BASE + Vector2(0, -46)
	beam.texture = _shaft_tex()
	beam.modulate = Color(1.0, 0.72, 0.38, 0.0)
	beam.visible = false
	beam.z_index = 0
	add_child(beam)
	_beam = beam


func _shaft_tex() -> Texture2D:
	var img := Image.create(10, 72, false, Image.FORMAT_RGBA8)
	for y in 72:
		for x in 10:
			var cx := absf(float(x) - 4.5) / 5.0
			var along := 1.0 - float(y) / 72.0
			var a := clampf((1.0 - cx) * (1.0 - cx) * along * 0.7, 0.0, 0.7)
			img.set_pixel(x, y, Color(1.0, 0.72, 0.36, a))
	return ImageTexture.create_from_image(img)


func _lean_flame() -> void:
	var lean := WorldClock.sway_radians() * 0.55 if _lit else 0.0
	if _flame != null:
		_flame.rotation = lean
	if _halo != null:
		_halo.rotation = lean * 0.2
	if _beam != null:
		_beam.rotation = lean * 0.35
		_beam.visible = _lit
		if _lit:
			var e := WorldClock.nest_light_energy()
			var soak := WorldClock.rain_opacity()
			_beam.modulate.a = (0.16 + 0.28 * clampf(e / 2.60, 0.0, 1.0)) * lerpf(1.0, 0.22, soak)
		else:
			_beam.modulate.a = 0.0


func _apply_rain_look() -> void:
	_sync_steam_audio()
	if _flame == null:
		return
	var soak := WorldClock.rain_opacity() if _lit else 0.0
	_flame.scale = Vector2.ONE * lerpf(1.0, 0.40, soak)
	if _lit:
		_flame.modulate = LIT_MOD.lerp(Color(0.58, 0.64, 0.76, 0.78), soak)
	else:
		_flame.modulate = LIT_MOD


func _sync_steam_audio() -> void:
	var steam := 0.0
	if _lit:
		steam = maxf(WorldClock.rain_audio_gain(), WorldClock.rust_rain_audio_gain())
	Sfx.set_nest_steam(get_instance_id(), steam)


func _apply_flame_state() -> void:
	if _coals != null:
		_coals.visible = _lit
	if _flame != null:
		_flame.visible = _lit
		_flame.modulate = LIT_MOD
		if not _lit:
			_flame.rotation = 0.0
	if _sparks != null:
		_sparks.visible = _lit
		if not _lit:
			for child in _sparks.get_children():
				child.queue_free()
	_sync_light(999.0)
	_sync_halo()
	_lean_flame()
	_apply_rain_look()


func can_interact(_actor: Node) -> bool:
	return true


func get_prompt(_actor: Node) -> String:
	return "E 点燃余烬巢" if not _lit else "余烬巢已点燃"


func is_lit() -> bool:
	return _lit


func interact(actor: Node) -> void:
	if actor is Player:
		var p := actor as Player
		p.health.heal_full()
		p.toxin.purify(1.0)
		GameEvents.player_health_changed.emit(p.health.current, p.health.max_hp)
		_lit = true
		_apply_flame_state()
		SaveData.register_lit_nest(SaveData.persist_path(self))
		var scene_path := GameContext.world_scene_path(self)
		if scene_path == "":
			scene_path = SCENE_PATH
		if SaveData.save_game(scene_path, p):
			GameEvents.announcement.emit("余烬重新点燃 —— 进度已刻入铁锈")
		else:
			GameEvents.announcement.emit("余烬亮了，但铁锈没刻住")
		Sfx.play(&"insert")


func get_persistent_state() -> Dictionary:
	return {"lit": _lit}


func apply_persistent_state(state: Dictionary) -> void:
	_lit = bool(state.get("lit", false))
	_apply_flame_state()


## 1x 余烬残片，从焰尖上飘；坐标取整以免 NEAREST 发糊。
class NestSpark extends Sprite2D:
	var _age := 0.0
	var _life := 0.7
	var _rise := 12.0
	var _phase := 0.0
	var _x0 := 0.0

	func _init(sheet: Texture2D, steam: bool = false) -> void:
		texture = sheet
		hframes = EmberNest.SPARK_FRAMES
		vframes = 1
		centered = true
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		scale = Vector2(1.2, 0.7) if steam else Vector2.ONE
		frame = randi_range(0, EmberNest.SPARK_FRAMES - 1)
		_x0 = float(randi_range(-2, 2))
		position = Vector2(_x0, float(randi_range(-8, -4)))
		_rise = randf_range(6.0, 11.0) if steam else randf_range(11.0, 18.0)
		_life = randf_range(0.40, 0.80)
		_phase = randf() * TAU
		modulate = Color(0.80, 0.86, 0.92, 0.55) if steam else Color(1.0, 0.78, 0.42, 0.80)

	func _process(delta: float) -> void:
		_age += delta
		if _age >= _life:
			queue_free()
			return
		var sway := sin(_age * 7.0 + _phase) * 1.4
		position = Vector2(roundf(_x0 + sway), roundf(position.y - _rise * delta))
		frame = int(_age / 0.10) % EmberNest.SPARK_FRAMES
		var k := _age / _life
		modulate.a = minf(k * 8.0, 1.0) * (1.0 - k)
