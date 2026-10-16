class_name ControlsPanel
extends CanvasLayer
## 操作说明面板：华丽边框 + 键位表。标题屏与暂停菜单共用，
## 也是原先挤在 HUD 右上角那行操作提示的新家。
##
## 之所以是 CanvasLayer 而不是 Control：这个面板生成时就是隐藏的，而隐藏的
## Control 不会被排版（子节点的锚点算在 0x0 的父矩形上，面板会缩在左上角）。
## CanvasLayer 下的 Control 以视口为父矩形，隐藏期间也能正确排版。
## 调用方负责设置 layer（要盖在自己那层之上）。

signal closed

## 键位表：与 project.godot 的 InputMap 手工对齐（改按键记得同步这里）。
const ROWS: Array[Array] = [
	["A / D  ←/→", "移动（沉重惯性）"],
	["空格", "跳跃 · 落地后可再跳一次"],
	["Shift", "冲刺 · 带无敌帧"],
	["J / 鼠标左键", "挥砍 · 判定帧碰到敌弹即弹反"],
	["K / 鼠标右键", "同为挥砍 · 判定末段或收刀时再按可接三连"],
	["E", "交互 · 废料堆 / 插座台 / 净化祠"],
	["1 / 2", "把锈核插入剑的 1 / 2 号插座"],
	["F", "钩锁 · 需先镶嵌钩锁核"],
	["Esc", "暂停 / 返回"],
]

var _root: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	PresentationMetrics.bind_layer(self)


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	# 遮罩会吃掉鼠标事件，所以点击关闭必须走 gui_input —— 被 GUI 消化的事件
	# 不会再进 _unhandled_input。
	_root.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			close())
	add_child(_root)

	_root.add_child(UiKit.scrim(0.86, 0.86, 0.86))

	var frame := UiKit.panel(&"OrnatePanel")
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 140.0
	frame.offset_right = -140.0
	frame.offset_top = 40.0
	frame.offset_bottom = -40.0
	_root.add_child(frame)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(column)

	column.add_child(UiKit.label("操 作 说 明", &"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiKit.divider())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(grid)
	for row in ROWS:
		var key := UiKit.label(String(row[0]), &"KeyCapLabel", HORIZONTAL_ALIGNMENT_RIGHT)
		key.custom_minimum_size = Vector2(190.0, 0.0)
		grid.add_child(key)
		grid.add_child(UiKit.label(String(row[1]), &"BodyLabel"))

	column.add_child(UiKit.divider())
	column.add_child(UiKit.label("弹反不是单独的格挡键 —— 巨剑的判定帧打中弹丸就会把它打回去",
			&"FootnoteLabel", HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiKit.label("Esc / 回车  返回", &"SubHeadLabel", HORIZONTAL_ALIGNMENT_CENTER))


func open() -> void:
	visible = true
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_select")


func close() -> void:
	if not visible:
		return
	visible = false
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_back")
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		close()
		get_viewport().set_input_as_handled()
