class_name SlashArc
extends Sprite2D
## 一次性挥砍弧光（纯表现层）。
## 用 AtlasTexture 从 3x3 雪碧图（每帧 64x47）切出 9 帧，播放约 0.12s 后自毁。
## 由 player.gd 轮询 melee.phase_name()=="active" 的上升沿后生成；
## 招架成功（GameEvents.parried）时把活跃弧光提亮为近白、放大并延长存活。
## headless 安全：素材缺失时立即退场，不影响任何逻辑判定。

const SHEET_PATH := "res://assets/kenney_clean/vfx/slash_spritesheet.png"
const FRAME_SIZE := Vector2i(64, 47)
const SHEET_COLS := 3
const SHEET_ROWS := 3
const PLAY_FRAMES := 4          # 播放前 4 帧
const PLAY_SECONDS := 0.12
const PARRY_MODULATE := Color(2.2, 2.2, 2.2)
const PARRY_SCALE := Vector2(1.4, 1.4)
const PARRY_SECONDS := 0.2

## 切帧结果按进程缓存，避免每次挥砍重复建 AtlasTexture。
static var _frame_cache: Array[AtlasTexture] = []

var _frames: Array[AtlasTexture] = []
var _elapsed := 0.0
var _lifetime := PLAY_SECONDS
## 毒素满溢：弧光在本色与过曝白之间闪（风险可读）。弹反炸亮后不再闪。
var flicker := false
var _base_modulate := Color.WHITE
var _parried := false
var _light: WorldLight
var _base_light_energy := 1.45
var _light_color := Color(1.0, 0.88, 0.52)
var _light_radius := 112.0


static func sheet_available() -> bool:
	return ResourceLoader.exists(SHEET_PATH)


static func _get_frames() -> Array[AtlasTexture]:
	if not _frame_cache.is_empty() or not sheet_available():
		return _frame_cache
	var sheet := load(SHEET_PATH) as Texture2D
	if sheet == null:
		return _frame_cache
	for i in range(SHEET_COLS * SHEET_ROWS):
		var frame := AtlasTexture.new()
		frame.atlas = sheet
		frame.region = Rect2(
			(i % SHEET_COLS) * FRAME_SIZE.x,
			int(i / float(SHEET_COLS)) * FRAME_SIZE.y,
			FRAME_SIZE.x,
			FRAME_SIZE.y
		)
		_frame_cache.append(frame)
	return _frame_cache


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	material = Fx.additive_mat()
	z_index = 10
	_frames = _get_frames()
	if _frames.is_empty():
		queue_free()  # 缺素材（如 headless 未导入）：立即退场
		return
	texture = _frames[0]
	_base_modulate = modulate
	_setup_light()
	GameEvents.parried.connect(_on_parried)


func _setup_light() -> void:
	_light = WorldLight.new()
	_light.name = "SlashGlow"
	_light.follow = &"authored"
	_light.authored_radius = _light_radius
	_light.radius_cap = _light_radius
	_light.color = _light_color
	_light.lit = true
	_light.shadow_enabled = false
	_light.set_base_energy(_base_light_energy)
	_light.set_as_top_level(true)
	_light.global_position = global_position
	add_child(_light)


func set_light_properties(tint: Color, energy: float, radius: float = 112.0) -> void:
	_light_color = tint
	_base_light_energy = energy
	_light_radius = radius
	if _light != null and is_instance_valid(_light):
		_light.color = tint
		_light.authored_radius = radius
		_light.radius_cap = radius
		_light.set_base_energy(energy)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _lifetime:
		queue_free()
		return
	var count := mini(PLAY_FRAMES, _frames.size())
	var idx: int = clampi(int(_elapsed / _lifetime * count), 0, count - 1)
	texture = _frames[idx]
	if _light != null and is_instance_valid(_light):
		_light.global_position = global_position
		var fade := clampf(1.0 - (_elapsed / _lifetime), 0.0, 1.0)
		var cur_energy := (2.4 if _parried else _base_light_energy) * fade
		_light.set_base_energy(cur_energy)
	if flicker and not _parried:
		# 每帧交替本色 / 过曝白：肉眼一闪一闪，比单纯调色更像「烫手」。
		modulate = _base_modulate if int(_elapsed * 60.0) % 2 == 0 else Color(2.0, 2.0, 2.0, _base_modulate.a)


func _on_parried(_projectile: Node, _by_actor: Node) -> void:
	# 招架瞬间：同屏活跃弧光炸亮为近白、放大 1.4 倍并延长存活。
	_parried = true
	modulate = PARRY_MODULATE
	scale = PARRY_SCALE
	_lifetime = PARRY_SECONDS
	if _light != null and is_instance_valid(_light):
		_light.color = Color(1.2, 1.15, 0.95)
		_light.set_base_energy(2.4)
