extends "res://scripts/ui/title_prop.gd"
## 远处的锻锤：立在对岸栈桥上的一架杠杆锤，周期性抬起、砸下，落砧那一刻迸火星、
## 把砧上的坯料砸成白热，然后慢慢暗成橙红。
##
## 节点原点 = 垫墩顶面中心（TitleWorld 把它摆在 HAMMER_POS）。一轮 3.7 秒（炉温 1.0）：
##   0–0.6 抬起 → 保持 → 2.4 起加速下落 → 2.52 落砧（struck）→ 反弹 → 停在砧上等下一轮。
## 炉温 ≈ 0（熄火）时锤停在抬起位、坯料是冷的。strike_now() = 聚焦「回火试炼」时敲一下。
## 节点：本体 + Glow（坯料的光晕与落砧闪光）= 2 个。

signal struck(at: Vector2)

const T_RAISE := 0.6
const T_FALL := 2.4
const T_HIT := 2.52
const T_REBOUND := 0.18
const T_END := 3.7
## 开屏就在下落的起点，零点几秒后砸第一下，白热闪光能被看见。
const START_AT := 2.40
const PIVOT := Vector2(17.0, -38.0)
const HEAD_X := -2.0
const HEAD_UP_Y := -44.0
const HEAD_DOWN_Y := -26.0
const BILLET_AT := Vector2(0.0, -14.0)
const BILLET_COLD := Color(0.25, 0.14, 0.12)

var _ct := START_AT
var _prev_ct := START_AT
var _head := 0.0
var _billet := 0.0
var _flash := 0.0
var _strikes := 0
var _requests := 0
var _force := false
## 烘焙贴图（tools/gen_title_hammer.py）：本体（砧 / 立柱 / 锈痕）与锤头。
var _body_tex: Texture2D
var _head_tex: Texture2D
var _arm_tex: Texture2D


func _setup() -> void:
	# START_AT 落在抬起段末尾：第一帧就该是抬起，不要先画成砸下再弹回去。
	_head = head_at(START_AT)
	_body_tex = DensityTextures.load_texture("res://assets/title/hammer_body.png")
	_head_tex = DensityTextures.load_texture("res://assets/title/hammer_head.png")
	_arm_tex = DensityTextures.load_texture("res://assets/title/hammer_arm.png")


func speed() -> float:
	if heat < 0.06:
		return 0.0
	return clampf(heat, 0.3, 1.3)


## 坯料在没被砸的时候保持的余温（炉越旺越亮一点）。
func _billet_floor() -> float:
	var h := heat01()
	if h <= 0.08:
		return 0.0
	return 0.28 + 0.35 * h


func _step(dt: float) -> void:
	_billet = move_toward(_billet, _billet_floor(), dt * 0.45)
	_flash = move_toward(_flash, 0.0, dt * 2.2)
	var sp := speed()
	if sp <= 0.0:
		_head = 0.0
		return
	_prev_ct = _ct
	_ct += dt * sp
	if _force and _ct >= T_RAISE and _ct < T_FALL:
		_ct = T_FALL
	if _ct >= T_FALL:
		_force = false
	if _prev_ct < T_HIT and _ct >= T_HIT:
		_hit()
	if _ct >= T_END:
		_ct -= T_END
		_prev_ct = _ct
	_head = head_at(_ct)


func _hit() -> void:
	_strikes += 1
	_billet = 1.0
	_flash = 1.0
	struck.emit(BILLET_AT)


## 锤头位置：0 = 抬起，1 = 压在坯料上。
static func head_at(ct: float) -> float:
	if ct < T_RAISE:
		var c := clampf(ct / T_RAISE, 0.0, 1.0)
		return 1.0 - c * c * (3.0 - 2.0 * c)
	if ct < T_FALL:
		return 0.0
	if ct < T_HIT:
		return pow((ct - T_FALL) / (T_HIT - T_FALL), 1.6)
	if ct < T_HIT + T_REBOUND:
		return 1.0 - 0.3 * sin(PI * (ct - T_HIT) / T_REBOUND)
	return 1.0


## 马上敲一下（菜单聚焦「回火试炼」）。炉子冷死（熄火）时只记一次请求，锤不动。
func strike_now() -> void:
	_requests += 1
	if speed() <= 0.0:
		return
	if _ct >= T_HIT:
		# 这一轮已经砸过了：回到抬起段，抬到位就直接砸。
		_ct = 0.0
		_prev_ct = 0.0
	_force = true


func _draw() -> void:
	# 本体（砧 / 垫墩 / 立柱 / 轴承 / 锈痕 / 铆钉）是烘焙贴图：
	# tools/gen_title_hammer.py 一次性画好，运行时只贴，不再每帧重算做旧。
	if _body_tex != null:
		draw_texture(_body_tex, Vector2(-18.0, -44.0))
	else:
		# 兜底：素材缺失时退回简化的线条轮廓，别画成一块平涂铁。
		draw_rect(Rect2(-11.0, -14.0, 22.0, 11.0), OUTLINE)
		draw_rect(Rect2(-10.0, -13.0, 20.0, 3.0), IRON)
		draw_rect(Rect2(15.0, -42.0, 4.0, 42.0), IRON_DARK)
	# 坯料；落砧那一帧整块刷白
	var billet_color := BILLET_COLD.lerp(HOT_CORE, clampf(_billet, 0.0, 1.0))
	if _flash > 0.45:
		billet_color = Color(1.0, 0.98, 0.92)
	var billet_lit := em(billet_color) if _billet > 0.12 or _flash > 0.2 else billet_color
	draw_rect(Rect2(-6.0, -15.75, 12.0, 2.5), billet_lit.darkened(0.23))
	draw_rect(Rect2(-5.75, -16.0, 11.25, 1.75), billet_lit)
	draw_line(Vector2(-5.25, -15.75), Vector2(4.75, -15.75), billet_lit.lightened(0.13), 0.25)
	# Broken mill scale stays darker than the hot core, even during a strike.
	for i in 5:
		var sx := -4.5 + float(i) * 1.875
		draw_line(Vector2(sx, -13.75), Vector2(sx + 0.75, -14.0), billet_lit.darkened(0.45), 0.25)
	# A textured forged link rotates around its end pins. Nearest sampling keeps
	# the native QHD texels sharp; the source art's two pin centers stay attached.
	var head_y := roundf(lerpf(HEAD_UP_Y, HEAD_DOWN_Y, _head))
	var attach := Vector2(HEAD_X, head_y + 2.0)
	if _arm_tex != null:
		var link := PIVOT - attach
		draw_set_transform(attach, link.angle(), Vector2(link.length() / 19.0, 1.0))
		draw_texture(_arm_tex, Vector2(-1.5, -3.5))
		draw_set_transform(Vector2.ZERO)
	else:
		draw_line(PIVOT, attach, OUTLINE, 5.0)
		draw_line(PIVOT, attach, IRON_LIGHT, 3.0)
	# 锤头：烘焙贴图（锈斑、锈底沿、崩角、铆钉都在图里）。
	if _head_tex != null:
		draw_texture(_head_tex, Vector2(HEAD_X - 9.0, head_y - 2.0))
	else:
		draw_rect(Rect2(HEAD_X - 9.0, head_y - 2.0, 18.0, 14.0), OUTLINE)
		draw_rect(Rect2(HEAD_X - 8.0, head_y - 1.0, 16.0, 12.0), IRON)
		draw_rect(Rect2(HEAD_X - 8.0, head_y - 1.0, 16.0, 1.0), IRON_LIGHT)


func _draw_overlay() -> void:
	var h := heat01()
	if _billet > 0.04:
		_glow_at(BILLET_AT, 28.0 + 30.0 * _billet, Color(1.0, 0.6, 0.25, 0.7 * _billet * maxf(h, 0.35)))
	if _flash > 0.0:
		_glow_at(BILLET_AT + Vector2(0.0, -4.0), 78.0, Color(1.0, 0.97, 0.88, 0.95 * _flash))
		_glow_rect(Rect2(-8.0, -18.0, 16.0, 6.0), Color(1.0, 1.0, 1.0, 0.85 * _flash))


# --- 测试 / 工具用 ------------------------------------------------------------

func strikes() -> int:
	return _strikes


func strike_requests() -> int:
	return _requests


func head() -> float:
	return _head


func billet_level() -> float:
	return _billet


func is_frozen() -> bool:
	return speed() <= 0.0
