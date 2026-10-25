extends RefCounted
## Load paths end in a foundation. Rear piers occupy the depth behind the
## walking plane; their openings preserve the authored passages and lift shafts.
## Low steps with no standing clearance get solid, colliding masonry plinths.

const QUEUED := &"terrain_structure_queued"
const BUILT := &"terrain_structure_built"
const GENERATED := &"terrain_structure_generated"
const MAX_PLINTH_GAP := 20.0
static var _materials: Dictionary = {}


static func request(source: Node) -> void:
	if source.has_meta(GENERATED):
		return
	var host := source.get_parent()
	while host != null and not host.is_in_group(&"game_world"):
		host = host.get_parent()
	if host == null or host.has_meta(QUEUED) or host.has_meta(BUILT):
		return
	host.set_meta(QUEUED, true)
	if host.is_node_ready():
		build.call_deferred(host)
	else:
		host.ready.connect(build.bind(host), CONNECT_ONE_SHOT)


static func build(host: Node2D) -> void:
	if host.has_meta(BUILT):
		return
	host.set_meta(BUILT, true)
	var bodies: Array[Node] = []
	_collect(host, bodies)
	var foundations: Array[Rect2] = []
	for body in bodies:
		if body is SolidPlatform:
			var p := body as SolidPlatform
			if p.size.x > 20.0 and p.size.y >= 32.0 and p.global_position.y + p.size.y >= 384.0:
				foundations.append(Rect2(p.global_position, p.size))
	for body in bodies:
		if body is MovingPlatform:
			_lift_frame(body as MovingPlatform, host, foundations)
		elif body is SolidPlatform:
			var p := body as SolidPlatform
			if p.size.x <= 20.0 or String(p.name).begins_with("Ceiling"):
				continue
			var bounds := Rect2(p.global_position, p.size)
			if bounds.end.y >= 384.0 or _rests_on_body(bounds, bodies, p):
				p.set_meta(&"structure_kind", "foundation")
				continue
			_support(p, bounds, _family(p.skin), p.tone, foundations, not (p is CollapsingPlatform))
		elif body is GearPlatform:
			var g := body as GearPlatform
			var block := DensityTextures.load_texture(String(g._block_choice()[0]))
			var visible_height := block.get_height() * (g.radius * 2.0 / block.get_width())
			var bounds := Rect2(g.global_position - Vector2(g.radius, 0.92 * g.radius), Vector2(g.radius * 2.0, visible_height))
			_support(g, bounds, _family(g.family), Color.WHITE, foundations, false)


static func _collect(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		if child.has_meta(GENERATED):
			continue
		if child is SolidPlatform or child is MovingPlatform or child is GearPlatform:
			out.append(child)
		_collect(child, out)


static func _rests_on_body(rect: Rect2, bodies: Array[Node], source: Node) -> bool:
	for body in bodies:
		if body == source or not (body is SolidPlatform) or body is CollapsingPlatform:
			continue
		var p := body as SolidPlatform
		var other := Rect2(p.global_position, p.size)
		if absf(rect.end.y - other.position.y) <= 1.0 and other.position.x <= rect.position.x + 1.0 and other.end.x >= rect.end.x - 1.0:
			return true
	return false


static func _family(skin: String) -> String:
	if skin in ["auto", "floating", "ground", "stone", ""]:
		return "stone"
	return skin.trim_suffix("_float")


static func _foot_y(x: float, below: float, foundations: Array[Rect2]) -> float:
	var result := 400.0
	for rect in foundations:
		if x >= rect.position.x and x <= rect.end.x and rect.position.y >= below - 1.0:
			result = minf(result, rect.position.y)
	return maxf(below, result)


static func _support(body: Node2D, bounds: Rect2, family: String, tone: Color,
		foundations: Array[Rect2], can_fill: bool) -> void:
	var foot := _foot_y(bounds.get_center().x, bounds.end.y, foundations)
	var gap := foot - bounds.end.y
	if gap <= 0.5:
		body.set_meta(&"structure_kind", "foundation")
		return
	# Fill only spaces too short for a standing body, and only above a real floor.
	var whole_floor := false
	for rect in foundations:
		if absf(rect.position.y - foot) < 1.0 and rect.position.x <= bounds.position.x and rect.end.x >= bounds.end.x:
			whole_floor = true
	if can_fill and whole_floor and gap <= MAX_PLINTH_GAP:
		var plinth := SolidPlatform.new()
		plinth.name = "MasonryPlinth"
		plinth.set_meta(GENERATED, true)
		plinth.set_meta("non_walkable", true)
		plinth.position = body.to_local(bounds.position + Vector2(0, bounds.size.y))
		plinth.size = Vector2(bounds.size.x, gap)
		plinth.skin = family
		plinth.cap_surface = false
		plinth.tone = tone
		body.add_child(plinth)
		body.set_meta(&"structure_kind", "solid_plinth")
		return
	var frame := Node2D.new()
	frame.name = "RearArcade"
	frame.set_meta(GENERATED, true)
	frame.z_index = -3
	# Fragile decks fall away from their permanent supporting trestles.
	if body is CollapsingPlatform:
		body.get_parent().add_child(frame)
		frame.global_position = bounds.position + Vector2(0, bounds.size.y - 3.0)
	else:
		body.add_child(frame)
		frame.global_position = bounds.position + Vector2(0, bounds.size.y - 3.0)
	var width := bounds.size.x
	var pier_width := clampf(width * 0.15, 8.0, 16.0)
	var bays := maxi(1, int(ceil(width / 144.0)))
	var span := (width - pier_width) / bays
	for i in bays + 1:
		var x := i * span
		var bottom := _foot_y(bounds.position.x + x + pier_width * 0.5, bounds.end.y, foundations) - frame.global_position.y
		_masonry(frame, Rect2(x, 0, pier_width, bottom + 4.0), family, tone * Color(0.63, 0.63, 0.68))
		_masonry(frame, Rect2(x - 2, 0, pier_width + 4, 6), family, tone * Color(0.85, 0.85, 0.9))
		_masonry(frame, Rect2(x - 2, bottom - 4, pier_width + 4, 8), family, tone * Color(0.68, 0.68, 0.73))
		if i < bays:
			_arch(frame, x, span + pier_width, minf(36, gap * 0.5), family, tone)
	body.set_meta(&"structure_kind", "rear_arcade")
	body.set_meta(&"structure_foot_y", foot)


static func _texture(family: String) -> Texture2D:
	if _materials.has(family):
		return _materials[family]
	if family == "stone":
		# Sample the intact middle course of the SAME lavender slab as the deck.
		var slab := DensityTextures.load_texture(SolidPlatform.STONE_SLABS[0])
		var density := slab.get_image().get_width() / int(slab.get_width())
		var image := slab.get_image().get_region(Rect2i(0, 16 * density, 48 * density, 16 * density))
		var texture := ImageTexture.create_from_image(image)
		texture.set_size_override(Vector2i(48, 16))
		_materials[family] = texture
		return texture
	var path := "res://assets/env/%s_fill.png" % family
	if not ResourceLoader.exists(path):
		path = "res://assets/env/nave_fill.png"
	var texture := DensityTextures.load_texture(path)
	_materials[family] = texture
	return texture


static func _masonry(parent: Node2D, rect: Rect2, family: String, color: Color) -> void:
	if rect.size.y <= 0:
		return
	var sprite := Sprite2D.new()
	sprite.texture = _texture(family)
	sprite.centered = false
	sprite.position = rect.position
	sprite.region_enabled = true
	sprite.region_rect = Rect2(Vector2.ZERO, rect.size)
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.modulate = color
	parent.add_child(sprite)


static func _arch(parent: Node2D, x: float, width: float, drop: float, family: String, tone: Color) -> void:
	var polygon := Polygon2D.new()
	var points := PackedVector2Array([Vector2(x, 0), Vector2(x + width, 0)])
	for i in range(13):
		var angle := float(i) / 12.0 * PI
		points.append(Vector2(x + width * (0.5 + 0.5 * cos(angle)), maxf(5.0, drop - sin(angle) * (drop - 5.0))))
	polygon.polygon = points
	polygon.uv = points
	polygon.texture = _texture(family)
	polygon.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	polygon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	polygon.color = tone * Color(0.8, 0.8, 0.85)
	parent.add_child(polygon)


static func _lift_frame(lift: MovingPlatform, host: Node2D, foundations: Array[Rect2]) -> void:
	var origin := lift.get_parent() as Node2D
	var start := origin.to_global(lift.start_position())
	var end := origin.to_global(lift.end_position())
	var top := minf(minf(start.y, end.y) - 32.0, origin.to_global(Vector2(0, lift.chain_top_y)).y)
	lift.chain_top_y = origin.to_local(Vector2(0, top + 12.0)).y
	var left := minf(start.x, end.x) - 16.0
	var right := maxf(start.x, end.x) + lift.width + 16.0
	var frame := Node2D.new()
	frame.name = String(lift.name) + "Gantry"
	frame.set_meta(GENERATED, true)
	frame.z_index = -3
	host.add_child(frame)
	frame.global_position = Vector2(left, top)
	for x in [0.0, right - left - 12.0]:
		var foot := _foot_y(left + x, maxf(start.y, end.y) + 16, foundations)
		_masonry(frame, Rect2(x, 0, 12, foot - top + 4), "iron", Color(0.7, 0.7, 0.74))
		_masonry(frame, Rect2(x - 3, foot - top - 4, 18, 8), "nave", Color(0.65, 0.65, 0.7))
	_masonry(frame, Rect2(0, 0, right - left, 12), "iron", Color(0.9, 0.9, 0.95))
	_masonry(frame, Rect2(0, 12, right - left, 3), "iron", Color(0.42, 0.42, 0.46))
	lift.set_meta(&"structure_kind", "gantry")
	lift._update_chains()
