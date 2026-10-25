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
			if c.enabled and c.is_visible_in_tree() and c.energy > 0.001:
				out_enabled.append(c)
		_count_lights(c, out_enabled, out_total)


func _touches_screen(light: PointLight2D, view: Rect2) -> bool:
	if light.texture == null: return false
	var size := light.texture.get_size() * light.texture_scale
	var bounds := light.global_transform * Rect2(light.offset - size * 0.5, size)
	return bounds.intersects(view)


## Scan the 640x360 world camera footprint over the authored geometry. Lights
## outside it cost no screen overdraw; a whole chapter is not one screen.
func _peak_visible(level: Node, lights: Array) -> int:
	var tops := LevelSanity.top_segments(level)
	var max_x := 640.0
	var min_y := 0.0
	for top in tops:
		max_x = maxf(max_x, float(top.x1))
		min_y = minf(min_y, float(top.y) - 180.0)
	var peak := 0
	for x in range(0, int(max_x) + 1, 80):
		for y in range(int(min_y), 361, 60):
			var view := Rect2(Vector2(x, y), Vector2(640, 360))
			var count := 0
			for light in lights:
				if _touches_screen(light, view): count += 1
			peak = maxi(peak, count)
	return peak

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
		var peak := _peak_visible(level, enabled_lights)
		print("%s: peak_screen=%d enabled_chapter=%d total_chapter=%d" % [lvl_name, peak, enabled_lights.size(), total_lights.size()])
		ok(peak <= BUDGET,
				"%s keeps its same-screen lights within the %d budget (got %d)" % [lvl_name, BUDGET, peak])
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
	var enabled_lights: Array = []
	var all_lights: Array = []
	_count_lights(host, enabled_lights, all_lights)
	eq(all_lights.size(), 20, "recursive measurement sees the real light inside every arc")
	await flush(60)
	all_lights.clear()
	enabled_lights.clear()
	_count_lights(host, enabled_lights, all_lights)
	eq(all_lights.size(), 0, "all nested lights leave with their expired slashes")
	eq(host.get_child_count(), 0, "temporary arcs reclaim their nodes")
	host.queue_free()
	await flush(1)
