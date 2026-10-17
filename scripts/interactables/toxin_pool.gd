class_name ToxinPool
extends Area2D
## Corrosive sludge pit. Murky teal liquid that darkens with depth, capped by
## a brighter scum film whose two frames slosh back and forth with a gentle
## bob, so it reads as "the ground broke open into acid", not a green slab.

@export var toxin_per_second: float = 36.0
## 液面与浮沫的整体着色。墓园里默认原色；地窟的青砖和苔盖本身就是绿的，
## 要把池子调成更酸的黄绿，液体才不会被读成又一层苔地。
@export var tint: Color = Color.WHITE

var _bodies: Array = []
var _pool_size := Vector2(112, 32)

const BUBBLE_INTERVAL := 0.55
var _bubble_accum := 0.0

const SLUDGE_PATH := "res://assets/env/toxin_sludge.png"
const SCUM_PATH := "res://assets/env/toxin_scum.png"
const SCUM_B_PATH := "res://assets/env/toxin_scum_b.png"
const WORLD := 16.0
## Scum frame swap cadence and bob amplitude (px).
const SCUM_FRAME_TIME := 0.45
const SCUM_BOB := 1.0

var _scum_sprites: Array[Sprite2D] = []
var _scum_frames: Array[Texture2D] = []
var _scum_time := 0.0
var _hinted := false

## 毒雾丝：从液面缓升、随风偏移、加法混合的 2px 绿点簇。纯表现，不进物理。
const VAPOR_INTERVAL := 0.45
const VAPOR_MAX := 8
## 毒雾：偏绿、偏暗的一团。以前往 Palette.FOG（灰白）混 40%，在夜里读成一簇
## 悬在水面上的白点，被用户误认成"雨滴"；现在只留 14% 灰，主要靠绿雾发光。
const VAPOR_TINT := Color(0.38, 0.70, 0.44)
## 峰值透明度：加法混合下 0.42 在夜里几乎读不出，0.62 是一缕能看见的雾。
const VAPOR_PEAK_ALPHA := 0.54
var _vapor: Node2D
## Optional recolour of the authored (green) sludge through the chapter grade shader:
## a 5-stop dark -> light ramp (e.g. the spec's orange coolant). Empty = authored colour.
var sludge_ramp: Array = []
## Multiplied onto the vapour wisps so they match a recoloured pool.
var vapor_modulate := Color.WHITE
var _vapor_accum := 0.0
var _headless := false


func _ready() -> void:
	# Sensor only — never a solid lid. Player mask is layer 1; this stays on 128.
	collision_layer = 128
	collision_mask = 2
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_headless = DisplayServer.get_name() == "headless"
	_rebuild_visual()


func configure(size: Vector2) -> void:
	_pool_size = size
	_rebuild_visual()


## World-space water film. Rain / splash FX use the top edge as the hit plane,
## not the pit floor. Do not shrink this to a collision inset — weather_fx
## samples `y = rect.position.y` as the scum surface.
func surface_rect() -> Rect2:
	return Rect2(global_position, _pool_size)


func _on_body_entered(body: Node2D) -> void:
	if not _bodies.has(body):
		_bodies.append(body)
	if body is Player:
		Sfx.play(&"splash", 0.08, -8.0)


func _on_body_exited(body: Node2D) -> void:
	_bodies.erase(body)
	if body is Player:
		_hinted = false


func set_sludge_ramp(ramp: Array, vapor: Color = Color.WHITE) -> void:
	sludge_ramp = ramp
	vapor_modulate = vapor
	_apply_sludge_ramp()


func _apply_sludge_ramp() -> void:
	if _vapor != null and is_instance_valid(_vapor):
		_vapor.modulate = vapor_modulate
	if sludge_ramp.size() < 5 or not ResourceLoader.exists(Level01Parallax.GRADE_SHADER):
		return
	var mat := ShaderMaterial.new()
	mat.shader = load(Level01Parallax.GRADE_SHADER) as Shader
	mat.set_shader_parameter("amount", 0.92)
	for i in 5:
		mat.set_shader_parameter("c%d" % i, sludge_ramp[i])
	for child in get_children():
		if child is Sprite2D:
			(child as Sprite2D).material = mat


func _rebuild_visual() -> void:
	for child in get_children():
		if child is CollisionShape2D:
			continue
		child.queue_free()
	_scum_sprites.clear()
	_scum_frames.clear()
	_vapor = null
	var sludge := _load_tex(SLUDGE_PATH)
	var scum := _load_tex(SCUM_PATH)
	var scum_b := _load_tex(SCUM_B_PATH)
	if sludge == null:
		sludge = scum
	if sludge != null:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector4(position.x, position.y, _pool_size.x, _pool_size.y))
		var cols := maxi(1, int(ceil(_pool_size.x / WORLD)))
		var rows := maxi(1, int(ceil(_pool_size.y / WORLD)))
		for r in rows:
			for c in cols:
				var spr := Sprite2D.new()
				spr.texture = sludge
				spr.centered = false
				spr.flip_h = rng.randf() < 0.5
				spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				spr.position = Vector2(c * WORLD, r * WORLD)
				var src := float(sludge.get_width())
				var s := WORLD / maxf(1.0, src)
				spr.scale = Vector2(s, s)
				var remain_x := _pool_size.x - c * WORLD
				var remain_y := _pool_size.y - r * WORLD
				if remain_x < WORLD - 0.01 or remain_y < WORLD - 0.01:
					spr.region_enabled = true
					spr.region_rect = Rect2(0, 0, minf(src, remain_x / s), minf(float(sludge.get_height()), remain_y / s))
				# Liquid darkens with depth; texture already fades, rows push further.
				var k := lerpf(0.9, 0.45, float(r) / maxf(1.0, float(rows - 1)))
				spr.modulate = Color(k * tint.r, k * tint.g, k * tint.b, tint.a)
				add_child(spr)
		if scum != null:
			_scum_frames.append(scum)
			if scum_b != null:
				_scum_frames.append(scum_b)
			var scum_h := float(scum.get_height())
			for c in cols:
				var spr := Sprite2D.new()
				spr.texture = scum
				spr.centered = false
				spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				spr.position = Vector2(c * WORLD, 0)
				var remain_x := _pool_size.x - c * WORLD
				if remain_x < WORLD - 0.01:
					spr.region_enabled = true
					spr.region_rect = Rect2(0, 0, minf(float(scum.get_width()), remain_x), scum_h)
				spr.modulate = tint
				add_child(spr)
				_scum_sprites.append(spr)
	else:
		var fill := ColorRect.new()
		fill.name = "Fill"
		fill.size = _pool_size
		fill.color = Color(0.18, 0.42, 0.34, 0.88)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fill)
	_apply_sludge_ramp()
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if col == null:
		col = CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		col.shape = shape
		add_child(col)
	(col.shape as RectangleShape2D).size = _pool_size
	col.position = _pool_size * 0.5


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _process(delta: float) -> void:
	_tick_vapor(delta)
	if _scum_sprites.is_empty():
		return
	_scum_time += delta
	var frame := 0
	if _scum_frames.size() > 1:
		frame = int(_scum_time / SCUM_FRAME_TIME) % _scum_frames.size()
	for i in _scum_sprites.size():
		var spr := _scum_sprites[i]
		if not is_instance_valid(spr):
			continue
		if _scum_frames.size() > 1 and spr.texture != _scum_frames[frame]:
			spr.texture = _scum_frames[frame]
		spr.position.y = sin(_scum_time * 1.7 + float(i) * 0.9) * SCUM_BOB - 0.5


## 液面持续呼出毒雾；下雨时雨点压住液面，雾丝少一半。
func _tick_vapor(delta: float) -> void:
	if _headless:
		return
	if _vapor == null or not is_instance_valid(_vapor):
		_vapor = Node2D.new()
		_vapor.name = "Vapor"
		_vapor.z_index = 2
		_vapor.modulate = vapor_modulate
		add_child(_vapor)
	_vapor_accum += delta
	var interval := VAPOR_INTERVAL * lerpf(1.0, 2.0, WorldClock.rain_opacity())
	if _vapor_accum < interval:
		return
	_vapor_accum = 0.0
	if _vapor.get_child_count() >= VAPOR_MAX:
		return
	var wisp := Wisp.new()
	wisp.position = Vector2(randf_range(6.0, _pool_size.x - 6.0), 1.0)
	wisp.span = Vector2(4.0, _pool_size.x - 4.0)
	_vapor.add_child(wisp)


func vapor_count() -> int:
	if _vapor == null or not is_instance_valid(_vapor):
		return 0
	return _vapor.get_child_count()


func _physics_process(delta: float) -> void:
	# 过场锁输入时人走不开，继续灌毒会在台词里把骑士灌满并触发满溢。
	# 池不改 velocity：人在腐液里仍能左右走、跳，爬岸靠关卡矮唇。
	if Director.is_input_locked():
		return
	_prune_bodies()
	for body in _bodies:
		if body is Player:
			(body as Player).toxin.expose(toxin_per_second * delta)
			_maybe_hint()
	_bubble_accum += delta
	if _bubble_accum >= BUBBLE_INTERVAL:
		_bubble_accum -= BUBBLE_INTERVAL
		Fx.toxin_bubbles(self, _bubble_rect(), _bubble_tint())


func _prune_bodies() -> void:
	var i := _bodies.size() - 1
	while i >= 0:
		if not is_instance_valid(_bodies[i]):
			_bodies.remove_at(i)
		i -= 1


func _maybe_hint() -> void:
	if _hinted:
		return
	# 初次入池由剧情字幕请客；过场中也先记一笔，避免解锁后再叠一句。
	if Director.is_input_locked() or Director.playing:
		_hinted = true
		return
	_hinted = true
	GameEvents.announcement.emit("腐液咬着靴底")


func _bubble_rect() -> Rect2:
	# 从水面（甚至略高于水面）开始冒：气泡要在水线以上看得见，不能整段生命
	# 都埋在暗色水体里——那样只剩水面下的绿色噪点。
	return Rect2(
		Vector2(4.0, -2.0),
		Vector2(_pool_size.x - 8.0, _pool_size.y * 0.40)
	)


## 气泡颜色跟液面一致：普通毒池是酸绿；第 4 章冷却液池通过 sludge ramp 的
## vapour tint 变成橙色，气泡不能还是绿的。
func _bubble_tint() -> Color:
	var base := vapor_modulate
	if base == Color.WHITE:
		base = VAPOR_TINT
	return base.lerp(Color.WHITE, 0.18)


## 一缕毒雾：3–5 个方点松散成簇，几乎垂直上升，只轻微摇摆；风只推一点点，
## 且 x 被夹在池面 `span` 内——雾不会飘到岸上，看起来像是池子在往外扩。
## 坐标取整以免 NEAREST 发糊。alpha 先起后落，寿命 2.4–3.6s。
class Wisp extends Node2D:
	const WIND_DRIFT := 5.0
	const WOBBLE := 1.6
	const CELL_SPREAD := 1.1

	## Pool-local x range the wisp may occupy (set by the pool on spawn).
	var span := Vector2(-INF, INF)

	var _age := 0.0
	var _life := 3.0
	var _rise := 9.0
	var _phase := 0.0
	## Sub-pixel state; node positions are snapped from these.
	var _pos := Vector2.ZERO
	var _cells: Array[Polygon2D] = []
	var _cell_pos: Array[Vector2] = []
	var _spread: Array[Vector2] = []


	func _init() -> void:
		_life = randf_range(2.4, 3.6)
		_rise = randf_range(7.0, 11.0)
		_phase = randf() * TAU
		var n := randi_range(3, 5)
		for i in n:
			var cell := Polygon2D.new()
			# 2px 与 3px 方点混合：全 2px 在 640×360 上只剩噼里啪啦的噪点。
			var half := 1.0 if randf() < 0.5 else 1.5
			cell.polygon = PackedVector2Array([
				Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half),
			])
			cell.color = ToxinPool.VAPOR_TINT.lerp(Palette.FOG, randf() * 0.14)
			cell.material = Fx.additive_mat()
			var p := Vector2(randf_range(-4.0, 4.0), randf_range(-3.0, 1.0))
			cell.position = p.round()
			add_child(cell)
			_cells.append(cell)
			_cell_pos.append(p)
			_spread.append(Vector2(randf_range(-CELL_SPREAD, CELL_SPREAD), randf_range(-1.2, 0.3)))
		modulate = Color(1.0, 1.0, 1.0, 0.0)


	func _ready() -> void:
		_pos = position


	func _process(delta: float) -> void:
		_age += delta
		if _age >= _life:
			queue_free()
			return
		var k := _age / _life
		var drift := Vector2(
			WorldClock.wind_vector().x * WIND_DRIFT + sin(_age * 1.6 + _phase) * WOBBLE,
			-_rise * (1.0 - 0.35 * k))
		_pos += drift * delta
		_pos.x = clampf(_pos.x, span.x, span.y)
		position = _pos.round()
		for i in _cells.size():
			_cell_pos[i] += _spread[i] * delta
			_cells[i].position = _cell_pos[i].round()
		modulate.a = minf(k * 4.0, 1.0) * (1.0 - k) * ToxinPool.VAPOR_PEAK_ALPHA
