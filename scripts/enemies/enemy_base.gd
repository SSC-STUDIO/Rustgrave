class_name EnemyBase
extends CharacterBody2D
## 敌人通用基类：编组/血量接线、受击白闪、CharFrames 帧动画装配、
## 死亡演出（尸体帧或通用烟雾 + 锈屑/火花 + 播报）、巡逻折返移动。
## 子类只保留各自的状态机与特殊攻击；静止敌人（喷吐者）把 _mobile
## 置 false，基类不施重力、不 move_and_slide。
##
## 受击反应（硬直 / 后仰 / 击退倍率）取自 CombatRules.HIT_FEEL，按本敌人的
## hit_material 与出手分量查表；读招暗号、破绽标记、钩锁拽人也在这里统一提供。

## 开始读招时发出（kind 是 CombatRules.TELEGRAPH 的键，duration 是暗号亮起到判定出现的秒数）。
signal telegraph_started(kind: StringName, duration: float)

const GRAVITY := 980.0
## Overbright modulate clamps to a white silhouette in the LDR framebuffer,
## which reads as a hit flash for sprites and ColorRect bodies alike.
const FLASH_MODULATE := Color(6.0, 6.0, 6.0)
## 受击硬直（flesh / light 的基准值）：挡住状态机改 velocity，否则巡逻/冲锋下一帧就把击退盖掉。
const HURT_LOCK := 0.12
## 与玩家身体重叠时的挤开半径（像素）；不改玩家碰撞层，只推开重叠。
const BODY_SEPARATE_X := 16.0
const BODY_SEPARATE_Y := 26.0
## 钩锁拽到骑士面前停下的距离。
const YANK_STOP_DISTANCE := 26.0
## 破绽 / 拽人时标记贴在头顶的位置（子类按身高覆盖）。
const MARK_OFFSET := Vector2(0.0, -34.0)

@export var patrol_range: float = 64.0
@export var patrol_speed: float = 40.0
@export var drop_equipment: EquipmentItem = null
@export var drop_equipment_id: StringName = &""
@export_range(0.0, 1.0) var drop_equipment_chance: float = 1.0

var health: Health
var _dir: float = -1.0
var _anchor_x: float = 0.0
var _anim: FrameAnimSprite     # 有帧素材时非 null
var _flash_target: CanvasItem  # 受击白闪作用的节点（默认 $Visual）
var _flash_tween: Tween
var _recoil_tween: Tween
## 静止敌人置 false：跳过重力与 move_and_slide。
var _mobile := true
var _dead := false
var _hurt_lock: float = 0.0
var _recoil_home_x: float = 0.0
var _recoil_home_ready := false
## 受击材质（CombatRules.MATERIALS）：决定顿帧 / 火花 / 击退 / 硬直的矩阵行。
var hit_material: StringName = &"flesh"
## 最近一次读招的暗号键（测试 / 诊断读）。
var telegraph_kind: StringName = &""
var _riposte_left: float = 0.0
var _riposte_mark: CombatMarker
var _opening_mark: CombatMarker
var _yank_tween: Tween
var _knight_ref: Player


func _ready() -> void:
	add_to_group("enemies")
	_anchor_x = global_position.x
	health = get_node_or_null("Health") as Health
	if health != null:
		health.died.connect(_on_died)
	GameEvents.hit.connect(_on_hit)
	_flash_target = get_node_or_null("Visual") as CanvasItem
	_enemy_ready()


## 子类初始化钩子：设 max_hp、装配视觉、接特有信号等。
func _enemy_ready() -> void:
	pass


func is_hurt_locked() -> bool:
	return _dead or _hurt_lock > 0.0


## 缓存的骑士引用（场景重载后自动重取），避免每帧各敌人各自扫编组。
func knight() -> Player:
	if _knight_ref == null or not is_instance_valid(_knight_ref) or not _knight_ref.is_inside_tree():
		_knight_ref = get_tree().get_first_node_in_group("player") as Player
	return _knight_ref


func _physics_process(delta: float) -> void:
	if _dead:
		return
	# 过场锁玩家时敌人也停手，否则 Boss 介绍里仍会被砍/被射。
	if Director.is_input_locked():
		if _mobile:
			if not is_on_floor():
				velocity.y += GRAVITY * delta
			velocity.x = 0.0
			move_and_slide()
		return
	if _hurt_lock > 0.0:
		_hurt_lock = maxf(0.0, _hurt_lock - delta)
		if _mobile:
			if not is_on_floor():
				velocity.y += GRAVITY * delta
			move_and_slide()
			_after_move()
			_separate_from_player()
		return
	if not _mobile:
		_tick_state(delta)
		return
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	_tick_state(delta)
	move_and_slide()
	_after_move()
	_separate_from_player()


func _process(delta: float) -> void:
	tick_riposte(delta)


## 子类状态机步进（move_and_slide 之前）。
func _tick_state(_delta: float) -> void:
	pass


## move_and_slide 之后的收尾（更新朝向/动画等）。
func _after_move() -> void:
	pass


## 巡逻折返：先按边界/撞墙修正方向，再赋速度。
## （bug fix）旧实现先赋速再翻向，越界帧速度仍朝外、下一帧又满足越界条件
## 再翻一次，敌人会在巡逻边界原地两帧振荡；改为越界时直接把方向定为
## "朝锚点回走"，判定收敛、不再抖动。
func _patrol_step() -> void:
	if global_position.x < _anchor_x - patrol_range:
		_dir = 1.0
	elif global_position.x > _anchor_x + patrol_range:
		_dir = -1.0
	elif is_on_wall():
		_dir = -_dir
	velocity.x = _dir * patrol_speed


## 受击白闪：闪至过曝白再落回 _flash_restore_color()（喷吐者蓄力时覆写）。
func _flash_white() -> void:
	if _flash_target == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_target, "modulate", FLASH_MODULATE, 0.03)
	_flash_tween.tween_interval(0.06)
	_flash_tween.tween_property(_flash_target, "modulate", _flash_restore_color(), 0.10)


func _flash_restore_color() -> Color:
	return Color.WHITE


func _on_hit(attacker: Node, target: Node, amount: int) -> void:
	if target != self or _dead:
		return
	_flash_white()
	if amount <= 0:
		return
	var killed := health != null and health.current <= 0
	var row := CombatRules.feel(hit_material, CombatRules.weight_for(attacker, amount, killed))
	_hurt_lock = maxf(_hurt_lock, float(row["lock"]))
	_pixel_recoil(attacker, float(row["recoil"]))


## 受击往攻击者反方向挪 px 像素，再弹回。只动视觉节点，不改碰撞原点。
func _pixel_recoil(attacker: Node, px: float = 2.0) -> void:
	if _flash_target == null or px <= 0.0:
		return
	if not _recoil_home_ready:
		_recoil_home_x = _flash_target.position.x
		_recoil_home_ready = true
	var dir := -_dir
	if attacker is Node2D:
		var ax := (attacker as Node2D).global_position.x
		if absf(ax - global_position.x) > 0.5:
			dir = signf(global_position.x - ax)
	if dir == 0.0:
		dir = -1.0
	if _recoil_tween != null and _recoil_tween.is_valid():
		_recoil_tween.kill()
	_flash_target.position.x = _recoil_home_x + dir * px
	_recoil_tween = create_tween()
	_recoil_tween.tween_property(_flash_target, "position:x", _recoil_home_x, 0.10)


## 中心距超过这个范围就不再挤人。X 是脚点之间的横向净空，Y 是脚点之间的竖向净空
## （脚必须抬过身体顶才算跳过去）。重甲子类按自己的躯干覆盖。
func body_clearance() -> Vector2:
	return Vector2(BODY_SEPARATE_X, BODY_SEPARATE_Y)


## 玩家与敌人互相不在对方 collision_mask 里，会穿模。从敌人侧把重叠的玩家挤开，
## 不改玩家移动公式、也不让冲锋把玩家当成墙。
func _separate_from_player() -> void:
	if not _mobile:
		return
	var player := knight()
	if player == null or player.is_invincible():
		return
	var to_p := player.global_position - global_position
	var clear := body_clearance()
	if absf(to_p.x) > clear.x or absf(to_p.y) > clear.y:
		return
	var push := signf(to_p.x)
	if push == 0.0:
		push = -_dir if _dir != 0.0 else 1.0
	if absf(player.velocity.x) < 90.0 or signf(player.velocity.x) != push:
		player.velocity.x = push * 88.0


# ---------------------------------------------------------------------------
# 破绽（弹反协同）：被弹回的弹丸打中 / 被盾挡下后，窗口内玩家近战第一击翻倍。
# ---------------------------------------------------------------------------
func is_marked() -> bool:
	return _riposte_left > 0.0


func riposte_left() -> float:
	return _riposte_left


## 打开破绽窗口：头顶出现青色菱形；非盾类敌人同时吃一小段硬直。
func open_riposte(duration: float = CombatRules.RIPOSTE_TIME) -> void:
	if _dead:
		return
	_riposte_left = maxf(_riposte_left, duration)
	if _riposte_mark == null or not is_instance_valid(_riposte_mark):
		_riposte_mark = CombatMarker.spawn(self, CombatMarker.Kind.RIPOSTE, _mark_offset(),
				0.0, Color(0.6, 1.4, 1.7, 1.0))
	_on_riposte_opened()


## 子类可覆盖（盾类已有自己的硬直）。
func _on_riposte_opened() -> void:
	_hurt_lock = maxf(_hurt_lock, CombatRules.RIPOSTE_STAGGER)


## 取走破绽：返回下一击的伤害倍率（没有标记返回 1）。窗口立刻关闭。
func consume_riposte() -> int:
	if _riposte_left <= 0.0:
		return 1
	_clear_riposte()
	Fx.burst(&"ring", hit_point())
	return CombatRules.RIPOSTE_MULT


func tick_riposte(delta: float) -> void:
	if _riposte_left <= 0.0:
		return
	_riposte_left = maxf(0.0, _riposte_left - delta)
	if _riposte_left <= 0.0:
		_clear_riposte()


func _clear_riposte() -> void:
	_riposte_left = 0.0
	if _riposte_mark != null and is_instance_valid(_riposte_mark):
		_riposte_mark.dismiss()
	_riposte_mark = null


func _mark_offset() -> Vector2:
	return MARK_OFFSET


## 命中点（Fx / 钩锁瞄准用）：Hurtbox 中心，没有就取身体中部。
func hit_point() -> Vector2:
	var hurt := get_node_or_null("Hurtbox") as Node2D
	if hurt != null:
		return hurt.global_position
	return global_position + Vector2(0.0, -14.0)


# ---------------------------------------------------------------------------
# 钩锁拽人：小型敌人被拉到骑士面前，硬直并露出破绽（重甲 / 首领不吃）。
# ---------------------------------------------------------------------------
func is_yankable() -> bool:
	return false


func yank_to(point: Vector2, duration: float = 0.22) -> bool:
	if _dead or not is_yankable():
		return false
	if _yank_tween != null and _yank_tween.is_valid():
		_yank_tween.kill()
	velocity = Vector2.ZERO
	_hurt_lock = maxf(_hurt_lock, duration + CombatRules.RIPOSTE_STAGGER)
	_yank_tween = create_tween()
	_yank_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_yank_tween.tween_property(self, "global_position", point, duration)
	_yank_tween.tween_callback(open_riposte)
	return true


# ---------------------------------------------------------------------------
# 读招 / 破绽提示
# ---------------------------------------------------------------------------
## 宣告一次读招：发信号（测试与旁观者读）；暗号的具体画面由各敌人自己做。
func begin_telegraph(kind: StringName, duration: float) -> void:
	telegraph_kind = kind
	telegraph_started.emit(kind, duration)


## 出招后露出破绽：头顶一个金色箭头，持续 duration 秒。
func show_opening(duration: float) -> void:
	if _dead or duration <= 0.0:
		return
	if _opening_mark != null and is_instance_valid(_opening_mark):
		_opening_mark.dismiss()
	_opening_mark = CombatMarker.spawn(self, CombatMarker.Kind.OPENING, _mark_offset(),
			duration, Palette.EMBER)


func hide_opening() -> void:
	if _opening_mark != null and is_instance_valid(_opening_mark):
		_opening_mark.dismiss()
	_opening_mark = null


## 装配 CharFrames 帧动画。specs 每行 [动作名, 帧目录名("" = 同动作名),
## fps, 是否循环, 基线位置]。素材缺失返回 null，调用方自行回退占位视觉。
func _build_frame_anim(char_name: String, specs: Array) -> FrameAnimSprite:
	if not CharFrames.available(char_name):
		return null
	var anim := FrameAnimSprite.new()
	anim.name = "BodySprite"
	for spec in specs:
		var action := String(spec[1])
		if action == "":
			action = String(spec[0])
		anim.register(String(spec[0]), CharFrames.anim(char_name, action),
				float(spec[2]), bool(spec[3]), spec[4])
	return anim


## 帧动画自带造型：隐藏容器下的占位色块。
static func _hide_placeholder_rects(container: Node) -> void:
	for c in container.get_children():
		if c is ColorRect:
			c.visible = false


func _try_drop_equipment() -> void:
	if drop_equipment == null and drop_equipment_id == &"":
		return
	if drop_equipment_chance < 1.0 and randf() > drop_equipment_chance:
		return

	var item: EquipmentItem = drop_equipment
	if item == null and drop_equipment_id != &"" and ResourceLoader.exists("res://scripts/data/equipment_catalog.gd"):
		var catalog: GDScript = load("res://scripts/data/equipment_catalog.gd")
		if catalog != null and catalog.has_method("for_id"):
			item = catalog.call("for_id", drop_equipment_id)
	if item == null:
		return

	var parent_node := get_parent()
	if parent_node == null:
		return

	var pickup_name := "EquipDrop_%s" % name
	var saved_path := SaveData.persist_path(self).get_base_dir() + "/" + pickup_name
	if SaveData.is_consumed(saved_path):
		return

	if not ResourceLoader.exists("res://scenes/interactables/EquipmentPickup.tscn"):
		return
	var pickup_scene: PackedScene = load("res://scenes/interactables/EquipmentPickup.tscn")
	if pickup_scene == null:
		return

	var pickup = pickup_scene.instantiate()
	pickup.name = pickup_name
	if "item" in pickup:
		pickup.set("item", item)
	pickup.position = position + Vector2(0, -8)
	parent_node.add_child(pickup)


## 死亡通用演出：尸体帧动画（空帧列表退化为通用烟雾）+ 锈屑 + 火花 +
## 播报，最后 queue_free。掉落物等差异由子类在调用前自行生成。
func _death_burst(frames: Array[Texture2D], fps: float, flip: bool,
		baseline: float, message: String) -> void:
	_try_drop_equipment()
	_disable_combat()
	if frames.is_empty():
		Fx.enemy_death_smoke(global_position)
	else:
		Fx.play_frames_once(frames, global_position, fps, flip, baseline)
	Fx.rust_debris(global_position)
	Fx.hit_sparks(global_position)
	if message != "":
		GameEvents.announcement.emit(message)
	Sfx.play_at(CombatRules.sfx_key(&"enemy_die"), global_position)
	queue_free()


## 死亡当帧立刻收刀：关掉 hit/hurt、去掉身体碰撞，并挡住本帧剩余 AI。
func _disable_combat() -> void:
	_dead = true
	_hurt_lock = 0.0
	_riposte_left = 0.0
	velocity = Vector2.ZERO
	collision_layer = 0
	collision_mask = 0
	if _yank_tween != null and _yank_tween.is_valid():
		_yank_tween.kill()
	for node in get_children():
		if node is Hitbox or node is Hurtbox:
			var area := node as Area2D
			area.monitoring = false
			area.monitorable = false
			area.collision_layer = 0
			area.collision_mask = 0


## 子类死亡回调（health.died）。
func _on_died() -> void:
	_death_burst([] as Array[Texture2D], 12.0, false, 0.0, "")
