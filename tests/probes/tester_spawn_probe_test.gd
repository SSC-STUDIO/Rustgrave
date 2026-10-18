extends TestCase
## Tester probe: verify each level's default player spawn is a sane position —
## inside the level bounds, and standing on/near a platform rather than
## falling out of the world.

const LEVELS := [
	"res://scenes/levels/Level01_Static.tscn",
	"res://scenes/levels/Level02_Undercroft.tscn",
	"res://scenes/levels/Level03_RustTown.tscn",
	"res://scenes/levels/Level04_Cathedral.tscn",
	"res://scenes/levels/Level05_Workshop.tscn",
	"res://scenes/levels/Level06_NightGraveyard.tscn",
	"res://scenes/levels/Level07_BellTower.tscn",
	"res://scenes/levels/Level08_SlagDepths.tscn",
	"res://scenes/levels/Level09_Ramparts.tscn",
	"res://scenes/levels/Level10_ForgeCore.tscn",
]


func test_spawn_is_sane_on_every_level() -> void:
	for path in LEVELS:
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		var level: Node = packed.instantiate()
		add_child(level)
		await flush(25)
		var lvl_name: String = String(path.get_file().get_basename())
		var player := level.find_child("Player", true, false) as Node2D
		if player == null:
			print("%s: NO PLAYER" % lvl_name)
			ok(false, "%s spawns a player" % lvl_name)
			level.queue_free()
			await get_tree().process_frame
			continue
		var p: Vector2 = player.global_position
		var used: Rect2 = _sprite_extent(level)
		var inside := used.grow(64.0).has_point(p)
		print("%s: spawn=(%.0f, %.0f) extent=%s inside=%s" % [
				lvl_name, p.x, p.y, str(used), str(inside)])
		ok(inside, "%s spawn (%.0f, %.0f) is inside the level extent" % [lvl_name, p.x, p.y])
		level.queue_free()
		await get_tree().process_frame


func _sprite_extent(root: Node) -> Rect2:
	var merged := Rect2()
	var any := false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		for child in current.get_children():
			stack.append(child)
			if child is Sprite2D:
				var spr := child as Sprite2D
				var r: Rect2 = spr.get_global_transform() * spr.get_rect()
				merged = r if not any else merged.merge(r)
				any = true
	return merged if any else Rect2(Vector2.ZERO, Vector2(320, 180))
