extends Control
## 角色/武器小牌（HUD 可选挂点，自包含）。
##
## 契约 §3.2：HUD 显示「当前角色 · 当前武器」一行；roster 不存在时隐藏控件。
## 本件不持有任何数据、不改 HUD：HUD 只需
##   const LOADOUT_CHIP := preload("res://scripts/ui/loadout_chip.gd")
##   var chip := LOADOUT_CHIP.new()
##   chip.name = "LoadoutChip"
##   add_child(chip)
##   chip.bind_player(player)
## 并在角色选择/拾取武器后调 chip.refresh()（或由 HUD 每帧/每 0.5s 调一次）。
## 无数据时 visible=false，布局上不占位。
##
## 外观与标题屏的数据片（TitleChip）是同一套语汇：阶梯切角、左缘色条、深底锈边，尺寸同为 26px 高。
## selected（默认 true）时边与色条烧成余烬色、文字亮起；false 时全部压暗成冷铁。

const TitleChipScript := preload("res://scripts/ui/title_chip.gd")
## 色条之后的文字起点（色条 3px + 9px 留白）与右侧留白。
const TEXT_INSET := 12.0
const TEXT_RIGHT := 10.0

var selected := true:
	set(value):
		selected = value
		_apply_tint()
		queue_redraw()

var _label: Label
var _player: Node


func _ready() -> void:
	name = "LoadoutChip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, TitleChipScript.CHIP_SIZE.y)
	_label = UiKit.label("", &"TinyStrongLabel")
	_label.name = "Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.position = Vector2(TEXT_INSET, 0.0)
	_label.size = Vector2(0.0, TitleChipScript.CHIP_SIZE.y)
	add_child(_label)
	_apply_tint()
	refresh()


## 绑定（或换绑）玩家：负责装备武器名。角色名来自 SaveData/LoadoutBridge。
func bind_player(player: Node) -> void:
	_player = player
	refresh()


## 重新读一次 LoadoutBridge；无数据时整件隐藏（HUD 不用自己判断 roster）。
func refresh() -> void:
	if _label == null:
		return
	var line := LoadoutBridge.loadout_line(_player)
	_label.text = line
	_label.visible = line != ""
	visible = line != ""
	if line != "":
		var font := _label.get_theme_font(&"font")
		var font_size := _label.get_theme_font_size(&"font_size")
		var text_w := 0.0
		if font != null:
			text_w = ceilf(font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		# 宽度取偶数像素（2px 栅格），文字区与芯片同高。
		var w := ceilf((TEXT_INSET + text_w + TEXT_RIGHT) / 2.0) * 2.0
		_label.size = Vector2(text_w + 2.0, TitleChipScript.CHIP_SIZE.y)
		custom_minimum_size = Vector2(w, TitleChipScript.CHIP_SIZE.y)
		size = custom_minimum_size
	queue_redraw()


## 测试/挂点用：当前是否真的显示了一行信息。
func is_showing() -> bool:
	return visible and _label != null and _label.text != ""


func current_line() -> String:
	return _label.text if _label != null else ""


func _apply_tint() -> void:
	if _label == null:
		return
	_label.modulate = Color.WHITE if selected else Color(1.0, 1.0, 1.0, 0.6)


func _draw() -> void:
	if not visible or size.x < 1.0:
		return
	var w := size.x
	var h := size.y
	var edge: Color = TitleChipScript.EDGE_LIT if selected else TitleChipScript.EDGE
	var stripe: Color = TitleChipScript.STRIPE_LIT if selected else TitleChipScript.STRIPE
	# 阶梯切角（2px 栅格）：与数据片、铁条用同一种边角语汇。
	draw_rect(Rect2(2.0, 0.0, w - 4.0, h), TitleChipScript.FILL)
	draw_rect(Rect2(0.0, 2.0, w, h - 4.0), TitleChipScript.FILL)
	draw_rect(Rect2(2.0, 0.0, w - 4.0, 1.0), edge)
	draw_rect(Rect2(2.0, h - 1.0, w - 4.0, 1.0), edge)
	draw_rect(Rect2(0.0, 2.0, 1.0, h - 4.0), Color(edge.r, edge.g, edge.b, 0.55))
	draw_rect(Rect2(w - 1.0, 2.0, 1.0, h - 4.0), Color(edge.r, edge.g, edge.b, 0.55))
	# 顶光 / 底影：一点钢板厚度。
	draw_rect(Rect2(3.0, 1.0, w - 6.0, 1.0), Color(0.9, 0.7, 0.5, 0.06))
	draw_rect(Rect2(3.0, h - 2.0, w - 6.0, 1.0), Color(0.0, 0.0, 0.0, 0.22))
	# 左缘色条：选中烧成余烬，未选中是冷铁。
	draw_rect(Rect2(0.0, 2.0, 3.0, h - 4.0), stripe)
