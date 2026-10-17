extends TestCase
## Phase 0 regression guard: the two repaired "scene layout" defects.
##  - The knight's spawn must place its feet on a platform top and stay on the
##    pixel grid (no fractional mid-fall position after ready).
##  - Every sprite that joins the "grounded" audit group must carry integer
##    feet metadata and a foot anchor describing which pixel line it means.


func _load_level01() -> Node2D:
	var packed := load("res://scenes/levels/Level01_Static.tscn") as PackedScene
	var level := packed.instantiate() as Node2D
	add_child(level)
	await flush(2)
	return level


func test_knight_spawns_with_feet_on_the_ground_top() -> void:
	var level := await _load_level01()
	var player := get_tree().get_first_node_in_group("player") as CharacterBody2D
	ok(player != null, "level spawns the knight")
	if player == null:
		level.free()
		return
	# The origin is the foot point; it must rest on the ground top (320)
	# and stay integer so the pixel grid check holds.
	almost(player.position.y, Level01Static.GROUND_TOP, 1.0, "feet rest on the ground top")
	eq(player.position, player.position.round(), "spawn stays on the pixel grid")
	level.free()
	await flush(1)


func test_grounded_sprites_carry_integer_feet_and_anchor() -> void:
	var packed := load("res://scenes/levels/Level02_Undercroft.tscn") as PackedScene
	var level := packed.instantiate() as Node2D
	add_child(level)
	await flush(2)
	var checked := 0
	for node in get_tree().get_nodes_in_group("grounded"):
		if not (node is Sprite2D):
			continue
		var spr := node as Sprite2D
		if spr.texture == null or not spr.has_meta("feet") or not spr.has_meta("foot_anchor"):
			continue
		var feet: Vector2 = spr.get_meta("feet")
		eq(feet, feet.round(), "%s feet are integer pixels" % spr.name)
		checked += 1
	ok(checked >= 3, "level02 has pinned grounded sprites to audit (%d)" % checked)
	Director.abort()
	get_tree().paused = false
	SaveData.delete_save()
	level.free()
	await flush(1)
