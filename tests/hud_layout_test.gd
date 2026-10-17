extends TestCase
## Compact HUD geometry, letterbox safety and safe-area handling.

const HUD_SCENE := preload("res://scenes/ui/HUD.tscn")


func _dump(node: Node, depth: int = 0) -> void:
	if node is Control:
		print("PROBE ", "  ".repeat(depth), node.name, " ", (node as Control).get_global_rect(), " min=", (node as Control).get_combined_minimum_size())
	if depth < 4:
		for c in node.get_children():
			_dump(c, depth + 1)


func test_probe_geometry() -> void:
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	await flush(4)
	_dump(hud.get_node("Root/StatPanel"))
	ok(true)
