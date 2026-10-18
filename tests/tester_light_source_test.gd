extends TestCase
## Tester probe: dump every light in every level with its source so the
## 12-light budget overrun can be attributed to specific nodes.

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


func _dump_lights(root: Node, path: String, out: Array) -> void:
	for c in root.get_children():
		if c is PointLight2D:
			var follow := ""
			if "follow" in c:
				follow = String(c.follow)
			var enabled := true
			if "enabled" in c:
				enabled = c.enabled
			var energy := 0.0
			if "energy" in c:
				energy = c.energy
			var script_path := ""
			var s := c.get_script() as Script
			if s != null:
				script_path = s.resource_path.get_file()
			out.append("%s | %s | script=%s | follow=%s | enabled=%s | energy=%.2f" % [
					path, c.name, script_path, follow, str(enabled), energy])
		_dump_lights(c, path + "/" + String(c.name), out)


func test_dump_all_lights_per_level() -> void:
	for p in LEVELS:
		var packed: PackedScene = load(p)
		if packed == null:
			continue
		var level: Node = packed.instantiate()
		add_child(level)
		await flush(40)
		var rows: Array = []
		_dump_lights(level, String(level.name), rows)
		print("=== %s : %d lights ===" % [p.get_file(), rows.size()])
		for r in rows:
			print("   " + str(r))
		level.queue_free()
		await get_tree().process_frame
