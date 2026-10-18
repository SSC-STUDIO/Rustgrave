class_name WeatherFx
extends CanvasLayer
## Screen-space weather: rain / rust rain streaks + horizontal ember motes.
## Dirt: bounce / splash / wet marks. Water: slap + ripple, no wet plates.
## Alpha follows WorldClock; indoor / title / menu hide particles.

const DROP_COUNT := 52
const FALL_SPEED := 240.0
const GRAVITY := 520.0
const EMBER_COUNT := 20
const EMBER_PATH := "res://assets/ui/ember_motes.png"
const EMBER_FRAMES := 8
const EMBER_DRIFT := 78.0
const PHASE_FALL := 0
const PHASE_BOUNCE := 1
const WET_CELL := 24.0
const WET_MAX := 16
const SPLASH_MAX := 24
const RIPPLE_MAX := 10
const BOUNCE_SHARE := 0.34
const WATER_BOUNCE_SHARE := 0.20
const DEFAULT_GROUND_Y := 320.0
const DEFAULT_TOXIN := Rect2(400.0, 336.0, 112.0, 32.0)
const HIT_NONE := 0
const HIT_WATER := 1
const HIT_GROUND := 2
## 特效不遮挡（docs/art-spec.md）：雨幕画在 backdrop（-10）与玩法画布（0）之间。
## 玩家 / 敌人 / 台缘 / 前摇都在雨滴前面；地面水痕与涟漪仍由 RainGroundFx 挂回
## 玩法画布，落在脚下而不盖住轮廓。
const WEATHER_LAYER := -5
## 全屏雨幕的 alpha 上限。再高就会把远处剪影洗成一层灰。
const RAIN_ALPHA_CAP := 0.42
## 余烬风微粒的 alpha 上限（小、暖、非加法）。
const EMBER_ALPHA_CAP := 0.22
## While it rains the ground / water spans are refreshed at most this often (seconds).
const SPAN_REFRESH_RAINING := 2.0
## 远景雨层：每 3 滴里 1 滴画得更小更暗更慢，和近景拉开纵深（不加新贴图）。
const FAR_EVERY := 3
const FAR_SCALE := 0.72
const FAR_ALPHA := 0.55
const FAR_SPEED := 0.78
## 顶板遮挡：雨滴不允许出现在这一列最近的顶板底面之上（洞里/屋檐下不下雨）。
const ROOF_PAD := 2.0

var _drops: Array[Sprite2D] = []
var _drop_vy: PackedFloat32Array = PackedFloat32Array()
var _drop_phase: PackedByteArray = PackedByteArray()
var _embers: Array[Sprite2D] = []
var _alpha := 0.0
var _ember_alpha := 0.0
var _tex: Texture2D
var _ember_tex: Texture2D
var _splash_tex: Texture2D
var _wet_tex: Texture2D
var _ground: Node2D
var _splashes: Node2D
var _wets: Node2D
var _ripples: Node2D
var _wet_by_cell: Dictionary = {}
var _span_x0: PackedFloat32Array = PackedFloat32Array()
var _span_x1: PackedFloat32Array = PackedFloat32Array()
var _span_y: PackedFloat32Array = PackedFloat32Array()
## 每个实心体的底面：判断"这一列上方有没有顶板"用。
var _span_bottom: PackedFloat32Array = PackedFloat32Array()
## 每滴雨在本列上方的顶板底面（世界 y）；-INF 表示这一列没有顶板。
var _drop_roof: PackedFloat32Array = PackedFloat32Array()
## 远层标记。
var _drop_far: PackedByteArray = PackedByteArray()
## 强度换算出的活动雨滴数（池子不变，只是可见/推进的数量变）。
var _active_drops: int = DROP_COUNT
var _water_x0: PackedFloat32Array = PackedFloat32Array()
var _water_x1: PackedFloat32Array = PackedFloat32Array()
var _water_y: PackedFloat32Array = PackedFloat32Array()
var _span_t := 0.0
var _headless := false
var _drops_hidden := false
var _embers_hidden := false
var _hit_y := 0.0
var _wind_x := 0.0
var _view_ok := false
var _view_size := Vector2(640.0, 360.0)
var _surfaces_dirty := false
var _cam_origin := Vector2.ZERO
var _cam_zoom := Vector2.ONE
var _vp_half := Vector2(640.0, 360.0)
var _pool_splash: Array[SplashSpeck] = []
var _pool_water: Array[WaterSpeck] = []
var _pool_ripple: Array[WaterRipple] = []
var _pool_wet: Array[Sprite2D] = []
var _wet_dead: Array[int] = []


func _ready() -> void:
	layer = WEATHER_LAYER
	follow_viewport_enabled = false
	_headless = DisplayServer.get_name() == "headless"
	_ensure_ground_fx()
	_rebuild_spans()
	var host := get_parent()
	if host != null:
		host.child_entered_tree.connect(_on_host_child_changed)
		host.child_exiting_tree.connect(_on_host_child_changed)
	if _headless:
		set_process(false)
		return
	_tex = _make_drop_tex()
	_splash_tex = _make_splash_tex()
	_wet_tex = _make_wet_tex()
	_drop_vy.resize(DROP_COUNT)
	_drop_phase.resize(DROP_COUNT)
	_drop_far.resize(DROP_COUNT)
	_drop_roof.resize(DROP_COUNT)
	for i in DROP_COUNT:
		var spr := Sprite2D.new()
		spr.texture = _tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.centered = true
		spr.position = Vector2(randf() * 1280.0, randf() * 720.0)
		spr.modulate = Color(0.78, 0.84, 0.92, 0.0)
		spr.visible = false
		add_child(spr)
		_drops.append(spr)
		_drop_far[i] = 1 if i % FAR_EVERY == 0 else 0
		if _drop_far[i] == 1:
			spr.scale = Vector2(FAR_SCALE, FAR_SCALE)
		_drop_vy[i] = FALL_SPEED * (FAR_SPEED if _drop_far[i] == 1 else 1.0)
		_drop_phase[i] = PHASE_FALL
		_drop_roof[i] = -INF
	_ember_tex = _load_ember_tex()
	for i in EMBER_COUNT:
		var spr := Sprite2D.new()
		spr.texture = _ember_tex
		if _ember_tex != null and _ember_tex.get_width() >= EMBER_FRAMES:
			spr.hframes = EMBER_FRAMES
			spr.frame = randi() % EMBER_FRAMES
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.centered = true
		spr.position = Vector2(randf() * 1280.0, 400.0 + randf() * 280.0)
		spr.modulate = Color(1.0, 0.62, 0.38, 0.0)
		spr.scale = Vector2(0.85, 0.85)
		spr.visible = false
		add_child(spr)
		_embers.append(spr)
	_drops_hidden = true
	_embers_hidden = true
	_prewarm_pools()


func _exit_tree() -> void:
	# The splash / ripple / wet-mark pools are built up front and parked outside the tree;
	# nothing else owns them, so every level load leaked ~74 orphan nodes.
	for pool in [_pool_splash, _pool_water, _pool_ripple, _pool_wet]:
		for node in pool:
			if is_instance_valid(node) and node.get_parent() == null:
				node.free()
		pool.clear()


func ground_fx() -> Node2D:
	return _ensure_ground_fx()


func wet_mark_count() -> int:
	return _wet_by_cell.size()


func splash_count() -> int:
	if _splashes == null:
		return 0
	return _splashes.get_child_count()


func ripple_count() -> int:
	if _ripples == null:
		return 0
	return _ripples.get_child_count()


func water_y_at(world_x: float) -> float:
	return _water_y_at(world_x)


func simulate_hit(world: Vector2) -> void:
	_ensure_ground_fx()
	_rebuild_spans()
	if _water_y_at(world.x) >= 0.0:
		_on_water_hit(Vector2(world.x, _water_y_at(world.x)))
		return
	_on_ground_hit(world)


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var frozen := WorldClock.is_frozen()
	if frozen:
		# Pause menu / cinematic / fade: every other ambient layer holds still
		# (LeafShed, ThemeMotes, WorldClock itself). Weather must too, or rain
		# keeps falling through a paused game and the frame keeps paying for it.
		if _drops_active() or not _embers_hidden:
			for spr in _drops:
				spr.modulate.a = 0.0
				spr.visible = false
			for spr in _embers:
				spr.modulate.a = 0.0
				spr.visible = false
			_embers_hidden = true
		return
	_cache_view()
	var target := WorldClock.rain_opacity()
	_alpha = move_toward(_alpha, target, delta / 4.5)
	var rust := WorldClock.rust_rain_mix() if WorldClock.weather_fx_allowed() else 0.0
	var rain_col := Color(0.78, 0.84, 0.92).lerp(Color(0.80, 0.48, 0.34), clampf(rust, 0.0, 1.0))
	# Spans only matter while drops can land. Walking the whole level tree every 0.45 s in
	# clear weather cost 2-7 ms per call for nothing; refresh on demand or slowly while raining.
	_span_t += delta
	if (target > 0.0 or _alpha > 0.001) and (_surfaces_dirty or _span_t >= SPAN_REFRESH_RAINING):
		_span_t = 0.0
		_rebuild_spans()
		_settle_drops_under_roofs()
	if _alpha <= 0.001 and target <= 0.0:
		if not _drops_hidden:
			for spr in _drops:
				spr.modulate.a = 0.0
				spr.visible = false
			_drops_hidden = true
	else:
		if _drops_hidden:
			for spr in _drops:
				spr.visible = true
			_drops_hidden = false
		# 强度决定"这一片下多大"：可见雨滴数按强度收放，池子本身不变。
		var intensity := clampf(WorldClock.weather_intensity(), 0.0, 1.0)
		_active_drops = clampi(roundi(float(DROP_COUNT) * intensity), 0, DROP_COUNT)
		var vis := _alpha * RAIN_ALPHA_CAP
		for i in _drops.size():
			if i >= _active_drops:
				_drops[i].modulate.a = 0.0
				_drops[i].visible = false
				continue
			_drops[i].visible = true
			_tick_drop(i, delta, rain_col, vis * (FAR_ALPHA if _drop_far[i] == 1 else 1.0))
	_tick_embers(delta)
	_tick_wets(delta)
	_tick_ground_fx(delta)


## Any drop currently drawn. Used by the frozen-clock early exit so the rain
## is parked visibly-off exactly once instead of every frame.
func _drops_active() -> bool:
	for spr in _drops:
		if spr.visible:
			return true
	return false


func _tick_drop(i: int, delta: float, rain_col: Color, vis: float) -> void:
	var spr := _drops[i]
	var p := spr.position
	if _drop_phase[i] == PHASE_BOUNCE:
		_drop_vy[i] += GRAVITY * delta
	p.y += _drop_vy[i] * delta
	p.x += _wind_x * delta
	var world := _screen_to_world(p)
	var kind := _classify_hit(world)
	if kind != HIT_NONE:
		if _drop_phase[i] == PHASE_FALL:
			var hy := _hit_y
			# 水花强度跟当前雨势走：雨刚停（alpha 趋零）时不再有全亮的溅落残留。
			var strength := clampf(_alpha * 1.15, 0.0, 1.0)
			if kind == HIT_WATER:
				_on_water_hit(Vector2(world.x, hy), strength)
				if randf() < WATER_BOUNCE_SHARE:
					_drop_phase[i] = PHASE_BOUNCE
					_drop_vy[i] = -randf_range(28.0, 52.0)
					p.y -= 1.0
				else:
					_recycle_drop(i, spr)
					return
			else:
				_on_ground_hit(Vector2(world.x, hy), strength)
				if randf() < BOUNCE_SHARE:
					_drop_phase[i] = PHASE_BOUNCE
					_drop_vy[i] = -randf_range(88.0, 140.0)
					p.y -= 2.0
				else:
					_recycle_drop(i, spr)
					return
		else:
			_recycle_drop(i, spr)
			return
	elif p.y > 728.0:
		_recycle_drop(i, spr)
		return
	elif p.x < -8.0:
		p.x = 1288.0
	spr.position.x = roundf(p.x)
	spr.position.y = roundf(p.y)
	var a := vis
	if _drop_phase[i] == PHASE_BOUNCE:
		a *= 0.72
	spr.modulate.r = rain_col.r
	spr.modulate.g = rain_col.g
	spr.modulate.b = rain_col.b
	spr.modulate.a = a


func _recycle_drop(i: int, spr: Sprite2D) -> void:
	_drop_phase[i] = PHASE_FALL
	_drop_vy[i] = FALL_SPEED * (FAR_SPEED if _drop_far[i] == 1 else 1.0)
	var sx := randf() * 1280.0
	var sy := -8.0
	# 顶板遮挡：这一列盖着顶板/屋檐就从它下面开始下，别让雨穿过天花板落进屋。
	var roof := roof_y_at(_screen_to_world(Vector2(sx, 0.0)).x)
	if roof > -INF:
		var roof_screen := _world_to_screen(Vector2(0.0, roof)).y + ROOF_PAD
		if roof_screen > sy:
			sy = roof_screen
	spr.position = Vector2(sx, sy)


## 这一列上方最近的顶板底面（世界 y）。上面什么都没有就返回 -INF。
## 用实心底面而不是顶面：屋檐下、坑道里、室内都一样成立。
func roof_y_at(world_x: float) -> float:
	var best := -INF
	for i in _span_x0.size():
		if world_x < _span_x0[i] or world_x >= _span_x1[i]:
			continue
		var bottom := _span_bottom[i]
		if bottom > best:
			best = bottom
	return best


func _world_to_screen(world: Vector2) -> Vector2:
	if _view_ok:
		return (world - _cam_origin) * _cam_zoom + _vp_half
	var vp := get_viewport()
	if vp == null:
		return world
	return vp.get_canvas_transform() * world


## 顶板数据刚刷新：已经在天上的雨滴按新顶板重新落位，别留一屏穿顶的雨。
func _settle_drops_under_roofs() -> void:
	for i in _drops.size():
		if i >= _active_drops:
			continue
		var spr := _drops[i]
		var roof := roof_y_at(_screen_to_world(spr.position).x)
		if roof <= -INF:
			continue
		var floor_screen := _world_to_screen(Vector2(0.0, roof)).y + ROOF_PAD
		if spr.position.y < floor_screen:
			spr.position.y = floor_screen


func _on_ground_hit(world: Vector2, strength: float = 1.0) -> void:
	if _water_y_at(world.x) >= 0.0:
		return
	if _ground_y_at(world.x) < 0.0 and not _is_default_standable(world.x):
		return
	_spawn_splash(world, strength)
	_soak_wet(world)


func _on_water_hit(world: Vector2, strength: float = 1.0) -> void:
	_spawn_water_splash(world, strength)
	_spawn_ripple(world, strength)


func _spawn_splash(world: Vector2, strength: float = 1.0) -> void:
	var host := _ensure_ground_fx()
	if host == null or _splashes == null:
		return
	if _splashes.get_child_count() >= SPLASH_MAX:
		return
	if _splash_tex == null:
		_splash_tex = _make_splash_tex()
	var n := randi_range(2, 5)
	if strength < 0.55:
		n = maxi(1, roundi(float(n) * clampf(strength, 0.25, 1.0)))
	for _i in n:
		if _splashes.get_child_count() >= SPLASH_MAX:
			break
		var speck := _take_splash()
		speck.position = Vector2(roundf(world.x), roundf(world.y))
		speck.arm(strength)
		_splashes.add_child(speck)


func _spawn_water_splash(world: Vector2, strength: float = 1.0) -> void:
	var host := _ensure_ground_fx()
	if host == null or _splashes == null:
		return
	if _splash_tex == null:
		_splash_tex = _make_splash_tex()
	var n := randi_range(2, 4)
	if strength < 0.55:
		n = maxi(1, roundi(float(n) * clampf(strength, 0.25, 1.0)))
	for _i in n:
		if _splashes.get_child_count() >= SPLASH_MAX:
			break
		var speck := _take_water()
		speck.position = Vector2(roundf(world.x), roundf(world.y))
		speck.arm(strength)
		_splashes.add_child(speck)


func _spawn_ripple(world: Vector2, strength: float = 1.0) -> void:
	_ensure_ground_fx()
	if _ripples == null:
		return
	if _ripples.get_child_count() >= RIPPLE_MAX:
		return
	var ring := _take_ripple()
	ring.position = Vector2(roundf(world.x), roundf(world.y))
	ring.arm(strength)
	_ripples.add_child(ring)


func _soak_wet(world: Vector2) -> void:
	if _wets == null:
		return
	if _wet_tex == null:
		_wet_tex = _make_wet_tex()
	var cell := int(floor(world.x / WET_CELL))
	if _wet_by_cell.has(cell):
		var spr: Sprite2D = _wet_by_cell[cell]
		if is_instance_valid(spr):
			spr.set_meta("wet", minf(1.0, float(spr.get_meta("wet")) + 0.28))
			return
	if _wet_by_cell.size() >= WET_MAX:
		_evict_driest_wet()
	var mark := _take_wet()
	var gy := _ground_y_at(world.x)
	if gy < 0.0:
		gy = DEFAULT_GROUND_Y
	mark.position = Vector2(roundf((float(cell) + 0.5) * WET_CELL), roundf(gy + 1.0))
	mark.modulate = Color(0.18, 0.16, 0.24, 0.22)
	mark.set_meta("wet", 0.42)
	mark.visible = true
	_wets.add_child(mark)
	_wet_by_cell[cell] = mark


func _evict_driest_wet() -> void:
	var driest := -1
	var least := 99.0
	for cell in _wet_by_cell:
		var spr: Sprite2D = _wet_by_cell[cell]
		if not is_instance_valid(spr):
			driest = int(cell)
			least = 0.0
			break
		var w := float(spr.get_meta("wet"))
		if w < least:
			least = w
			driest = int(cell)
	if driest < 0:
		return
	var gone: Sprite2D = _wet_by_cell[driest]
	_wet_by_cell.erase(driest)
	if is_instance_valid(gone):
		_recycle_wet(gone)


func _tick_wets(delta: float) -> void:
	if _wets == null:
		return
	var rain := WorldClock.rain_opacity()
	var drain := 0.08 if rain > 0.05 else 0.22
	_wet_dead.clear()
	for cell in _wet_by_cell:
		var spr: Sprite2D = _wet_by_cell[cell]
		if not is_instance_valid(spr):
			_wet_dead.append(int(cell))
			continue
		var w := float(spr.get_meta("wet"))
		w = maxf(0.0, w - drain * delta)
		spr.set_meta("wet", w)
		spr.modulate.a = 0.10 + 0.38 * w
		if w <= 0.01:
			_wet_dead.append(int(cell))
			_recycle_wet(spr)
	for cell in _wet_dead:
		_wet_by_cell.erase(cell)


func _tick_embers(delta: float) -> void:
	var target := WorldClock.ember_wind_opacity()
	_ember_alpha = move_toward(_ember_alpha, target, delta / 4.0)
	if _ember_alpha <= 0.001 and target <= 0.0:
		if not _embers_hidden:
			for spr in _embers:
				spr.modulate.a = 0.0
				spr.visible = false
			_embers_hidden = true
		return
	if _embers_hidden:
		for spr in _embers:
			spr.visible = true
		_embers_hidden = false
	var vis := _ember_alpha * EMBER_ALPHA_CAP
	for spr in _embers:
		var p := spr.position
		p.x += _wind_x * (EMBER_DRIFT / 36.0) * delta
		p.y += sin(p.x * 0.04 + p.y * 0.01) * 10.0 * delta
		if p.x < -10.0:
			p.x = 1290.0
			p.y = 400.0 + randf() * 280.0
		elif p.y < 380.0:
			p.y = 680.0
		elif p.y > 730.0:
			p.y = 400.0 + randf() * 80.0
		spr.position.x = roundf(p.x)
		spr.position.y = roundf(p.y)
		if spr.hframes > 1 and randf() < delta * 6.0:
			spr.frame = (spr.frame + 1) % spr.hframes
		spr.modulate.a = vis


func rain_wind_x() -> float:
	var v := WorldClock.wind_vector().x
	if absf(v) < 0.02:
		return -36.0
	return v * 150.0


func _ensure_ground_fx() -> Node2D:
	if _ground != null and is_instance_valid(_ground):
		return _ground
	var host := get_parent()
	if host == null:
		return null
	var n := host.get_node_or_null("RainGroundFx") as Node2D
	if n == null:
		n = Node2D.new()
		n.name = "RainGroundFx"
		n.z_index = 2
		host.add_child(n)
	_ground = n
	_splashes = n.get_node_or_null("Splashes") as Node2D
	if _splashes == null:
		_splashes = Node2D.new()
		_splashes.name = "Splashes"
		n.add_child(_splashes)
	_wets = n.get_node_or_null("WetMarks") as Node2D
	if _wets == null:
		_wets = Node2D.new()
		_wets.name = "WetMarks"
		n.add_child(_wets)
	_ripples = n.get_node_or_null("Ripples") as Node2D
	if _ripples == null:
		_ripples = Node2D.new()
		_ripples.name = "Ripples"
		n.add_child(_ripples)
	return _ground


func _cache_view() -> void:
	_wind_x = rain_wind_x()
	var vp := get_viewport()
	var cam := vp.get_camera_2d() if vp != null else null
	if cam == null:
		_view_ok = false
		_view_size = vp.get_visible_rect().size if vp != null else Vector2(640.0, 360.0)
		return
	_view_ok = true
	_cam_origin = cam.get_screen_center_position()
	_cam_zoom = cam.zoom
	if _cam_zoom.x == 0.0:
		_cam_zoom = Vector2.ONE
	_view_size = vp.get_visible_rect().size
	_vp_half = _view_size * 0.5


func _screen_to_world(screen: Vector2) -> Vector2:
	if not _view_ok:
		var vp := get_viewport()
		var cam := vp.get_camera_2d() if vp != null else null
		if cam == null:
			return vp.get_canvas_transform().affine_inverse() * screen if vp != null else screen
		var zoom := cam.zoom
		if zoom.x == 0.0:
			zoom = Vector2.ONE
		return cam.get_screen_center_position() + (screen - vp.get_visible_rect().size * 0.5) / zoom
	return _cam_origin + (screen - _vp_half) / _cam_zoom


func _rebuild_spans() -> void:
	_span_x0.clear()
	_span_x1.clear()
	_span_y.clear()
	_span_bottom.clear()
	_water_x0.clear()
	_water_x1.clear()
	_water_y.clear()
	var host := get_parent()
	if host != null:
		_collect_ground(host)
	if _span_x0.is_empty():
		_span_x0.append(0.0)
		_span_x1.append(400.0)
		_span_y.append(DEFAULT_GROUND_Y)
		_span_bottom.append(DEFAULT_GROUND_Y + 80.0)
		_span_x0.append(512.0)
		_span_x1.append(2240.0)
		_span_y.append(DEFAULT_GROUND_Y)
		_span_bottom.append(DEFAULT_GROUND_Y + 80.0)
	if _water_x0.is_empty():
		_water_x0.append(DEFAULT_TOXIN.position.x)
		_water_x1.append(DEFAULT_TOXIN.end.x)
		_water_y.append(DEFAULT_TOXIN.position.y)
	_surfaces_dirty = false


func _on_host_child_changed(_node: Node) -> void:
	_surfaces_dirty = true


func _collect_ground(n: Node) -> void:
	if n is Light2D or n is CineFx or n is WeatherFx:
		return
	if n is Parallax2D or n is CanvasModulate:
		return
	if n is CanvasLayer and String(n.name).begins_with("Parallax"):
		return
	if String(n.name) == "RainGroundFx":
		return
	if n is SolidPlatform:
		var p := n as SolidPlatform
		_span_x0.append(p.global_position.x)
		_span_x1.append(p.global_position.x + p.size.x)
		_span_y.append(p.global_position.y)
		_span_bottom.append(p.global_position.y + p.size.y)
	_try_append_water(n)
	for child in n.get_children():
		_collect_ground(child)


func _try_append_water(n: Node) -> void:
	if n is ToxinPool:
		var r := (n as ToxinPool).surface_rect()
		_water_x0.append(r.position.x)
		_water_x1.append(r.end.x)
		_water_y.append(r.position.y)
		return
	if n.has_method("water_surface"):
		var raw: Variant = n.call("water_surface")
		if raw is Rect2:
			var wr: Rect2 = raw
			_water_x0.append(wr.position.x)
			_water_x1.append(wr.end.x)
			_water_y.append(wr.position.y)
		return
	if n.is_in_group("water"):
		_append_water_collision(n)
		return
	var nm := String(n.name)
	if nm.contains("Water") or nm.ends_with("Pond"):
		_append_water_collision(n)


func _append_water_collision(n: Node) -> void:
	var node := n as Node2D
	if node == null:
		return
	for child in node.get_children():
		var col := child as CollisionShape2D
		if col == null:
			continue
		var rect := col.shape as RectangleShape2D
		if rect == null:
			continue
		var top: float = node.global_position.y + col.position.y - rect.size.y * 0.5
		var x0: float = node.global_position.x + col.position.x - rect.size.x * 0.5
		_water_x0.append(x0)
		_water_x1.append(x0 + rect.size.x)
		_water_y.append(top)
		return
	_water_x0.append(node.global_position.x)
	_water_x1.append(node.global_position.x + 64.0)
	_water_y.append(node.global_position.y)


func _ground_y_at(world_x: float) -> float:
	var best := -1.0
	for i in _span_x0.size():
		if world_x < _span_x0[i] or world_x >= _span_x1[i]:
			continue
		var y := _span_y[i]
		if best < 0.0 or y < best:
			best = y
	return best


func _water_y_at(world_x: float) -> float:
	var best := -1.0
	for i in _water_x0.size():
		if world_x < _water_x0[i] or world_x >= _water_x1[i]:
			continue
		var y := _water_y[i]
		if best < 0.0 or y < best:
			best = y
	return best


func _classify_hit(world: Vector2) -> int:
	var wy := _water_y_at(world.x)
	var gy := _ground_y_at(world.x)
	var kind := HIT_NONE
	var hy := 0.0
	if wy >= 0.0 and world.y >= wy:
		kind = HIT_WATER
		hy = wy
	if gy >= 0.0 and world.y >= gy:
		if kind == HIT_NONE or gy < hy:
			kind = HIT_GROUND
			hy = gy
	_hit_y = hy
	return kind


func _hit_surface(world: Vector2) -> Dictionary:
	var kind := _classify_hit(world)
	if kind == HIT_NONE:
		return {}
	if kind == HIT_WATER:
		return {"kind": "water", "y": _hit_y}
	return {"kind": "ground", "y": _hit_y}


func _is_default_standable(world_x: float) -> bool:
	return (world_x >= 0.0 and world_x <= 400.0) or (world_x >= 512.0 and world_x <= 2240.0)


func _prewarm_pools() -> void:
	for _i in SPLASH_MAX:
		_pool_splash.append(SplashSpeck.new(_splash_tex))
		_pool_water.append(WaterSpeck.new(_splash_tex))
	for _i in RIPPLE_MAX:
		_pool_ripple.append(WaterRipple.new())
	for _i in WET_MAX:
		_pool_wet.append(_make_wet_sprite())


func _make_wet_sprite() -> Sprite2D:
	var mark := Sprite2D.new()
	mark.texture = _wet_tex
	mark.centered = true
	mark.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mark.z_index = 1
	mark.visible = false
	mark.set_process(false)
	return mark


func _take_splash() -> SplashSpeck:
	if _pool_splash.is_empty():
		return SplashSpeck.new(_splash_tex)
	return _pool_splash.pop_back()


func _take_water() -> WaterSpeck:
	if _pool_water.is_empty():
		return WaterSpeck.new(_splash_tex)
	return _pool_water.pop_back()


func _take_ripple() -> WaterRipple:
	if _pool_ripple.is_empty():
		return WaterRipple.new()
	return _pool_ripple.pop_back()


func _take_wet() -> Sprite2D:
	if _pool_wet.is_empty():
		return _make_wet_sprite()
	return _pool_wet.pop_back()


func _recycle_wet(spr: Sprite2D) -> void:
	var parent := spr.get_parent()
	if parent != null:
		parent.remove_child(spr)
	spr.visible = false
	_pool_wet.append(spr)


func _tick_ground_fx(delta: float) -> void:
	if _splashes != null:
		var i := 0
		while i < _splashes.get_child_count():
			var n := _splashes.get_child(i)
			var alive := true
			if n is SplashSpeck:
				alive = (n as SplashSpeck).tick(delta)
			elif n is WaterSpeck:
				alive = (n as WaterSpeck).tick(delta)
			if alive:
				i += 1
				continue
			_splashes.remove_child(n)
			if n is SplashSpeck:
				_pool_splash.append(n as SplashSpeck)
			elif n is WaterSpeck:
				_pool_water.append(n as WaterSpeck)
	if _ripples == null:
		return
	var j := 0
	while j < _ripples.get_child_count():
		var ring := _ripples.get_child(j) as WaterRipple
		if ring != null and ring.tick(delta):
			j += 1
			continue
		if ring != null:
			_ripples.remove_child(ring)
			_pool_ripple.append(ring)
		else:
			j += 1


func _load_ember_tex() -> Texture2D:
	if ResourceLoader.exists(EMBER_PATH):
		var tex := load(EMBER_PATH) as Texture2D
		if tex != null:
			return tex
	return _make_ember_tex()


func _make_ember_tex() -> Texture2D:
	var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.set_pixel(1, 1, Color(1.0, 0.62, 0.34, 0.85))
	img.set_pixel(1, 0, Color(1.0, 0.78, 0.42, 0.45))
	img.set_pixel(0, 1, Color(0.90, 0.40, 0.22, 0.35))
	return ImageTexture.create_from_image(img)


func _make_drop_tex() -> Texture2D:
	var img := Image.create(2, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.set_pixel(0, 0, Color(0.70, 0.78, 0.88, 0.25))
	img.set_pixel(1, 1, Color(0.82, 0.88, 0.94, 0.55))
	img.set_pixel(0, 2, Color(0.88, 0.92, 0.97, 0.70))
	img.set_pixel(1, 3, Color(0.85, 0.90, 0.96, 0.50))
	img.set_pixel(0, 4, Color(0.78, 0.84, 0.92, 0.28))
	img.set_pixel(1, 5, Color(0.72, 0.80, 0.90, 0.12))
	return ImageTexture.create_from_image(img)


func _make_splash_tex() -> Texture2D:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.set_pixel(0, 0, Color(0.82, 0.88, 0.96, 0.70))
	img.set_pixel(1, 1, Color(0.70, 0.78, 0.90, 0.40))
	return ImageTexture.create_from_image(img)


func _make_wet_tex() -> Texture2D:
	var img := Image.create(20, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in 20:
		var edge := 1.0 - absf(float(x) - 9.5) / 10.0
		var a := clampf(edge * 0.55, 0.0, 0.55)
		img.set_pixel(x, 1, Color(0.12, 0.11, 0.18, a))
		img.set_pixel(x, 2, Color(0.22, 0.24, 0.30, a * 0.45))
	img.set_pixel(6, 0, Color(0.40, 0.44, 0.50, 0.22))
	img.set_pixel(13, 0, Color(0.36, 0.40, 0.48, 0.16))
	return ImageTexture.create_from_image(img)


class SplashSpeck extends Sprite2D:
	var _age := 0.0
	var _life := 0.22
	var _vel := Vector2.ZERO
	var _alpha0 := 0.75

	func _init(tex: Texture2D) -> void:
		texture = tex
		centered = true
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		set_process(false)
		visible = false

	func arm(strength: float = 1.0) -> void:
		_age = 0.0
		_vel = Vector2(randf_range(-38.0, 38.0), randf_range(-52.0, -18.0))
		_life = randf_range(0.16, 0.28)
		_alpha0 = 0.75 * clampf(strength, 0.0, 1.0)
		modulate = Color(0.80, 0.86, 0.94, _alpha0)
		visible = true

	func tick(delta: float) -> bool:
		_age += delta
		if _age >= _life:
			visible = false
			return false
		_vel.y += 260.0 * delta
		position.x = roundf(position.x + _vel.x * delta)
		position.y = roundf(position.y + _vel.y * delta)
		modulate.a = _alpha0 * (1.0 - _age / _life)
		return true


class WaterSpeck extends Sprite2D:
	var _age := 0.0
	var _life := 0.20
	var _vel := Vector2.ZERO
	var _alpha0 := 0.80

	func _init(tex: Texture2D) -> void:
		texture = tex
		centered = true
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		set_process(false)
		visible = false

	func arm(strength: float = 1.0) -> void:
		_age = 0.0
		# 落水只往上溅：入水方向是竖直的，水花朝上收束（用户反馈"单方向"），
		# 不再用 8 点径向扩散环去表现水面。
		_vel = Vector2(randf_range(-11.0, 11.0), randf_range(-36.0, -16.0))
		_life = randf_range(0.14, 0.24)
		_alpha0 = 0.80 * clampf(strength, 0.0, 1.0)
		modulate = Color(0.70, 0.88, 0.86, _alpha0)
		visible = true

	func tick(delta: float) -> bool:
		_age += delta
		if _age >= _life:
			visible = false
			return false
		_vel.y += 220.0 * delta
		position.x = roundf(position.x + _vel.x * delta)
		position.y = roundf(position.y + _vel.y * delta)
		modulate.a = _alpha0 * (1.0 - _age / _life)
		return true


## 雨滴落水的水面反馈：**只沿水面横向张开**的一道 1px 亮线（两侧各补 1px 高点），
## 不做圆的径向扩散、也不画 8 点环——用户报告"怎么是扩散的，明明只有单方向"。
class WaterRipple extends Node2D:
	var _age := 0.0
	var _life := 0.22
	var _strength := 1.0

	func _init() -> void:
		z_index = 3
		set_process(false)
		visible = false

	func arm(strength: float = 1.0) -> void:
		_age = 0.0
		_strength = clampf(strength, 0.0, 1.0)
		visible = true
		queue_redraw()

	func tick(delta: float) -> bool:
		_age += delta
		queue_redraw()
		if _age >= _life:
			visible = false
			return false
		return true

	func _draw() -> void:
		var k := clampf(_age / _life, 0.0, 1.0)
		var a := 0.60 * _strength * (1.0 - k)
		if a <= 0.01:
			return
		var col := Color(0.72, 0.90, 0.88, a)
		var half := 1.0 + 3.0 * k
		draw_rect(Rect2(-roundf(half), 0, roundf(half * 2.0) + 1, 1), col)
		if k > 0.30:
			var b := Color(col.r, col.g, col.b, a * 0.55)
			draw_rect(Rect2(roundf(-half) - 1, 1, 1, 1), b)
			draw_rect(Rect2(roundf(half) + 1, 1, 1, 1), b)
