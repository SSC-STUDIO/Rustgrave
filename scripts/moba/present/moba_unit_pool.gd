extends Node3D
## Object pool for sim-driven lane minions.
##
## MobaSim owns the minion lifecycle: a wave spawns entities with ids and ids
## disappear when the unit dies. Creating a Node3D per spawn would churn the
## scene tree every wave, so this pool keeps minion views alive, hands them to
## new ids and only creates a view when no retired one of the same silhouette
## and team is free. Views are never created in steady state.
##
## `sync()` is fed the simulation's entity dictionaries every frame; the hero
## itself has its own dedicated view and is not part of this pool.

const MINION_VIEW := preload("res://scripts/moba/present/moba_minion_view.gd")
const VIEW_MAP := preload("res://scripts/moba/present/moba_view_map.gd")

## id -> minion view that is currently showing a live sim entity.
var _views: Dictionary = {}
## variant key ("team:caster") -> recycled views, hidden and reset.
var _free: Dictionary = {}
## Views fading out after their sim entity disappeared.
var _retiring: Array = []
var _seen: Dictionary = {}
var created_count := 0


func sync(entities: Array, delta: float) -> void:
	var seen := _seen
	seen.clear()
	for raw in entities:
		if raw is not Dictionary:
			continue
		var entity: Dictionary = raw
		var id := int(entity.get("id", 0))
		var team := int(entity.get("team", 0))
		var variant := variant_of(entity)
		var view: Variant = _views.get(id)
		if view == null or not is_instance_valid(view):
			view = _acquire(team, variant)
			_views[id] = view
		seen[id] = true
		var anim := anim_of(entity)
		var alive := bool(entity.get("alive", anim != &"dead"))
		var lane := lane_of(entity)
		view.apply(
				VIEW_MAP.lane_to_world(lane),
				VIEW_MAP.yaw_for_facing(int(entity.get("facing", 1))),
				anim,
				alive)
		view.advance(delta)
	for id_v in _views.keys():
		var id := int(id_v)
		if seen.has(id):
			continue
		var view: Variant = _views[id]
		_views.erase(id)
		if is_instance_valid(view):
			view.retire()
			_retiring.append(view)
	for i in range(_retiring.size() - 1, -1, -1):
		var view: Variant = _retiring[i]
		if not is_instance_valid(view):
			_retiring.remove_at(i)
			continue
		view.advance(delta)
		if view.retire_done():
			_recycle(view)
			_retiring.remove_at(i)


func flash(id: int) -> void:
	var view: Variant = _views.get(id)
	if view != null and is_instance_valid(view):
		view.flash()


func view_for(id: int) -> Node3D:
	var view: Variant = _views.get(id)
	if view != null and is_instance_valid(view):
		return view as Node3D
	return null


func active_views() -> Array:
	var out: Array = []
	for view in _views.values():
		if is_instance_valid(view):
			out.append(view)
	return out


func active_count() -> int:
	return _views.size()


func retiring_count() -> int:
	return _retiring.size()


func free_count() -> int:
	var total := 0
	for bucket: Array in _free.values():
		total += bucket.size()
	return total


func pool_children() -> int:
	return get_child_count()


func clear() -> void:
	for view in _views.values():
		if is_instance_valid(view):
			view.queue_free()
	for view in _retiring:
		if is_instance_valid(view):
			view.queue_free()
	for bucket: Array in _free.values():
		for view in bucket:
			if is_instance_valid(view):
				view.queue_free()
	_views.clear()
	_retiring.clear()
	_free.clear()
	_seen.clear()
	created_count = 0


## Team plus silhouette for one entity. The sim only publishes kind, so casters
## are picked deterministically from the id: the same match always looks alike.
static func variant_of(entity: Dictionary) -> String:
	var team := int(entity.get("team", 0))
	var kind := StringName(entity.get("kind", &"minion"))
	var caster := kind == &"caster" or kind == &"minion_caster" \
			or (kind == &"minion" and int(entity.get("id", 0)) % 3 == 2)
	return "%d:%d" % [team, 1 if caster else 0]


static func anim_of(entity: Dictionary) -> StringName:
	var anim: Variant = entity.get("anim", &"idle")
	if anim is StringName:
		return anim
	return StringName(String(anim))


static func lane_of(entity: Dictionary) -> Vector2:
	var pos: Variant = entity.get("pos", Vector2.ZERO)
	if pos is Vector2:
		return pos
	return Vector2(float(pos.x), float(pos.y))


func _acquire(team: int, variant: String) -> Variant:
	var bucket: Array = _free.get(variant, [])
	var view: Variant = null
	while not bucket.is_empty() and view == null:
		var candidate: Variant = bucket.pop_back()
		if is_instance_valid(candidate):
			view = candidate
	if view == null:
		var minion: Variant = MINION_VIEW.new()
		minion.team = team
		minion.caster = variant.ends_with(":1")
		add_child(minion)
		created_count += 1
		return minion
	view.visible = true
	view.reset_visual()
	return view


func _recycle(view: Variant) -> void:
	if not is_instance_valid(view):
		return
	view.visible = false
	var variant := "%d:%d" % [int(view.team), 1 if bool(view.caster) else 0]
	var bucket: Array = _free.get(variant, [])
	bucket.append(view)
	_free[variant] = bucket
