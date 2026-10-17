class_name HookshotTether
extends Node2D
## 钩锁（Hookshot Tether）：按 F 朝面朝方向斜上方寻找锚点，
## 命中后把玩家匀速拉向锚点，接近时自动脱钩并向上弹起。
## 纯移动能力 —— 不改伤害/判定数值。


@export var max_range: float = 260.0
@export var pull_speed: float = 430.0
@export var release_radius: float = 26.0
@export var cooldown: float = 0.45
@export var release_pop: float = -170.0
## 出索方向允许的偏差（与面朝向+略朝上的向量做点积阈值）。
const AIM_DOT_MIN := 0.25
const ROPE_ORIGIN := Vector2(0.0, -48.0)

## 战斗里的钩锁：没有锚点可钩时，瞄准锥内的小型敌人（EnemyBase.is_yankable）会被拽到骑士面前，
## 吃一小段硬直并露出破绽（下一刀翻倍）。重甲 / 首领不吃。
const YANK_REACH := 180.0
## 拽人的瞄准锥比锚点宽一点：战斗里没人会精确对准一只会动的敌人。
const YANK_AIM_DOT_MIN := 0.55
const YANK_STOP_DISTANCE := 26.0
const YANK_ROPE_TIME := 0.22

var _anchor: Node2D = null
var _cooldown_left: float = 0.0
var _rope: Line2D
var _yank_target: Node2D = null
var _yank_left: float = 0.0


func _ready() -> void:
	_rope = Line2D.new()
	_rope.name = "Rope"
	_rope.width = 2.5
	_rope.default_color = Palette.TEAL
	_rope.visible = false
	_rope.z_index = 5
	add_child(_rope)
	GameEvents.hit.connect(_on_game_hit)


func is_active() -> bool:
	return _anchor != null and is_instance_valid(_anchor)


func _process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	_tick_yank_rope(delta)
	if not is_active():
		return
	# 绳索：从手部到锚点，中点略微下垂。
	var from := ROPE_ORIGIN
	var to := to_local(_anchor.global_position)
	var mid := (from + to) * 0.5 + Vector2(0.0, clampf(from.distance_to(to) * 0.05, 0.0, 9.0))
	_rope.points = PackedVector2Array([from, mid, to])


func try_fire(player: Player) -> bool:
	if is_active() or _cooldown_left > 0.0:
		return false
	if player.inventory.has_pair(AbilityIds.HEAT_FORGE, AbilityIds.HOOKSHOT_TETHER):
		if _try_melt_hook(player):
			return true
	var anchor := _pick_anchor(player)
	if anchor == null:
		return _try_yank(player)
	_anchor = anchor
	_rope.visible = true
	Sfx.play_at(CombatRules.sfx_key(&"hook_fire"), anchor.global_position)
	Fx.hit_sparks(anchor.global_position)
	return true


## 战斗用法：把瞄准锥里最合适的小型敌人拽到骑士面前。只在按下钩锁键时扫一次编组。
func _try_yank(player: Player) -> bool:
	var target := _pick_yank_target(player)
	if target == null:
		return false
	var face := signf(player.visual.scale.x)
	if face == 0.0:
		face = 1.0
	# 敌人保持自己的高度（飞行的拽到骑士胸前，地面的仍踩在原来的台面上）。
	var stop := Vector2(player.global_position.x + face * YANK_STOP_DISTANCE, target.global_position.y)
	if not (target as EnemyBase).yank_to(stop):
		return false
	_yank_target = target
	_yank_left = YANK_ROPE_TIME
	_rope.visible = true
	_set_cooldown()
	Sfx.play_at(CombatRules.sfx_key(&"hook_fire"), player.global_position)
	Sfx.play_at(CombatRules.sfx_key(&"hook_hit"), target.global_position)
	Fx.hit_sparks(target.global_position + Vector2(0.0, -14.0))
	return true


func _pick_yank_target(player: Player) -> Node2D:
	var origin := player.global_position + ROPE_ORIGIN
	var aim := _aim_dir(player)
	var reach := minf(_hook_reach(player), YANK_REACH)
	var best: Node2D = null
	var best_score := -1.0
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyBase
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_yankable():
			continue
		var point := enemy.hit_point()
		var to := point - origin
		var dist := to.length()
		if dist > reach or dist < YANK_STOP_DISTANCE:
			continue
		var score := (to / dist).dot(aim)
		if score < YANK_AIM_DOT_MIN or not _has_line_of_sight(origin, point):
			continue
		if score > best_score:
			best_score = score
			best = enemy
	return best


## 拽人时的绳子：只亮一瞬，从手到敌人；敌人先被释放就收绳。
func _tick_yank_rope(delta: float) -> void:
	if _yank_left <= 0.0:
		return
	_yank_left = maxf(0.0, _yank_left - delta)
	if _yank_left <= 0.0 or _yank_target == null or not is_instance_valid(_yank_target):
		_yank_target = null
		_yank_left = 0.0
		if not is_active():
			_rope.visible = false
		return
	var from := ROPE_ORIGIN
	var to := to_local((_yank_target as EnemyBase).hit_point())
	var mid := (from + to) * 0.5 + Vector2(0.0, clampf(from.distance_to(to) * 0.05, 0.0, 9.0))
	_rope.points = PackedVector2Array([from, mid, to])


func yank_rope_active() -> bool:
	return _yank_left > 0.0


func cooldown_left() -> float:
	return _cooldown_left


func _try_melt_hook(player: Player) -> bool:
	var gate := _pick_melt_gate(player)
	if gate == null:
		return false
	gate.melt(player)
	Fx.hit_sparks(gate.global_position)
	return true


func _pick_melt_gate(player: Player) -> RustyGate:
	var origin := player.global_position + ROPE_ORIGIN
	var aim := _aim_dir(player)
	var reach := _hook_reach(player)
	var best: RustyGate = null
	var best_score := -1.0
	for node in get_tree().get_nodes_in_group("rusty_gate"):
		var gate := node as RustyGate
		if gate == null or not is_instance_valid(gate):
			continue
		var to := gate.global_position - origin
		var dist := to.length()
		if dist > reach or dist < 8.0:
			continue
		var dir := to / dist
		var score := dir.dot(aim)
		if score < AIM_DOT_MIN:
			continue
		if not _has_line_of_sight(origin, gate.global_position, gate):
			continue
		if score > best_score:
			best_score = score
			best = gate
	return best


func _hook_reach(player: Player) -> float:
	return max_range * float(CombatRules.toxin_tier(player.toxin.band())["hook"])


func _aim_dir(player: Player) -> Vector2:
	return Vector2(signf(player.visual.scale.x), -0.35).normalized()


## 每物理帧由 Player 在 controller 之后调用：直接接管速度。
func apply_tether_velocity(player: CharacterBody2D) -> void:
	if not is_active():
		_release()
		return
	var to_anchor := _anchor.global_position - player.global_position
	var dist := to_anchor.length()
	# 跳跃键提前脱钩 / 撞墙强制脱钩。
	if Input.is_action_just_pressed("jump") or player.is_on_wall():
		_pop_off(player, to_anchor)
		return
	if dist <= release_radius:
		_pop_off(player, to_anchor)
		return
	player.velocity = to_anchor / dist * pull_speed


func _pop_off(player: CharacterBody2D, to_anchor: Vector2) -> void:
	var dir_x := signf(to_anchor.x) if absf(to_anchor.x) > 4.0 else 0.0
	player.velocity.x = player.velocity.x * 0.5 + dir_x * 130.0
	player.velocity.y = release_pop
	Fx.dust_puff(player.global_position + Vector2(0.0, -40.0))
	Sfx.play(&"jump")
	if player is Player:
		var knight := player as Player
		if knight.inventory.has_pair(AbilityIds.HOOKSHOT_TETHER, AbilityIds.EMBER_STEP):
			knight.controller.grant_air_jump()
			player.velocity.y = knight.controller.jump_velocity * knight.controller.extra_jump_scale
	_release()


func _release() -> void:
	_anchor = null
	_rope.visible = false
	_set_cooldown()


## 冷却：共鸣窗口里减半（弹反的回报之一）。
func _set_cooldown() -> void:
	var cd := cooldown
	var host := get_parent()
	if host is Player and (host as Player).resonance.is_active():
		cd *= 0.5
	_cooldown_left = cd


func _pick_anchor(player: Player) -> Node2D:
	var origin := player.global_position + ROPE_ORIGIN
	var aim := _aim_dir(player)
	var reach := _hook_reach(player)
	var best: Node2D = null
	var best_score := -1.0
	for node in get_tree().get_nodes_in_group("hook_anchor"):
		var anchor := node as Node2D
		if anchor == null:
			continue
		var to := anchor.global_position - origin
		var dist := to.length()
		if dist > reach or dist < 8.0:
			continue
		var dir := to / dist
		var score := dir.dot(aim)
		if score < AIM_DOT_MIN:
			continue
		if not _has_line_of_sight(origin, anchor.global_position, anchor):
			continue
		if score > best_score:
			best_score = score
			best = anchor
	return best


func _has_line_of_sight(from: Vector2, to: Vector2, target: Node = null) -> bool:
	# 只查世界层（mask=1），玩家/敌人/锚点都不会挡道。
	# 命中目标自身（锈门的 Solid 也在 layer 1）仍算视线通。
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	if target == null:
		return false
	var collider: Variant = hit.get("collider")
	if collider == target:
		return true
	return collider is Node and target.is_ancestor_of(collider)


func _on_game_hit(_attacker: Node, target: Node, _amount: int) -> void:
	# 受击打断钩索（表现层接管，不影响伤害结算）。
	if target == owner and is_active():
		_release()
