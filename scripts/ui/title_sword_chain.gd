extends "res://scripts/ui/title_prop.gd"
## 送剑链：屋架下的一条传送链，挂着刻了名字的巨剑，缓缓送向炉口——把「炉约」画出来：
## 人死了，名字刻上剑，剑被一把一把送进炉里烧。
##
## 路线：从左侧沿导轨水平走到炉口上方（RAIL_Y），再顺着竖链垂下去，剑尖朝下，
## 一直垂到被右侧炉房的外墙挡住——就是「送进去了」。每把剑进炉时发 delivered
## （TitleWorld 在那里迸一簇火星、让炉光闪一下）。
##
## 三种模式（TitleWorld.prop_plan 按存档变体给）：
##   RUN    正常运转：三把剑等距挂在链上，速度随炉温（冷炉几乎不动）
##   EMPTY  还火结局：链还挂在那儿，剑一把不剩，也不再动（魂光升起来了，不需要再送）
##   STILL  熄火结局：剑还挂着，链停了，刻字是冷的
## 节点：本体（导轨 / 链 / 剑）+ Glow（刻字的微光、进炉处的光团）= 2 个。

signal delivered(at: Vector2)

const MODE_RUN := 0
const MODE_EMPTY := 1
const MODE_STILL := 2

const RAIL_Y := 66.0
const X_START := 200.0
## 竖链所在的 x：在右侧屋架立柱（x≈473–488）的左边，剑垂下来不会被立柱吞掉。
const X_END := 462.0
## 竖链垂到这里：炉房外墙顶（y≈170）以下就被墙挡住了。
const DROP_END := 176.0
const SWORD_COUNT := 3
## 剑从导轨左端挂上链时，前 14 像素路程里淡入。
const FADE_IN := 14.0
## 链速（像素/秒，炉温 1.0）：缓缓地，一把剑走完全程要一分钟出头。
const SPEED := 6.0
const HANG := 52.0
const STEEL := Color("#8A8F9A")
const STEEL_LIGHT := Color("#B9BEC8")
const STEEL_DARK := Color("#555B68")
const NAME_MARK := Color(1.0, 0.72, 0.30)

var _mode := MODE_RUN
## 链的滚动量（像素）：所有剑与链节一起前进。
var _roll := 0.0
var _deliveries := 0
var _flash := 0.0
## 每把剑上一帧所在的路程，用来判断「刚刚过了进炉线」。
var _prev := PackedFloat32Array()
## 烘焙的剑身（tools/gen_title_props.py）；缺图时退回平涂几何。
var _blade_tex: Texture2D


func _setup() -> void:
	_blade_tex = load("res://assets/title/sword_blade.png") as Texture2D
	_prev.resize(SWORD_COUNT)
	for i in SWORD_COUNT:
		_prev[i] = sword_s(i)


func set_mode(new_mode: int) -> void:
	_mode = new_mode


func mode() -> int:
	return _mode


func speed() -> float:
	if _mode != MODE_RUN or heat < 0.06:
		return 0.0
	return SPEED * clampf(heat, 0.2, 1.3)


## 一圈的长度：水平段 + 竖直段。
static func path_length() -> float:
	return (X_END - X_START) + (DROP_END - RAIL_Y)


## 路程 s（0 = 导轨左端）→ 吊点的位置。
static func point_at(s: float) -> Vector2:
	var horizontal := X_END - X_START
	if s <= horizontal:
		return Vector2(X_START + s, RAIL_Y)
	return Vector2(X_END, RAIL_Y + (s - horizontal))


## 第 i 把剑现在的路程。
func sword_s(i: int) -> float:
	var length := path_length()
	return fposmod(_roll + float(i) * length / float(SWORD_COUNT), length)


func _step(dt: float) -> void:
	_flash = move_toward(_flash, 0.0, dt * 1.6)
	var v := speed()
	if v <= 0.0:
		return
	_roll += v * dt
	var gate := path_length() - 6.0
	for i in SWORD_COUNT:
		var s := sword_s(i)
		# s 从大值绕回小值 = 这把剑刚刚被「收走」；进炉线是 gate：上一帧在线前、这一帧在线后。
		if _prev[i] < gate and s >= gate:
			_deliveries += 1
			_flash = 1.0
			delivered.emit(Vector2(X_END, DROP_END - 8.0))
		_prev[i] = s


func _draw() -> void:
	var horizontal := X_END - X_START
	# 导轨与竖导槽
	draw_rect(Rect2(X_START - 22.0, RAIL_Y - 4.0, horizontal + 30.0, 3.0), IRON_DARK)
	draw_rect(Rect2(X_START - 22.0, RAIL_Y - 4.0, horizontal + 30.0, 1.0), IRON)
	draw_rect(Rect2(X_END - 1.0, RAIL_Y - 4.0, 3.0, DROP_END - RAIL_Y + 4.0), IRON_DARK)
	# 滑轮
	draw_rect(Rect2(X_END - 4.0, RAIL_Y - 7.0, 9.0, 9.0), OUTLINE)
	draw_rect(Rect2(X_END - 3.0, RAIL_Y - 6.0, 7.0, 7.0), IRON)
	draw_rect(Rect2(X_END - 1.0, RAIL_Y - 4.0, 3.0, 3.0), IRON_LIGHT)
	# 链节：随 _roll 前进，走到哪儿画到哪儿（水平段 + 竖直段）
	var offset := fposmod(_roll, 6.0)
	var s := -offset
	var length := path_length()
	var k := 0
	while s < length:
		if s >= 0.0:
			var at := point_at(s)
			var flat := s <= horizontal
			if k % 2 == 0:
				draw_rect(Rect2(at.x - (1.0 if flat else 0.0), at.y - (0.0 if flat else 1.0),
						3.0 if flat else 2.0, 2.0 if flat else 3.0), IRON_LIGHT)
			else:
				draw_rect(Rect2(at.x - (0.0 if flat else 1.0), at.y - (1.0 if flat else 0.0),
						2.0 if flat else 3.0, 3.0 if flat else 2.0), IRON)
		s += 3.0
		k += 1
	# 剑（EMPTY 模式一把不画，只留空着的吊钩）
	for i in SWORD_COUNT:
		var hook := point_at(sword_s(i))
		hook = Vector2(roundf(hook.x), roundf(hook.y))
		if _mode == MODE_EMPTY:
			draw_rect(Rect2(hook.x - 1.0, hook.y, 2.0, 6.0), IRON_LIGHT)
			draw_rect(Rect2(hook.x - 2.0, hook.y + 5.0, 4.0, 2.0), IRON_LIGHT)
			continue
		# 从导轨左端「挂上链」时淡入，不是凭空冒出来
		_draw_sword(hook, clampf(sword_s(i) / FADE_IN, 0.0, 1.0))


## 一把剑：吊环 → 柄 → 护手 → 刻着名字的剑身 → 剑尖（朝下）。
func _draw_sword(hook: Vector2, alpha: float) -> void:
	var x := hook.x
	var y := hook.y
	var warm := _mode == MODE_RUN and heat > 0.06
	# 静态几何（吊环 / 柄 / 护手 / 剑身 / 剑尖）是烘焙贴图（tools/gen_title_props.py），
	# 挂点在贴图的 (8, 0)；刻痕随炉温变色，仍在运行时画。淡入靠 modulate 的 alpha。
	if _blade_tex != null:
		draw_texture(_blade_tex, Vector2(x - 8.0, y), Color(1.0, 1.0, 1.0, alpha))
	else:
		_draw_sword_flat(x, y, alpha)
	# 刻着的名字：剑身中线上的几处短刻痕，炉子烧着时发暖橙
	for m in 4:
		var mark := Rect2(x - 1.0, y + 24.0 + 7.0 * float(m), 2.0, 3.0)
		draw_rect(mark, _fade(em(NAME_MARK) if warm else STEEL_DARK, alpha))


## 贴图缺失时的兜底：原来的平涂几何，保证素材丢失时剑仍然可见。
func _draw_sword_flat(x: float, y: float, alpha: float) -> void:
	draw_rect(Rect2(x - 1.0, y, 2.0, 5.0), _fade(IRON_LIGHT, alpha))
	draw_rect(Rect2(x - 5.0, y + 6.0, 10.0, HANG - 6.0), _fade(OUTLINE, alpha))
	draw_rect(Rect2(x - 2.0, y + 5.0, 4.0, 3.0), _fade(IRON_LIGHT, alpha))
	draw_rect(Rect2(x - 1.0, y + 8.0, 2.0, 8.0), _fade(IRON, alpha))
	draw_rect(Rect2(x - 8.0, y + 16.0, 16.0, 3.0), _fade(IRON_LIGHT, alpha))
	draw_rect(Rect2(x - 4.0, y + 19.0, 8.0, 36.0), _fade(STEEL, alpha))
	draw_rect(Rect2(x - 4.0, y + 19.0, 1.0, 36.0), _fade(STEEL_LIGHT, alpha))
	draw_rect(Rect2(x + 3.0, y + 19.0, 1.0, 36.0), _fade(STEEL_DARK, alpha))
	draw_rect(Rect2(x - 2.0, y + 55.0, 4.0, 3.0), _fade(STEEL, alpha))
	draw_rect(Rect2(x - 1.0, y + 58.0, 2.0, 2.0), _fade(STEEL_DARK, alpha))


static func _fade(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * alpha)


func _draw_overlay() -> void:
	var h := heat01()
	if _mode == MODE_RUN and h > 0.06:
		for i in SWORD_COUNT:
			var hook := point_at(sword_s(i))
			var blade := Vector2(roundf(hook.x), roundf(hook.y) + 40.0)
			_glow_at(blade, 46.0, Color(1.0, 0.55, 0.22, 0.38 * h))
			_glow_rect(Rect2(blade.x - 5.0, blade.y - 16.0, 10.0, 40.0), Color(1.0, 0.62, 0.28, 0.16 * h))
	elif _mode == MODE_STILL:
		for i in SWORD_COUNT:
			var hook := point_at(sword_s(i))
			_glow_at(Vector2(roundf(hook.x), roundf(hook.y) + 40.0), 28.0, Color(0.55, 0.62, 0.8, 0.16))
	if _flash > 0.0:
		_glow_at(Vector2(X_END, DROP_END - 6.0), 64.0, Color(1.0, 0.55, 0.2, 0.7 * _flash))


# --- 测试 / 工具用 ------------------------------------------------------------

func deliveries() -> int:
	return _deliveries


func roll() -> float:
	return _roll


func is_moving() -> bool:
	return speed() > 0.0


## 画出来的剑的数量（EMPTY = 0）。
func visible_swords() -> int:
	return 0 if _mode == MODE_EMPTY else SWORD_COUNT
