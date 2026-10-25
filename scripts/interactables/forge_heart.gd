class_name ForgeHeart
extends Interactable
## 锻炉炉座（第一章的终点）：熄火写入 ending 并播结局分镜后回标题；续火不写结局，
## 只是把火种续上、带它往下走。ID 保持 rekindle / snuff（存档、音乐和测试都认这两个）。

const TITLE_PATH := "res://scenes/ui/TitleScreen.tscn"
const ID_REKINDLE := &"rekindle"
const ID_SNUFF := &"snuff"
const CHOICE_TITLE := "炉 座 前"
const CHOICE_HINT := "续火：带它下去。熄火：名字没路走，你也散成铁。"

var unlocked: bool = false
var _choosing := false
var _layer: CanvasLayer
var _menu: MenuList
var _glow: WorldLight


func _ready() -> void:
	super._ready()
	prompt = "E 把火种放上炉座"
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
	# 回火试炼：炉心结局不属于试炼流程（会写战役结局/旗标），试炼里不触发。
	if TrialRun.active():
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
	column.add_child(UiKit.label(CHOICE_TITLE, &"HeadLabel", HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(UiKit.divider())
	column.add_child(UiKit.label(CHOICE_HINT, &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER))
	_menu = MenuList.new()
	_menu.add_theme_constant_override("separation", 12)
	column.add_child(_menu)
	# 续火是默认项（燕尾板），熄火是不可逆的第三层（只剩四只角标）。
	_menu.compact(_menu.add_item(ID_REKINDLE, "续 火", false, MenuItem.Kind.SECONDARY))
	_menu.compact(_menu.add_item(ID_SNUFF, "熄 火", false, MenuItem.Kind.GHOST))
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
		# 契约 §5：任一结局解锁回火试炼（战役写；试炼里 mark_flag 会被守卫 no-op）。
		SaveData.mark_flag("trial_unlocked")
	GameEvents.ending_chosen.emit(id)
	var player := get_tree().get_first_node_in_group("player")
	if player:
		SaveData.save_game(GameContext.world_scene_path(player), player)
	Director.play(choice_steps(kind))
	await Director.finished
	if kind == "snuff":
		# 结局分镜 / 滚动字幕的「看过」旗标是播完才点上的，上面那次存档里还没有；补写一次，
		# 故事页才回放得出这个结局（续火那条路由 LevelExit.travel 自己会存）。
		SaveData.persist_story(player if is_instance_valid(player) else null)
	if kind == "rekindle":
		if player is Player:
			LevelExit.travel(GameContext.LEVEL02_PATH, Level02Undercroft.ENTRY_SPAWN, player as Player)
		else:
			Director.fade_to(GameContext.LEVEL02_PATH)
		return
	Director.fade_to(TITLE_PATH)


## 选完后的 Director 步骤（纯构造，测试直接读）。
## 续火 = 一句两行字幕，不是结局；熄火 = 结局分镜 + 滚动字幕。
static func choice_steps(kind: String) -> Array:
	if kind == "rekindle":
		var steps: Array = [
			{"kind": "lock"},
			{"kind": "fx", "id": "heart_pulse", "seconds": 0.5},
			{"kind": "fx", "id": "ember_rise", "seconds": 0.8},
		]
		for line in ChapterText.exit_captions_of("level01"):
			steps.append({"kind": "caption", "text": String(line), "hold": 2.0})
		steps.append({"kind": "wait", "seconds": 0.2})
		steps.append({"kind": "unlock"})
		return steps
	return LevelExit.ending_play_steps(ChapterText.ending_lines_of("snuff"), "ash_fall", "snuff")
