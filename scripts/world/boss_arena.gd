class_name BossArena
extends Node2D
## 一场 Boss 战斗的空间容器（docs/integration-contracts.md §4.1）。由
## ChapterLayout.boss() 统一生成，也可以由夹具 / 关卡手工挂载。职责：
##   1. 边界：战斗期间把 Boss 与骑士 clamp 在竞技场内（x 轴，脚点不动）；
##   2. 锁门：把「开战锁门 / 清场解锁」翻译成门上真实存在的 lock / unlock 调用；
##   3. 相机：开战时把 GameCamera 的 limit 同步到竞技场，清场后按原值还原；
##   4. 机关：火柱 / 落石 / 水流占位接口 —— 注册、按事件触发、判定不出场地；
##   5. Boss 前存档点校验（余烬巢距场门 <= checkpoint_max_distance）；
##   6. 战后解锁：Boss 的 slain / died 信号 -> clear_arena()（门开、相机还原、边界放开）。
##
## 它只加「空间与机关」，不改 Boss 自己的状态机与伤害数值：现有两场 Boss 的行为
## 由各自的章节脚本负责，本节点只在被挂载时生效。

signal arena_started
signal arena_cleared
signal gate_locked_changed(locked: bool)
signal hazard_triggered(id: StringName, data: Dictionary)
signal camera_limits_synced(limits: Rect2i)

enum HazardKind { FIRE_PILLAR, ROCKFALL, WATER_FLOW }

## 火柱 / 落石预警的最短时长（契约 §4.1：Boss 场地预警 >= 0.35 s）。
const BOSS_TELEGRAPH_MIN := 0.35
const DEFAULT_HAZARD_TELEGRAPH := 0.45
const DEFAULT_HAZARD_ACTIVE := 0.25
const WALL_THICKNESS := 16.0
const ARENAS_GROUP := "Arenas"

## 竞技场横向边界（世界 x，含两端）。
@export var arena_left: float = 0.0
@export var arena_right: float = 640.0
## 竖向边界：只在 sync_camera_y / 锁门墙使用；clamp 默认只做 x。
@export var arena_top: float = -320.0
@export var arena_bottom: float = 400.0
## 地面 y（存档点校验 / 相机 padding / 墙高用）。
@export var floor_y: float = 320.0
## Boss 前存档点必须离场门这么近（像素）。
@export var checkpoint_max_distance: float = 80.0
## Boss / 骑士被 clamp 时留的半宽。
@export var boss_half_width: float = 20.0
@export var player_half_width: float = 8.0
## 开战（boss_intro_started）自动激活；start_immediately 则入树即激活。
@export var start_on_intro: bool = true
@export var start_immediately: bool = false
## 锁门时是否补两道实心空气墙（默认不：很多竞技场用真实地形 / 闸门锁）。
@export var solid_walls: bool = false
## 相机竖向 limit 是否也同步（默认不，避免改观感）。
@export var sync_camera_y: bool = false
## 相机的水平 / 竖向 padding（世界像素）。
@export var camera_padding: Vector2 = Vector2.ZERO
@export var clamp_player: bool = true
@export var clamp_boss: bool = true

var boss: Node2D
var director: BossDirector
var active: bool = false
var cleared: bool = false
var gate_locked: bool = false
## 当前竞技场矩形（activate() 时按左右边界计算）。
var bounds: Rect2 = Rect2()
## 开战前相机 limit 快照（清场后还原）。
var saved_camera_limits: Rect2i = Rect2i()
var has_saved_camera_limits: bool = false

var _gate_targets: Array = []
var _hazards: Dictionary = {}
var _walls: Array[StaticBody2D] = []
var _camera: GameCamera
var _frozen: bool = false
var _checkpoint_checked: bool = false


func _ready() -> void:
	_recompute_bounds()
	if start_immediately:
		activate()
	elif start_on_intro:
		if not GameEvents.boss_intro_started.is_connected(_on_boss_intro_started):
			GameEvents.boss_intro_started.connect(_on_boss_intro_started)


func _exit_tree() -> void:
	# 关卡切换 / 死亡重载时相机要拿回原来的取景，不能把 limit 留在竞技场。
	restore_camera_limits()


# ---------------------------------------------------------------------------
# 构建 / 绑定
# ---------------------------------------------------------------------------
## 在 host 的 "Arenas" 组下生成一场竞技场并绑定 Boss。ChapterLayout.boss() 与
## 夹具都走这里。返回 BossArena；host / boss 为空时返回 null。
## p_start_on_intro = true 时，Boss 的 boss_intro_started（且名号匹配）会自动开战。
static func attach(host: Node2D, node_name: String, p_boss: Node2D,
		left: float, right: float, p_floor_y: float = NAN,
		p_start_on_intro: bool = true) -> BossArena:
	if host == null:
		return null
	var folder := host.get_node_or_null(ARENAS_GROUP) as Node2D
	if folder == null:
		folder = Node2D.new()
		folder.name = ARENAS_GROUP
		host.add_child(folder)
	var arena := BossArena.new()
	arena.name = node_name
	arena.arena_left = left
	arena.arena_right = right
	arena.start_on_intro = p_start_on_intro
	if not is_nan(p_floor_y):
		arena.floor_y = p_floor_y
	folder.add_child(arena)
	arena.bind_boss(p_boss)
	return arena


## 绑定 Boss：胜负信号、导演层的场地事件都接到这场竞技场。
func bind_boss(p_boss: Node2D) -> void:
	boss = p_boss
	if boss == null:
		return
	if boss.has_signal("slain") and not boss.is_connected("slain", clear_arena):
		boss.connect("slain", clear_arena)
	if boss.has_method("boss_director"):
		director = boss.call("boss_director") as BossDirector
	if director != null and not director.is_connected("arena_event", _on_arena_event):
		director.connect("arena_event", _on_arena_event)


func bind_director(p_director: BossDirector) -> void:
	director = p_director
	if director != null and not director.is_connected("arena_event", _on_arena_event):
		director.connect("arena_event", _on_arena_event)


# ---------------------------------------------------------------------------
# 开战 / 清场
# ---------------------------------------------------------------------------
## 开战：锁门、clamp、相机 limit 同步。重复调用无副作用；清场后不再激活。
func activate() -> void:
	if active or cleared:
		return
	active = true
	_recompute_bounds()
	_set_gate_locked(true)
	if solid_walls:
		_spawn_walls()
	sync_camera_limits()
	emit_signal("arena_started")


## 清场：Boss 死亡 / 被击败时调用。门开、相机还原、边界放开（幂等）。
func clear_arena() -> void:
	if cleared:
		return
	cleared = true
	active = false
	_set_gate_locked(false)
	_free_walls()
	restore_camera_limits()
	emit_signal("arena_cleared")


## 提前解除（不标记 cleared，例如战前退出关卡）；restore 相机 + 解锁门。
func deactivate() -> void:
	if cleared:
		return
	active = false
	_set_gate_locked(false)
	_free_walls()
	restore_camera_limits()


func is_active() -> bool:
	return active


func is_cleared() -> bool:
	return cleared


func _physics_process(_delta: float) -> void:
	if not active or cleared:
		return
	if _camera == null:
		# 相机可能在竞技场之后才入树（关卡先搭地形后放相机）。
		_camera = _find_camera()
		if _camera != null:
			sync_camera_limits()
	if clamp_boss:
		clamp_actor(boss, boss_half_width)
	if clamp_player and get_tree() != null:
		var knight := get_tree().get_first_node_in_group("player") as Node2D
		clamp_actor(knight, player_half_width)


func _on_boss_intro_started(boss_name: String) -> void:
	if cleared:
		return
	if boss != null and boss.has_method("boss_kit"):
		var kit := boss.call("boss_kit") as BossKit
		if kit != null and kit.boss_title() != boss_name and boss_name != "":
			return
	activate()


# ---------------------------------------------------------------------------
# 边界 clamp
# ---------------------------------------------------------------------------
## 把 actor 的 x 夹回竞技场（留 half_width 净空），返回是否真的夹了。
func clamp_actor(actor: Node2D, half_width: float) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var x := actor.global_position.x
	var low := arena_left + half_width
	var high := arena_right - half_width
	if high < low:
		var mid := (arena_left + arena_right) * 0.5
		if not is_equal_approx(x, mid):
			actor.global_position.x = mid
			return true
		return false
	var clamped := clampf(x, low, high)
	if is_equal_approx(clamped, x):
		return false
	actor.global_position.x = clamped
	if actor is CharacterBody2D:
		# 撞在边界上就别继续把速度往墙里塞，否则下一帧还会被推出界。
		if (x < low and (actor as CharacterBody2D).velocity.x < 0.0) \
				or (x > high and (actor as CharacterBody2D).velocity.x > 0.0):
			(actor as CharacterBody2D).velocity.x = 0.0
	return true


func _recompute_bounds() -> void:
	bounds = Rect2(arena_left, arena_top, maxf(0.0, arena_right - arena_left),
			maxf(0.0, arena_bottom - arena_top))


# ---------------------------------------------------------------------------
# 锁门
# ---------------------------------------------------------------------------
## 注册一扇门：Node（有 lock/unlock 或 close/open 方法）或 Callable(bool)。
func register_gate(target: Variant) -> void:
	if target == null:
		return
	if not _gate_targets.has(target):
		_gate_targets.append(target)


## 手动锁 / 解锁（锁门时同时补空气墙，解锁时撤掉）。
func set_gate_locked(locked: bool) -> void:
	_set_gate_locked(locked)


func _set_gate_locked(locked: bool) -> void:
	gate_locked = locked
	for target in _gate_targets:
		_apply_gate_target(target, locked)
	if solid_walls:
		if locked:
			_spawn_walls()
		else:
			_free_walls()
	emit_signal("gate_locked_changed", locked)


func _apply_gate_target(target: Variant, locked: bool) -> void:
	if target is Callable:
		if (target as Callable).is_valid():
			(target as Callable).call(locked)
		return
	var node := target as Node
	if node == null or not is_instance_valid(node):
		return
	if locked:
		if node.has_method("lock"):
			node.call("lock")
		elif node.has_method("close"):
			node.call("close")
	else:
		if node.has_method("unlock"):
			node.call("unlock")
		elif node.has_method("open"):
			node.call("open")


func _spawn_walls() -> void:
	if not _walls.is_empty():
		return
	_walls = [_make_wall("BossArenaWallLeft", arena_left), _make_wall("BossArenaWallRight", arena_right)]
	for wall in _walls:
		add_child(wall)


func _make_wall(wall_name: String, x: float) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.name = wall_name
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = Vector2(x, (arena_top + arena_bottom) * 0.5)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(WALL_THICKNESS, maxf(64.0, arena_bottom - arena_top))
	shape.shape = rect
	wall.add_child(shape)
	return wall


func _free_walls() -> void:
	for wall in _walls:
		if is_instance_valid(wall):
			wall.queue_free()
	_walls = []


# ---------------------------------------------------------------------------
# 相机 limit 同步
# ---------------------------------------------------------------------------
## 把相机 limit 同步到竞技场（战斗期间）。返回是否成功（无相机时 false）。
func sync_camera_limits() -> bool:
	_camera = _find_camera()
	if _camera == null:
		return false
	if not has_saved_camera_limits:
		saved_camera_limits = Rect2i(_camera.limit_left, _camera.limit_top,
				_camera.limit_right - _camera.limit_left, _camera.limit_bottom - _camera.limit_top)
		has_saved_camera_limits = true
	_apply_camera_limits()
	return true


## 还原开战前的相机 limit（清场 / 退出关卡）。
func restore_camera_limits() -> void:
	if _camera == null or not is_instance_valid(_camera) or not has_saved_camera_limits:
		return
	_camera.limit_left = saved_camera_limits.position.x
	_camera.limit_top = saved_camera_limits.position.y
	_camera.limit_right = saved_camera_limits.position.x + saved_camera_limits.size.x
	_camera.limit_bottom = saved_camera_limits.position.y + saved_camera_limits.size.y
	has_saved_camera_limits = false


func _apply_camera_limits() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	_camera.limit_left = int(round(arena_left - camera_padding.x))
	_camera.limit_right = int(round(arena_right + camera_padding.x))
	if sync_camera_y:
		_camera.limit_top = int(round(arena_top - camera_padding.y))
		_camera.limit_bottom = int(round(arena_bottom + camera_padding.y))
	emit_signal("camera_limits_synced", Rect2i(_camera.limit_left, _camera.limit_top,
			_camera.limit_right - _camera.limit_left, _camera.limit_bottom - _camera.limit_top))


func _find_camera() -> GameCamera:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group("game_camera") as GameCamera


# ---------------------------------------------------------------------------
# 机关接口（火柱 / 落石 / 水流）
# ---------------------------------------------------------------------------
## 注册机关：Node（有 trigger() 方法）或 Callable()。
func register_hazard(id: StringName, target: Variant) -> void:
	if String(id) == "" or target == null:
		return
	_hazards[id] = target


func registered_hazard_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in _hazards:
		out.append(StringName(key))
	out.sort()
	return out


## 触发已注册机关（导演层的场地事件 / 测试 / 章节脚本都能调）。
## 返回是否找到并触发。
func trigger_hazard(id: StringName, data: Dictionary = {}) -> bool:
	if not _hazards.has(id):
		return false
	var target: Variant = _hazards[id]
	if target is Callable:
		if (target as Callable).is_valid():
			(target as Callable).call(data)
			emit_signal("hazard_triggered", id, data)
			return true
		return false
	var node := target as Node
	if node == null or not is_instance_valid(node):
		return false
	if node.has_method("trigger"):
		node.call("trigger", data)
		emit_signal("hazard_triggered", id, data)
		return true
	return false


## 生成一个内置机关（已 clamp 在竞技场内、已画预警，等 trigger() 才出判定）。
## params：telegraph / active / size / offset / damage / color / knockback / flow。
func make_hazard(kind: int, at: Vector2, params: Dictionary = {}) -> Node2D:
	var hazard := HazardNode.new()
	hazard.name = String(params.get("name", "Hazard"))
	hazard.kind = kind
	hazard.telegraph = maxf(BOSS_TELEGRAPH_MIN,
			float(params.get("telegraph", DEFAULT_HAZARD_TELEGRAPH)))
	hazard.active_time = maxf(0.05, float(params.get("active", DEFAULT_HAZARD_ACTIVE)))
	hazard.damage = maxi(0, int(params.get("damage", 1)))
	var tint: Color = params.get("color", _hazard_color(kind))
	hazard.color = tint
	var push: Vector2 = params.get("flow", Vector2(90.0, 0.0))
	hazard.flow = push
	var recoil: Vector2 = params.get("knockback", Vector2(0.0, -60.0))
	hazard.knockback = recoil
	var size: Vector2 = params.get("size", _hazard_size(kind))
	var offset: Vector2 = params.get("offset", _hazard_offset(kind))
	hazard.hitbox_size = size
	hazard.hitbox_offset = offset
	hazard.start_auto = bool(params.get("auto", false))
	var center := _clamp_hazard_center(at, size, offset)
	add_child(hazard)
	hazard.global_position = center
	hazard.spawn_warning()
	if hazard.start_auto:
		hazard.call_deferred("trigger")
	return hazard


## 生成 + 注册 + 立刻触发（kit 的场地事件常用这个）。
func spawn_hazard(id: StringName, kind: int, at: Vector2, params: Dictionary = {}) -> Node2D:
	var hazard := make_hazard(kind, at, params)
	register_hazard(id, hazard)
	trigger_hazard(id, params)
	return hazard


## 把机关中心夹进竞技场：保证「中心 + offset ± size/2」不越界（hitbox 不出场地）。
func _clamp_hazard_center(at: Vector2, size: Vector2, offset: Vector2) -> Vector2:
	var half := size * 0.5
	var low_x := arena_left + half.x - offset.x
	var high_x := arena_right - half.x - offset.x
	var x := at.x
	if high_x >= low_x:
		x = clampf(x, low_x, high_x)
	else:
		x = (low_x + high_x) * 0.5
	var y := at.y
	var low_y := arena_top + half.y - offset.y
	var high_y := arena_bottom - half.y - offset.y
	if high_y >= low_y:
		y = clampf(y, low_y, high_y)
	return Vector2(x, y)


func _hazard_color(kind: int) -> Color:
	match kind:
		HazardKind.ROCKFALL:
			return Color(0.95, 0.82, 0.55, 0.95)
		HazardKind.WATER_FLOW:
			return Color(0.45, 0.8, 0.95, 0.9)
		_:
			return Color(1.0, 0.45, 0.2, 0.95)


func _hazard_size(kind: int) -> Vector2:
	match kind:
		HazardKind.ROCKFALL:
			return Vector2(40.0, 28.0)
		HazardKind.WATER_FLOW:
			return Vector2(160.0, 64.0)
		_:
			return Vector2(32.0, 64.0)


func _hazard_offset(kind: int) -> Vector2:
	match kind:
		HazardKind.WATER_FLOW:
			return Vector2(0.0, 0.0)
		_:
			return Vector2(0.0, -8.0)


func _on_arena_event(id: StringName, data: Dictionary) -> void:
	# 导演层的场地事件默认转发给同名机关（trigger_hazard 成功后自己发
	# hazard_triggered；没有同名机关时静默，章节脚本 / 测试可直接读导演层信号）。
	trigger_hazard(id, data)


# ---------------------------------------------------------------------------
# Boss 前存档点校验
# ---------------------------------------------------------------------------
## 场门位置：竞技场左侧入口的地面点（校验存档点距离的锚点）。
func checkpoint_anchor() -> Vector2:
	return Vector2(arena_left, floor_y)


## 找最近的余烬巢（同世界的 "ember_nests" 组）。
func nearest_nest() -> Node2D:
	if get_tree() == null:
		return null
	var anchor := checkpoint_anchor()
	var best: Node2D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("ember_nests"):
		var nest := node as Node2D
		if nest == null or not is_instance_valid(nest):
			continue
		var distance := nest.global_position.distance_to(anchor)
		if distance < best_distance:
			best_distance = distance
			best = nest
	return best


## 存档点校验报告（夹具 / 测试 / 关卡自检读）。
func checkpoint_report() -> Dictionary:
	var anchor := checkpoint_anchor()
	var nest := nearest_nest()
	var distance := INF
	if nest != null:
		distance = nest.global_position.distance_to(anchor)
	return {
		"anchor": anchor,
		"checkpoint_max_distance": checkpoint_max_distance,
		"nest": String(nest.name) if nest != null else "",
		"nest_position": nest.global_position if nest != null else Vector2.INF,
		"distance": distance,
		"ok": distance <= checkpoint_max_distance,
	}


## 校验 Boss 前存档点：不足时 push_warning（不阻塞关卡搭建）。
func validate_checkpoint() -> bool:
	_checkpoint_checked = true
	var report := checkpoint_report()
	if not bool(report.ok):
		push_warning("BossArena '%s': no ember nest within %.0f px of the arena gate (nearest: %s)"
				% [name, checkpoint_max_distance, report.nest])
	return bool(report.ok)


func has_checked_checkpoint() -> bool:
	return _checkpoint_checked


# ---------------------------------------------------------------------------
# 冻结（暂停 / 过场）
# ---------------------------------------------------------------------------
func freeze() -> void:
	_frozen = true
	if director != null and is_instance_valid(director):
		director.freeze()


func resume() -> void:
	_frozen = false
	if director != null and is_instance_valid(director):
		director.resume()


func is_frozen() -> bool:
	return _frozen


# ---------------------------------------------------------------------------
# 内置机关节点（火柱 / 落石 / 水流）
# ---------------------------------------------------------------------------
class HazardNode extends Node2D:
	## 与 BossArena.HazardKind 同值（这里用局部常量，避免内嵌类在类注册阶段
	## 反向引用外层 class_name —— headless 扫描时外层类名还没注册）。
	const KIND_FIRE := 0
	const KIND_ROCK := 1
	const KIND_WATER := 2

	var kind: int = 0
	var telegraph: float = 0.45
	var active_time: float = 0.25
	var damage: int = 1
	var color: Color = Color(1.0, 0.45, 0.2, 0.95)
	var flow: Vector2 = Vector2(90.0, 0.0)
	var knockback: Vector2 = Vector2(0.0, -60.0)
	var hitbox_size: Vector2 = Vector2(32.0, 64.0)
	var hitbox_offset: Vector2 = Vector2(0.0, -8.0)
	var start_auto: bool = false

	var _started: bool = false
	var _box: Hitbox
	var _water: Node

	## 画预警（CombatMarker 区域框），必须在入树后调用。
	func spawn_warning() -> void:
		if telegraph <= 0.0:
			return
		CombatMarker.spawn(self, CombatMarker.Kind.ZONE, hitbox_offset, telegraph, color,
				{"rect": Rect2(-hitbox_size * 0.5, hitbox_size)})
		var visual := HazardVisual.new()
		visual.rect = Rect2(-hitbox_size * 0.5, hitbox_size)
		visual.color = Color(color.r, color.g, color.b, 0.18)
		add_child(visual)

	func trigger(_data: Dictionary = {}) -> void:
		if _started:
			return
		_started = true
		_run()

	func is_started() -> bool:
		return _started

	func _run() -> void:
		if get_tree() == null:
			return
		if telegraph > 0.0:
			await get_tree().create_timer(telegraph, false).timeout
		if not is_instance_valid(self) or not is_inside_tree():
			return
		if kind == KIND_WATER:
			_water = WaterZone.new()
			_water.name = "WaterZone"
			(_water as WaterZone).zone_size = hitbox_size
			(_water as WaterZone).flow = flow
			add_child(_water)
		else:
			_box = Hitbox.new()
			_box.name = "HazardHitbox"
			_box.damage = damage
			_box.team = &"enemy"
			_box.blow = &"heavy"
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = hitbox_size
			shape.shape = rect
			_box.add_child(shape)
			add_child(_box)
			_box.position = hitbox_offset
			_box.collision_layer = 8
			_box.collision_mask = 32
			_box.arm(Vector2(knockback.x, knockback.y))
			if kind == KIND_FIRE:
				Sfx.play_at(CombatRules.sfx_key(&"boss_axe_slam"), global_position, 0.1, -6.0)
			else:
				Sfx.play_at(CombatRules.sfx_key(&"land"), global_position, 0.1, -6.0)
		if get_tree() == null:
			return
		await get_tree().create_timer(active_time, false).timeout
		if is_instance_valid(_box):
			_box.disarm()
			_box.queue_free()
			_box = null
		if is_instance_valid(self):
			queue_free()


	class HazardVisual extends Node2D:
		var rect: Rect2 = Rect2()
		var color: Color = Color.WHITE

		func _ready() -> void:
			z_index = 5
			z_as_relative = true

		func _draw() -> void:
			draw_rect(rect, color, true)
			draw_rect(rect, Color(color.r, color.g, color.b, 0.9), false, 1.0)


	## 水流占位：站在水里会被往 flow 方向推（真实速度，不改玩家公式）。
	class WaterZone extends Area2D:
		var zone_size: Vector2 = Vector2(160.0, 64.0)
		var flow: Vector2 = Vector2(90.0, 0.0)
		var _bodies: Array[Node2D] = []

		func _ready() -> void:
			collision_layer = 0
			collision_mask = 2
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = zone_size
			shape.shape = rect
			add_child(shape)
			body_entered.connect(_on_body_entered)
			body_exited.connect(_on_body_exited)

		func _on_body_entered(body: Node2D) -> void:
			if not _bodies.has(body):
				_bodies.append(body)

		func _on_body_exited(body: Node2D) -> void:
			_bodies.erase(body)

		func _physics_process(delta: float) -> void:
			for body in _bodies:
				if is_instance_valid(body) and body is CharacterBody2D:
					(body as CharacterBody2D).velocity.x += flow.x * delta
