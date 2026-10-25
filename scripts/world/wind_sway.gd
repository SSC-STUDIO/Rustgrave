class_name WindSway
extends Node
## Rotates the parent Node2D around its origin (planted at the sprite's feet).
## Reads WorldClock; never owns particles or clock state.
##
## Perf: one WindSway node per planted tree/bush (a level carries 20-60 of
## them), so this ran once per plant per frame. The sway angle is a pure
## function of the clock's wind, so it is derived once per clock change and
## shared: each node then only compares a cached float and writes the parent's
## rotation when it actually changed. Rotation writes that repeat the previous
## value still dirty the canvas item in Godot, so skipping them is what keeps
## a foliage-heavy level cheap.

@export var amplitude: float = 1.0
@export var freq: float = 0.85

var phase: float = 0.0
var _host: Node2D
var _last_angle: float = 0.0
var _has_host: bool = false

## Shared clock read, invalidated by the wind state itself. The clock's three
## wind fields (heading, speed, gust) are exactly what sway_radians() reads, so
## comparing them is a faithful change test that also survives tests poking the
## fields directly — and costs three float reads instead of a full re-derive.
static var _cached_angle: float = 0.0
static var _cached_heading: float = 0.0
static var _cached_speed: float = -1.0
static var _cached_gust: float = -1.0


func _ready() -> void:
	if is_equal_approx(phase, 0.0):
		phase = randf() * TAU
	_host = get_parent() as Node2D
	_has_host = _host != null
	_apply()


## One shared read of the clock per wind change. Every WindSway instance in
## the level asks this instead of calling into WorldClock itself, so the wind
## query (and its clamps) runs once per wind change rather than once per plant
## per frame.
static func clock_angle() -> float:
	if not is_equal_approx(WorldClock.wind_heading, _cached_heading) \
			or not is_equal_approx(WorldClock.wind_speed, _cached_speed) \
			or not is_equal_approx(WorldClock.gust, _cached_gust):
		_cached_heading = WorldClock.wind_heading
		_cached_speed = WorldClock.wind_speed
		_cached_gust = WorldClock.gust
		_cached_angle = WorldClock.sway_radians()
	return _cached_angle


func _process(delta: float) -> void:
	if not WorldClock.is_frozen():
		phase += delta * freq
	_apply()


func _apply() -> void:
	if not _has_host:
		return
	var angle: float = clock_angle() * amplitude * (0.72 + 0.28 * cos(phase))
	if is_equal_approx(angle, _last_angle):
		return
	_last_angle = angle
	_host.rotation = angle
