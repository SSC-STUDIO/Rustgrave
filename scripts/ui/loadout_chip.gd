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

const FONT_SIZE := 10
const PAD := Vector2(6, 2)

var _label: Label
var _player: Node


func _ready() -> void:
	name = "LoadoutChip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, FONT_SIZE + PAD.y * 2.0)
	_label = Label.new()
	_label.name = "Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", Palette.PALE)
	_label.add_theme_color_override("font_outline_color", Palette.VOID)
	_label.add_theme_constant_override("outline_size", 1)
	_label.position = PAD
	add_child(_label)
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
		var font := _label.get_theme_font("font")
		if font != null:
			var width := font.get_string_size(
					line, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
			_label.size = Vector2(width + PAD.x * 2.0, FONT_SIZE + PAD.y * 2.0)
			custom_minimum_size = _label.size


## 测试/挂点用：当前是否真的显示了一行信息。
func is_showing() -> bool:
	return visible and _label != null and _label.text != ""


func current_line() -> String:
	return _label.text if _label != null else ""
