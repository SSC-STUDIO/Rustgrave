extends Node
## Match HUD for the sim-driven 3D arena.
##
## The HUD never reads MobaSim directly. RenderSpike hands it one plain
## snapshot dictionary every frame, which keeps the display unit-testable with
## crafted values and keeps all formatting in one place:
##   {outcome, wave_index, next_wave_ms, blue{...}, red{...}, hero{...}}
## Node creation happens once in build(); apply() only moves rectangles and
## changes text, so no HUD node is ever created per frame.

const VIEW_MAP := preload("res://scripts/moba/present/moba_view_map.gd")

const TEXT_COLOR := Color("#f2e8da")
const MUTED_COLOR := Color("#c8c2b8")
const DEAD_COLOR := Color("#e8735a")
const BAR_BACK := Color(0.05, 0.03, 0.04, 0.92)
const BAR_BORDER := Color(0.02, 0.01, 0.015, 0.98)
const PLATE_COLOR := Color(0.06, 0.04, 0.05, 0.86)
const HERO_COLOR := Color("#ffc14a")
const BAR_HEIGHT := 16.0
const MIN_BAR_WIDTH := 200.0

## Bars are dictionaries: {holder, label, border, fill, ratio, text}.
var root: Control
var blue_crystal_bar: Dictionary = {}
var red_crystal_bar: Dictionary = {}
var hero_bar: Dictionary = {}
var enemy_bar: Dictionary = {}
var wave_label: Label
var respawn_label: Label
var result_panel: Control
var result_label: Label
var result_hint: Label

var _last_wave := ""
var _last_respawn := ""
var _result_text := ""


func build(overlay: CanvasLayer) -> void:
	root = Control.new()
	root.name = "MobHud"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(root)
	blue_crystal_bar = _make_bar("BlueCrystal", VIEW_MAP.team_name(VIEW_MAP.TEAM_BLUE),
			_hud_color(VIEW_MAP.TEAM_BLUE), HORIZONTAL_ALIGNMENT_LEFT, VIEW_MAP.TEAM_BLUE)
	red_crystal_bar = _make_bar("RedCrystal", VIEW_MAP.team_name(VIEW_MAP.TEAM_RED),
			_hud_color(VIEW_MAP.TEAM_RED), HORIZONTAL_ALIGNMENT_RIGHT, VIEW_MAP.TEAM_RED)
	hero_bar = _make_bar("HeroBar", "余烬骑士", HERO_COLOR, HORIZONTAL_ALIGNMENT_LEFT, -1)
	enemy_bar = _make_bar("EnemyHeroBar", "锈誓骑士", _hud_color(VIEW_MAP.TEAM_RED),
			HORIZONTAL_ALIGNMENT_RIGHT, VIEW_MAP.TEAM_RED)
	enemy_bar["holder"].visible = false
	wave_label = _make_label(14)
	wave_label.name = "WaveClock"
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wave_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(wave_label)
	respawn_label = _make_label(15)
	respawn_label.name = "Respawn"
	respawn_label.add_theme_color_override("font_color", DEAD_COLOR)
	respawn_label.visible = false
	root.add_child(respawn_label)
	_build_result()
	reset()


func _build_result() -> void:
	result_panel = Control.new()
	result_panel.name = "Result"
	result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_panel.visible = false
	root.add_child(result_panel)
	var border := ColorRect.new()
	border.name = "Border"
	border.color = BAR_BORDER
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_panel.add_child(border)
	var plate := ColorRect.new()
	plate.name = "Plate"
	plate.color = PLATE_COLOR
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_panel.add_child(plate)
	result_label = _make_label(30)
	result_label.name = "ResultText"
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_panel.add_child(result_label)
	result_hint = _make_label(14)
	result_hint.name = "ResultHint"
	result_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_hint.text = "R 重开 · Esc 返回"
	result_panel.add_child(result_hint)


## Places everything in the overlay's uniform units (the window is always
## `window.y` tall, so `width` is the current aspect-ratio dependent width).
func layout(width: float) -> void:
	if root == null:
		return
	root.size = Vector2(width, 720.0)
	var centre := width * 0.5
	var bar_width := clampf(width * 0.26, MIN_BAR_WIDTH, 400.0)
	var gap := 84.0
	_place_bar(blue_crystal_bar, Vector2(centre - gap - bar_width, 54.0), bar_width)
	_place_bar(red_crystal_bar, Vector2(centre + gap, 54.0), bar_width)
	wave_label.position = Vector2(centre - gap, 56.0)
	wave_label.size = Vector2(gap * 2.0, 44.0)
	var hero_width := clampf(width * 0.24, MIN_BAR_WIDTH, 320.0)
	_place_bar(hero_bar, Vector2(18.0, 566.0), hero_width)
	# Enemy hero bar tucks under the red crystal bar, right-aligned with it.
	var enemy_width := clampf(bar_width * 0.7, 170.0, 280.0)
	_place_bar(enemy_bar, Vector2(centre + gap + bar_width - enemy_width, 110.0), enemy_width)
	respawn_label.position = Vector2(18.0, 538.0)
	respawn_label.size = Vector2(hero_width + 160.0, 22.0)
	var result_width := minf(width - 96.0, 760.0)
	result_panel.position = Vector2(centre - result_width * 0.5, 286.0)
	result_panel.size = Vector2(result_width, 150.0)
	var plate: Control = result_panel.get_node("Plate")
	plate.position = Vector2(4.0, 4.0)
	plate.size = Vector2(result_width - 8.0, 142.0)
	var border: Control = result_panel.get_node("Border")
	border.position = Vector2.ZERO
	border.size = Vector2(result_width, 150.0)
	result_label.position = Vector2(0.0, 24.0)
	result_label.size = Vector2(result_width, 52.0)
	result_hint.position = Vector2(0.0, 92.0)
	result_hint.size = Vector2(result_width, 26.0)


## One snapshot of the match; see the class comment for the keys.
func apply(snapshot: Dictionary) -> void:
	if root == null:
		return
	_apply_crystal(blue_crystal_bar, snapshot.get("blue", {}))
	_apply_crystal(red_crystal_bar, snapshot.get("red", {}))
	var wave := wave_text(
			int(snapshot.get("wave_index", 0)),
			int(snapshot.get("next_wave_ms", 0)),
			bool(snapshot.get("wave_active", false)))
	if wave != _last_wave:
		_last_wave = wave
		wave_label.text = wave
	var hero: Dictionary = snapshot.get("hero", {})
	_apply_hero(hero)
	_apply_enemy(snapshot.get("enemy_hero", {}))
	var outcome := StringName(snapshot.get("outcome", &""))
	var banner := result_text(outcome)
	if banner != _result_text:
		_result_text = banner
		result_label.text = banner
	result_panel.visible = not banner.is_empty()


func reset() -> void:
	_last_wave = ""
	_last_respawn = ""
	_result_text = ""
	wave_label.text = "等待模拟核心"
	respawn_label.visible = false
	respawn_label.text = ""
	result_panel.visible = false
	result_label.text = ""
	_apply_crystal(blue_crystal_bar, {"crystal_hp": VIEW_MAP.CRYSTAL_HP, "crystal_max": VIEW_MAP.CRYSTAL_HP})
	_apply_crystal(red_crystal_bar, {"crystal_hp": VIEW_MAP.CRYSTAL_HP, "crystal_max": VIEW_MAP.CRYSTAL_HP})
	_apply_hero({"hp": VIEW_MAP.HERO_HP, "max_hp": VIEW_MAP.HERO_HP, "alive": true, "respawn_ms": 0})
	_apply_enemy({})


func hero_ratio() -> float:
	return _bar_ratio(hero_bar)


# ------------------------------------------------------------ pure helpers --

static func hp_ratio(current: float, maximum: float) -> float:
	return clampf(current / maxf(maximum, 1.0), 0.0, 1.0)


## Crystal health fractions, exposed for the tests and the render layer.
static func crystal_ratio(snapshot: Dictionary, team: int) -> float:
	var side: Dictionary = snapshot.get("blue", {}) if team == VIEW_MAP.TEAM_BLUE else snapshot.get("red", {})
	return hp_ratio(float(side.get("crystal_hp", 0.0)), float(side.get("crystal_max", VIEW_MAP.CRYSTAL_HP)))


static func crystal_text(side: Dictionary, team: int) -> String:
	return "%s水晶 %d / %d" % [
		VIEW_MAP.team_name(team),
		int(round(float(side.get("crystal_hp", 0.0)))),
		int(round(float(side.get("crystal_max", VIEW_MAP.CRYSTAL_HP)))),
	]


static func hero_text(hero: Dictionary) -> String:
	return "余烬骑士 %d / %d" % [
		int(round(float(hero.get("hp", 0.0)))),
		int(round(float(hero.get("max_hp", VIEW_MAP.HERO_HP)))),
	]


static func enemy_text(hero: Dictionary) -> String:
	return "锈誓骑士 %d / %d" % [
		int(round(float(hero.get("hp", 0.0)))),
		int(round(float(hero.get("max_hp", VIEW_MAP.HERO_HP)))),
	]


static func respawn_text(hero: Dictionary) -> String:
	var seconds := float(hero.get("respawn_ms", 0.0)) / 1000.0
	if seconds <= 0.01:
		return "余烬骑士阵亡 · 等待复活"
	return "余烬骑士阵亡 · %s 后复活" % clock_text(seconds * 1000.0)


static func wave_text(wave_index: int, next_wave_ms: int, wave_active: bool = false) -> String:
	if wave_active:
		return "第 %d 波 · 兵线交战中" % maxi(wave_index, 1)
	if wave_index <= 0:
		return "首波 %s" % clock_text(next_wave_ms)
	return "第 %d 波 · 下一波 %s" % [wave_index, clock_text(next_wave_ms)]


static func clock_text(ms: int) -> String:
	return "%.1fs" % maxf(float(ms) / 1000.0, 0.0)


## Original Rustgrave wording: 灰卫 is the blue side, 锈誓 the red side.
static func result_text(outcome: StringName) -> String:
	match String(outcome):
		"blue":
			return "%s攻破%s水晶" % [VIEW_MAP.team_name(VIEW_MAP.TEAM_BLUE), VIEW_MAP.team_name(VIEW_MAP.TEAM_RED)]
		"red":
			return "%s攻破%s水晶" % [VIEW_MAP.team_name(VIEW_MAP.TEAM_RED), VIEW_MAP.team_name(VIEW_MAP.TEAM_BLUE)]
	return ""


# ------------------------------------------------------------------ private --

func _apply_crystal(bar: Dictionary, side: Dictionary) -> void:
	if bar.is_empty():
		return
	var current := float(side.get("crystal_hp", VIEW_MAP.CRYSTAL_HP))
	var maximum := float(side.get("crystal_max", VIEW_MAP.CRYSTAL_HP))
	var team := int(bar.get("team", 0))
	_set_bar(bar, hp_ratio(current, maximum))
	var label := crystal_text(side, team)
	if bar.get("text", "") != label:
		bar["text"] = label
		(bar["label"] as Label).text = label


func _apply_hero(hero: Dictionary) -> void:
	if hero_bar.is_empty():
		return
	var alive := bool(hero.get("alive", true))
	_set_bar(hero_bar, hp_ratio(float(hero.get("hp", 0.0)), float(hero.get("max_hp", VIEW_MAP.HERO_HP))))
	var label := hero_text(hero)
	if hero_bar.get("text", "") != label:
		hero_bar["text"] = label
		(hero_bar["label"] as Label).text = label
	var respawn := "" if alive else respawn_text(hero)
	if respawn != _last_respawn:
		_last_respawn = respawn
		respawn_label.visible = not respawn.is_empty()
		respawn_label.text = respawn


## The red AI knight (multi-instance heroes): optional extra bar, only shown
## once the simulation publishes an enemy hero.
func _apply_enemy(enemy: Dictionary) -> void:
	if enemy_bar.is_empty():
		return
	var visible := bool(enemy.get("visible", false)) and not enemy.is_empty()
	(enemy_bar["holder"] as Control).visible = visible
	if not visible:
		return
	var hp := float(enemy.get("hp", 0.0))
	var max_hp := float(enemy.get("max_hp", VIEW_MAP.HERO_HP))
	_set_bar(enemy_bar, hp_ratio(hp, max_hp))
	var label := enemy_text({"hp": hp, "max_hp": max_hp})
	if enemy_bar.get("text", "") != label:
		enemy_bar["text"] = label
		(enemy_bar["label"] as Label).text = label


func _set_bar(bar: Dictionary, ratio: float) -> void:
	bar["ratio"] = ratio
	var fill: ColorRect = bar["fill"]
	var width := float(bar.get("width", MIN_BAR_WIDTH)) - 4.0
	fill.size = Vector2(maxf(width * ratio, 0.0), BAR_HEIGHT - 4.0)


func _bar_ratio(bar: Dictionary) -> float:
	return float(bar.get("ratio", 0.0))


func _make_bar(bar_name: String, title: String, color: Color, align: int, team: int) -> Dictionary:
	var holder := Control.new()
	holder.name = bar_name
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	var label := _make_label(12)
	label.name = "Title"
	label.horizontal_alignment = align
	label.text = title
	holder.add_child(label)
	var border := ColorRect.new()
	border.name = "Border"
	border.color = BAR_BORDER
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(border)
	var back := ColorRect.new()
	back.name = "Back"
	back.color = BAR_BACK
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(back)
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.color = color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(fill)
	return {
		"holder": holder, "label": label, "border": border, "back": back, "fill": fill,
		"ratio": 1.0, "text": "", "width": 0.0, "team": team,
	}


func _place_bar(bar: Dictionary, origin: Vector2, width: float) -> void:
	if bar.is_empty():
		return
	bar["width"] = width
	var holder: Control = bar["holder"]
	holder.position = origin
	holder.size = Vector2(width, BAR_HEIGHT + 18.0)
	(bar["label"] as Label).position = Vector2.ZERO
	(bar["label"] as Label).size = Vector2(width, 16.0)
	(bar["border"] as Control).position = Vector2(0.0, 17.0)
	(bar["border"] as Control).size = Vector2(width, BAR_HEIGHT)
	(bar["back"] as Control).position = Vector2(2.0, 19.0)
	(bar["back"] as Control).size = Vector2(width - 4.0, BAR_HEIGHT - 4.0)
	(bar["fill"] as Control).position = Vector2(2.0, 19.0)
	_set_bar(bar, float(bar.get("ratio", 1.0)))


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_color_override("font_outline_color", Color(0.04, 0.02, 0.03, 0.92))
	label.add_theme_constant_override("outline_size", 5)
	return label


static func _hud_color(team: int) -> Color:
	return Color("#4f7db8") if team == VIEW_MAP.TEAM_BLUE else Color("#b23a2e")
