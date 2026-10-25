extends TestCase

const CATALOG := preload("res://scripts/visuals/redrawn_texture_catalog.gd")


func _check_characters(names: Array[String]) -> void:
	for character in names:
		var source_dir := DirAccess.open("res://assets/characters/" + character)
		ok(source_dir != null)
		if source_dir == null:
			continue
		for action in source_dir.get_directories():
			var frames := CharFrames.anim(character, action)
			for i in frames.size():
				var path := "res://assets/characters/%s/%s/%s_%d.png" % [character, action, action, i]
				ok(CATALOG.REPLACEMENTS.has(path), "every original character action has detail: " + path)
				if not CATALOG.REPLACEMENTS.has(path):
					continue
				var source := load(path) as Texture2D
				var frame := frames[i]
				eq(DensityTextures.source_path(frame), path, "animation retains its original frame order")
				eq(frame.get_size(), source.get_size(), "logical canvas and sprite foot offsets stay fixed")
				eq(frame.get_image().get_size(), source.get_image().get_size() * 4, "actual native density is four")
				var before := source.get_image()
				var after := frame.get_image()
				var matched := true
				for y in range(before.get_height()):
					for x in range(before.get_width()):
						if absf(before.get_pixel(x, y).a - after.get_pixel(x * 4, y * 4).a) > 0.005:
							matched = false
				ok(matched, "source silhouette, gaps and foot mask: " + path)


func test_knight_animation_geometry() -> void:
	_check_characters(["player_fantasy_knight"])


func test_other_player_animation_geometry() -> void:
	_check_characters(["player_cemetery_hero", "player_gothic_hero"])


func test_undead_and_beast_animation_geometry() -> void:
	_check_characters(["skeleton", "ghost", "scrapper_hell_hound", "spitter_hell_beast"])


func test_boss_and_flying_animation_geometry() -> void:
	_check_characters(["gear_shield_executioner", "boss_nightmare", "flying_demon", "flying_demon_px", "fire_skull"])
