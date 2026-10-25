extends Node2D
## 标题活景里「会动的小物件」的共同底座：吊运坩埚 / 远处锻锤 / 送剑链 / 破旗 / 火盆 / 亡魂巡行
## 都从它继承（title_crucible.gd 等）。
##
## 约束（docs/title-live-scene.md §6）：
##   · 每件 1–3 个节点：本体（自己 _draw）+ 一个加色的 `Glow` 子节点（需要光感时）；
##   · 全部整像素绘制，没有逐帧新建节点 / 数组；
##   · 不加 PointLight2D（灯光预算已满）：光感只用加色精灵的做法——`Glow` 节点套
##     Fx.additive_mat()，画 glow.png 的径向渐变；
##   · 时间自己走（advance），测试可以直接喂 delta，大步长会被拆成 ≤0.1s 的小步，
##     状态机不会漏掉转场；
##   · 不写 class_name：TitleWorld 用 preload 常量取用（避开 .godot 类缓存导致标题黑屏）。
##
## TitleWorld 每帧把两样东西推进来（set_look）：
##   heat  = 炉温 × 开屏/退场亮度（0 = 冷死、不动；1 = 正常；>1 = 守炉结局那样更旺）
##   lift  = 1 / 环境色：活景是被 CanvasModulate 压暗的，自发光的部分（铁水、火、灯）要乘它
##           才读得出来（和 _river / _mouth 的做法一样）。

const GLOW := "res://assets/title/glow.png"

## 暗色剪影的描边 / 铁件的三档灰（各件共用，免得每件各写一套调色板）。
const OUTLINE := Color("#0B0910")
const IRON_DARK := Color("#241C22")
const IRON := Color("#3C343C")
const IRON_LIGHT := Color("#6A5A5E")
const HOT_CORE := Color(1.0, 0.93, 0.70)
const HOT := Color(1.0, 0.62, 0.20)
const HOT_DEEP := Color(0.86, 0.30, 0.10)
const GLOW_WARM := Color(1.0, 0.55, 0.20)
## 状态机一步最长 0.1 秒。
const MAX_STEP := 0.1

## 子类在 _init 里置 false：不需要光感就不建 Glow 节点（破旗）。
var has_glow := true
## 0 = 冷死不动，1 = 正常，> 1 = 更旺。
var heat := 1.0
var lift := Color(1.0, 1.0, 1.0, 1.0)

var _t := 0.0
var _overlay: Node2D
var _glow_tex: Texture2D


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if has_glow:
		_glow_tex = DensityTextures.load_texture(GLOW)
		_overlay = Node2D.new()
		_overlay.name = "Glow"
		_overlay.material = Fx.additive_mat()
		_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(_overlay)
		_overlay.draw.connect(_draw_overlay)
	_setup()
	_redraw()


func _process(delta: float) -> void:
	advance(delta)


## 子类的一次性初始化（_ready 里调；不要在子类里重写 _ready，会盖掉底座的建节点）。
func _setup() -> void:
	pass


## 前进 delta 秒。
func advance(delta: float) -> void:
	var left := maxf(delta, 0.0)
	while left > 0.0:
		var step := minf(left, MAX_STEP)
		left -= step
		_t += step
		_step(step)
	_redraw()


## 子类的状态机：每次最多 0.1 秒。
func _step(_dt: float) -> void:
	pass


func set_look(new_heat: float, new_lift: Color) -> void:
	heat = new_heat
	lift = new_lift


func _redraw() -> void:
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


## 自发光的颜色：乘 lift 抵消环境暗色（alpha 不动）。
func em(color: Color) -> Color:
	return Color(color.r * lift.r, color.g * lift.g, color.b * lift.b, color.a)


## 0..1 的「炉温」（给亮度用，不让守炉结局的 >1 把光晕撑爆）。
func heat01() -> float:
	return clampf(heat, 0.0, 1.0)


## 子类重写：在 Glow 节点上画加色光晕（只在 draw 信号里调用）。
func _draw_overlay() -> void:
	pass


## 在 Glow 节点上画一团径向光晕（center 为本节点坐标，diameter 像素，color 已含 alpha）。
func _glow_at(center: Vector2, diameter: float, color: Color) -> void:
	if _overlay == null or _glow_tex == null or color.a <= 0.003:
		return
	var half := Vector2(diameter, diameter) * 0.5
	_overlay.draw_texture_rect(_glow_tex, Rect2((center - half).round(), Vector2(diameter, diameter)),
			false, Color(color.r * lift.r, color.g * lift.g, color.b * lift.b, color.a))


## 在 Glow 节点上画一块加色矩形（不带光晕的亮点 / 亮条）。
func _glow_rect(rect: Rect2, color: Color) -> void:
	if _overlay == null or color.a <= 0.003:
		return
	_overlay.draw_rect(rect, Color(color.r * lift.r, color.g * lift.g, color.b * lift.b, color.a))


static func smooth(p: float) -> float:
	var c := clampf(p, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## 加色光晕节点（测试读：有没有建、是不是加色材质）。
func glow_node() -> Node2D:
	return _overlay
