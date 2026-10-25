extends TestCase

const STRUCTURES := preload("res://scripts/world/terrain_structures.gd")


func test_print_spots() -> void:
	for id in GameContext.LEVELS:
		SaveData.delete_save()
		SaveData.flags.clear()
		var host := (load(GameContext.LEVELS[id]) as PackedScene).instantiate() as Node2D
		add_child(host)
		await flush(2)
		Director.abort()
		var bodies: Array[Node] = []
		STRUCTURES._collect(host, bodies)
		var rows: PackedStringArray = []
		for body in bodies:
			var kind := String(body.get_meta("structure_kind", ""))
			if kind == "rear_support":
				var piers: Array = body.get_meta("structure_piers", [])
				var top := 9999.0
				for p in piers:
					top = minf(top, (p as Rect2).position.y)
				rows.append("%s x=%d y=%d w=%d sys=%s arch=%s" % [body.name, int(body.global_position.x), int(top), int(piers.size()), body.get_meta("structure_system", ""), body.get_meta("structure_arch", "")])
			elif kind == "gantry":
				var lift := body as MovingPlatform
				rows.append("%s x=%d y=%d hoist=%s rope=%d deck=%s" % [lift.name, int(lift.global_position.x), int(lift.global_position.y), lift.get_meta("structure_hoist", ""), int(lift.chain_top_y), lift.get_meta("structure_deck", "authored")])
		print("== %s ==\n%s" % [id, "\n".join(rows)])
		host.free()
		await flush(1)
	ok(true)
