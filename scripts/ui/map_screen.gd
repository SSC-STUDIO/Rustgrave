class_name MapScreen
extends CanvasLayer
## 暂停菜单里的"地图"：从正在运行的场景直接画出来，不依赖任何关卡数据文件。
##   · 平台：所有 SolidPlatform 的矩形，整幅关卡等比压进一条横带
##   · 余烬巢：已点燃（实心琥珀）/ 未点燃（空心灰）
##   · 出口门：已开 / 封锁；骑士：脉动的白色箭头
## 找不到任何平台（测试夹具、标题屏）时显示"地图暂不可用"，不画错的图。
## 地图只在打开时取一次快照（暂停时世界不动），所以不会逐帧遍历场景。

signal closed

const Modal := preload("res://scripts/ui/ui_modal.gd")

const VIEW_SIZE := Vector2(1000.0, 320.0)
const PAD := 40.0
const MIN_SCALE := 0.02

const COL_BACK := Color(0.03, 0.02, 0.05, 0.92)
const COL_FRAME := Color("#A0522D")
const COL_PLATFORM := Color("#7A4026")
const COL_PLATFORM_TOP := Color("#B8703E")
const COL_NEST_LIT := Color("#FFC14A")
const COL_NEST_DIM := Color("#8A8680")
const COL_EXIT := Color("#E4DCCC")
const COL_EXIT_LOCKED := Color("#6E5A50")
const COL_PLAYER := Color("#FFFFFF")

var _root: Control
var _shell: Dictionary = {}
var _closing := false  ## 退场动画进行中：防连按 Esc 起两条 tween
var _view: MapView
var _title: Label
var _empty: Label
var _snapshot: Dictionary = {}
## 章节名淡入补间（换关重开地图时先掐掉上一段）。
var _title_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()
	PresentationMetrics.bind_layer(self)


func _build() -> void:
	_shell = Modal.build(self, {
		"title": "地 图",
		"size": Vector2(1120.0, 640.0),
		"hint": "实心余烬 = 已点燃 · 空心 = 未点燃 · 白箭头是你",
		"back": "Esc / 回车 返回",
	})
	_root = _shell["root"] as Control
	_root.theme = UiKit.extras_theme()
	_root.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			close())

	var body := _shell["body"] as Control
	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)
	body.add_child(column)
	_title = UiKit.label("", &"SubHeadLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_title.name = "ChapterTitle"
	# 章节名是这页的主答案：染成余烬、居中压在铆钉横线上方，
	# 和图例的小字（灰白）拉开一级，不用逐行读就知道"这是哪一章"。
	_title.modulate = UiKit.EMBER
	column.add_child(_title)
	var rule := UiKit.divider()
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(rule)

	var holder := Control.new()
	holder.custom_minimum_size = VIEW_SIZE
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(holder)
	_view = MapView.new()
	_view.name = "View"
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_view)
	_empty = UiKit.label("地图暂不可用", &"DimLabel", HORIZONTAL_ALIGNMENT_CENTER)
	_empty.name = "Empty"
	_empty.set_anchors_preset(Control.PRESET_FULL_RECT)
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.visible = false
	holder.add_child(_empty)

	var legend := HBoxContainer.new()
	legend.name = "Legend"
	legend.alignment = BoxContainer.ALIGNMENT_CENTER
	legend.add_theme_constant_override("separation", 10)
	column.add_child(legend)
	_legend(legend, MapView.GLYPH_NEST_LIT, "已点燃的余烬巢")
	_legend(legend, MapView.GLYPH_NEST_DIM, "未点燃")
	_legend(legend, MapView.GLYPH_EXIT, "出口")
	_legend(legend, MapView.GLYPH_PLAYER, "你")


## 图例一项：符号与文字用同一个色相 —— 文字不再统一压成灰，
## 扫一眼图例就能把"哪个颜色是哪种东西"带到地图里去。
func _legend(row: HBoxContainer, kind: int, text: String) -> void:
	var glyph := MapView.Glyph.new(kind)
	row.add_child(glyph)
	var label := UiKit.label(text, &"HudLabel")
	label.modulate = MapView.GLYPH_COLORS.get(kind, Color.WHITE)
	row.add_child(label)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(14.0, 0.0)
	row.add_child(gap)


## 从当前世界取快照。player 为空 / 场景里没有平台时返回空字典。
static func collect(world: Node, player: Node2D) -> Dictionary:
	var platforms: Array[Rect2] = []
	var nests: Array[Dictionary] = []
	var exits: Array[Dictionary] = []
	if world != null:
		_gather(world, platforms, nests, exits)
	if platforms.is_empty():
		return {}
	return {
		"platforms": platforms,
		"nests": nests,
		"exits": exits,
		"player": player.global_position if player != null else Vector2.INF,
		"title": chapter_title(world),
	}


## 当前关的章节名。暂停菜单档案与地图共用这一份口径：
## 数据驱动章节读 layout.title()，旧章节读脚本常量，第一章读开场分镜的 CHAPTER。
## 任何一个来源都取不到时返回 ""（地图不显示空标题，档案显示破折号）。
static func chapter_title(world: Node) -> String:
	if world == null or not is_instance_valid(world):
		return ""
	var layout: Variant = world.get("layout")
	if layout != null and layout.has_method("title"):
		var from_property := String(layout.call("title"))
		if from_property != "":
			return from_property
	var node := world.get_node_or_null("Layout")
	if node != null and node.has_method("title"):
		var from_node := String(node.call("title"))
		if from_node != "":
			return from_node
	var script := world.get_script() as Script
	if script != null:
		var consts := script.get_script_constant_map()
		if consts.has("LEVEL_TITLE"):
			return String(consts["LEVEL_TITLE"])
		if consts.has("CHAPTER"):
			return String(consts["CHAPTER"])
	# 第一章的名字只在 ChapterTitles 里写一次。不要 preload opening_cinematic.gd：
	# HUD.tscn → PauseMenu → MapScreen 已经在 preload 链上，开场分镜又引 ChapterLevel
	# （它 preload HUD.tscn），这条链会让所有关卡拿到空 PackedScene。
	if script != null and script.resource_path.get_file() == "level01_static.gd":
		return String(ChapterTitles.LEVEL01)
	return ""


static func _gather(node: Node, platforms: Array[Rect2], nests: Array[Dictionary],
		exits: Array[Dictionary]) -> void:
	for child in node.get_children():
		if child is SolidPlatform:
			var plat := child as SolidPlatform
			platforms.append(Rect2(plat.global_position, plat.size))
			continue
		if child is EmberNest:
			nests.append({"pos": (child as Node2D).global_position,
					"lit": (child as EmberNest).is_lit()})
		elif child is LevelExit:
			exits.append({"pos": (child as Node2D).global_position,
					"locked": (child as LevelExit).is_locked()})
		elif child is Player or child is Camera2D:
			continue
		if child.get_child_count() > 0:
			_gather(child, platforms, nests, exits)


func snapshot() -> Dictionary:
	return _snapshot


func open() -> void:
	_closing = false
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var world := GameContext.world_root(player) if player != null else null
	_snapshot = collect(world, player)
	_view.setup(_snapshot)
	_view.running = true
	_view.visible = not _snapshot.is_empty()
	_empty.visible = _snapshot.is_empty()
	_title.text = String(_snapshot.get("title", ""))
	_fade_title()
	visible = true
	(_shell.get("play_intro") as Callable).call()
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_select")


## 章节名随开屏淡入：卡片是"啪"一下到位（见 ui_modal 的约定），但文字
## 慢 0.12s 亮起，读起来像标题先落、内容后显，而不是整块一起闪出来。
func _fade_title() -> void:
	if _title == null:
		return
	if _title_tween != null and _title_tween.is_valid():
		_title_tween.kill()
	_title.modulate = Color(UiKit.EMBER.r, UiKit.EMBER.g, UiKit.EMBER.b, 0.0)
	_title_tween = create_tween()
	_title_tween.tween_property(_title, "modulate:a", 1.0, 0.24) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	_view.running = false
	GameContext.suppress_gameplay_input()
	Sfx.play(&"ui_back")
	# 退场动画播完才隐藏：卡片沉回去、纱幕收掉，然后才 emit closed。
	(_shell.get("play_outro") as Callable).call(func() -> void:
		if not is_instance_valid(self):
			return
		_closing = false
		visible = false
		closed.emit()
	)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		close()
		get_viewport().set_input_as_handled()


## 把快照画成一条横带。纯绘制，数据在 setup() 里换成屏幕坐标。
class MapView extends Control:
	const GLYPH_NEST_LIT := 0
	const GLYPH_NEST_DIM := 1
	const GLYPH_EXIT := 2
	const GLYPH_PLAYER := 3

	## 图例与地图共用的符号色：图例文字、地图里的图标、暂停菜单档案的
	## 锈核/巢穴行都从这里取，玩家在三个屏之间不用重新学"哪个颜色是什么"。
	const GLYPH_COLORS := {
		GLYPH_NEST_LIT: COL_NEST_LIT,
		GLYPH_NEST_DIM: COL_NEST_DIM,
		GLYPH_EXIT: COL_EXIT,
		GLYPH_PLAYER: COL_PLAYER,
	}
	## 玩家箭头的描边色：压在已点燃的琥珀巢或暖白出口门上时，纯白箭头会
	## 溶进底色；一圈深墨描边让"你"在任何符号上都读得出来。
	const GLYPH_EDGE := Color("#2A1E32")

	## 地图打开时才逐帧重绘（脉动的玩家箭头）；关着的时候不白耗。
	var running := false
	var _snap: Dictionary = {}
	var _bounds := Rect2()
	var _scale := 1.0
	var _origin := Vector2.ZERO
	var _time := 0.0

	func setup(snap: Dictionary) -> void:
		_snap = snap
		_fit()
		queue_redraw()

	func _process(delta: float) -> void:
		if not running or _snap.is_empty():
			return
		_time += delta
		queue_redraw()

	## 世界 → 视图。边界取平台 + 所有标记，四周留 PAD。
	func _fit() -> void:
		if _snap.is_empty():
			return
		var box: Rect2 = (_snap["platforms"] as Array[Rect2])[0]
		for rect in _snap["platforms"]:
			box = box.merge(rect)
		for n in _snap["nests"]:
			box = box.expand(n["pos"])
		for e in _snap["exits"]:
			box = box.expand(e["pos"])
		var player_pos: Vector2 = _snap["player"]
		if player_pos != Vector2.INF:
			box = box.expand(player_pos)
		_bounds = box.grow(24.0)
		var avail := VIEW_SIZE - Vector2(PAD, PAD)
		_scale = maxf(MIN_SCALE, minf(avail.x / _bounds.size.x, avail.y / _bounds.size.y))
		_origin = (VIEW_SIZE - _bounds.size * _scale) * 0.5

	func to_view(world: Vector2) -> Vector2:
		return (_origin + (world - _bounds.position) * _scale).round()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), COL_BACK)
		draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), COL_FRAME, false, 2.0)
		if _snap.is_empty():
			return
		for rect in _snap["platforms"]:
			var a := to_view(rect.position)
			var size := Vector2(maxf(2.0, rect.size.x * _scale), maxf(2.0, rect.size.y * _scale)).round()
			draw_rect(Rect2(a, size), COL_PLATFORM)
			draw_rect(Rect2(a, Vector2(size.x, 2.0)), COL_PLATFORM_TOP)
		for e in _snap["exits"]:
			Glyph.paint(self, to_view(e["pos"]), GLYPH_EXIT if not e["locked"] else GLYPH_NEST_DIM, 1.0)
		for n in _snap["nests"]:
			Glyph.paint(self, to_view(n["pos"]), GLYPH_NEST_LIT if n["lit"] else GLYPH_NEST_DIM, 1.0)
		var player_pos: Vector2 = _snap["player"]
		if player_pos != Vector2.INF:
			var pulse := 0.7 + 0.3 * sin(TAU * _time / 1.2)
			Glyph.paint(self, to_view(player_pos), GLYPH_PLAYER, pulse)

	## 图例与地图共用的小图标：以 center 为中心，约 12x12 的像素块。
	class Glyph extends Control:
		var kind := 0

		func _init(p_kind: int = 0) -> void:
			kind = p_kind
			custom_minimum_size = Vector2(18.0, 18.0)
			mouse_filter = Control.MOUSE_FILTER_IGNORE

		func _draw() -> void:
			paint(self, size * 0.5, kind, 1.0)

		static func paint(canvas: CanvasItem, c: Vector2, p_kind: int, alpha: float) -> void:
			match p_kind:
				GLYPH_NEST_LIT:
					var pts := PackedVector2Array([c + Vector2(0, -7), c + Vector2(6, 0),
							c + Vector2(0, 7), c + Vector2(-6, 0)])
					canvas.draw_colored_polygon(pts, Color(COL_NEST_LIT, alpha))
					canvas.draw_polyline(pts + PackedVector2Array([pts[0]]), Color("#7A3A12"), 1.0)
				GLYPH_NEST_DIM:
					var pts2 := PackedVector2Array([c + Vector2(0, -6), c + Vector2(5, 0),
							c + Vector2(0, 6), c + Vector2(-5, 0)])
					canvas.draw_polyline(pts2 + PackedVector2Array([pts2[0]]), COL_NEST_DIM, 2.0)
				GLYPH_EXIT:
					canvas.draw_rect(Rect2(c + Vector2(-5, -8), Vector2(10, 16)), COL_EXIT)
					canvas.draw_rect(Rect2(c + Vector2(-5, -8), Vector2(10, 16)), Color("#2A1E32"), false, 1.0)
					canvas.draw_rect(Rect2(c + Vector2(-2, -3), Vector2(4, 11)), Color("#2A1E32"))
				GLYPH_PLAYER:
					var tri := PackedVector2Array([c + Vector2(0, -8), c + Vector2(6, 6), c + Vector2(-6, 6)])
					canvas.draw_colored_polygon(tri, Color(COL_PLAYER, alpha))
					canvas.draw_polyline(tri + PackedVector2Array([tri[0]]), Color("#2A1E32"), 1.0)
