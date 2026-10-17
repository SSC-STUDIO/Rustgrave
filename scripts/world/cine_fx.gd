class_name CineFx
extends Node2D
## World-space depth dust / scrap plus a faint moon shaft.
## Presentation only — wind and zone come from WorldClock.

const FAR_COUNT := 12
const MID_COUNT := 10
const NEAR_COUNT := 6
const MOTE_PATH := "res://assets/ui/ember_motes.png"
const GLOW_PATH := "res://assets/env/glow_soft.png"
## Story halos alive at once (the forge answering from down the corridor, a core's flare).
const GLOW_CAP := 3
## 特效不遮挡（docs/art-spec.md）：世界尘埃与故事光晕都在玩法层之后。
## 玩家 / 敌人 z=0；把它们放在 -2 就不会用加法亮斑盖住剪影、前摇和台缘。
const DEPTH_Z := -2
const GLOW_Z := -2
## 故事光晕的 alpha 上限：再亮就会把角色轮廓洗白。
const GLOW_ALPHA_CAP := 0.5

static var _glow_mat: CanvasItemMaterial
static var _glows: Array[Sprite2D] = []

var _far: Array[Sprite2D] = []
var _mid: Array[Sprite2D] = []
var _near: Array[Sprite2D] = []
var _shaft: Sprite2D
var _mote_tex: Texture2D
var _headless := false
var _mid_suppressed := false


func _ready() -> void:
	z_index = DEPTH_Z
	_headless = DisplayServer.get_name() == "headless"
	_mote_tex = _load_motes()
	_shaft = Sprite2D.new()
	_shaft.name = "MoonShaft"
	_shaft.centered = true
	_shaft.texture = _make_shaft_tex()
	_shaft.position = Vector2(420, 80)
	_shaft.rotation = deg_to_rad(11.0)
	_shaft.modulate = Color(0.78, 0.82, 1.0, 0.0)
	_shaft.z_index = -4
	_shaft.visible = false
	add_child(_shaft)
	if _headless:
		return
	# Pale dust may sit in the sky. Warm scrap stays on the ground band —
	# spawning at y=0..360 put orange motes on the moon (read as "sky fire").
	_spawn_layer(_far, FAR_COUNT, 0.70, Color(0.82, 0.84, 0.90, 0.28), 80.0, 260.0)
	_spawn_layer(_mid, MID_COUNT, 1.15, Color(0.82, 0.62, 0.44, 0.48), 230.0, 360.0)
	_spawn_layer(_near, NEAR_COUNT, 1.55, Color(0.94, 0.86, 0.74, 0.62), 250.0, 380.0)


## One soft additive halo in world space that swells and fades on its own. Story
## beats use it to light something the camera is about to find (the forge remnant at
## the end of the corridor). Bounded: past GLOW_CAP the oldest is retired first.
static func glow_pulse(host: Node, world_pos: Vector2, tint: Color, seconds: float, glow_scale: float = 1.6) -> Sprite2D:
	if host == null or not host.is_inside_tree() or not ResourceLoader.exists(GLOW_PATH):
		return null
	var layer := GameContext.world_effects(host)
	if layer == null:
		return null
	_prune_glows()
	while _glows.size() >= GLOW_CAP:
		var oldest: Sprite2D = _glows.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	if _glow_mat == null:
		_glow_mat = CanvasItemMaterial.new()
		_glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var spr := Sprite2D.new()
	spr.name = "StoryGlow"
	spr.texture = load(GLOW_PATH) as Texture2D
	spr.centered = true
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.material = _glow_mat
	spr.z_index = GLOW_Z
	spr.scale = Vector2.ONE * glow_scale * 0.7
	spr.modulate = Color(tint.r, tint.g, tint.b, 0.0)
	var peak := minf(tint.a, GLOW_ALPHA_CAP)
	layer.add_child(spr)
	spr.global_position = world_pos
	_glows.append(spr)
	var span := maxf(seconds, 0.1)
	var swell := spr.create_tween()
	swell.tween_property(spr, "scale", Vector2.ONE * glow_scale, span).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var fade := spr.create_tween()
	fade.tween_property(spr, "modulate:a", peak, span * 0.35)
	fade.tween_property(spr, "modulate:a", 0.0, span * 0.65)
	fade.tween_callback(spr.queue_free)
	return spr


static func glow_count() -> int:
	_prune_glows()
	return _glows.size()


static func clear_glows() -> void:
	for spr in _glows:
		if is_instance_valid(spr):
			spr.queue_free()
	_glows.clear()


static func _prune_glows() -> void:
	var live: Array[Sprite2D] = []
	for spr in _glows:
		if is_instance_valid(spr) and spr.is_inside_tree() and not spr.is_queued_for_deletion():
			live.append(spr)
	_glows = live


func mid_motes_allowed() -> bool:
	return WorldClock.weather_fx_allowed() and WorldClock.wind_speed > 0.05


func shaft_alpha() -> float:
	if WorldClock.menu_hold:
		return 0.0
	if WorldClock.zone == WorldClock.Zone.INDOORS:
		return 0.04
	match WorldClock.phase:
		WorldClock.Phase.NIGHT:
			return 0.20
		WorldClock.Phase.DUSK:
			return 0.12
		WorldClock.Phase.DAWN:
			return 0.08
		_:
			return 0.03


func _process(delta: float) -> void:
	var wind := WorldClock.wind_vector()
	if _shaft != null:
		_shaft.rotation = deg_to_rad(11.0) + wind.x * 0.08
		var a := shaft_alpha()
		_shaft.modulate.a = move_toward(_shaft.modulate.a, a, delta * 0.35)
		var show_shaft := _shaft.modulate.a > 0.004
		if _shaft.visible != show_shaft:
			_shaft.visible = show_shaft
	if _headless:
		return
	var cam := get_viewport().get_camera_2d()
	var origin := cam.global_position if cam != null else global_position
	var rain_cut := 1.0 - WorldClock.rain_opacity() * 0.65
	var wind_vis := clampf(WorldClock.wind_speed * 2.4, 0.2, 1.0)
	_drift(_far, delta, wind, 18.0, origin, 0.22 * rain_cut * wind_vis, -120.0, 80.0)
	if mid_motes_allowed():
		if _mid_suppressed:
			_show_layer(_mid)
			_show_layer(_near)
			_mid_suppressed = false
		_drift(_mid, delta, wind, 52.0, origin, 0.42 * rain_cut * wind_vis, 20.0, 170.0)
		_drift(_near, delta, wind, 88.0, origin, 0.58 * rain_cut * wind_vis, 40.0, 180.0)
	elif not _mid_suppressed:
		_hide_layer(_mid)
		_hide_layer(_near)
		_mid_suppressed = true


func _spawn_layer(bucket: Array[Sprite2D], count: int, scale: float, col: Color, y_min: float, y_max: float) -> void:
	for i in count:
		var spr := Sprite2D.new()
		spr.texture = _mote_tex
		if _mote_tex != null and _mote_tex.get_width() >= 8:
			spr.hframes = 8
			spr.frame = randi() % 8
		spr.centered = true
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(scale, scale)
		spr.modulate = col
		spr.position = Vector2(randf() * 1280.0, randf_range(y_min, y_max))
		add_child(spr)
		bucket.append(spr)


func _drift(bucket: Array[Sprite2D], delta: float, wind: Vector2, speed: float, origin: Vector2, fade: float, y_lo: float, y_hi: float) -> void:
	for spr in bucket:
		var p := spr.position
		p.x += wind.x * speed * delta
		p.y += sin(p.x * 0.03 + p.y * 0.02) * 6.0 * delta
		if p.x < origin.x - 420.0:
			p.x = origin.x + 420.0
			p.y = origin.y + randf_range(y_lo, y_hi)
		elif p.x > origin.x + 420.0:
			p.x = origin.x - 420.0
			p.y = origin.y + randf_range(y_lo, y_hi)
		if p.y < origin.y + y_lo:
			p.y = origin.y + y_hi
		elif p.y > origin.y + y_hi:
			p.y = origin.y + y_lo
		spr.position.x = roundf(p.x)
		spr.position.y = roundf(p.y)
		spr.modulate.a = fade
		if spr.hframes > 1 and randf() < delta * 4.0:
			spr.frame = (spr.frame + 1) % spr.hframes


func _hide_layer(bucket: Array[Sprite2D]) -> void:
	for spr in bucket:
		spr.visible = false
		spr.modulate.a = 0.0


func _show_layer(bucket: Array[Sprite2D]) -> void:
	for spr in bucket:
		spr.visible = true


func _load_motes() -> Texture2D:
	if ResourceLoader.exists(MOTE_PATH):
		return load(MOTE_PATH) as Texture2D
	var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.set_pixel(1, 1, Color(1, 1, 1, 0.8))
	return ImageTexture.create_from_image(img)


func _make_shaft_tex() -> Texture2D:
	var img := Image.create(16, 96, false, Image.FORMAT_RGBA8)
	for y in 96:
		for x in 16:
			var cx := absf(float(x) - 7.5) / 8.0
			var along := 1.0 - float(y) / 96.0
			var a := clampf((1.0 - cx) * (1.0 - cx) * along * 0.55, 0.0, 0.55)
			img.set_pixel(x, y, Color(0.85, 0.88, 1.0, a))
	return ImageTexture.create_from_image(img)
