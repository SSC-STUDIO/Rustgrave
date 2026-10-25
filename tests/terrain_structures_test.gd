extends TestCase

const STRUCTURES := preload("res://scripts/world/terrain_structures.gd")


func teardown() -> void:
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.pending_spawn = Vector2.INF
	Director.abort()


func _slab(host: Node2D, pos: Vector2, sz: Vector2, skin: String, slab_name: String = "") -> SolidPlatform:
	var slab := SolidPlatform.new()
	if slab_name != "":
		slab.name = slab_name
	slab.position = pos
	slab.size = sz
	slab.skin = skin
	host.add_child(slab)
	return slab


func _lift(host: Node2D, lift_name: String, pos: Vector2, travel: Vector2) -> MovingPlatform:
	var lift := MovingPlatform.new()
	lift.name = lift_name
	lift.position = pos
	lift.travel = travel
	host.add_child(lift)
	return lift


## Fixed tops a load can rest on (independent of the builder's own bookkeeping).
func _fixed_tops(bodies: Array[Node]) -> Array[Rect2]:
	var tops: Array[Rect2] = []
	for body in bodies:
		if body is SolidPlatform and not (body is CollapsingPlatform) and not (body is ConveyorBelt):
			var p := body as SolidPlatform
			if p.size.x > 20.0 and not String(p.name).begins_with("Ceiling"):
				tops.append(Rect2(p.global_position, p.size))
	return tops


func _lands_on_solid(pier: Rect2, tops: Array[Rect2]) -> bool:
	if pier.end.y >= STRUCTURES.BEDROCK_Y - 0.5:
		return true
	var x := pier.get_center().x
	for top in tops:
		if absf(top.position.y - pier.end.y) < 0.6 and x >= top.position.x - 0.5 and x <= top.end.x + 0.5:
			return true
	return false


func _passes_through(pier: Rect2, tops: Array[Rect2]) -> String:
	var x := pier.get_center().x
	for top in tops:
		if top.position.y > pier.position.y + 0.5 and top.position.y < pier.end.y - 0.5 \
				and x > top.position.x + 0.5 and x < top.end.x - 0.5:
			return str(top)
	return ""


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
	eq(deck.get_meta("structure_kind", ""), "rear_support")
	eq(deck.size, Vector2(160, 16), "a walkable passage is not filled with a solid wall")
	ok(deck.get_node_or_null("RearSupport") != null)
	ok(fragile.get_node_or_null("RearSupport") == null, "the fixed trestle must not fall with the broken deck")
	await flush(2)
	var query := PhysicsPointQueryParameters2D.new()
	query.position = Vector2(72, 290)
	query.collision_mask = 1
	ok(host.get_world_2d().direct_space_state.intersect_point(query).is_empty(), "rear piers do not collide in the foreground walking plane")
	fragile.trigger()
	fragile.tick(1.0)
	ok(fragile.is_collapsed())
	host.queue_free()


func test_each_material_is_built_the_way_its_chapter_would_build_it() -> void:
	var host := Node2D.new()
	add_child(host)
	_slab(host, Vector2(0, 320), Vector2(1240, 80), "stone")
	var expected := {
		"brick_float": [Vector2(40, 224), 128.0, "masonry_arcade", "round"],
		"nave_float": [Vector2(220, 224), 128.0, "gothic_arcade", "pointed"],
		"rampart_float": [Vector2(400, 224), 128.0, "buttressed_arcade", "round"],
		"iron_float": [Vector2(580, 224), 160.0, "steel_frame", ""],
		"basalt_float": [Vector2(780, 224), 128.0, "rock_pillar", ""],
		"moss_float": [Vector2(960, 224), 128.0, "masonry_arcade", "round"],
	}
	var decks := {}
	for skin in expected:
		var spec: Array = expected[skin]
		decks[skin] = _slab(host, spec[0], Vector2(spec[1], 16), skin)
	STRUCTURES.build(host)
	for skin in expected:
		var deck := decks[skin] as SolidPlatform
		var spec: Array = expected[skin]
		eq(deck.get_meta("structure_system", ""), spec[2], "%s is carried by its own trade" % skin)
		if String(spec[3]) != "":
			eq(deck.get_meta("structure_arch", ""), spec[3], "%s arches" % skin)
		var limit := float(STRUCTURES.system_for(STRUCTURES._family(skin))["max_span"])
		for span in deck.get_meta("structure_spans", PackedFloat32Array()):
			ok(span <= limit + 1.0, "%s bay %.0f stays within %.0f" % [skin, span, limit])
		for pier in deck.get_meta("structure_piers", []):
			almost((pier as Rect2).end.y, 320.0, 0.01, "%s pier stands on the floor" % skin)
	ok(decks["iron_float"].get_meta("structure_braced", false), "a 4 m steel bent is braced against sway")
	host.queue_free()


func test_piers_bear_on_the_first_solid_top_below() -> void:
	var host := Node2D.new()
	add_child(host)
	_slab(host, Vector2(0, 320), Vector2(480, 80), "brick")
	var gallery := _slab(host, Vector2(0, 256), Vector2(480, 16), "brick")
	var upper := _slab(host, Vector2(160, 128), Vector2(160, 16), "brick_float")
	STRUCTURES.build(host)
	for pier in upper.get_meta("structure_piers", []):
		almost((pier as Rect2).end.y, 256.0, 0.01, "the upper arcade stands on the gallery, not through it")
	for pier in gallery.get_meta("structure_piers", []):
		almost((pier as Rect2).end.y, 320.0, 0.01, "the gallery carries down to the street")
	host.queue_free()


func test_hoists_hang_from_the_slab_above_or_stand_on_a_headframe() -> void:
	var host := Node2D.new()
	add_child(host)
	_slab(host, Vector2(0, 320), Vector2(800, 80), "iron")
	_slab(host, Vector2(0, -32), Vector2(800, 32), "iron", "Ceiling")
	var runway := _lift(host, "Runway", Vector2(300, 296), Vector2(200, 0))
	var shaft := _lift(host, "Shaft", Vector2(100, 296), Vector2(0, -120))
	var ledge := _slab(host, Vector2(130, 40), Vector2(64, 16), "iron_float")
	STRUCTURES.build(host)
	eq(runway.get_meta("structure_hoist", ""), "hung_runway")
	ok(runway.get_node_or_null("Trolley") != null, "the horizontal hoist rides a trolley")
	almost(runway.chain_top_y, 16.0, 0.01, "ropes leave the trolley under a runway hung from the slab")
	eq(runway.get_meta("structure_deck", ""), "steel", "workshop hoists carry tread plate")
	eq(shaft.get_meta("structure_hoist", ""), "frame_sheaves", "a ledge across the ropes forces a headframe")
	almost(shaft.chain_top_y, 176.0 - STRUCTURES.HOIST_HEADROOM + 10.0, 0.01, "ropes leave the head sheaves")
	ok(shaft.chain_top_y > ledge.position.y + ledge.size.y, "ropes stop below the ledge that would cut them")
	var legs: Array = shaft.get_meta("structure_legs", [])
	ok(legs.size() >= 2, "the headframe has legs")
	for leg in legs:
		almost((leg as Rect2).end.y, 320.0, 0.01, "headframe legs stand on the floor")
	eq((shaft.get_meta("structure_sheaves", PackedVector2Array()) as PackedVector2Array).size(), 2)
	host.queue_free()


func test_all_campaign_structures_follow_real_world_rules() -> void:
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
		var tops := _fixed_tops(bodies)
		var hoist := "steel" if STRUCTURES._dominant_family(bodies) in ["iron", "basalt"] else "timber"
		for body in bodies:
			if body is SolidPlatform:
				var p := body as SolidPlatform
				if p.size.x <= 20 or String(p.name).begins_with("Ceiling"):
					continue
				ok(p.has_meta("structure_kind"), "%s/%s has structural support" % [id, p.name])
				_check_support(id, p, STRUCTURES._family(p.skin), p.size.x, tops)
			elif body is MovingPlatform:
				_check_hoist(id, body as MovingPlatform, tops, hoist)
			elif body is GearPlatform:
				var g := body as GearPlatform
				ok(g.has_meta("structure_kind"), "%s/%s is a pier, not a floating stone" % [id, g.name])
				_check_support(id, g, STRUCTURES._family(g.family), g.radius * 2.0, tops)
		host.free()
		await flush(1)


func _check_support(id: String, body: Node2D, family: String, width: float, tops: Array[Rect2]) -> void:
	if body.get_meta("structure_kind", "") != "rear_support":
		return
	var spec := STRUCTURES.system_for(family)
	var label := "%s/%s" % [id, body.name]
	eq(body.get_meta("structure_system", ""), spec["name"], "%s is built in its chapter's material" % label)
	for span in body.get_meta("structure_spans", PackedFloat32Array()):
		ok(span <= float(spec["max_span"]) + 1.0, "%s bay %.0f px stays within %.0f px" % [label, span, spec["max_span"]])
	var piers: Array = body.get_meta("structure_piers", [])
	ok(not piers.is_empty(), "%s has piers" % label)
	var tallest := 0.0
	for r in piers:
		var pier := r as Rect2
		tallest = maxf(tallest, pier.size.y)
		ok(_lands_on_solid(pier, tops), "%s pier at x=%.0f stands on solid ground (foot %.0f)" % [label, pier.position.x, pier.end.y])
		var through := _passes_through(pier, tops)
		ok(through == "", "%s pier at x=%.0f does not pass through %s" % [label, pier.position.x, through])
		if spec.has("slender"):
			var need := minf(minf(pier.size.y / float(spec["slender"]), 32.0), width)
			ok(pier.size.x + 0.01 >= need, "%s pier %.0f px wide carries %.0f px (needs %.1f)" % [label, pier.size.x, pier.size.y, need])
	if spec["name"] == "steel_frame" and tallest > 24.0:
		ok(body.get_meta("structure_braced", false), "%s steel bent is braced" % label)


func _check_hoist(id: String, lift: MovingPlatform, tops: Array[Rect2], material: String) -> void:
	var label := "%s/%s" % [id, lift.name]
	eq(lift.get_meta("structure_kind", ""), "gantry", "%s is mounted" % label)
	var chain := lift.get_node("Chain0") as Line2D
	almost(lift.position.y + chain.points[1].y, lift.chain_top_y, 0.1, "%s chain endpoint %s meets its hoist %s" % [label, lift.position.y + chain.points[1].y, lift.chain_top_y])
	eq(lift.get_meta("structure_material", ""), material, "%s hoist gear matches the chapter" % label)
	var origin := lift.get_parent() as Node2D
	var start := origin.to_global(lift.start_position())
	var end := origin.to_global(lift.end_position())
	var high := minf(start.y, end.y)
	var rope_top := float(lift.get_meta("structure_rope_top", 0.0))
	var rope_l := minf(start.x, end.x) + 6.0
	var rope_r := maxf(start.x, end.x) + lift.width - 6.0
	for top in tops:
		var crosses := top.end.x > rope_l and top.position.x < rope_r
		if crosses and top.end.y <= high - STRUCTURES.HOIST_HEADROOM:
			ok(top.end.y <= rope_top - 0.5, "%s ropes (from %.0f) do not pass through the deck at %s" % [label, rope_top, top])
	for leg in lift.get_meta("structure_legs", []):
		ok(_lands_on_solid(leg as Rect2, tops), "%s headframe leg at x=%.0f stands on solid ground" % [label, (leg as Rect2).position.x])
	var authored := false
	for child in lift.get_children():
		if child is Sprite2D and not (child as Sprite2D).visible and not lift.has_meta("structure_deck"):
			authored = true
	ok(authored or lift.get_meta("structure_deck", "") == material, "%s deck is %s planking, not a stone slab on a rope" % [label, material])
