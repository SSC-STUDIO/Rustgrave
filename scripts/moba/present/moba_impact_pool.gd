extends Node3D
## Pooled hit sparks for the arena.
##
## Every damage event the simulation settles spawns one short-lived ring and a
## few ember shards. They are not gameplay objects: the sim already applied the
## damage, this is only the "something got hit" read. Building the ring mesh on
## every hit would allocate a node and a mesh per exchange, so a fixed set of
## premade ember rings is animated and recycled instead.

const KIT := preload("res://scripts/moba/view/toon_kit.gd")
const TOON_PART := preload("res://scripts/moba/view/toon_part.gd")
const FX := preload("res://scripts/moba/present/moba_unit_fx.gd")

const POOL_SIZE := 14
const LIFE := 0.22

var _idle: Array[TOON_PART] = []
var _active: Array[Dictionary] = []
## Ring -> its mesh parts, collected once (the fade walks them every frame).
var _parts: Dictionary = {}
var _serial := 0


func _ready() -> void:
	for i in POOL_SIZE:
		var ring := _make_ring()
		add_child(ring)
		ring.visible = false
		_parts[ring] = FX.collect_parts(ring)
		_idle.append(ring)


## `at` is a world position, `strength` 0.5 for minion hits and 1.0 for a hero
## swing or a structure dropping.
func spawn(at: Vector3, strength: float = 0.6) -> void:
	if _idle.is_empty():
		return
	var ring: TOON_PART = _idle.pop_back()
	_serial += 1
	ring.visible = true
	ring.global_position = at + Vector3(0.0, 0.08, 0.0)
	ring.rotation.y = float(_serial % 8) * TAU / 8.0
	ring.scale = Vector3.ONE * (0.45 + 0.35 * strength)
	FX.set_fade(_parts[ring], 1.0)
	_active.append({"node": ring, "t": 0.0, "strength": clampf(strength, 0.2, 1.4)})


func advance(delta: float) -> void:
	for i in range(_active.size() - 1, -1, -1):
		var entry: Dictionary = _active[i]
		var ring: TOON_PART = entry["node"]
		if not is_instance_valid(ring):
			_active.remove_at(i)
			continue
		entry["t"] = float(entry["t"]) + delta
		var t: float = float(entry["t"])
		if t >= LIFE:
			ring.visible = false
			_active.remove_at(i)
			_idle.append(ring)
			continue
		var u := t / LIFE
		var strength: float = float(entry["strength"])
		ring.scale = Vector3.ONE * ((0.45 + 0.35 * strength) + u * 1.5 * strength)
		FX.set_fade(_parts[ring], 1.0 - u)


func active_count() -> int:
	return _active.size()


func idle_count() -> int:
	return _idle.size()


func clear() -> void:
	for entry: Dictionary in _active:
		var ring: TOON_PART = entry["node"]
		if is_instance_valid(ring):
			ring.visible = false
			_idle.append(ring)
	_active.clear()


## Eight flat ember shards make one ring, merged into a single draw call and
## without the inverted-hull outline (a spark should not have a dark edge).
func _make_ring() -> TOON_PART:
	var ring := TOON_PART.new()
	ring.name = "HitSpark"
	var fx := KIT.EMISSIVE | KIT.NO_OUTLINE
	for i in 8:
		var angle := TAU * float(i) / 8.0
		ring.box(Vector3(0.16, 0.05, 0.36), Vector3(cos(angle) * 0.5, 0.0, sin(angle) * 0.5),
				Palette.EMBER, Vector3(0.0, -rad_to_deg(angle), 0.0), fx)
	ring.box(Vector3(0.3, 0.05, 0.3), Vector3.ZERO, Palette.EMBER_ASH, Vector3.ZERO, fx)
	ring.build()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return ring
