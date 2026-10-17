extends Node
## 诊断用探针：检查 level01 材质色阶是否真的重挂到了平台贴片上。
##   godot --headless --path . res://scenes/tools/MaterialProbe.tscn

func _ready() -> void:
	GameContext.pending_world_path = GameContext.WORLD_PATH
	SaveData.save_path = "user://material_probe.cfg"
	SaveData.delete_save()
	var pres := preload("res://scenes/ui/GamePresentation.tscn").instantiate()
	add_child(pres)
	await get_tree().process_frame
	await get_tree().process_frame
	var world := get_tree().get_first_node_in_group("game_world")
	if world == null:
		printerr("no world")
		get_tree().quit(1)
		return
	var platforms := world.get_node_or_null("Platforms")
	_dump(platforms, 0)
	var toxin := world.get_node_or_null("Props/ToxinPool") as ToxinPool
	if toxin != null:
		print("toxin tint=", toxin.tint)
	var fg := world.get_node_or_null("ParallaxForeground")
	if fg != null:
		_dump_layer(fg)
	var backdrop := world.get_node_or_null("ParallaxBackdrop")
	if backdrop != null:
		for c in backdrop.get_children():
			print("backdrop child=", c.name, " type=", c.get_class(), " modulate=",
					(c as CanvasItem).modulate if c is CanvasItem else "?")
	SaveData.delete_save()
	get_tree().quit(0)


func _dump(root: Node, depth: int) -> void:
	if depth > 3 or root == null:
		return
	for child in root.get_children():
		if child is SolidPlatform:
			var plat := child as SolidPlatform
			var sprites := 0
			var modul := ""
			for c in plat.get_children():
				if c is Sprite2D:
					sprites += 1
					if sprites == 2:
						modul = str((c as Sprite2D).modulate)
			print("plat=", plat.name, " skin=", plat.skin, " tone=", plat.tone,
					" sprites=", sprites, " row1_modulate=", modul)
		_dump(child, depth + 1)


func _dump_layer(node: Node) -> void:
	for c in node.get_children():
		if c is Parallax2D:
			for s in c.get_children():
				if s is Sprite2D:
					var spr := s as Sprite2D
					print("fg layer=", c.name, " tex=",
							spr.texture.resource_path.get_file() if spr.texture else "null",
							" modulate=", spr.modulate, " layer_modulate=", (c as CanvasItem).modulate)
		_dump_layer(c)
