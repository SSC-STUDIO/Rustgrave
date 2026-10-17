extends Node
## 诊断用探针：把第一章世界里所有较大的 Sprite2D 装饰列出来（贴图路径 / 世界坐标 /
## 纹理尺寸 / 缩放 / 父链），用于定位"读不出用途的大方块"。
##   godot --headless --path . res://scenes/tools/DecorDumpProbe.tscn

const MIN_PX := 40.0


func _ready() -> void:
	SaveData.save_path = "user://decor_dump.cfg"
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.mark_flag("opening_seen")
	SaveData.mark_flag("wake")
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	SaveData.ending = ""
	Director.abort()
	GameContext.pending_world_path = GameContext.WORLD_PATH
	var pres := preload("res://scenes/ui/GamePresentation.tscn").instantiate()
	add_child(pres)
	for _i in 6:
		await get_tree().process_frame
	Director.abort()
	var world := GameContext.world_root(get_tree().get_first_node_in_group("player"))
	if world == null:
		printerr("no world")
		get_tree().quit(1)
		return
	var rows: Array = []
	_scan(world, "world", rows)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["x"]) < float(b["x"]))
	for row in rows:
		print("DECOR x=%6.1f y=%6.1f %4dx%-4d scale=%s z=%d path=%s chain=%s" % [
			row["x"], row["y"], row["w"], row["h"], str(row["scale"]), row["z"],
			row["path"], row["chain"]])
	SaveData.delete_save()
	get_tree().quit(0)


func _scan(node: Node, chain: String, rows: Array) -> void:
	for child in node.get_children():
		var label := chain + "/" + String(child.name)
		if child is Sprite2D:
			var spr := child as Sprite2D
			if spr.texture != null:
				var w := int(round(float(spr.texture.get_width()) * absf(spr.global_scale.x)))
				var h := int(round(float(spr.texture.get_height()) * absf(spr.global_scale.y)))
				if float(w) >= MIN_PX and float(h) >= 24.0:
					rows.append({
						"x": spr.global_position.x,
						"y": spr.global_position.y,
						"w": w,
						"h": h,
						"scale": spr.global_scale,
						"z": spr.z_index,
						"path": spr.texture.resource_path.get_file(),
						"chain": label,
					})
		_scan(child, label, rows)
