extends CanvasLayer
## Read-only campaign summary and one-Boss practice entry.
signal closed
const Modal := preload("res://scripts/ui/ui_modal.gd")
const Catalog := preload("res://scripts/data/trial_catalog.gd")
const Records := preload("res://scripts/data/trial_records.gd")
var _shell: Dictionary
var _summary: Label
var _chapters: Label
var _records: Label
var _bosses: OptionButton
var _practice: Button
var _available: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_shell = Modal.build(self, {"title": "回 看 余 烬", "size": Vector2(980, 650),
		"hint": "复战使用独立试炼记录 · 战役存档保留"})
	var root := _shell["root"] as Control
	root.theme = UiKit.extras_theme()
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	(_shell["body"] as Control).add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 16)
	scroll.add_child(box)
	_summary = _text(box, &"SubHeadLabel")
	_chapters = _text(box, &"BodyLabel")
	_records = _text(box, &"BodyLabel")
	box.add_child(UiKit.divider())
	_bosses = OptionButton.new()
	_bosses.custom_minimum_size.y = UiKit.TOUCH_MIN
	box.add_child(_bosses)
	_practice = Button.new()
	_practice.text = "复 战 所 选 Boss"
	_practice.custom_minimum_size.y = UiKit.TOUCH_MIN
	_practice.pressed.connect(start_selected_rematch)
	box.add_child(_practice)
	var back := Button.new()
	back.text = "返 回 标 题"
	back.custom_minimum_size.y = UiKit.TOUCH_MIN
	back.pressed.connect(close)
	box.add_child(back)
	PresentationMetrics.bind_layer(self)


func _text(box: VBoxContainer, variation: StringName) -> Label:
	var label := UiKit.label("", variation)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	return label


func open(refresh_from_disk: bool = true) -> void:
	if refresh_from_disk and SaveData.has_save():
		SaveData.load_game()
	_summary.text = ChapterText.ending_summary_of(SaveData.ending)
	if _summary.text == "":
		_summary.text = "这段旅程的余温仍在。"
	var done := Catalog.cleared_chapters()
	var names := PackedStringArray()
	for row in done:
		names.append(String(row["title"]))
	_chapters.text = "章节  %d / %d\n%s" % [done.size(), GameContext.LEVEL_ORDER.size(), " · ".join(names)]
	var total_runs := 0
	var bests := PackedStringArray()
	for track in Catalog.TRACKS:
		var per_track := Records.for_track(track)
		for id in per_track:
			var record: Dictionary = per_track[id]
			total_runs += int(record.get("runs", 0))
			bests.append("%s %s · %s" % [Catalog.track_name(track), String(record.get("rank", "")), Records.format_ms(int(record.get("ms", 0)))])
	var arena := ArenaRun.read_records()
	_records.text = "试炼  %d 次 · %s\n竞技场  %d 次 · 最高分 %d · 最多击杀 %d" % [total_runs,
		" / ".join(bests) if not bests.is_empty() else "暂无记录", int(arena.get("runs", 0)),
		int(arena.get("best_score", 0)), int(arena.get("best_kills", 0))]
	_available = Catalog.available_bosses()
	_bosses.clear()
	for row in _available:
		_bosses.add_item(String(row["title"]))
	_practice.disabled = _available.is_empty() or not Catalog.unlocked()
	if _available.is_empty():
		_bosses.add_item("尚无已击败的 Boss")
	visible = true
	(_shell["play_intro"] as Callable).call()
	_bosses.grab_focus()


func start_selected_rematch() -> bool:
	if _available.is_empty() or _bosses.selected < 0:
		return false
	var started := TrialRun.start(Catalog.Track.BOSS_RUSH, String(_available[_bosses.selected]["kind"]))
	if started:
		visible = false
	return started


func summary_text() -> String:
	return _summary.text + "\n" + _chapters.text + "\n" + _records.text


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
