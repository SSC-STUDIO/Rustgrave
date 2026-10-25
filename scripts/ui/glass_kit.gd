class_name GlassKit
extends RefCounted
## 玻璃卡与跨界面共用的小部件：半透明卡片材质、小题头、章节刻度条、结局印记。
##
## 玻璃只改卡片的着色透明度（StyleBoxTexture.modulate_color）：纹理、切角和花边都不动，
## 场景的光从后面透出来，文字靠浅色保证对比。ui_modal.gd 的弹窗外壳默认套用，所以所有弹窗
## 是同一个透明度；标题档案卡用 TitleCard.body_alpha 走同一个数。
##
## 章节刻度条（ChapterRail）与结局印记（SealMark）原本只在回看余烬里，现在暂停菜单、地图、
## 回看页用的是同一套「第几章、走到哪」的语汇。

const CARD_ALPHA := 0.78
const EMBER := Color("#FFC14A")
const EMBER_HOT := Color("#FFF0C0")
const ROD := Color("#4A2A18")
const COLD := Color("#3A3036")
const COLD_EDGE := Color("#241C22")
const COLD_IRON := Color("#5E4A3E")
const INK := Color("#0E0C15")


## 给弹窗卡片套玻璃：取额外主题里的 OrnatePanel 纹理盒，复制一份只改着色透明度。
## 卡片已经有自定义 panel 样式时不动，免得透明度叠两次。
static func glass(card: Control, alpha: float = CARD_ALPHA) -> void:
	if card == null or card.has_theme_stylebox_override(&"panel"):
		return
	var base := UiKit.extras_theme().get_stylebox(&"panel", &"OrnatePanel") as StyleBoxTexture
	if base == null:
		return
	var glass_box := base.duplicate() as StyleBoxTexture
	glass_box.modulate_color = Color(1.0, 1.0, 1.0, alpha)
	card.add_theme_stylebox_override(&"panel", glass_box)


## 卡片里的小题头：12px 余烬色，不接收鼠标。
static func kicker(text: String, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := UiKit.label(text, &"TinyStrongLabel", align)
	label.modulate = UiKit.EMBER
	label.custom_minimum_size = Vector2(0.0, 22.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## 撑满剩余高度的空白：把内容推向中间或两端。
static func spacer() -> Control:
	var gap := Control.new()
	gap.name = "Spacer"
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


## 1px 的余烬短线，标题与正文之间用。
static func rule(width: float = 120.0) -> Control:
	var line := ColorRect.new()
	line.name = "Rule"
	line.color = Color(UiKit.EMBER.r, UiKit.EMBER.g, UiKit.EMBER.b, 0.35)
	line.custom_minimum_size = Vector2(width, 1.0)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## 菱形（刻度与印记共用）：画在 canvas 上，中心 c，半径 r。
static func diamond(canvas: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(c.x, c.y - r), Vector2(c.x + r, c.y),
			Vector2(c.x, c.y + r), Vector2(c.x - r, c.y)]), col)


## 从存档 flags 取每章是否已通关（战役顺序，口径与 StoryFlow.DONE_FLAGS 一致）。
static func done_from_flags(flags: Variant) -> Array[bool]:
	var out: Array[bool] = []
	for id in ChapterText.order():
		var flag := StoryFlow.done_flag(id)
		out.append(flag != "" and flags.has(flag))
	return out


## 结局印记：一枚菱形章，颜色随结局（还火金 / 守炉橙 / 熄火灰紫），两侧各一道细线。
class SealMark extends Control:
	var tint: Color = GlassKit.EMBER:
		set(value):
			tint = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0.0, 44.0)

	func _draw() -> void:
		var c := Vector2(floorf(size.x * 0.5), floorf(size.y * 0.5))
		var line := Color(tint.r, tint.g, tint.b, 0.4)
		draw_rect(Rect2(c.x - 64.0, c.y, 40.0, 1.0), line)
		draw_rect(Rect2(c.x + 24.0, c.y, 40.0, 1.0), line)
		GlassKit.diamond(self, c, 17.0, Color(tint.r, tint.g, tint.b, 0.14))
		GlassKit.diamond(self, c, 14.0, tint)
		GlassKit.diamond(self, c, 10.0, GlassKit.INK)
		GlassKit.diamond(self, c, 6.0, tint)
		GlassKit.diamond(self, c, 2.0, GlassKit.EMBER_HOT)


## 章节刻度条：每章一粒菱形，已通关的烧成余烬，正在进行的那一章外圈一道光晕，其余是冷铁；
## 幕与幕之间立一道竖线（幕的起点取自标题标尺 TitleGauge.ACT_STARTS，同一口径）。
class ChapterRail extends Control:
	const PITCH := 20.0
	var _done: Array[bool] = []
	var _current := -1

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0.0, 14.0)

	## done = 每章是否通关（战役顺序）；current = 正在进行的章下标（-1 = 不标）。
	func set_journey(done: Array[bool], current: int = -1) -> void:
		_done = done.duplicate()
		_current = current
		queue_redraw()

	func _draw() -> void:
		var n := _done.size()
		if n == 0:
			return
		var x0 := floorf((size.x - float(n - 1) * PITCH) * 0.5)
		var cy := floorf(size.y * 0.5)
		for i in n - 1:
			var lit := _done[i] and _done[i + 1]
			draw_rect(Rect2(x0 + float(i) * PITCH + 6.0, cy, PITCH - 12.0, 1.0),
					GlassKit.EMBER if lit else GlassKit.ROD)
		for i in n:
			var c := Vector2(floorf(x0 + float(i) * PITCH), cy)
			if i > 0 and TitleGauge.ACT_STARTS.has(i):
				draw_rect(Rect2(c.x, cy - 6.0, 1.0, 13.0), GlassKit.ROD)
			if i == _current:
				GlassKit.diamond(self, c, 8.0, Color(GlassKit.EMBER.r, GlassKit.EMBER.g, GlassKit.EMBER.b, 0.3))
			if _done[i]:
				GlassKit.diamond(self, c, 5.0, GlassKit.EMBER)
				GlassKit.diamond(self, c, 2.0, GlassKit.EMBER_HOT)
			else:
				GlassKit.diamond(self, c, 4.0, GlassKit.COLD_EDGE)
				GlassKit.diamond(self, c, 2.0, GlassKit.COLD)
