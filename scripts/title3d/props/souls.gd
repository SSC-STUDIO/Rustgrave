extends "res://scripts/title3d/props/title_prop3d.gd"
## Ember-souls rising from the lava (2D: scripts/ui/title_souls.gd,
## docs/title-live-scene.md §6.1).
##
## A fixed pool of 16 additive light motes lifts off the molten river
## (TitleLayout SOULS_MIN..SOULS_MAX). Normally a soul only rises a couple of metres
## and fades — the dead are still trapped in the fire. With `souls_escape` (the
## 'give' / 'true_break' endings) every one of them climbs all the way to the skylight
## and leaves through the roof (SOULS_EXIT). The pool size comes from the grade's
## `souls_goal` (0..16) and `soul_boost(n)` / `kick(n)` adds up to n more for four
## seconds (the 'quit' menu reaction).
##
## Node contract: exactly 16 billboard sprites are built; the pool marks them alive /
## dead, so advance() never allocates and never touches the tree.

const POOL := 16
const SOULS_MIN := Vector3(-7.5, -5.4, -18.0)
const SOULS_MAX := Vector3(7.5, -5.4, -4.0)
const SOULS_EXIT := Vector3(3.5, 14.4, -12.0)
## 2D: 8..14 px/s rise, 40..110 px of climb before fading -> 0.3..0.52 m/s, 1.5..4 m.
const RISE_MIN := 0.30
const RISE_MAX := 0.52
const KICK_SECONDS := 4.0
const CORE := Color(0.92, 0.97, 1.0)
const HALO := Color(0.55, 0.78, 1.0)

var _sprites: Array[MeshInstance3D] = []
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _size := PackedFloat32Array()
var _alive := PackedByteArray()

var _rate := 0.0
var _goal := 0
var _escape := false
var _extra := 0
var _extra_left := 0.0
var _seeded := false
var _spawn_min := SOULS_MIN
var _spawn_max := SOULS_MAX
var _exit := SOULS_EXIT


func _build() -> void:
	_spawn_min = LV3("SOULS_MIN", SOULS_MIN)
	_spawn_max = LV3("SOULS_MAX", SOULS_MAX)
	_exit = LV3("SOULS_EXIT", SOULS_EXIT)
	_pos.resize(POOL)
	_vel.resize(POOL)
	_age.resize(POOL)
	_life.resize(POOL)
	_phase.resize(POOL)
	_size.resize(POOL)
	_alive.resize(POOL)
	var tex := GEO.glow_texture()
	for i in POOL:
		_alive[i] = 0
		_life[i] = 1.0
		_age[i] = 0.0
		var sprite := GEO.sprite_quad(0.22, 0.22, tex)
		sprite.name = "Soul%d" % i
		sprite.visible = false
		add_child(sprite)
		_sprites.append(sprite)
	_apply_grade()
	_sync()


func _apply_plan() -> void:
	if _plan.has("souls_rate"):
		set_flow(p_float("souls_rate", _rate), p_bool("souls_escape", _escape))


func _apply_grade() -> void:
	var goal := g_int("souls_goal", -1)
	if goal >= 0:
		set_goal(goal, g_bool("souls_escape", _escape))
	else:
		set_flow(g_float("souls_rate", _rate), g_bool("souls_escape", _escape))
	if is_built():
		_sync()


## Pool goal (0..16) + whether the souls leave through the roof (3D grade contract).
func set_goal(n: int, escape: bool) -> void:
	var next_goal := clampi(n, 0, POOL)
	if next_goal != _goal or escape != _escape:
		_goal = next_goal
		_escape = escape
		_rate = float(next_goal) / float(POOL)
		_seeded = false
		if next_goal == 0:
			_clear()


## 2D TitleWorld name: rate 0..1 of the pool plus the escape route.
func set_flow(new_rate: float, escape: bool) -> void:
	set_goal(clampi(int(roundf(clampf(new_rate, 0.0, 1.0) * float(POOL))), 0, POOL), escape)


func _clear() -> void:
	for i in POOL:
		_alive[i] = 0


## Simultaneous souls allowed right now (goal + the temporary 'quit' surplus).
func target_count() -> int:
	var n := _goal
	if _extra_left > 0.0:
		n += _extra
	return clampi(n, 0, POOL)


## 'quit' menu reaction: up to n extra souls for KICK_SECONDS seconds.
func soul_boost(n: int = 6) -> void:
	_extra = clampi(n, 0, POOL)
	_extra_left = KICK_SECONDS
	if is_built():
		_sync()


## 2D name for the same reaction.
func kick(n: int) -> void:
	soul_boost(n)


func live_count() -> int:
	var n := 0
	for i in POOL:
		n += int(_alive[i])
	return n


func is_escaping() -> bool:
	return _escape


func rate() -> float:
	return _rate


## Highest altitude reached by a live soul (metres; -100000 when the pool is idle).
func highest_y() -> float:
	var best := -100000.0
	for i in POOL:
		if _alive[i] == 1:
			best = maxf(best, _pos[i].y)
	return best


func _tick(dt: float) -> void:
	if _extra_left > 0.0:
		_extra_left = maxf(_extra_left - dt, 0.0)
	var allowed := target_count()
	if not _seeded:
		_seeded = true
		# First frame: spread the pool over its rise so the hall opens populated.
		for i in allowed:
			if _alive[i] == 0:
				_spawn(i, true)
	for i in POOL:
		if _alive[i] == 0:
			if i < allowed:
				_spawn(i, false)
			continue
		_age[i] += dt
		if _escape:
			# steer toward the skylight gap and let it carry them out
			var to_exit := _exit - _pos[i]
			_vel[i] = _vel[i].lerp(to_exit.normalized() * maxf(_vel[i].length(), 0.9),
					1.0 - exp(-0.6 * dt))
		var p := _pos[i] + _vel[i] * dt
		p.x += sin(t * 1.1 + _phase[i]) * 0.06 * dt
		_pos[i] = p
		if _age[i] >= _life[i] or (_escape and p.y > _exit.y):
			_alive[i] = 0
			if i < allowed:
				_spawn(i, false)


func _spawn(i: int, initial: bool) -> void:
	var at := Vector3(
			rng.randf_range(_spawn_min.x, _spawn_max.x),
			_spawn_min.y,
			rng.randf_range(_spawn_min.z, _spawn_max.z))
	_phase[i] = rng.randf() * TAU
	_size[i] = 0.20 + rng.randf() * 0.10
	if _escape:
		var life := rng.randf_range(9.0, 13.0)
		_life[i] = life
		var dir := at.direction_to(_exit)
		_vel[i] = dir * maxf(_exit.distance_to(at) / life, 1.0)
		_vel[i].x += (_exit.x - at.x) / life * 0.2
	else:
		var life := rng.randf_range(5.0, 8.0)
		_life[i] = life
		_vel[i] = Vector3(rng.randf_range(-0.08, 0.08),
				rng.randf_range(RISE_MIN, RISE_MAX), rng.randf_range(-0.05, 0.05))
	_age[i] = _life[i] * rng.randf() * 0.9 if initial else 0.0
	_pos[i] = at + _vel[i] * _age[i]
	_alive[i] = 1


func _sync() -> void:
	if _sprites.is_empty():
		return
	for i in POOL:
		var sprite := _sprites[i]
		if _alive[i] == 0:
			sprite.visible = false
			continue
		sprite.visible = true
		sprite.position = _pos[i]
		var f := _age[i] / maxf(_life[i], 0.001)
		var twinkle := 0.55 + 0.45 * sin(t * 2.6 + _phase[i])
		var alpha := minf(pow(maxf(sin(f * PI), 0.0), 0.65) * twinkle, 1.0)
		if _extra_left > 0.0 and i >= _goal:
			alpha = minf(alpha * 1.4, 1.0)
		var size := _size[i]
		sprite.scale = Vector3.ONE * (size / 0.22)
		# additive white-blue mote; the escape route reads a little brighter
		set_sprite(sprite, Color(CORE.r, CORE.g, CORE.b, alpha * 0.85))


func alive_count() -> int:
	return live_count()


func pool_size() -> int:
	return POOL


func _snapshot_into(out: Dictionary) -> void:
	out["goal"] = _goal
	out["escape"] = _escape
	out["alive"] = live_count()
	out["highest"] = snappedf(highest_y(), 0.000001)
