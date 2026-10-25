extends TestCase

const STRUCTURES := preload("res://scripts/world/terrain_structures.gd")


func teardown() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	Director.abort()


func _slab(host: Node2D, pos: Vector2, sz: Vector2, skin: String) -> SolidPlatform:
	var slab := SolidPlatform.new()
	slab.position = pos
	slab.size = sz
	slab.skin = skin
	host.add_child(slab)
	return slab


func test_low_step_has_actual_collision_to_its_foundation() -> void:
	var host := Node2D.new()
	add_child(host)
	_slab(host, Vector2(0, 320), Vector2(400, 80), "nave")
	var step := _slab(host, Vector2(64, 288), Vector2(64, 16), "nave_float")
	STRUCTURES.build(host)
	eq(step.get_meta("structure_kind", ""), "solid_plinth")
	var plinth := step.get_node_or_null("MasonryPlinth") as SolidPlatform
	ok(plinth != null, "the support is solid terrain")
	if plinth != null:
		eq(plinth.global_position, Vector2(64, 304))
		eq(plinth.size, Vector2(64, 16))
		await flush(2)
		var query := PhysicsPointQueryParameters2D.new()
		query.position = Vector2(96, 312)
		query.collision_mask = 1
		ok(not host.get_world_2d().direct_space_state.intersect_point(query).is_empty(), "the foundation fills the physical gap")
	host.queue_free()


func test_high_arcade_preserves_a_passage_and_collapse_keeps_its_piers() -> void:
	var host := Node2D.new()
	add_child(host)
	_slab(host, Vector2(0, 320), Vector2(400, 80), "nave")
	var deck := _slab(host, Vector2(64, 208), Vector2(160, 16), "nave_float")
	var fragile := CollapsingPlatform.new()
	fragile.position = Vector2(240, 208)
	host.add_child(fragile)
	STRUCTURES.build(host)
	eq(deck.get_meta("structure_kind", ""), "rear_arcade")
	eq(deck.size, Vector2(160, 16), "a walkable passage is not filled with a solid wall")
	ok(deck.get_node_or_null("RearArcade") != null)
	ok(fragile.get_node_or_null("RearArcade") == null, "the fixed trestle must not fall with the broken deck")
	await flush(2)
	var query := PhysicsPointQueryParameters2D.new()
	query.position = Vector2(72, 290)
	query.collision_mask = 1
	ok(host.get_world_2d().direct_space_state.intersect_point(query).is_empty(), "rear piers do not collide in the foreground walking plane")
	fragile.trigger()
	fragile.tick(1.0)
	ok(fragile.is_collapsed())
	host.queue_free()


func test_all_campaign_platforms_have_a_load_path_and_lift_ropes_meet_gantries() -> void:
	for id in GameContext.LEVELS:
		SaveData.delete_save()
		SaveData.flags.clear()
		var host := (load(GameContext.LEVELS[id]) as PackedScene).instantiate() as Node2D
		add_child(host)
		await flush(2)
		Director.abort()
		ok(host.has_meta(STRUCTURES.BUILT), "%s assembled its structures" % id)
		var bodies: Array[Node] = []
		STRUCTURES._collect(host, bodies)
		for body in bodies:
			if body is SolidPlatform:
				var p := body as SolidPlatform
				if p.size.x <= 20 or String(p.name).begins_with("Ceiling"):
					continue
				ok(p.has_meta("structure_kind"), "%s/%s has structural support" % [id, p.name])
			elif body is MovingPlatform:
				var lift := body as MovingPlatform
				eq(lift.get_meta("structure_kind", ""), "gantry", "%s/%s is mounted" % [id, lift.name])
				var chain := lift.get_node("Chain0") as Line2D
				almost(lift.position.y + chain.points[1].y, lift.chain_top_y, 0.1, "%s/%s chain endpoint %s meets beam %s" % [id, lift.name, lift.position.y + chain.points[1].y, lift.chain_top_y])
			elif body is GearPlatform:
				ok(body.has_meta("structure_kind"), "%s/%s is a pier, not a floating stone" % [id, body.name])
		host.free()
		await flush(1)
