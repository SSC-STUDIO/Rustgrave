extends TestCase
## Floating slabs stay thin and top-aligned; ground skin stays grass.


const FLOAT_PATHS: Array[String] = [
	"res://assets/env/float_left.png",
	"res://assets/env/float_right.png",
	"res://assets/env/float_mid_a.png",
	"res://assets/env/float_mid_b.png",
	"res://assets/env/float_mid_c.png",
	"res://assets/env/float_mid_d.png",
	"res://assets/env/float_small.png",
]


func test_float_textures_are_thin_slabs() -> void:
	for path in FLOAT_PATHS:
		ok(ResourceLoader.exists(path), "missing %s" % path)
		var tex := load(path) as Texture2D
		ok(tex != null, "failed to load %s" % path)
		if tex == null:
			continue
		ok(tex.get_height() <= 16, "%s is %dpx tall (want <= 16)" % [path, tex.get_height()])
		ok(tex.get_height() >= 10, "%s is %dpx tall (want hang leftover)" % [path, tex.get_height()])


func test_floating_sprites_hang_from_collision_top() -> void:
	var plat := SolidPlatform.new()
	plat.skin = "floating"
	plat.size = Vector2(64, 16)
	plat.position = Vector2(100, 200)
	add_child(plat)
	var sprites := 0
	for child in plat.get_children():
		if child is Sprite2D:
			sprites += 1
			almost(child.position.y, 0.0, 0.01, "float sprite must hang from collision top")
			ok(child.texture.get_height() <= 16, "in-game float sprite taller than 16px")
	ok(sprites >= 3, "left + mid + right pieces")
	var col: CollisionShape2D
	for child in plat.get_children():
		if child is CollisionShape2D:
			col = child
	ok(col != null, "floating platform keeps a collision box")
	var shape := col.shape as RectangleShape2D
	almost(shape.size.y, 16.0, 0.01, "collision height must stay 16px")
	almost(col.position.y, 8.0, 0.01, "collision stays centered on the 16px box")
	almost(plat.position.y, 200.0, 0.01, "platform origin must not move")


func test_stone_skin_paves_flagstones_over_cemetery_earth() -> void:
	var plat := SolidPlatform.new()
	plat.skin = "stone"
	plat.size = Vector2(64, 64)
	plat.position = Vector2(1600, 320)
	add_child(plat)
	var by_row: Dictionary = {}
	for child in plat.get_children():
		if child is Sprite2D:
			var spr := child as Sprite2D
			var row := int(roundf(spr.position.y / 16.0))
			if not by_row.has(row):
				by_row[row] = []
			(by_row[row] as Array).append(spr)
			ok(not DensityTextures.source_path(spr.texture).contains("float_"), "stone never uses hovering slabs")
			ok(not DensityTextures.source_path(spr.texture).contains("tile_top"), "stone has no grass cap")
	eq(by_row.size(), 4, "64px tall floor paints four rows")
	for row in [0, 1]:
		for spr in by_row.get(row, []):
			var s := spr as Sprite2D
			ok(DensityTextures.source_path(s.texture).contains("slab_"), "row %d is cut from a church slab" % row)
			ok(s.region_enabled, "flagstone tiles are 16px regions of the 48px slab")
			almost(s.region_rect.position.y, row * 16.0, 0.01, "row %d samples its own band of the slab" % row)
			almost(s.region_rect.size.x, 16.0, 0.01)
			eq(s.scale, Vector2.ONE, "slab art is already world 1x")
	for spr in by_row.get(2, []):
		var s := spr as Sprite2D
		ok(not DensityTextures.source_path(s.texture).contains("slab_"), "under the paving the cemetery earth returns")
		ok(s.modulate.r < 0.95, "earth under the flagstones sinks darker")
	var col: CollisionShape2D
	for child in plat.get_children():
		if child is CollisionShape2D:
			col = child
	ok(col != null and (col.shape as RectangleShape2D).size == Vector2(64, 64), "skin never touches collision")


func test_east_floor_is_paved_stone() -> void:
	var host := Node2D.new()
	add_child(host)
	for folder in ["Platforms", "Hooks", "Pickups", "Props"]:
		var n := Node2D.new()
		n.name = folder
		host.add_child(n)
	var wing := Level01EastWing.new()
	add_child(wing)
	wing.build(host)
	var floor := host.get_node_or_null("Platforms/EastFloor") as SolidPlatform
	ok(floor != null, "east floor is named so the arena can be dressed against it")
	if floor == null:
		return
	eq(floor.skin, "stone", "the Executioner's nave is paved, not grass")
	eq(floor.position, Level01EastWing.east_floor_rect().position)
	eq(floor.size, Level01EastWing.east_floor_rect().size)


func test_ground_skin_does_not_use_float_tiles() -> void:
	var plat := SolidPlatform.new()
	plat.skin = "ground"
	plat.size = Vector2(64, 16)
	add_child(plat)
	var sprites := 0
	for child in plat.get_children():
		if child is Sprite2D:
			sprites += 1
			ok(not DensityTextures.source_path(child.texture).contains("float_"),
					"ground used float tile %s" % DensityTextures.source_path(child.texture))
	ok(sprites >= 1, "ground skin still paints tiles")
