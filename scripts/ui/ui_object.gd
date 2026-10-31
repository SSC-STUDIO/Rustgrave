extends RefCounted
## ObjectKit: 运行时 2px 栅格实物外壳生成库（挂牌 / 账簿 / 铁板 / 便签 / 手札 / 信笺）。
## 本文件不声明 class_name，外部通过 preload 取用：
##   const ObjectKit := preload("res://scripts/ui/ui_object.gd")
##
## 遵循约束：
##   1. 运行时现画，0 新增 PNG 贴图。
##   2. 2px 栅格与设计调色板，完全融入游戏工坊场景。
##   3. 坐标整数对齐，0 几何缩放。

enum Kind {
	BOARD,    ## 吊挂铁牌：暂停菜单（两根铁链吊放、锈斑铆钉、削角倒角）
	LEDGER,   ## 锻炉账簿：设置页（摊开皮面账本、米黄纸页、中缝深影、书签布条）
	PLATE,    ## 蚀刻铁板：地图界面（工业冲孔、边角锚固重栓、蚀刻冷轧钢）
	NOTES,    ## 钉附手纸：操作说明（四张泛黄旧纸错开滑入、黄铜图钉、毛边）
	JOURNAL,  ## 随身手札：教程回看（紧凑型牛皮手札、左右双联开页、黄铜包角搭扣）
	LETTER,   ## 封蜡信笺：覆盖确认（折痕文书、红封蜡火漆印、确认时白热熔解）
}

const CELL := 2

## 锈墓实物质感全套调色板（铁 / 皮 / 纸 / 蜡 / 铜）
const PAL := {
	## 铁件与冷阴影
	"void": Color("#09070B"),
	"outline": Color("#120E14"),
	"iron_dark": Color("#1E1822"),
	"iron_bevel": Color("#3A3036"),
	"iron_mid": Color("#5E4A3E"),
	"iron_light": Color("#8B4513"),
	"rust_orange": Color("#A0522D"),
	"rust_bright": Color("#B8703E"),
	"rust_glow": Color("#FFC14A"),

	## 皮革与装订
	"leather_deep": Color("#160E0A"),
	"leather_base": Color("#2A160E"),
	"leather_mid": Color("#3E2014"),
	"leather_rim": Color("#5A301C"),
	"leather_lit": Color("#7C4426"),
	"stitch_gold": Color("#C49A45"),
	"stitch_dim": Color("#6E5422"),

	## 纸页与中缝
	"parchment_dark": Color("#8A765A"),
	"parchment_shadow": Color("#AFA080"),
	"parchment_base": Color("#D8C8A6"),
	"parchment_light": Color("#E8DCBE"),
	"parchment_pure": Color("#F4ECDC"),
	"gutter_deep": Color("#140E0A"),
	"gutter_shadow": Color("#402E1E"),

	## 封蜡与火漆
	"wax_dark": Color("#3E0B10"),
	"wax_base": Color("#8C1D24"),
	"wax_mid": Color("#B82830"),
	"wax_lit": Color("#E64848"),
	"wax_hot": Color("#FFF0C0"),

	## 黄铜五金
	"brass_shadow": Color("#3A2810"),
	"brass_base": Color("#7A5420"),
	"brass_mid": Color("#B88630"),
	"brass_lit": Color("#FFC14A"),
	"brass_spark": Color("#FFF4D0"),
}

static var _style_cache := {}
static var _wash_cache := {}
static var _tag_cache: StyleBoxTexture = null
static var _ribbon_cache := {}
static var _slider_track_cache: StyleBoxTexture = null
static var _slider_fill_cache := {}
static var _brass_bead_cache := {}
static var _surface_themes := {}


## Paper uses ink throughout; keep the existing font sizes and control classes.
static func surface_theme(kind: Kind) -> Theme:
	if kind not in [Kind.LEDGER, Kind.JOURNAL, Kind.LETTER]:
		return UiKit.extras_theme()
	if _surface_themes.has(kind):
		return _surface_themes[kind]
	var theme := (load("res://assets/ui/theme_rust.tres") as Theme).duplicate() as Theme
	theme.merge_with(UiKit.extras_theme())
	for type in theme.get_type_list():
		if "Label" in String(type):
			var color := Color("#302319")
			if "Dim" in String(type) or "Tiny" in String(type) or "Foot" in String(type):
				color = Color("#64503A")
			theme.set_color("font_color", type, color)
			theme.set_color("default_color", type, color)
			theme.set_color("font_outline_color", type, Color.TRANSPARENT)
			theme.set_color("font_shadow_color", type, Color.TRANSPARENT)
			theme.set_constant("outline_size", type, 0)
			theme.set_constant("shadow_offset_x", type, 0)
			theme.set_constant("shadow_offset_y", type, 0)
	for type in [&"Button", &"PlateButton", &"SettingsButton"]:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			theme.set_stylebox(state, type, ink_row_style(state in ["hover", "focus", "pressed"]))
		for state in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
			theme.set_color(state, type, Color("#302319"))
		theme.set_color("font_outline_color", type, Color.TRANSPARENT)
		theme.set_constant("outline_size", type, 0)
	for type in [&"SettingsRowNormal", &"SettingsRowFocused"]:
		theme.set_stylebox("panel", type, ink_row_style(type == &"SettingsRowFocused"))
	_surface_themes[kind] = theme
	return theme


static func ink_row_style(focused: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.46, 0.27, 0.10, 0.10 if focused else 0.0)
	style.border_color = Color(0.38, 0.20, 0.10, 0.6 if focused else 0.24)
	style.border_width_bottom = 2 if focused else 1
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	return style


# ==============================================================================
# 1. 样式盒生成器 style_box
# ==============================================================================

static func style_box(kind: Kind, size: Vector2) -> StyleBoxTexture:
	var w := int(ceil(size.x / float(CELL))) * CELL
	var h := int(ceil(size.y / float(CELL))) * CELL
	var key := "%d:%dx%d" % [kind, w, h]
	if _style_cache.has(key):
		return _style_cache[key]

	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var sb := StyleBoxTexture.new()

	match kind:
		Kind.BOARD:
			_paint_board(img, w, h)
			_setup_board_stylebox(sb, img, w, h)
		Kind.LEDGER:
			_paint_ledger(img, w, h)
			_setup_ledger_stylebox(sb, img, w, h)
		Kind.PLATE:
			_paint_plate(img, w, h)
			_setup_plate_stylebox(sb, img, w, h)
		Kind.NOTES:
			_paint_notes(img, w, h)
			_setup_notes_stylebox(sb, img, w, h)
		Kind.JOURNAL:
			_paint_journal(img, w, h)
			_setup_journal_stylebox(sb, img, w, h)
		Kind.LETTER:
			_paint_letter(img, w, h)
			_setup_letter_stylebox(sb, img, w, h)

	_style_cache[key] = sb
	return sb


# --- BOARD 吊挂铁牌 -----------------------------------------------------------

static func _paint_board(img: Image, w: int, h: int) -> void:
	var cham := 16 # 16px 削角
	img.fill(Color(0, 0, 0, 0))

	# 1. 填充倒角多边形本体（Base iron fill）
	for y in range(0, h, CELL):
		for x in range(0, w, CELL):
			# 检查是否落在 4 个 45 度削角外
			if x + y < cham:
				continue
			if (w - x - CELL) + y < cham:
				continue
			if x + (h - y - CELL) < cham:
				continue
			if (w - x - CELL) + (h - y - CELL) < cham:
				continue

			# 边框检测
			var dist_top := y
			var dist_bottom := h - y - CELL
			var dist_left := x
			var dist_right := w - x - CELL
			var min_edge := mini(mini(dist_top, dist_bottom), mini(dist_left, dist_right))

			# 削角斜边距离
			var diag_tl := x + y
			var diag_tr := (w - x - CELL) + y
			var diag_bl := x + (h - y - CELL)
			var diag_br := (w - x - CELL) + (h - y - CELL)
			var min_diag := mini(mini(diag_tl - cham, diag_tr - cham), mini(diag_bl - cham, diag_br - cham))
			var edge_dist := mini(min_edge, min_diag)

			var col: Color
			if edge_dist < 2:
				col = PAL["outline"]
			elif edge_dist < 4:
				col = PAL["rust_orange"] if (x <= y and x < w - y) or y < h / 3 else PAL["iron_dark"]
			elif edge_dist < 8:
				col = PAL["iron_bevel"]
			elif edge_dist < 10:
				col = PAL["void"]
			else:
				# 铁板表面与确定性锈斑噪点
				col = PAL["iron_dark"]
				var n := int((x * 374761393 + y * 668265263) ^ 0x5bf03635) & 0x7fffffff
				var pct := n % 1000
				if pct < 3:
					col = PAL["iron_mid"]
				elif pct < 5:
					col = PAL["iron_light"]
				elif pct < 7:
					col = PAL["rust_orange"]
				elif pct < 8:
					col = PAL["rust_bright"]

			img.fill_rect(Rect2i(x, y, CELL, CELL), col)

	# 2. 4 角与边缘锻造铆钉 (6x6 px)
	var rivet_pos: Array[Vector2i] = [
		Vector2i(24, 24),
		Vector2i(w - 24, 24),
		Vector2i(24, h - 24),
		Vector2i(w - 24, h - 24),
	]
	# 顶底边缘铆钉
	var steps := maxi(int(w / 120), 2)
	for i in range(1, steps):
		var rx := int(w * float(i) / float(steps))
		rivet_pos.append(Vector2i(rx, 14))
		rivet_pos.append(Vector2i(rx, h - 14))

	for pos in rivet_pos:
		_draw_rivet(img, pos.x, pos.y)


static func _draw_rivet(img: Image, cx: int, cy: int) -> void:
	# 6x6 锻造铆钉
	img.fill_rect(Rect2i(cx - 3, cy - 3, 6, 6), PAL["outline"])
	img.fill_rect(Rect2i(cx - 2, cy - 2, 4, 4), PAL["iron_light"])
	img.fill_rect(Rect2i(cx - 1, cy - 1, 2, 2), PAL["rust_orange"])
	img.fill_rect(Rect2i(cx - 1, cy - 1, 1, 1), PAL["rust_glow"])


static func _setup_board_stylebox(sb: StyleBoxTexture, img: Image, w: int, h: int) -> void:
	var tex := ImageTexture.create_from_image(img)
	sb.texture = tex
	sb.texture_margin_left = 28.0
	sb.texture_margin_top = 28.0
	sb.texture_margin_right = 28.0
	sb.texture_margin_bottom = 28.0
	sb.content_margin_left = 36.0
	sb.content_margin_top = 32.0
	sb.content_margin_right = 36.0
	sb.content_margin_bottom = 32.0
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH


# --- LEDGER 锻炉账簿 -----------------------------------------------------------

static func _paint_ledger(img: Image, w: int, h: int) -> void:
	img.fill(Color(0, 0, 0, 0))

	# 1. 皮革底板 (12px 外周)
	var leather_margin := 12
	for y in range(0, h, CELL):
		for x in range(0, w, CELL):
			var dist_top := y
			var dist_bottom := h - y - CELL
			var dist_left := x
			var dist_right := w - x - CELL
			var min_edge := mini(mini(dist_top, dist_bottom), mini(dist_left, dist_right))

			var col: Color = PAL["leather_base"]
			if min_edge < 2:
				col = PAL["outline"]
			elif min_edge < 4:
				col = PAL["leather_lit"] if (x <= y and x < w - y) or y < h / 3 else PAL["leather_deep"]
			elif min_edge < 6:
				col = PAL["leather_mid"]
			elif min_edge < 8:
				# 缝线位
				var stitch_pos := (x + y) / 4
				col = PAL["stitch_gold"] if (stitch_pos % 2 == 0) else PAL["leather_base"]
			else:
				col = PAL["leather_base"]

			img.fill_rect(Rect2i(x, y, CELL, CELL), col)

	# 2. 左右对开米黄纸页
	var cx := w / 2
	var gutter_half := 18
	var page_margin_top := 14
	var page_margin_bottom := 14
	var page_margin_side := 14

	var left_rect := Rect2i(page_margin_side, page_margin_top, cx - gutter_half - page_margin_side, h - page_margin_top - page_margin_bottom)
	var right_rect := Rect2i(cx + gutter_half, page_margin_top, w - page_margin_side - (cx + gutter_half), h - page_margin_top - page_margin_bottom)

	for r in [left_rect, right_rect]:
		# 纸页基底
		img.fill_rect(r, PAL["parchment_base"])
		# 纸页叠层阴影（顶光与边缘）
		img.fill_rect(Rect2i(r.position.x, r.position.y, r.size.x, 2), PAL["parchment_light"])
		img.fill_rect(Rect2i(r.position.x, r.position.y + r.size.y - 2, r.size.x, 2), PAL["parchment_dark"])
		# 细微纸页纹理噪点
		for py in range(r.position.y + 2, r.position.y + r.size.y - 2, CELL * 2):
			for px in range(r.position.x + 2, r.position.x + r.size.x - 2, CELL * 2):
				var n := int((px * 2654435761 + py * 2246822519) ^ 0x9e3779b9) & 0x7fffffff
				if n % 43 < 2:
					img.fill_rect(Rect2i(px, py, CELL, CELL), PAL["parchment_shadow"])

	# 3. 中缝装订与阴影过渡（Gutter shadow）
	for y in range(page_margin_top, h - page_margin_bottom, CELL):
		for x in range(cx - gutter_half * 2, cx + gutter_half * 2, CELL):
			var dist := absf(float(x - cx))
			var t := clampf(dist / float(gutter_half * 2), 0.0, 1.0)
			var shadow_val := (1.0 - t)
			if dist < 3.0:
				img.fill_rect(Rect2i(x, y, CELL, CELL), PAL["gutter_deep"])
			elif dist < float(gutter_half):
				var shadow_col: Color = PAL["gutter_shadow"].lerp(PAL["parchment_base"], t)
				img.fill_rect(Rect2i(x, y, CELL, CELL), shadow_col)
			elif dist < float(gutter_half * 2):
				var shadow_col: Color = PAL["parchment_shadow"].lerp(PAL["parchment_base"], t)
				img.fill_rect(Rect2i(x, y, CELL, CELL), shadow_col)

	# 4. 黄铜包角 (Brass corners)
	_draw_corner_plate(img, 0, 0, false, false)
	_draw_corner_plate(img, w, 0, true, false)
	_draw_corner_plate(img, 0, h, false, true)
	_draw_corner_plate(img, w, h, true, true)


static func _draw_corner_plate(img: Image, x: int, y: int, flip_x: bool, flip_y: bool) -> void:
	var sz := 22
	for dy in range(sz):
		for dx in range(sz - dy):
			var px := x - dx - 1 if flip_x else x + dx
			var py := y - dy - 1 if flip_y else y + dy
			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				var c: Color = PAL["brass_base"]
				if dx + dy < 4:
					c = PAL["brass_lit"]
				elif dx + dy == sz - dy - 1:
					c = PAL["brass_shadow"]
				elif (dx == 4 and dy == 4):
					c = PAL["brass_spark"]
				img.set_pixel(px, py, c)


static func _setup_ledger_stylebox(sb: StyleBoxTexture, img: Image, w: int, h: int) -> void:
	var tex := ImageTexture.create_from_image(img)
	sb.texture = tex
	sb.texture_margin_left = 24.0
	sb.texture_margin_top = 24.0
	sb.texture_margin_right = 24.0
	sb.texture_margin_bottom = 24.0
	sb.content_margin_left = 40.0
	sb.content_margin_top = 36.0
	sb.content_margin_right = 40.0
	sb.content_margin_bottom = 36.0
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH


# --- PLATE 蚀刻铁板 -----------------------------------------------------------

static func _paint_plate(img: Image, w: int, h: int) -> void:
	img.fill(Color("#24272D"))
	# 边缘与冲压槽
	for y in range(0, h, CELL):
		for x in range(0, w, CELL):
			var dist := mini(mini(x, w - x - CELL), mini(y, h - y - CELL))
			if dist < 2:
				img.fill_rect(Rect2i(x, y, CELL, CELL), PAL["outline"])
			elif dist < 6:
				img.fill_rect(Rect2i(x, y, CELL, CELL), PAL["iron_bevel"])
			elif dist == 6 or dist == 8:
				img.fill_rect(Rect2i(x, y, CELL, CELL), PAL["void"])
			elif (x * 31 + y * 17) % 163 < 2:
				img.fill_rect(Rect2i(x, y, CELL, CELL), Color("#2C3036"))
	# Sparse cold-rolled scratches stay away from the route and reading areas.
	for i in 12:
		var x := 28 + (i * 173) % maxi(2, w - 100)
		var y := 18 + (i * 97) % maxi(2, h - 36)
		img.fill_rect(Rect2i(x, y, 12 + (i % 3) * 8, 2), Color("#34373B"))
	# 顶部冲孔 notches (14 个方孔)
	var hole_w := 8
	var hole_h := 8
	var spacing := (w - 120) / 14
	for i in 14:
		var hx := 60 + i * spacing
		img.fill_rect(Rect2i(hx, 10, hole_w, hole_h), PAL["void"])
		img.fill_rect(Rect2i(hx, 10, hole_w, 1), PAL["iron_mid"])


static func _setup_plate_stylebox(sb: StyleBoxTexture, img: Image, w: int, h: int) -> void:
	var tex := ImageTexture.create_from_image(img)
	sb.texture = tex
	sb.texture_margin_left = 24.0
	sb.texture_margin_top = 24.0
	sb.texture_margin_right = 24.0
	sb.texture_margin_bottom = 24.0
	sb.content_margin_left = 34.0
	sb.content_margin_top = 38.0
	sb.content_margin_right = 34.0
	sb.content_margin_bottom = 32.0


# --- NOTES 钉附便签 -----------------------------------------------------------

static func _paint_notes(img: Image, _w: int, _h: int) -> void:
	# Each sheet follows its own layout and animation in ControlsPanel.
	img.fill(Color.TRANSPARENT)


static func _setup_notes_stylebox(sb: StyleBoxTexture, img: Image, w: int, h: int) -> void:
	var tex := ImageTexture.create_from_image(img)
	sb.texture = tex
	sb.texture_margin_left = 24.0
	sb.texture_margin_top = 24.0
	sb.texture_margin_right = 24.0
	sb.texture_margin_bottom = 24.0
	sb.content_margin_left = 32.0
	sb.content_margin_top = 32.0
	sb.content_margin_right = 32.0
	sb.content_margin_bottom = 30.0


# --- JOURNAL 随身手札 ---------------------------------------------------------

static func _paint_journal(img: Image, w: int, h: int) -> void:
	_paint_ledger(img, w, h)
	# A compact travel journal has a stitched spine rather than a dark split.
	var cx := (w / 2 / CELL) * CELL
	for y in range(20, h - 20, 24):
		img.fill_rect(Rect2i(cx - 6, y, 12, 2), PAL["stitch_dim"])
		img.fill_rect(Rect2i(cx - 6, y, 2, 4), PAL["stitch_gold"])


static func _setup_journal_stylebox(sb: StyleBoxTexture, img: Image, w: int, h: int) -> void:
	var tex := ImageTexture.create_from_image(img)
	sb.texture = tex
	sb.texture_margin_left = 20.0
	sb.texture_margin_top = 20.0
	sb.texture_margin_right = 20.0
	sb.texture_margin_bottom = 20.0
	sb.content_margin_left = 36.0
	sb.content_margin_top = 32.0
	sb.content_margin_right = 36.0
	sb.content_margin_bottom = 32.0


# --- LETTER 封蜡信笺 -----------------------------------------------------------

static func _paint_letter(img: Image, w: int, h: int) -> void:
	img.fill(PAL["parchment_base"])
	for y in range(0, h, CELL):
		for x in range(0, w, CELL):
			var edge := mini(mini(x, w - x - CELL), mini(y, h - y - CELL))
			var noise := (x * 17 + y * 71) % 89
			if edge < 2:
				img.fill_rect(Rect2i(x, y, CELL, CELL), PAL["parchment_dark"])
			elif edge < 8 or noise < 2:
				img.fill_rect(Rect2i(x, y, CELL, CELL), PAL["parchment_shadow"])
	img.fill_rect(Rect2i(0, 0, w, 2), PAL["parchment_light"])
	img.fill_rect(Rect2i(0, h - 2, w, 2), PAL["parchment_dark"])
	# 水平折痕 (Fold crease at y = 35%)
	var fold_y := int(h * 0.35)
	img.fill_rect(Rect2i(0, fold_y, w, 2), PAL["parchment_dark"])
	img.fill_rect(Rect2i(0, fold_y + 2, w, 2), PAL["parchment_light"])
	# The seal is drawn by LetterDressing so a press can heat it independently.


static func _setup_letter_stylebox(sb: StyleBoxTexture, img: Image, w: int, h: int) -> void:
	var tex := ImageTexture.create_from_image(img)
	sb.texture = tex
	sb.texture_margin_left = 16.0
	sb.texture_margin_top = 16.0
	sb.texture_margin_right = 16.0
	sb.texture_margin_bottom = 16.0
	sb.content_margin_left = 28.0
	sb.content_margin_top = 28.0
	sb.content_margin_right = 28.0
	sb.content_margin_bottom = 28.0


# ==============================================================================
# 2. 专用装饰与附件生成器 dressing
# ==============================================================================

static func dressing(kind: Kind, card: Control) -> Node2D:
	match kind:
		Kind.BOARD:
			var d := BoardDressing.new()
			d.bind_card(card)
			return d
		Kind.LEDGER:
			var d := LedgerDressing.new()
			d.bind_card(card)
			return d
		Kind.PLATE:
			var d := PlateDressing.new()
			d.bind_card(card)
			return d
		Kind.NOTES:
			var d := NotesDressing.new()
			d.bind_card(card)
			return d
		Kind.JOURNAL:
			var d := JournalDressing.new()
			d.bind_card(card)
			return d
		Kind.LETTER:
			var d := LetterDressing.new()
			d.bind_card(card)
			return d
	return null


# --- BoardDressing: 吊挂铁链与吊环 --------------------------------------------

class BoardDressing extends Node2D:
	var _card: Control = null
	var sway_angle := 0.0
	var drop_bounce := 0.0
	var _time := 0.0
	var _swaying := false

	func _init() -> void:
		name = "BoardDressing"
		z_index = -1

	func bind_card(card: Control) -> void:
		_card = card
		if _card != null:
			_card.item_rect_changed.connect(queue_redraw)

	func _process(delta: float) -> void:
		if _swaying:
			_time += delta
			sway_angle = 0.008 * sin(_time * 7.0) * exp(-_time * 2.5)
			if _time > 1.2:
				_swaying = false
				sway_angle = 0.0
			queue_redraw()
		elif not is_zero_approx(drop_bounce):
			queue_redraw()

	func play_spring_settle(force: bool = false) -> void:
		if DisplayServer.get_name() == "headless" and not force:
			snap()
			return
		_swaying = true
		_time = 0.0
		queue_redraw()

	func snap() -> void:
		_swaying = false
		sway_angle = 0.0
		drop_bounce = 0.0
		queue_redraw()

	func get_anchor_point(index: int) -> Vector2:
		if _card == null or not is_instance_valid(_card):
			return Vector2.ZERO
		var cp := _card.position
		var cs := _card.size
		var chain_x := roundf(cp.x + cs.x * (0.22 if index == 0 else 0.78))
		var top_y := 0.0
		var anchor_y := roundf(cp.y + 6.0)
		var local_anchor := Vector2(0.0, anchor_y - top_y).rotated(sway_angle)
		return Vector2(chain_x, top_y) + local_anchor

	func _draw() -> void:
		if _card == null or not is_instance_valid(_card):
			return
		var cp := _card.position
		var cs := _card.size
		if cs.x <= 0 or cs.y <= 0:
			return

		var chain_x1 := roundf(cp.x + cs.x * 0.22)
		var chain_x2 := roundf(cp.x + cs.x * 0.78)
		var top_y := 0.0 # 屏幕顶部
		var anchor_y := roundf(cp.y + 6.0)

		# 绘制左/右悬挂铁链 (应用 sway_angle 动态摆动)
		_draw_swaying_chain(chain_x1, top_y, anchor_y, sway_angle)
		_draw_swaying_chain(chain_x2, top_y, anchor_y, sway_angle)

	func _draw_swaying_chain(chain_x: float, top_y: float, anchor_y: float, angle: float) -> void:
		draw_set_transform(Vector2(chain_x, top_y), angle, Vector2.ONE)
		_draw_chain_column(0.0, 0.0, anchor_y - top_y)
		_draw_shackle(Vector2(0.0, anchor_y - top_y))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw_chain_column(x: float, y_start: float, y_end: float) -> void:
		var link_h := 12.0
		var cur_y := y_start
		var i := 0
		while cur_y < y_end:
			var link_rect := Rect2(x - 4.0, cur_y, 8.0, link_h)
			if i % 2 == 0:
				# 正面扁环
				draw_rect(link_rect, PAL["outline"])
				draw_rect(Rect2(x - 2.0, cur_y + 2.0, 4.0, link_h - 4.0), PAL["iron_dark"])
				draw_rect(Rect2(x - 1.0, cur_y + 3.0, 2.0, 2.0), PAL["rust_bright"])
			else:
				# 侧向细环
				draw_rect(Rect2(x - 2.0, cur_y, 4.0, link_h), PAL["iron_light"])
				draw_rect(Rect2(x - 1.0, cur_y + 2.0, 2.0, link_h - 4.0), PAL["rust_orange"])
			cur_y += link_h - 2.0
			i += 1

	func _draw_shackle(pos: Vector2) -> void:
		# U-shackle bracket (16x14 px)
		draw_rect(Rect2(pos.x - 7.0, pos.y - 4.0, 14.0, 12.0), PAL["outline"])
		draw_rect(Rect2(pos.x - 5.0, pos.y - 2.0, 10.0, 8.0), PAL["iron_bevel"])
		draw_rect(Rect2(pos.x - 3.0, pos.y, 6.0, 4.0), PAL["void"])
		# 横穿重销钉与琥珀火光
		draw_rect(Rect2(pos.x - 8.0, pos.y + 4.0, 16.0, 3.0), PAL["iron_light"])
		draw_rect(Rect2(pos.x - 2.0, pos.y + 4.0, 4.0, 3.0), PAL["rust_glow"])


# --- LedgerDressing: 书签布条与角板 --------------------------------------------

class LedgerDressing extends Node2D:
	var _card: Control = null
	var _active_tab := 0
	var _cover_time := 1.0

	func play_open() -> void:
		_cover_time = 0.0
		queue_redraw()

	func snap() -> void:
		_cover_time = 1.0
		queue_redraw()

	func _process(delta: float) -> void:
		if _cover_time < 0.18:
			_cover_time += delta
			queue_redraw()

	func _draw_cover() -> void:
		if _cover_time >= 0.18 or not is_instance_valid(_card):
			return
		var amount := 0.45 if _cover_time < 0.09 else 0.16
		var height := roundf(_card.size.y * amount / 2.0) * 2.0
		var base := _card.position + Vector2(12, _card.size.y - height - 12)
		draw_rect(Rect2(base, Vector2(_card.size.x - 24, height)), PAL["leather_mid"])
		draw_line(base, base + Vector2(_card.size.x - 24, 0), PAL["stitch_gold"], 2.0)

	const RIBBON_COLORS := [
		Color("#8C1D24"), # Tab 0: 音频 Crimson
		Color("#D4881E"), # Tab 1: 画面 Amber
		Color("#4A3E44"), # Tab 2: 键位 Cold Iron
		Color("#2E5E52"), # Tab 3: 辅助 Weathered Teal
	]

	func _init() -> void:
		name = "LedgerDressing"
		z_index = 1

	func bind_card(card: Control) -> void:
		_card = card
		if _card != null:
			_card.item_rect_changed.connect(queue_redraw)

	func set_active_tab(idx: int) -> void:
		_active_tab = clampi(idx, 0, 3)
		queue_redraw()

	func _draw() -> void:
		if _card == null or not is_instance_valid(_card):
			return
		var cp := _card.position
		var cs := _card.size
		if cs.x <= 0 or cs.y <= 0:
			return

		# 绘制 4 根从账簿顶部边缘探出的丝绸书签布条
		var tab_w := 156.0
		var sep := 12.0
		var total_w := 4.0 * tab_w + 3.0 * sep
		var start_x := roundf(cp.x + (cs.x - total_w) * 0.5)

		for i in 4:
			var rx := start_x + float(i) * (tab_w + sep) + tab_w * 0.5 - 14.0
			var is_active := (i == _active_tab)
			var h := 22.0 if is_active else 14.0
			var ry := roundf(cp.y + 12.0 - h)
			var col: Color = RIBBON_COLORS[i]
			if is_active:
				col = col.lightened(0.2)

			# 丝带本体 (28px 宽)
			draw_rect(Rect2(rx, ry, 28.0, h), col)
			# 丝带金边与暗影
			draw_rect(Rect2(rx, ry, 2.0, h), PAL["stitch_gold"] if is_active else col.darkened(0.3))
			draw_rect(Rect2(rx + 26.0, ry, 2.0, h), col.darkened(0.4))
			# 燕尾剪口 (Chevron notch)
			var tip_y := ry
			draw_line(Vector2(rx, tip_y), Vector2(rx + 14.0, tip_y + 5.0), PAL["outline"], 1.0)
			draw_line(Vector2(rx + 28.0, tip_y), Vector2(rx + 14.0, tip_y + 5.0), PAL["outline"], 1.0)

		_draw_cover()

# --- PlateDressing / NotesDressing / JournalDressing / LetterDressing ---------

class PlateDressing extends Node2D:
	var _card: Control
	var _time := 1.0
	func bind_card(card: Control) -> void:
		_card = card
		card.item_rect_changed.connect(queue_redraw)
	func play_open() -> void:
		_time = 0.0
		queue_redraw()
	func snap() -> void:
		_time = 1.0
		queue_redraw()
	func _process(delta: float) -> void:
		if _time < 0.5:
			_time += delta
			queue_redraw()
	func _draw() -> void:
		if not is_instance_valid(_card):
			return
		var rect := _card.get_rect().grow(-18.0)
		var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		for i in corners.size():
			if _time < i * 0.06:
				continue
			var p: Vector2 = corners[i].round()
			draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), PAL["outline"])
			draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), PAL["iron_mid"])
			draw_line(p + Vector2(-2, -2), p + Vector2(2, 2), PAL["brass_shadow"], 2.0)
			if _time < i * 0.06 + 0.08:
				for ray in 4:
					var direction := Vector2.from_angle(float(ray) * PI / 2.0 + 0.4)
					draw_line((p + direction * 8.0).round(), (p + direction * 18.0).round(), PAL["brass_lit"], 2.0)

class NotesDressing extends Node2D:
	func bind_card(_card: Control) -> void:
		pass

class JournalDressing extends LedgerDressing:
	func _draw() -> void:
		# Travel-book clasp at the edge, away from either page's text.
		if not is_instance_valid(_card):
			return
		var p := (_card.position + Vector2(_card.size.x - 6.0, _card.size.y * 0.5)).round()
		draw_rect(Rect2(p - Vector2(12, 12), Vector2(22, 24)), PAL["leather_mid"])
		draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), PAL["brass_base"])
		draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), PAL["brass_lit"])
		_draw_cover()

class LetterDressing extends Node2D:
	var _card: Control
	var heat := 0.0:
		set(value):
			heat = value
			queue_redraw()
	func bind_card(card: Control) -> void:
		_card = card
		card.item_rect_changed.connect(queue_redraw)
	func snap() -> void:
		heat = 0.0
	func seal_center() -> Vector2:
		return (_card.position + Vector2(_card.size.x * 0.5, _card.size.y - 32.0)).round()
	func _draw() -> void:
		if not is_instance_valid(_card):
			return
		var center := seal_center()
		# Chunked wax rim and a stamped furnace rune, never a new texture/light.
		for y in range(-20, 22, 2):
			for x in range(-20, 22, 2):
				var d := Vector2(x, y).length()
				if d > 20.0 + sin(float(x + y)) * 1.5:
					continue
				var color: Color = PAL["wax_dark"] if d > 16.0 else PAL["wax_base"]
				if y < -8 and d < 16.0:
					color = PAL["wax_mid"]
				draw_rect(Rect2(center + Vector2(x, y), Vector2(2, 2)), color.lerp(PAL["wax_hot"], heat))
		var ink: Color = PAL["wax_lit"].lerp(PAL["wax_hot"], heat)
		draw_rect(Rect2(center + Vector2(-8, -8), Vector2(16, 16)), ink, false, 2.0)
		draw_line(center + Vector2(-6, 4), center + Vector2(0, -5), ink, 2.0)
		draw_line(center + Vector2(0, -5), center + Vector2(6, 4), ink, 2.0)


# ==============================================================================
# 3. 顶光与暗角光晕 light_wash
# ==============================================================================

static func light_wash(kind: Kind, size: Vector2) -> TextureRect:
	var w := int(ceil(size.x / float(CELL))) * CELL
	var h := int(ceil(size.y / float(CELL))) * CELL
	var key := "%d:%dx%d" % [kind, w, h]

	var tex: ImageTexture
	if _wash_cache.has(key):
		tex = _wash_cache[key]
	else:
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		var cx := float(w) * 0.5
		var cy := float(h) * 0.08
		var max_r := float(maxi(w, h)) * 0.72

		for b in h / CELL:
			var y := float(b * CELL)
			for a in w / CELL:
				var x := float(a * CELL)
				var d := sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy) * 1.4)
				var norm := clampf(d / max_r, 0.0, 1.0)

				# 顶光暖晕 (Warm amber falloff)
				var warm := clampf(1.0 - norm * 1.3, 0.0, 1.0)
				var warm_a := warm * 0.16

				# 边缘暗角 (Edge vignette)
				var edge_x := absf(x - cx) / (float(w) * 0.5)
				var edge_y := absf(y - float(h) * 0.5) / (float(h) * 0.5)
				var vig := clampf(maxf(edge_x, edge_y) - 0.70, 0.0, 1.0) * 3.3
				var vig_a := clampf(vig * 0.26, 0.0, 0.32)

				var c := Color(1.0, 0.76, 0.38, warm_a)
				if vig_a > 0.01:
					c = c.blend(Color(0.04, 0.02, 0.06, vig_a))

				img.fill_rect(Rect2i(int(x), int(y), CELL, CELL), c)

		tex = ImageTexture.create_from_image(img)
		_wash_cache[key] = tex

	var r := TextureRect.new()
	r.name = "LightWash"
	r.texture = tex
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.custom_minimum_size = Vector2.ZERO
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# ==============================================================================
# 4. 辅助样式生成：行程签 / 书签 / 滑条轨 / 铜珠 / 印章
# ==============================================================================

## 行程签样式盒：用于暂停菜单右列 Dossier（羊皮纸条 + 4 角铁铆钉）
static func journey_tag_style_box() -> StyleBoxTexture:
	if _tag_cache != null:
		return _tag_cache

	var w := 460
	var h := 480
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)

	# 羊皮纸底色
	img.fill(PAL["parchment_base"])
	# 边缘与磨损
	for y in range(0, h, CELL):
		for x in range(0, w, CELL):
			var dist := mini(mini(x, w - x - CELL), mini(y, h - y - CELL))
			if dist < 2:
				img.fill_rect(Rect2i(x, y, CELL, CELL), PAL["outline"])
			elif dist < 4:
				img.fill_rect(Rect2i(x, y, CELL, CELL), PAL["parchment_shadow"])
			elif dist < 6:
				img.fill_rect(Rect2i(x, y, CELL, CELL), PAL["parchment_light"] if (y < h / 2) else PAL["parchment_dark"])

	# 4 角固定铁铆钉
	var corners := [Vector2i(14, 14), Vector2i(w - 14, 14), Vector2i(14, h - 14), Vector2i(w - 14, h - 14)]
	for c in corners:
		_draw_rivet(img, c.x, c.y)

	var tex := ImageTexture.create_from_image(img)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = 18.0
	sb.texture_margin_top = 18.0
	sb.texture_margin_right = 18.0
	sb.texture_margin_bottom = 18.0
	sb.content_margin_left = 24.0
	sb.content_margin_top = 20.0
	sb.content_margin_right = 24.0
	sb.content_margin_bottom = 20.0
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	_tag_cache = sb
	return sb


## 书签布条样式盒：用于设置页 Tab0..Tab3
static func ribbon_style_box(tab_index: int, active: bool) -> StyleBoxTexture:
	var key := "%d:%s" % [tab_index, "1" if active else "0"]
	if _ribbon_cache.has(key):
		return _ribbon_cache[key]

	var w := 156
	var h := 52 if active else 44
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)

	var colors := [
		Color("#8C1D24"), # Audio
		Color("#D4881E"), # Display
		Color("#4A3E44"), # Keys
		Color("#2E5E52"), # Assist
	]
	var base_col: Color = colors[tab_index % colors.size()]
	if active:
		base_col = base_col.lightened(0.18)

	img.fill(base_col)
	# 织物边缘暗影
	for y in range(0, h, CELL):
		for x in range(0, w, CELL):
			var dist := mini(mini(x, w - x - CELL), mini(y, h - y - CELL))
			if dist < 2:
				img.fill_rect(Rect2i(x, y, CELL, CELL), PAL["outline"])
			elif dist < 4:
				img.fill_rect(Rect2i(x, y, CELL, CELL), PAL["stitch_gold"] if active else base_col.darkened(0.25))

	var tex := ImageTexture.create_from_image(img)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = 12.0
	sb.texture_margin_top = 12.0
	sb.texture_margin_right = 12.0
	sb.texture_margin_bottom = 12.0
	sb.content_margin_left = 16.0
	sb.content_margin_top = 8.0
	sb.content_margin_right = 16.0
	sb.content_margin_bottom = 8.0
	_ribbon_cache[key] = sb
	return sb


## 墨线滑条轨道样式盒
static func ink_track_style_box() -> StyleBoxTexture:
	if _slider_track_cache != null:
		return _slider_track_cache

	var w := 64
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# 2px 墨线槽
	img.fill_rect(Rect2i(0, 7, w, 2), Color("#2C1D11"))
	img.fill_rect(Rect2i(0, 6, w, 1), Color("#120E14", 0.5))
	img.fill_rect(Rect2i(0, 9, w, 1), Color("#5E4A3E", 0.5))

	var tex := ImageTexture.create_from_image(img)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = 8.0
	sb.texture_margin_right = 8.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	_slider_track_cache = sb
	return sb


## 墨线滑条填充样式盒
static func ink_fill_style_box(highlight: bool = false) -> StyleBoxTexture:
	var key := "hi" if highlight else "norm"
	if _slider_fill_cache.has(key):
		return _slider_fill_cache[key]

	var w := 32
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var fill_col := Color("#C6691A") if highlight else Color("#8B4513")
	img.fill_rect(Rect2i(0, 7, w, 2), fill_col)

	var tex := ImageTexture.create_from_image(img)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = 4.0
	sb.texture_margin_right = 4.0
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	_slider_fill_cache[key] = sb
	return sb


## 黄铜珠滑块图标 (14x14 px 3D 球体)
static func create_brass_bead_icon(highlight: bool = false) -> ImageTexture:
	var key := "hi" if highlight else "norm"
	if _brass_bead_cache.has(key):
		return _brass_bead_cache[key]

	var sz := 14
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(7.0, 7.0)
	var r := 5.5

	for y in sz:
		for x in sz:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(c)
			if d <= r:
				var col: Color = PAL["brass_base"].lerp(PAL["brass_lit"], 1.0 - d / r)
				if highlight:
					col = col.lightened(0.25)
				# 高光光斑
				if p.distance_to(Vector2(5.0, 5.0)) <= 1.8:
					col = PAL["brass_spark"]
				# 轮廓暗边
				if d >= r - 1.0:
					col = PAL["brass_shadow"]
				img.set_pixel(x, y, col)
			elif d <= r + 1.2 and y >= 7:
				# 投影到纸面
				img.set_pixel(x, y, Color(0.1, 0.08, 0.06, 0.35))

	var tex := ImageTexture.create_from_image(img)
	_brass_bead_cache[key] = tex
	return tex
