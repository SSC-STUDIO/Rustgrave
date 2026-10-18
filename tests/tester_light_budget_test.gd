extends TestCase
## Tester probe: count live lights per level and check the 12-light budget.
##
## AmbientLighting.MAX_LIGHTS = 12 is the project's documented same-screen
## light budget (ambient_lighting.gd:72). This test measures how many
## PointLight2D each level actually brings on screen and fails any level
## whose ENABLED count exceeds that budget.

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

const BUDGET := 12


func _count_lights(root: Node, out_enabled: Array, out_total: Array) -> void:
	for c in root.get_children():
		if c is PointLight2D:
			out_total.append(c)
			var is_enabled := true
			if "enabled" in c:
				is_enabled = c.enabled
			if is_enabled:
				out_enabled.append(c)
		_count_lights(c, out_enabled, out_total)


func test_light_count_per_level() -> void:
	for path in LEVELS:
		var packed: PackedScene = load(path)
		if packed == null:
			ok(false, "%s loads" % path.get_file())
			continue
		var level: Node = packed.instantiate()
		add_child(level)
		await flush(40)
		var enabled_lights: Array = []
		var total_lights: Array = []
		_count_lights(level, enabled_lights, total_lights)
		var lvl_name: String = String(path.get_file().get_basename())
		print("%s: enabled=%d total=%d" % [lvl_name, enabled_lights.size(), total_lights.size()])
		ok(enabled_lights.size() <= BUDGET,
				"%s keeps its enabled lights within the %d budget (got %d)" % [
						lvl_name, BUDGET, enabled_lights.size()])
		level.queue_free()
		await get_tree().process_frame


func test_slash_arc_light_spam() -> void:
	# Every slash spawns a WorldLight. Spam 20 slashes and count the lights.
	const PLAYER := preload("res://scenes/player/Player.tscn")
	var host := Node2D.new()
	add_child(host)
	var arcs: Array[Node] = []
	for i in 20:
		var arc = load("res://scripts/combat/slash_arc.gd").new()
		arc.position = Vector2(100.0 + i * 8.0, 100.0)
		host.add_child(arc)
		arcs.append(arc)
	await flush(4)
	var lights := 0
	for c in host.get_children():
		if c is PointLight2D:
			lights += 1
	print("slash arcs: %d children, %d PointLight2D" % [host.get_child_count(), lights])
	ok(lights <= 20, "each arc has at most one light (got %d)" % lights)
	# The real risk: 20 simultaneous lights, each with a per-frame apply().
	for a in arcs:
		a.queue_free()
	host.queue_free()
	await get_tree().process_frame
