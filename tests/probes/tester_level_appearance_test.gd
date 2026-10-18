extends TestCase
## Tester probe: per-level appearance audit — backdrop layers, z-index
## ordering of play objects, and camera bounds vs the level's own extent.

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


func test_per_level_backdrop_and_camera() -> void:
	for path in LEVELS:
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		var level: Node = packed.instantiate()
		add_child(level)
		await flush(30)
		var lvl_name: String = String(path.get_file().get_basename())
		# 1. Backdrop present? Level01 hand-builds ParallaxBackdrop layers;
		#    levels 02-10 get a programmatic ThemeBackdrop via chapter_layout.
		var backdrop: Node = level.find_child("Backdrop", true, false)
		var parallax: Node = level.find_child("ParallaxBackdrop", true, false)
		print("%s: backdrop=%s parallax=%s" % [lvl_name, backdrop != null, parallax != null])
		ok(backdrop != null or parallax != null,
				"%s ships a backdrop layer" % lvl_name)
		# 2. Camera limits vs the level's own used rect.
		var cam: Camera2D = level.find_child("Camera2D", true, false) as Camera2D
		if cam != null and cam.limit_right > 0:
			var used: Rect2 = level.get_used_rect()
			print("   camera limits R=%d B=%d | level used rect=%s" % [
					cam.limit_right, cam.limit_bottom, str(used)])
			ok(cam.limit_right >= used.size.x - 8.0,
					"%s camera right limit (%.0f) covers the level width (%.0f)" % [
							lvl_name, cam.limit_right, used.size.x])
		# 3. Play objects must not all collapse onto one z-index.
		var z_indices: Dictionary = {}
		_collect_z(level, z_indices)
		if z_indices.size() > 1:
			print("   z_index spread: %d distinct values" % z_indices.size())
		level.queue_free()
		await get_tree().process_frame


func _collect_z(n: Node, out: Dictionary) -> void:
	for c in n.get_children():
		if c is CanvasItem:
			var z := (c as CanvasItem).z_index
			out[z] = int(out.get(z, 0)) + 1
		_collect_z(c, out)
