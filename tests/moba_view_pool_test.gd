extends TestCase
## Sim entity -> pooled minion view: world mapping, anim state, death fade and
## the guarantee that the lane never allocates a node per frame.

const UNIT_POOL := preload("res://scripts/moba/present/moba_unit_pool.gd")
const IMPACT_POOL := preload("res://scripts/moba/present/moba_impact_pool.gd")
const VIEW_MAP := preload("res://scripts/moba/present/moba_view_map.gd")

const STEP := 1.0 / 30.0


func _minion(id: int, team: int, lane_x: float, anim: StringName = &"run", alive: bool = true) -> Dictionary:
	return {
		"id": id, "team": team, "kind": &"minion", "pos": Vector2(lane_x, 0.0),
		"hp": 300.0 if alive else 0.0, "max_hp": 300.0, "facing": 1,
		"anim": anim, "attack_t": 0.0, "alive": alive,
	}


func _pool():
	var pool = UNIT_POOL.new()
	add_child(pool)
	return pool


func test_entities_appear_at_the_mapped_world_position() -> void:
	var pool = _pool()
	pool.sync([_minion(3, 0, -3.0), _minion(9, 1, 4.0, &"idle")], STEP)
	eq(pool.active_count(), 2)
	var blue: Variant = pool.view_for(3)
	var red: Variant = pool.view_for(9)
	ok(blue != null and red != null)
	var blue_world := VIEW_MAP.lane_to_world(Vector2(-3.0, 0.0))
	almost(blue.global_position.x, blue_world.x, 0.0001, "view x follows the lane mapping")
	almost(blue.global_position.z, blue_world.z, 0.0001)
	almost(blue.global_position.y, 0.0, 0.0001)
	eq(blue.team, 0)
	eq(red.team, 1)
	eq(StringName(blue._anim), &"run")
	eq(StringName(red._anim), &"idle")
	almost(blue.visual.rotation.y, VIEW_MAP.yaw_for_facing(1), 0.0001)
	pool.queue_free()


func test_pool_reuses_views_and_never_grows_while_ids_are_stable() -> void:
	var pool = _pool()
	var entities := [_minion(3, 0, -2.0), _minion(4, 0, -1.0), _minion(9, 1, 2.0)]
	pool.sync(entities, STEP)
	var created: int = pool.created_count
	var children: int = pool.pool_children()
	eq(created, 3)
	for i in 60:
		entities[0]["pos"] = Vector2(-2.0 + float(i) * 0.05, 0.0)
		pool.sync(entities, STEP)
	eq(pool.created_count, created, "no minion node is created after the first sync")
	eq(pool.pool_children(), children, "the pool scene subtree does not grow")
	eq(pool.active_count(), 3)
	pool.queue_free()


func test_despawned_entities_fade_out_and_are_recycled() -> void:
	var pool = _pool()
	pool.sync([_minion(3, 0, -2.0), _minion(4, 0, -1.0)], STEP)
	eq(pool.pool_children(), 2)
	# Entity 4 dies: the view plays the death fade while still tracked.
	var dead := _minion(4, 0, -1.0, &"dead", false)
	for i in 20:
		pool.sync([_minion(3, 0, -2.0), dead], STEP * 2.0)
	eq(pool.active_count(), 2, "a dead entity still has its view until it is removed")
	# The sim then removes the minion from entities(): return the view to the pool.
	pool.sync([_minion(3, 0, -2.0)], STEP)
	eq(pool.active_count(), 1)
	eq(pool.retiring_count(), 0, "the finished death fade is recycled at once")
	eq(pool.free_count(), 1)
	eq(pool.pool_children(), 2, "recycling keeps the node, it is just hidden")
	# A later minion reuses the retired view instead of creating one.
	pool.sync([_minion(3, 0, -2.0), _minion(6, 0, -0.5)], STEP)
	eq(pool.created_count, 2, "the pooled view served the new entity")
	eq(pool.active_count(), 2)
	eq(pool.free_count(), 0)
	pool.queue_free()


func test_hit_flash_is_transient_and_cleared_on_reset() -> void:
	var pool = _pool()
	pool.sync([_minion(3, 0, 0.0)], STEP)
	var view: Variant = pool.view_for(3)
	pool.flash(3)
	ok(view._parts[0].material_overlay != null, "the hit flash paints the unit white")
	pool.sync([_minion(3, 0, 0.0)], 0.2)
	ok(view._parts[0].material_overlay == null, "the flash ends on its own")
	pool.flash(3)
	view.retire()
	pool.sync([], STEP)
	eq(pool.active_count(), 0)
	eq(pool.retiring_count(), 1, "a retired view fades before it is recycled")
	pool.queue_free()


func test_silhouette_variant_is_deterministic_per_id() -> void:
	eq(UNIT_POOL.variant_of(_minion(3, 0, 0.0)), "0:0")
	eq(UNIT_POOL.variant_of(_minion(5, 0, 0.0)), "0:1")
	eq(UNIT_POOL.variant_of(_minion(9, 1, 0.0)), "1:0")
	eq(UNIT_POOL.anim_of({"anim": "run"}), &"run")
	eq(UNIT_POOL.anim_of({"anim": &"attack"}), &"attack")
	eq(UNIT_POOL.lane_of({"pos": Vector2(3.5, -1.25)}), Vector2(3.5, -1.25))


func test_impact_pool_recycles_a_fixed_ring_set() -> void:
	var pool = IMPACT_POOL.new()
	add_child(pool)
	var children: int = pool.get_child_count()
	eq(children, IMPACT_POOL.POOL_SIZE)
	for i in 20:
		pool.spawn(Vector3(float(i), 0.0, 0.0), 1.0)
	eq(pool.active_count(), IMPACT_POOL.POOL_SIZE, "spawning never exceeds the pool")
	pool.advance(0.3)
	eq(pool.active_count(), 0)
	eq(pool.idle_count(), IMPACT_POOL.POOL_SIZE)
	for i in 5:
		pool.spawn(Vector3.ZERO, 0.5)
	eq(pool.active_count(), 5)
	eq(pool.get_child_count(), children, "impact sparks never allocate nodes after warm-up")
	pool.queue_free()
