extends Control
## 竞技场主路小地图：铁框切角、半透明玻璃底，菱形标记。
## 主路画成一条有宽度的纵深带；纵深用带内的上下位置表示。
## 标记：玩家 = 余烬菱形外加一圈环；敌方单位 = 冷铁菱形（带灰边）；己方单位 = 淡蓝菱形；
## 门（塔与水晶）= 锈色菱形，贯穿带子的一道细线；没露出的水晶是空心菱形。摄像机是视窗框。
## 没有 class_name，由 arena_hud.gd preload。

const ArenaCatalog := preload("res://scripts/data/arena_catalog.gd")

const IRON := Color("#4A2A18")
const GATE := Color("#A0522D")
const GLASS := Color(0.05, 0.04, 0.06, 0.6)
const BAND := Color(0.16, 0.11, 0.09, 0.8)
const BAND_BACK := Color(0.34, 0.4, 0.5, 0.85)
const BAND_FRONT := Color(0.62, 0.48, 0.32, 0.9)
const EMBER := Color("#FFC14A")
const EMBER_HOT := Color("#FFF0C0")
const COLD_EDGE := Color("#8A8680")
const ALLY := Color(0.62, 0.78, 1.0, 1.0)
const ALTAR := Color(0.95, 0.78, 0.38, 0.85)
const VIEW := Color(0.93, 0.88, 0.72, 0.95)

var _data: Dictionary = {}
var _view := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(212, 80)
	resized.connect(queue_redraw)


func set_snapshot(data: Dictionary, view: Rect2) -> void:
	_data = data
	_view = view
	queue_redraw()


func _draw() -> void:
	var box := get_size()
	if box.x < 16.0 or box.y < 16.0:
		return
	_draw_frame(box)
	var lane_left := float(_data.get("lane_left", 0.0))
	var lane_right := float(_data.get("lane_right", ArenaCatalog.LANE_RIGHT))
	var span := maxf(1.0, lane_right - lane_left)
	var band := _band_rect(box)
	_draw_band(band)
	_draw_altar(lane_left, span, box.x, band)
	_draw_structures(lane_left, span, box.x, band)
	var player_at := _draw_units(lane_left, span, box.x, band)
	_draw_view(lane_left, span, box, band)
	_draw_player(player_at)


## 外框：半透明玻璃底（4px 阶梯切角），四边 2px 铁线，四角一粒铁钉。
func _draw_frame(box: Vector2) -> void:
	draw_colored_polygon(_stair_points(box, 4.0), GLASS)
	var iron := Color(IRON.r, IRON.g, IRON.b, 0.95)
	draw_rect(Rect2(4.0, 0.0, box.x - 8.0, 2.0), iron)
	draw_rect(Rect2(4.0, box.y - 2.0, box.x - 8.0, 2.0), iron)
	draw_rect(Rect2(0.0, 4.0, 2.0, box.y - 8.0), iron)
	draw_rect(Rect2(box.x - 2.0, 4.0, 2.0, box.y - 8.0), iron)
	for p in [Vector2(2.0, 2.0), Vector2(box.x - 4.0, 2.0), Vector2(2.0, box.y - 4.0),
			Vector2(box.x - 4.0, box.y - 4.0)]:
		draw_rect(Rect2(p, Vector2(2.0, 2.0)), iron)
	# 顶线里侧一道余烬发丝：铁框被炉火照着。
	draw_rect(Rect2(8.0, 2.0, box.x - 16.0, 1.0), Color(EMBER.r, EMBER.g, EMBER.b, 0.35))


func _band_rect(box: Vector2) -> Rect2:
	return Rect2(8.0, floorf(box.y * 0.22), maxf(4.0, box.x - 16.0), floorf(box.y * 0.56))


func _depth_y(depth: float, band: Rect2) -> float:
	var back := float(_data.get("depth_back", ArenaCatalog.DEPTH_BACK))
	var front := float(_data.get("depth_front", ArenaCatalog.DEPTH_FRONT))
	var t := clampf((depth - back) / maxf(1.0, front - back), 0.0, 1.0)
	return lerpf(band.position.y + 3.0, band.position.y + band.size.y - 3.0, t)


func _draw_band(band: Rect2) -> void:
	draw_rect(band, BAND)
	draw_rect(Rect2(band.position, Vector2(band.size.x, 2.0)), BAND_BACK)
	draw_rect(Rect2(band.position + Vector2(0.0, band.size.y - 2.0), Vector2(band.size.x, 2.0)), BAND_FRONT)


func _draw_altar(lane_left: float, span: float, width: float, band: Rect2) -> void:
	var altar := _as_dict(_data.get("altar", {}))
	if altar.is_empty():
		return
	var ax := _map_x(float(altar.get("x", 0.0)) + float(altar.get("w", 0.0)) * 0.5, lane_left, span, width)
	var mid := floorf(band.position.y + band.size.y * 0.5)
	_outline_diamond(Vector2(floorf(ax), mid), 5.0, ALTAR)


func _draw_structures(lane_left: float, span: float, width: float, band: Rect2) -> void:
	var rows: Variant = _data.get("structures", [])
	if rows is not Array:
		return
	var mid := floorf(band.position.y + band.size.y * 0.5)
	for raw in rows:
		if raw is not Dictionary:
			continue
		var row: Dictionary = raw
		var x := floorf(_map_x(float(row.get("x", 0.0)), lane_left, span, width))
		var kind := String(row.get("kind", ""))
		var r := 4.5 if kind == "crystal" else 3.5
		if not bool(row.get("alive", false)):
			GlassKit.diamond(self, Vector2(x, mid), r, Color(GATE.r, GATE.g, GATE.b, 0.28))
			continue
		# 门：贯穿纵深带的一道细线。
		draw_rect(Rect2(x, band.position.y + 1.0, 1.0, band.size.y - 2.0),
				Color(GATE.r, GATE.g, GATE.b, 0.45))
		if kind == "crystal" and not bool(row.get("exposed", true)):
			_outline_diamond(Vector2(x, mid), r, GATE)
		else:
			GlassKit.diamond(self, Vector2(x, mid), r, GATE)


func _draw_units(lane_left: float, span: float, width: float, band: Rect2) -> Vector2:
	var rows: Variant = _data.get("units", [])
	if rows is not Array:
		return Vector2(-1.0, -1.0)
	var player_at := Vector2(-1.0, -1.0)
	for raw in rows:
		if raw is not Dictionary:
			continue
		var row: Dictionary = raw
		var id := String(row.get("id", ""))
		var x := _map_x(float(row.get("x", 0.0)), lane_left, span, width)
		var depth := float(row.get("depth", row.get("y", ArenaCatalog.DEPTH_MID)))
		var p := Vector2(floorf(x), floorf(_depth_y(depth, band)))
		if id == "player":
			player_at = p
			continue
		if not bool(row.get("alive", true)) or bool(row.get("spans", false)):
			continue
		var r := 3.5 if String(row.get("kind", "")) == "hero" else 2.5
		if String(row.get("team", "")) == ArenaCatalog.TEAM_PLAYER:
			GlassKit.diamond(self, p, r, ALLY)
		else:
			# 敌方：冷铁菱形，外缘压一圈浅灰，暗带上也读得出。
			GlassKit.diamond(self, p, r + 1.0, COLD_EDGE)
			GlassKit.diamond(self, p, r, GlassKit.COLD_IRON)
	return player_at


func _draw_view(lane_left: float, span: float, box: Vector2, _band: Rect2) -> void:
	if _view.size.x <= 8.0:
		return
	var x0 := _map_x(_view.position.x, lane_left, span, box.x)
	var x1 := _map_x(_view.position.x + _view.size.x, lane_left, span, box.x)
	var left := floorf(minf(x0, x1))
	var wide := maxf(2.0, floorf(absf(x1 - x0)))
	draw_rect(Rect2(left, 4.0, wide, box.y - 8.0), VIEW, false, 1.0)


func _draw_player(at: Vector2) -> void:
	if at.x < 0.0:
		return
	_outline_diamond(at, 7.0, Color(EMBER_HOT.r, EMBER_HOT.g, EMBER_HOT.b, 0.9))
	GlassKit.diamond(self, at, 4.0, EMBER)
	GlassKit.diamond(self, at, 1.5, EMBER_HOT)


func _outline_diamond(c: Vector2, r: float, col: Color) -> void:
	draw_polyline(PackedVector2Array([
		Vector2(c.x, c.y - r), Vector2(c.x + r, c.y), Vector2(c.x, c.y + r),
		Vector2(c.x - r, c.y), Vector2(c.x, c.y - r),
	]), col, 1.0)


## 2px 阶梯切角的外轮廓（单块多边形，半透明铺底时不会在重叠处叠出色差）。
static func _stair_points(box: Vector2, c: float) -> PackedVector2Array:
	var w := box.x
	var h := box.y
	return PackedVector2Array([
		Vector2(c, 0.0), Vector2(w - c, 0.0), Vector2(w - c, c - 2.0), Vector2(w - 2.0, c - 2.0),
		Vector2(w - 2.0, c), Vector2(w, c), Vector2(w, h - c), Vector2(w - 2.0, h - c),
		Vector2(w - 2.0, h - c + 2.0), Vector2(w - c, h - c + 2.0), Vector2(w - c, h), Vector2(c, h),
		Vector2(c, h - c + 2.0), Vector2(2.0, h - c + 2.0), Vector2(2.0, h - c), Vector2(0.0, h - c),
		Vector2(0.0, c), Vector2(2.0, c), Vector2(2.0, c - 2.0), Vector2(c, c - 2.0),
	])


func _map_x(world_x: float, lane_left: float, span: float, width: float) -> float:
	var t := clampf((world_x - lane_left) / span, 0.0, 1.0)
	return lerpf(8.0, maxf(9.0, width - 8.0), t)


func _as_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		return value as Dictionary
	return {}
