class_name ThemeMotes
extends Node2D
## One drifting-speck flavour per chapter, so rooms that share a pack still feel
## different in motion: forge embers climb, core cinders fall, workshop sparks
## spit and arc, tower dust sinks through the shafts, chapel candle-motes hang,
## undercroft spores rise slowly. Presentation only: it reads the camera, never
## touches physics, saves or Engine.time_scale. One CanvasItem, hard-capped.

const MAX_MOTES := 40
const MARGIN := Vector2(340.0, 200.0)
## 特效不遮挡（docs/art-spec.md）：浮尘是氛围层，画在玩法层（角色 z=0）之后、
## 地形贴片（z=-1）之前。之前 z=4 会让 2px 亮粒横穿脸和敌人前摇。
const DEPTH_Z := -2

## count / size / color / alpha / vel (px/s) / jitter / gravity / sway (px/s²-ish) /
## life range / spawn: "any" (anywhere in view), "bottom", "top", "burst" /
## twinkle: alpha wobble rate (0 = none) / glow: draw a dim 1px halo.
const FLAVORS := {
	"embers": {
		"count": 28, "size": 2, "color": Color(1.0, 0.55, 0.18), "alpha": 0.9,
		"vel": Vector2(4.0, -30.0), "jitter": Vector2(10.0, 12.0), "gravity": 0.0, "sway": 16.0,
		"life": Vector2(3.5, 7.0), "spawn": "bottom", "twinkle": 5.0, "glow": true,
	},
	"cinders": {
		"count": 24, "size": 2, "color": Color(0.95, 0.4, 0.24), "alpha": 0.7,
		"vel": Vector2(-8.0, 20.0), "jitter": Vector2(8.0, 8.0), "gravity": 0.0, "sway": 20.0,
		"life": Vector2(5.0, 9.0), "spawn": "top", "twinkle": 2.0, "glow": false,
	},
	"sparks": {
		"count": 30, "size": 1, "color": Color(1.0, 0.86, 0.5), "alpha": 1.0,
		"vel": Vector2(0.0, -70.0), "jitter": Vector2(48.0, 34.0), "gravity": 170.0, "sway": 0.0,
		"life": Vector2(0.45, 1.0), "spawn": "burst", "twinkle": 0.0, "glow": false,
		"burst": Vector2(1.6, 3.4), "burst_count": Vector2(4.0, 8.0),
	},
	"candle": {
		"count": 16, "size": 1, "color": Color(1.0, 0.82, 0.48), "alpha": 0.7,
		"vel": Vector2(0.0, -4.0), "jitter": Vector2(4.0, 4.0), "gravity": 0.0, "sway": 8.0,
		"life": Vector2(5.0, 10.0), "spawn": "any", "twinkle": 1.6, "glow": false,
	},
	"dust": {
		"count": 22, "size": 1, "color": Color(0.74, 0.78, 0.9), "alpha": 0.5,
		"vel": Vector2(0.0, 9.0), "jitter": Vector2(3.0, 3.0), "gravity": 0.0, "sway": 6.0,
		"life": Vector2(6.0, 12.0), "spawn": "top", "twinkle": 0.0, "glow": false,
	},
	"spores": {
		"count": 18, "size": 2, "color": Color(0.6, 1.0, 0.55), "alpha": 0.6,
		"vel": Vector2(0.0, -9.0), "jitter": Vector2(5.0, 4.0), "gravity": 0.0, "sway": 10.0,
		"life": Vector2(5.0, 9.0), "spawn": "bottom", "twinkle": 2.4, "glow": true,
	},
}

@export var flavor: String = "embers"

var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _burst_t := 0.0
var _primed := false
var _headless := false
var _spec: Dictionary = {}
## `_draw` is one draw call for the whole pool, but queue_redraw() still marks
## the canvas item dirty every frame and re-runs the draw script for all 40
## motes even when nothing moved (a paused menu, a frozen clock). Only redraw
## when the simulation actually advanced something.
var _needs_redraw := true


static func has_flavor(id: String) -> bool:
	return FLAVORS.has(id)


func _ready() -> void:
	z_index = DEPTH_Z
	_headless = DisplayServer.get_name() == "headless"
	_rng.seed = hash(flavor) ^ 0x51ed
	configure(flavor)
	material = Fx.additive_mat()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _headless:
		set_process(false)


## Reset the pool for `id`. Unknown ids fall back to embers so a typo is visible,
## not silent.
func configure(id: String) -> void:
	flavor = id if FLAVORS.has(id) else "embers"
	_spec = FLAVORS[flavor]
	var n := mini(int(_spec["count"]), MAX_MOTES)
	_pos.resize(n)
	_vel.resize(n)
	_age.resize(n)
	_life.resize(n)
	_phase.resize(n)
	for i in n:
		_life[i] = 0.0
		_age[i] = 0.0
	_burst_t = 0.4
	_primed = false


func mote_count() -> int:
	return _pos.size()


func live_count() -> int:
	var n := 0
	for i in _pos.size():
		if _age[i] < _life[i]:
			n += 1
	return n


func _process(delta: float) -> void:
	# A frozen clock (pause menu, cinematic, fade) holds every other ambient
	# layer still — LeafShed and WeatherFx already bail here. Motes must too,
	# or they keep drifting while the world is paused.
	if delta <= 0.0 or WorldClock.is_frozen():
		return
	var cam := get_viewport().get_camera_2d()
	var origin := cam.get_screen_center_position() if cam != null else global_position
	step(delta, origin)
	if _needs_redraw:
		_needs_redraw = false
		queue_redraw()


## Advance the simulation. Public so tests drive it without a camera.
func step(delta: float, origin: Vector2) -> void:
	if _spec.is_empty() or delta <= 0.0:
		return
	var burst := String(_spec["spawn"]) == "burst"
	if not _primed:
		# First real frame: scatter the pool across the actual view with random ages,
		# so the room is not empty for five seconds and nothing fades in in lockstep.
		_primed = true
		if not burst:
			for i in _pos.size():
				_respawn(i, origin, true)
	if burst:
		_burst_t -= delta
		if _burst_t <= 0.0:
			var gap: Vector2 = _spec["burst"]
			_burst_t = _rng.randf_range(gap.x, gap.y)
			_spawn_burst(origin)
	var sway: float = _spec["sway"]
	var grav: float = _spec["gravity"]
	for i in _pos.size():
		if _age[i] >= _life[i]:
			if not burst:
				_respawn(i, origin, false)
			continue
		_age[i] += delta
		var v := _vel[i]
		v.y += grav * delta
		_vel[i] = v
		var p := _pos[i]
		p += v * delta
		if sway > 0.0:
			p.x += sin(_age[i] * 1.7 + _phase[i]) * sway * delta
		_pos[i] = p
		# Drifted out of the view: recycle instead of simulating off-screen motes.
		if not burst and (absf(p.x - origin.x) > MARGIN.x or absf(p.y - origin.y) > MARGIN.y):
			_age[i] = _life[i]


func _respawn(i: int, origin: Vector2, anywhere: bool) -> void:
	var jitter: Vector2 = _spec["jitter"]
	var vel: Vector2 = _spec["vel"]
	var life: Vector2 = _spec["life"]
	var spawn := String(_spec["spawn"])
	var x := origin.x + _rng.randf_range(-MARGIN.x, MARGIN.x)
	var y := origin.y + _rng.randf_range(-MARGIN.y, MARGIN.y)
	if not anywhere:
		match spawn:
			"bottom":
				y = origin.y + MARGIN.y * _rng.randf_range(0.2, 0.95)
			"top":
				y = origin.y - MARGIN.y * _rng.randf_range(0.6, 1.0)
	_pos[i] = Vector2(x, y)
	_vel[i] = vel + Vector2(_rng.randf_range(-jitter.x, jitter.x), _rng.randf_range(-jitter.y, jitter.y))
	_life[i] = _rng.randf_range(life.x, life.y)
	_age[i] = _rng.randf_range(0.0, _life[i]) if anywhere else 0.0
	_phase[i] = _rng.randf() * TAU
	_needs_redraw = true


## A cluster of sparks thrown from one point on the lower third of the view.
func _spawn_burst(origin: Vector2) -> void:
	var count_range: Vector2 = _spec["burst_count"]
	var want := _rng.randi_range(int(count_range.x), int(count_range.y))
	var jitter: Vector2 = _spec["jitter"]
	var vel: Vector2 = _spec["vel"]
	var life: Vector2 = _spec["life"]
	var at := Vector2(origin.x + _rng.randf_range(-260.0, 260.0), origin.y + _rng.randf_range(60.0, 130.0))
	var spawned := 0
	for i in _pos.size():
		if spawned >= want:
			break
		if _age[i] < _life[i]:
			continue
		_pos[i] = at
		_vel[i] = vel + Vector2(_rng.randf_range(-jitter.x, jitter.x), _rng.randf_range(-jitter.y, jitter.y))
		_life[i] = _rng.randf_range(life.x, life.y)
		_age[i] = 0.0
		_phase[i] = _rng.randf() * TAU
		spawned += 1


## Alpha envelope for mote `i`: quick fade-in, long fade-out, optional twinkle.
func mote_alpha(i: int) -> float:
	if i < 0 or i >= _pos.size() or _age[i] >= _life[i]:
		return 0.0
	var t := _age[i] / maxf(_life[i], 0.001)
	var env := minf(t / 0.12, 1.0) * minf((1.0 - t) / 0.45, 1.0)
	var a: float = float(_spec["alpha"]) * clampf(env, 0.0, 1.0)
	var tw: float = _spec["twinkle"]
	if tw > 0.0:
		a *= 0.65 + 0.35 * sin(_age[i] * tw + _phase[i])
	return clampf(a, 0.0, 1.0)


func _draw() -> void:
	if _spec.is_empty():
		return
	var base: Color = _spec["color"]
	var px: int = _spec["size"]
	var glow: bool = _spec["glow"]
	var is_spark := String(_spec["spawn"]) == "burst"
	for i in _pos.size():
		var a := mote_alpha(i)
		if a <= 0.01:
			continue
		var c := base
		if is_spark:
			# Hot white at birth, cooling to orange as it dies.
			var t := _age[i] / maxf(_life[i], 0.001)
			c = Color(1.0, lerpf(0.95, 0.4, t), lerpf(0.75, 0.12, t))
		c.a = a
		var at := Vector2(roundf(_pos[i].x), roundf(_pos[i].y))
		if glow:
			var halo := c
			halo.a = a * 0.22
			draw_rect(Rect2(at - Vector2.ONE, Vector2(px + 2, px + 2)), halo)
		draw_rect(Rect2(at, Vector2(px, px)), c)
