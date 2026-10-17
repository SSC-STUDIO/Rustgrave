class_name ForgeHeart
extends Interactable
## 锻炉残芯：熄灭写入 ending 并回标题。复燃不写结局，只答应往下走。

const TITLE_PATH := "res://scenes/ui/TitleScreen.tscn"
const ID_REKINDLE := &"rekindle"
const ID_SNUFF := &"snuff"

var unlocked: bool = false
var _choosing := false
var _layer: CanvasLayer
var _menu: MenuList
var _glow: WorldLight


func _ready() -> void:
	super._ready()
	prompt = "E 触碰炉心"
	ensure_sprite("res://assets/env/bg_altar_cut.png", Vector2(36, 40), Vector2(-10, -8), Palette.EMBER)
	_ensure_light()
	if SaveData.has_flag("boss_dead"):
		unlock()
	else:
		lock()


func can_interact(_actor: Node) -> bool:
	return unlocked


func lock() -> void:
	unlocked = false
	visible = false
	monitoring = false
	monitorable = false
	_ensure_light()
	if _glow != null:
		_glow.lit = false
		_glow.apply(true)


func unlock() -> void:
	unlocked = true
	visible = true
	monitoring = true
	monitorable = true
	_ensure_light()
	if _glow != null:
		_glow.lit = true
		_glow.apply(true)


func _ensure_light() -> void:
	if _glow != null:
		return
	var light := WorldLight.new()
	light.name = "HeartLight"
	light.follow = &"heart"
	light.color = Color(1.0, 0.48, 0.26)
	light.position = Vector2(8, -10)
	# Clock radius is 80; keep a coal so WarmPool + heart do not ADD-clip the remnant.
	light.radius_cap = 44.0
	add_child(light)
	_glow = light


func interact(actor: Node) -> void:
	if _choosing or not actor is Player or not can_interact(actor):
		return
	_choosing = true
	_open_choice()


func _open_choice() -> void:
	Director.choice_hold = true
	Director.suspend()
	_layer = CanvasLayer.new()
	_layer.layer = 25
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	# 菜单必须住在根视口的 UI 宿主（和 HUD / 暂停菜单一层）。挂在炉心自己底下就是
	# 挂进 640×360 的世界子视口，而 GamePresentation 在 choice_hold + 暂停时不再向
	# 子视口转发输入——结局菜单会打开却永远按不动。
	GameContext.ui_host(self).add_child(_layer)
	var root := Control.new()
	root.name = "ChoiceRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(root)
	root.add_child(UiKit.scrim(0.72, 0.72, 0.72))
	var frame := UiKit.panel(&"OrnatePanel")
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
	frame.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(frame)
	var column := VBoxContainer.new()
	frame.add_child(column)
	column.add_child(UiKit.label("炉 心 还 在 跳", &"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiKit.divider())
	column.add_child(UiKit.label("复燃会唤醒整座陵墓。熄灭，连你一并散掉。",
			&"DimLabel", HORIZONTAL_ALIGNMENT_CENTER))
	_menu = MenuList.new()
	_menu.add_theme_constant_override("separation", 12)
	column.add_child(_menu)
	# 复燃是默认项（燕尾板），熄灭是不可逆的第三层（只剩四只角标）。
	_menu.compact(_menu.add_item(ID_REKINDLE, "复 燃", false, MenuItem.Kind.SECONDARY))
	_menu.compact(_menu.add_item(ID_SNUFF, "熄 灭", false, MenuItem.Kind.GHOST))
	_menu.chosen.connect(_on_chosen)
	get_tree().paused = true


func _on_chosen(id: StringName) -> void:
	Director.choice_hold = false
	Director.resume()
	get_tree().paused = false
	if _layer:
		_layer.queue_free()
		_layer = null
	var kind := "rekindle" if id == ID_REKINDLE else "snuff"
	if kind == "snuff":
		SaveData.ending = kind
	GameEvents.ending_chosen.emit(id)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		SaveData.save_game(GameContext.world_scene_path(player), player)
	if kind == "rekindle":
		# 复燃不是结局：答应把剑里的人带到炉心再问一次。不写入 ending。
		Director.play([
			{"kind": "lock"},
			{"kind": "fx", "id": "heart_pulse", "seconds": 0.5},
			{"kind": "fx", "id": "ember_rise", "seconds": 0.8},
			{"kind": "caption", "text": "不是拯救。", "hold": 1.4},
			{"kind": "caption", "text": "把剑里的人带到炉心，再问一次。", "hold": 2.2},
			{"kind": "wait", "seconds": 0.2},
			{"kind": "unlock"},
		])
		await Director.finished
		if player is Player:
			LevelExit.travel(GameContext.LEVEL02_PATH, Level02Undercroft.ENTRY_SPAWN, player as Player)
		else:
			Director.fade_to(GameContext.LEVEL02_PATH)
		return
	Director.play([
		{"kind": "lock"},
		{"kind": "fx", "id": "heart_pulse", "seconds": 0.5},
		{"kind": "fx", "id": "ash_fall", "seconds": 0.9},
		{"kind": "caption", "text": "余烬落回炉灰。骑士也是。", "hold": 2.2},
		{"kind": "wait", "seconds": 0.2},
		{"kind": "unlock"},
	])
	await Director.finished
	Director.fade_to(TITLE_PATH)
