extends "res://scripts/ui/title_prop.gd"
## 亡魂巡行：对岸那条细栈桥上，几个提着灯的小剪影慢慢往炉口方向走——被炉约烧过名字的人，
## 魂还在照着旧例排队。走到右侧炉房后面就看不见了，再从左侧机房后面绕出来。
##
## 一个节点画全部亡魂（披风剪影 + 幽光的眼），一个 Glow 节点画全部提灯的暖光点
## （加色精灵，不加 PointLight2D）。数量由存档变体给（TitleWorld.prop_plan）：
## 旅程越深越多，守炉结局最多（魂还困着），还火 / 熄火结局一个也没有。

const MAX_GHOSTS := 3
## 脚线：亡魂站在对岸细栈桥的桥面上（高度见 title_world.gd 的 FAR_DECK_Y）。
const FLOOR_Y := 215.0
const X_LEFT := 120.0
const X_RIGHT := 560.0
## 走路速度（像素/秒）：慢到几乎看不出在动，盯一会儿才发现位置变了。
const SPEED := 7.0
const CLOAK := Color("#1B2230")
const CLOAK_RIM := Color("#3A4660")
const EYES := Color(0.62, 0.84, 1.0)
const LAMP := Color(1.0, 0.72, 0.35)

var _count := 0
var _walk := 0.0


func set_count(n: int) -> void:
	_count = clampi(n, 0, MAX_GHOSTS)


func count() -> int:
	return _count


## 一圈的长度（亡魂从左绕到右再回到左）。
static func loop_length() -> float:
	return X_RIGHT - X_LEFT


func ghost_x(index: int) -> float:
	var length := loop_length()
	return X_LEFT + fposmod(_walk + float(index) * length / float(MAX_GHOSTS), length)


func speed() -> float:
	return SPEED * clampf(heat, 0.35, 1.0)


func _step(dt: float) -> void:
	if _count > 0:
		_walk += speed() * dt


## 第 index 个亡魂这一刻的步态（0 / 1），抬脚时身子跟着抬 1px。
func _stride(index: int) -> int:
	return int(_t * 1.8 + float(index) * 0.7) % 2


func _draw() -> void:
	for i in _count:
		var gx := roundf(ghost_x(i))
		var gy := FLOOR_Y
		var stride := _stride(i)
		var bob := -float(stride)
		# 披风 + 兜帽（放大到桥上能认出来的剪影）
		draw_rect(Rect2(gx - 5.0, gy - 18.0 + bob, 10.0, 14.0), CLOAK)
		draw_rect(Rect2(gx - 6.0, gy - 6.0 + bob, 12.0, 4.0), CLOAK)
		draw_rect(Rect2(gx - 4.0, gy - 23.0 + bob, 8.0, 6.0), CLOAK)
		draw_rect(Rect2(gx - 4.0, gy - 23.0 + bob, 8.0, 1.0), CLOAK_RIM)
		draw_rect(Rect2(gx - 5.0, gy - 18.0 + bob, 1.0, 12.0), CLOAK_RIM)
		# 兜帽里的两点幽光
		draw_rect(Rect2(gx - 1.0, gy - 20.0 + bob, 2.0, 2.0), em(EYES))
		draw_rect(Rect2(gx + 2.0, gy - 20.0 + bob, 2.0, 2.0), em(EYES))
		# 脚：两步轮换
		if stride == 0:
			draw_rect(Rect2(gx - 5.0, gy - 2.0, 3.0, 2.0), CLOAK)
			draw_rect(Rect2(gx + 2.0, gy - 2.0, 3.0, 2.0), CLOAK)
		else:
			draw_rect(Rect2(gx - 4.0, gy - 2.0, 3.0, 2.0), CLOAK)
			draw_rect(Rect2(gx + 3.0, gy - 2.0, 3.0, 2.0), CLOAK)
		# 提灯：手里的杆 + 灯体
		draw_rect(Rect2(gx + 6.0, gy - 16.0 + bob, 1.0, 8.0), CLOAK_RIM)
		draw_rect(Rect2(gx + 5.0, gy - 9.0 + bob, 4.0, 4.0), em(LAMP))


func _draw_overlay() -> void:
	var lamp := clampf(0.55 + heat * 0.45, 0.0, 1.0)
	for i in _count:
		var gx := roundf(ghost_x(i))
		var bob := -float(_stride(i))
		var flick := 0.82 + 0.18 * sin(floorf(_t * 10.0) * 2.3 + float(i) * 1.7)
		var at := Vector2(gx + 7.0, FLOOR_Y - 7.0 + bob)
		_glow_at(at, 48.0, Color(LAMP.r, LAMP.g, LAMP.b, 0.72 * lamp * flick))
		_glow_at(at, 16.0, Color(1.0, 0.9, 0.6, 0.55 * lamp * flick))
		_glow_rect(Rect2(at.x - 1.0, at.y - 1.0, 4.0, 4.0), Color(1.0, 0.92, 0.65, 0.85 * lamp))


# --- 测试 / 工具用 ------------------------------------------------------------

func walked() -> float:
	return _walk
