class_name Greatsword
extends Node2D
## 余烬骑士的锈蚀锯齿巨剑（纯表现层）。
##
## 为什么存在：主角逐帧动画（Fantasy Knight）自带的是小剑，角色读起来像普通
## 板甲兵，和文档里的「扛着过重的锯齿巨剑 / 剑长约身长 1.3–1.6 倍」不符。
## 这里把巨剑做成 1x 像素贴图（tools/gen_greatsword.py），背扛在身后：
## 探索 / 跑 / 跳 / 冲刺时它是剪影的主角；挥砍交给帧动画自带的剑与 SlashArc，
## 巨剑在这段时间淡出，避免同屏两把剑。
##
## 设计约束（docs/art-spec.md）：
## - 像素贴图 1x、NEAREST，节点原点在「握柄」上，绕握柄轻微摆动（不绕脚点转）。
## - 只在探索表现里动 ±2° + 1px 呼吸下沉；不做大幅旋转，保持像素边缘。
## - 攻击 / 死亡 / 过场让位（淡出），恢复时淡入，不闪。
## - 不写物理、不写存档、不读 Engine.time_scale；只表现。

const BACK_PATH := "res://assets/player/greatsword_back.png"
const PLANTED_PATH := "res://assets/player/greatsword_planted.png"
## 贴图里握柄的像素坐标（tools/gen_greatsword.py 的 hilt 决定）。
const BACK_HILT_PX := Vector2(13.0, 41.0)
const PLANTED_TIP_PX := Vector2(17.0, 64.0)
## 背扛位置：握柄落在左后腰（视觉节点坐标，脚点为原点、朝右）。
const BACK_HILT := Vector2(-6.0, -15.0)
## 挥砍 / 死亡时的淡出速度（1/s）：砍下去人已经换了武器，不能让巨剑慢慢化掉。
const FADE_OUT := 22.0
const FADE_IN := 10.0
## 呼吸：待机 ±1.2°，跑动 ±2.2° 并带 1px 上下沉。
const IDLE_SWAY := 0.022
const RUN_SWAY := 0.040

var _sprite: Sprite2D
var _t: float = 0.0
var _alpha: float = 1.0
var _target_alpha: float = 1.0


func _ready() -> void:
	name = "Greatsword"
	z_index = -1
	# 绕握柄摆动：节点原点 = 握柄，贴图按握柄像素反向偏移。
	position = BACK_HILT
	_sprite = Sprite2D.new()
	_sprite.name = "Blade"
	_sprite.texture = _load_tex(BACK_PATH)
	_sprite.centered = false
	_sprite.position = -BACK_HILT_PX
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.visible = _sprite.texture != null
	add_child(_sprite)
	set_process(true)


static func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


## 每帧由 Player 驱动。`player` 只读：位置由父节点给，这里只算姿态与可见度。
func tick(player: Player, delta: float) -> void:
	if _sprite == null or _sprite.texture == null:
		return
	_t += delta
	var dead := player.health != null and player.health.current <= 0
	var busy := player.melee != null and player.melee.is_busy()
	# 死亡与挥砍时让位；过场（cutscene_locked）保留在背上，开场由 OpeningCinematic
	# 显式管理（他要先躺下、剑插在地上）。
	_target_alpha = 0.0 if (dead or busy) else 1.0
	_alpha = move_toward(_alpha, _target_alpha, (FADE_OUT if _target_alpha < _alpha else FADE_IN) * delta)
	_sprite.modulate.a = _alpha
	visible = _alpha > 0.01
	if not visible:
		return

	var target_rot := 0.0
	var target_y := BACK_HILT.y
	if player.controller != null and player.controller.is_dashing():
		target_rot = 0.09
	elif not player.is_on_floor():
		target_rot = -0.05 if player.velocity.y < 0.0 else 0.045
	elif absf(player.velocity.x) > 12.0:
		target_rot = sin(_t * 9.0) * RUN_SWAY
		target_y = BACK_HILT.y - absf(sin(_t * 9.0)) * 1.1
	else:
		target_rot = sin(_t * 1.7) * IDLE_SWAY
	var k := 1.0 - exp(-14.0 * delta)
	rotation = lerpf(rotation, target_rot, k)
	position.y = lerpf(position.y, target_y, k)


## 开场用：把剑"插"在脚边。返回的 Sprite2D 由调用方负责释放。
## `tip_world` = 剑尖落地点（地面 y），贴图底边即地面线。
static func spawn_planted(host: Node2D, tip_world: Vector2) -> Sprite2D:
	if host == null:
		return null
	var tex := _load_tex(PLANTED_PATH)
	if tex == null:
		return null
	var spr := Sprite2D.new()
	spr.name = "PlantedGreatsword"
	spr.texture = tex
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.position = tip_world - PLANTED_TIP_PX
	spr.z_index = 1
	host.add_child(spr)
	return spr


## 过场 / 开场用：直接摆出「背在背上」的姿态（不经过 tick）。
func show_carried() -> void:
	_alpha = 1.0
	_target_alpha = 1.0
	rotation = 0.0
	position = BACK_HILT
	if _sprite != null:
		_sprite.modulate.a = 1.0
	visible = true


func hide_carried() -> void:
	_alpha = 0.0
	_target_alpha = 0.0
	if _sprite != null:
		_sprite.modulate.a = 0.0
	visible = false


func is_showing() -> bool:
	return visible and _alpha > 0.5
