extends TestCase
## HUD 毒素文案跟 ToxinMeter 档位走同一套阈值。


const HUD_SCENE := preload("res://scenes/ui/HUD.tscn")


func _find_toxin(root: Node) -> Label:
	if root is Label and String(root.name) == "ToxinLabel":
		return root as Label
	for child in root.get_children():
		var found := _find_toxin(child)
		if found != null:
			return found
	return null


func test_hud_toxin_label_tracks_bands() -> void:
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	await flush(1)
	var label := _find_toxin(hud)
	ok(label != null, "toxin label exists")
	GameEvents.toxin_changed.emit(0.0, 100.0)
	eq(label.text, "冷 0%")
	GameEvents.toxin_changed.emit(30.0, 100.0)
	eq(label.text, "温 30%")
	GameEvents.toxin_changed.emit(60.0, 100.0)
	eq(label.text, "炽 60%")
	GameEvents.toxin_changed.emit(100.0, 100.0)
	eq(label.text, "溢 100%")
	eq(ToxinMeter.band_for(60.0, 100.0), &"hot")
	eq(ToxinMeter.band_label_for(&"hot"), "炽")
