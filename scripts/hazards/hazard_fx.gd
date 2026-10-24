class_name HazardFx
extends RefCounted
## 关卡机关共用的表现小工具：音效键解析（新键没做出来时退回老键）、首遇提示区、
## 一小段整数像素绘制助手。纯表现，不碰物理与存档。

## 每个机关皮肤在每个时刻的候选音效键，按顺序取第一个在 Sfx.LIBRARY 里存在的。
## 新做的专用音效（tools/gen_audio_sfx.py）只要加进 LIBRARY，这里自动改用，不必改机关代码。
const SFX := {
	"steam": {
		"warn": [&"hazard_steam_warn", &"gear_creak"],
		"fire": [&"hazard_steam", &"splash"],
	},
	"flame": {
		"warn": [&"hazard_flame_warn", &"nest_light"],
		"fire": [&"hazard_flame", &"skull_flame"],
	},
	"slag": {
		"warn": [&"hazard_slag_warn", &"drip"],
		"fire": [&"hazard_slag", &"splash"],
	},
	"bell": {
		"warn": [&"hazard_bell_warn", &"gear_creak"],
		"fire": [&"hazard_bell", &"bell_toll"],
	},
	"shock": {
		"warn": [&"hazard_shock_warn", &"forge_pulse"],
		"fire": [&"hazard_shock", &"forge_pulse"],
	},
	"collapse": {
		"warn": [&"hazard_collapse_warn", &"gear_creak"],
		"fire": [&"hazard_collapse", &"land_heavy"],
	},
	"pendulum": {
		"warn": [],
		"fire": [&"hazard_pendulum", &"swing_heavy"],
	},
}


## 解析出实际可用的音效键；都没有时返回空。
static func resolve(skin: String, moment: String) -> StringName:
	var moments: Dictionary = SFX.get(skin, {})
	var options: Array = moments.get(moment, [])
	for key in options:
		if Sfx.LIBRARY.has(key):
			return key
	return &""


static func play(skin: String, moment: String, pos: Vector2, volume_db: float = -6.0) -> void:
	var key := resolve(skin, moment)
	if key == &"":
		return
	Sfx.play_at(key, pos, 0.06, volume_db)


## 在机关周围放一块首遇提示区（走进去触发，每个存档一次，文案取 HintService.CATALOG）。
## `local_rect` 是机关本地坐标里要覆盖的区域，`grow` 往外各扩多少，让玩家在到达之前就读到。
static func attach_hint(owner: Node2D, hint_id: StringName, local_rect: Rect2,
		grow: Vector2 = Vector2(112.0, 40.0)) -> HintArea:
	if owner == null or hint_id == &"":
		return null
	var existing := owner.get_node_or_null("HazardHint") as HintArea
	if existing != null:
		return existing
	var area := HintArea.new()
	area.name = "HazardHint"
	area.hint_id = hint_id
	var rect := local_rect.grow_individual(grow.x, grow.y, grow.x, grow.y)
	area.size = rect.size
	area.position = rect.get_center()
	owner.add_child(area)
	return area


## 1px 整数像素矩形（所有机关绘制都走它，边缘不发虚）。
static func px_rect(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	var pos := Vector2(roundf(rect.position.x), roundf(rect.position.y))
	var end := Vector2(roundf(rect.end.x), roundf(rect.end.y))
	var size := Vector2(maxf(1.0, end.x - pos.x), maxf(1.0, end.y - pos.y))
	canvas.draw_rect(Rect2(pos, size), color)


## 把方向吸附到四个正方向（机关的朝向只允许 90° 的倍数，像素不会被旋转糊掉）。
static func cardinal(dir: Vector2) -> Vector2:
	if dir == Vector2.ZERO:
		return Vector2.UP
	if absf(dir.x) > absf(dir.y):
		return Vector2.RIGHT if dir.x > 0.0 else Vector2.LEFT
	return Vector2.DOWN if dir.y > 0.0 else Vector2.UP


## 「向上」坐标系转到朝向 `dir` 需要旋转的弧度（只会是 0 / ±90° / 180°）。
static func rotation_for(dir: Vector2) -> float:
	return cardinal(dir).angle() + PI * 0.5
