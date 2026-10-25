extends Node2D
## One structure's members in a single canvas item: tiled member strips, textured
## masonry and rock polygons, rotated bars, discs and joint lines. Built once by
## TerrainStructures; a level carries hundreds of members, not hundreds of nodes.

enum Op { STRIP, BAR, POLYGON, LINES, DISC }

var _ops: Array = []


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


## Axis-aligned member; a texture tiles from the rectangle's origin.
func strip(rect: Rect2, texture: Texture2D, color: Color) -> void:
	if rect.size.x > 0.01 and rect.size.y > 0.01:
		_ops.append([Op.STRIP, rect, texture, color])
		queue_redraw()


## Straight member of `thickness` from `from` to `to`, its texture running lengthwise.
func bar(from: Vector2, to: Vector2, thickness: float, texture: Texture2D, color: Color) -> void:
	if from.distance_to(to) > 0.5:
		_ops.append([Op.BAR, from, to, thickness, texture, color])
		queue_redraw()


func polygon(points: PackedVector2Array, texture: Texture2D, color: Color) -> void:
	if points.size() >= 3:
		_ops.append([Op.POLYGON, points, texture, color])
		queue_redraw()


## Pairs of points, one segment per pair.
func lines(segments: PackedVector2Array, color: Color, width: float) -> void:
	if segments.size() >= 2:
		_ops.append([Op.LINES, segments, color, width])
		queue_redraw()


func disc(center: Vector2, radius: float, color: Color) -> void:
	_ops.append([Op.DISC, center, radius, color])
	queue_redraw()


func op_count() -> int:
	return _ops.size()


func _draw() -> void:
	for op in _ops:
		match int(op[0]):
			Op.STRIP:
				var tex := op[2] as Texture2D
				if tex != null:
					draw_texture_rect(tex, op[1], true, op[3])
				else:
					draw_rect(op[1], op[3])
			Op.BAR:
				var from: Vector2 = op[1]
				var to: Vector2 = op[2]
				var thickness: float = op[3]
				var rect := Rect2(0.0, -thickness * 0.5, from.distance_to(to), thickness)
				draw_set_transform(from, (to - from).angle())
				if op[4] != null:
					draw_texture_rect(op[4], rect, true, op[5])
				else:
					draw_rect(rect, op[5])
				draw_set_transform(Vector2.ZERO)
			Op.POLYGON:
				var points: PackedVector2Array = op[1]
				var tex := op[2] as Texture2D
				if tex == null:
					draw_colored_polygon(points, op[3])
					continue
				var size := tex.get_size()
				var uvs := PackedVector2Array()
				for p in points:
					uvs.append(Vector2(p.x / size.x, p.y / size.y))
				draw_polygon(points, PackedColorArray([op[3]]), uvs, tex)
			Op.LINES:
				draw_multiline(op[1], op[2], op[3])
			Op.DISC:
				draw_circle(op[1], op[2], op[3])
