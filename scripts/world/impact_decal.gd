extends Node2D
## 一次环境打击留下的像素痕迹（焦痕 / 裂口 / 金属坑 / 水渍 / 木屑痕）。
##
## 全部用 2px 栅格画在 _draw 里，不加贴图、不参与碰撞；寿命到了自己淡出释放。
## 形状按 (材质, 位置) 做确定性随机，同一个落点重载后仍是同一块痕迹。
## 贴花画在地形贴图之上一层（DecalField.z_index=1），所以能盖住草皮/石面；
## 位置只沿法线外抬 1px，读起来是"印在表面上"而不是浮在空中。

const CELL := 2
## 焦痕/裂口的滞留时间（秒）。余烬贴花比冷痕短一点，免得地上一直亮。
const LIFETIME := 16.0
const FADE_TIME := 2.5

var decal_kind: StringName = &"scorch"
var _cells: Array = []
var _ember_cells: Array = []
var _age := 0.0
var _inverted := false
## 地面焚痕的寿命比墙上的裂口短得多：它只负责"刚烧过"的几秒，不长期占画面。
var _life := LIFETIME


## kind: scorch/chip/pit/puddle/gash/none（来自 ImpactCatalog 的 decal 字段）。
## normal: 命中面法线，决定贴花旋转（地面水平、墙面竖直）。
func setup(kind: StringName, pos: Vector2, normal: Vector2, weight_scale: float = 1.0) -> void:
	decal_kind = kind
	var n := normal.normalized() if normal.length_squared() > 0.0001 else Vector2.UP
	# 地面碰撞面在地皮之下 ~8px（草冠/石板顶沿在地表线上方）；贴花整体上抬，
	# 让 V 形缺口咬住可见地表线，而不是埋进草叶中间。
	var lift := 1.0
	position = Vector2(roundf(pos.x + n.x * lift), roundf(pos.y + n.y * lift))
	rotation = 0.0
	_inverted = false
	if absf(n.x) > 0.5:
		# 墙面：贴花立起来；法线朝左时把可见的半边留在墙外。
		rotation = PI * 0.5 * signf(n.x)
	elif n.y > 0.5:
		# 天花板：贴花倒过来，余烬往下掉。
		rotation = PI
		_inverted = true
	_build(weight_scale)
	_age = 0.0
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	if _age >= _life:
		queue_free()
		return
	if _age > _life - FADE_TIME:
		modulate.a = clampf((_life - _age) / FADE_TIME, 0.0, 1.0)
	# 余烬点先冷掉：前 1/3 寿命之后不再画。
	if not _ember_cells.is_empty() and _age > LIFETIME * 0.32:
		_ember_cells.clear()
		queue_redraw()


func _build(weight_scale: float) -> void:
	_cells.clear()
	_ember_cells.clear()
	if decal_kind == &"none":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(position.x), roundi(position.y))) ^ hash(decal_kind)
	var big := clampi(int(round(weight_scale)), 1, 2)
	match decal_kind:
		&"scorch":
			_scorch(rng, big)
		&"chip":
			_chip(rng, big)
		&"pit":
			_pit(rng, big)
		&"puddle":
			_puddle(rng, big)
		&"gash":
			_gash(rng, big)
	queue_redraw()


func _add_cell(x: int, y: int, color: Color) -> void:
	var row := y if not _inverted else 4 - y
	_cells.append({"rect": Rect2(x * CELL, row * CELL, CELL, CELL), "color": color})


func _add_ember_cell(x: int, y: int, color: Color) -> void:
	var row := y if not _inverted else 4 - y
	_ember_cells.append({"rect": Rect2(x * CELL, row * CELL, CELL, CELL), "color": color})


## 焦痕：实心阶梯椭圆，外圈锈色，内部近黑，再撒几粒将熄的余烬。
## 地面焚痕：只把地表压暗成一块抖动的小焦痕（不描边、不画土沿、不实心纯黑），
## 3.5 秒内淡掉。这样从侧面看是"地上刚被烧过"，不会出现悬浮的黑色几何块。
func _scorch(rng: RandomNumberGenerator, big: int) -> void:
	_life = 3.5
	var half := 4 + big            # 半宽（格，1 格 = 2px）
	var ash := Color(0.07, 0.05, 0.08, 0.62)
	var ember_dark := Color(0.16, 0.09, 0.07, 0.62)
	var rows := 3 + big
	for y in range(0, rows):
		for x in range(-half, half + 1):
			# 抖动/稀疏：只压暗大约一半的像素，保留下面的草与土纹理。
			if (x + y) % 2 != 0:
				continue
			if absi(x) > half - 2:
				continue
			_add_cell(x, y, ember_dark if y == 0 else ash)
	for _e in rng.randi_range(1, 2):
		_add_ember_cell(rng.randi_range(-2, 2), 0,
				Palette.EMBER.lerp(Color("#FF8C00"), rng.randf() * 0.5))


## 石面裂口：一小块暗坑 + 从中心放射的浅灰裂纹。
func _chip(rng: RandomNumberGenerator, big: int) -> void:
	var pit := Color("#120E14")
	var pale := Color("#8A8680").lerp(Palette.CONCRETE, 0.55)
	for y in 2:
		for x in 2:
			_add_cell(x - 1, y - 1, pit)
	for arm in 4 + big:
		var ang := rng.randf() * TAU
		var x := 0
		var y := 0
		for step in 3:
			x += int(round(cos(ang)))
			y += int(round(sin(ang)))
			_add_cell(clampi(x, -5, 5), clampi(y, -4, 4), pale if step % 2 == 0 else pit)


## 金属坑：暗坑 + 一圈亮铁屑。
func _pit(rng: RandomNumberGenerator, big: int) -> void:
	var hole := Color("#120E14")
	var bright := Color("#FFC14A").lerp(Palette.RUST_LIGHT, 0.35)
	_add_cell(0, 0, hole)
	_add_cell(-1, 0, hole)
	_add_cell(0, 1, hole)
	for i in 6 + big * 2:
		var ang := rng.randf() * TAU
		var r := rng.randi_range(2, 3)
		_add_cell(int(round(cos(ang) * r)), int(round(sin(ang) * r)), bright)


## 水渍：一小滩暗色湿痕 + 两点青绿反光。
func _puddle(rng: RandomNumberGenerator, big: int) -> void:
	var wet := Color(0.10, 0.14, 0.16, 0.72)
	var glint := Color("#7FA8A0")
	var widths := [1, 3, 4, 3, 1]
	for y in widths.size():
		var w := int(widths[y])
		for i in range(-w, w + 1):
			_add_cell(i, y - 2, wet)
	for i in 2 + big:
		_add_cell(rng.randi_range(-2, 2), rng.randi_range(-2, 1), glint)


## 木屑痕：几道短木色划痕。
func _gash(rng: RandomNumberGenerator, big: int) -> void:
	var pale := Color("#E8B090").lerp(Palette.RUST_DARK, 0.4)
	var dark := Color("#120E14")
	for _arm in 3 + big:
		var x := rng.randi_range(-3, 2)
		var y := rng.randi_range(-2, 2)
		_add_cell(x, y, dark)
		_add_cell(x + 1, y, pale)


func _draw() -> void:
	for cell in _cells:
		draw_rect(cell["rect"] as Rect2, cell["color"] as Color)
	for cell in _ember_cells:
		draw_rect(cell["rect"] as Rect2, cell["color"] as Color)


## 测试用：当前痕迹的格子总数（0 = none）。
func cell_count() -> int:
	return _cells.size() + _ember_cells.size()
