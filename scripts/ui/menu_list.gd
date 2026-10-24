class_name MenuList
extends VBoxContainer
## 一列 MenuItem 的键鼠导航容器：上下键跳过禁用项并回环，回车/点击确认，
## 鼠标悬停同步选中。暂停菜单 / 结局选择 / 覆盖确认用默认行（主题样式盒），
## 标题屏的菜单架用 kind 指定三档异形板（见 MenuItem.Kind）。
##
## 导航只看 add_item 进来的项：标题屏在项之间插的空白、铆钉横线是普通子节点，
## 不参与上下键的顺序。
##
## `active` 为 false 时不吃输入 —— 打开操作说明这类子面板时由上层置 false。

signal chosen(id: StringName)
## 选中项变了（键盘、悬停、代码都算）：标题屏用它放火花、推一下场景。
signal focus_changed(id: StringName)

var active := true
## 新加进来的项用铁条版式（标题屏；之后的 add_item 才生效）。
var strip_style := false

var _items: Array[MenuItem] = []
var _ids: Array[StringName] = []
var _index := -1


func add_item(id: StringName, text: String, item_disabled: bool = false,
		kind: MenuItem.Kind = MenuItem.Kind.DEFAULT,
		compact: bool = false) -> MenuItem:
	var item := MenuItem.new(text, kind)
	item.id = id
	item.compact = compact
	item.strip = strip_style
	add_child(item)
	item.disabled = item_disabled
	item.activated.connect(func() -> void: _activate_index(_items.find(item)))
	item.hover_requested.connect(func() -> void: _hover_index(_items.find(item)))
	_items.append(item)
	_ids.append(id)
	if _index < 0 and not item_disabled:
		select(_items.size() - 1, false)
	return item


## 对话框用：关掉铁架的挂钉；第三层（GHOST）比上面窄，居中放才不歪。
func compact(item: MenuItem) -> MenuItem:
	item.show_tick = false
	if item.kind == MenuItem.Kind.GHOST:
		item.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return item


func selected_id() -> StringName:
	return _ids[_index] if _index >= 0 else &""


## 当前挂着的菜单项 id 顺序副本：上层重建菜单后按 id 找回原来的选中位置
## （更新提示到来时重建菜单架、不能把玩家的光标弹回第一格）。
## 兼容旧调用：返回所有 MenuItem 子节点（标题/章节测试按这个口径读）。
func items() -> Array:
	var out: Array = []
	for child in get_children():
		if child is MenuItem:
			out.append(child)
	return out


func item_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(_ids)
	return out


func select(index: int, play_sound: bool = true) -> void:
	if index < 0 or index >= _items.size() or index == _index:
		return
	if _index >= 0:
		_items[_index].selected = false
	_index = index
	_items[_index].selected = true
	if play_sound:
		Sfx.play(&"ui_move")
	focus_changed.emit(_ids[_index])


## 从 _index 出发按 step 找下一个可用项（回环），全禁用时原地不动。
func _step(step: int) -> void:
	if _items.is_empty():
		return
	var n := _items.size()
	for i in range(1, n + 1):
		var candidate := (_index + step * i + n * n) % n
		if not _items[candidate].disabled:
			select(candidate)
			return


func _hover_index(index: int) -> void:
	if active and index >= 0 and not _items[index].disabled:
		select(index)


func _activate_index(index: int) -> void:
	if not active or index < 0:
		return
	if _items[index].disabled:
		Sfx.play(&"ui_denied")
		return
	select(index, false)
	Sfx.play(&"ui_select")
	chosen.emit(_ids[index])


func _unhandled_input(event: InputEvent) -> void:
	if not active or not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_down"):
		_step(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_step(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_activate_index(_index)
		get_viewport().set_input_as_handled()
