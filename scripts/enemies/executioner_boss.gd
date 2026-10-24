class_name ExecutionerBoss
extends GearShieldEnemy
## 锻炉残室的刽子手。保留正面盾规则；半血后射弹加密并挥斧。
##
## 原创像素帧见 tools/art/gen_original_executioner_nightmare.py；不再复用盾卫。
## 100×100 帧按整数 2 倍绘制（BOSS_SCALE，脚点仍在节点原点 y=0），
## 身体 / 受击盒 / 斩击落点随之同比放大 —— 判定关系与读招表不变，画面与判定
## 仍然同位同尺寸。身后一团有上限的加法背光把暗剪影从暗背景里剥出来，脚下有
## 接地阴影；进场时背光涌一下，二阶段转红热（斧上挂余烬），倒地后熄灭。
## 全部是表现层：不改输入、不改时间、不写存档。

signal slain

enum SlashPhase { NONE, ACTIVE, RECOVERY }
const SLASH_WINDUP := 0.52
const SLASH_ACTIVE := 0.16
const SLASH_RECOVERY := 0.65
## 与 boss_appeared / boss_intro_started / boss_phase_changed 共用的显示名。
## 不加字间空格：StoryStage 用 `boss_name.contains("刽子手")` 判断「第一章自己演」，
## 有空格的标题会让它把通用 Boss 登场再叠在拱门入场前面（两段镜头连播）。
## 名号卡自己会把 "·" 前面压成「炉约刽子手」，显示不受影响。
const BOSS_TITLE := "炉约刽子手 · 铸渣残躯"

const BOSS_CHAR := "original_executioner"
## 保留原有整数2倍画幅、身体、受击与挥斧判定契约。
const BOSS_SCALE := 2
## 帧基线：原图脚底距画布底边 16.5px、身体中线在画布 x≈56.5。1x 是 EXEC_POS(6,-34)，
## 2x 用 (13,-66) 让画出来的脚正好落在节点原点、身体中线落在 x=0（翻转由 Visual 负责）。
const BOSS_EXEC_POS := Vector2(13.0, -66.0)
## 尸体帧（centered Sprite）的基线：脚底在画布底边上方 33px，2 倍后 66px。
const BOSS_DEATH_BASELINE := -66.0
## 与 2× 画幅匹配的碰撞 / 受击盒：脚在 y=0，向上长。
const BOSS_BODY_SIZE := BODY_SIZE * BOSS_SCALE     # 56×96
const BOSS_HURT_SIZE := HURT_SIZE * BOSS_SCALE     # 72×120
## 帧素材的主色几乎是纯黑（#0E0C0C），夜色 CanvasModulate 一乘就只剩剪影。
## 这里把整只 Body 的 modulate 抬到「暗剪影里仍读得出兜帽 / 甲片 / 斧柄」，
## 二阶段再往炉火色偏。数值 < 骑士的明度：Boss 永远比骑士暗，只是不再糊成黑洞。
const BODY_LIFT := Color(1.12, 1.08, 1.03)
const BODY_LIFT_HOT := Color(1.18, 0.98, 0.84)
## 斩击落点框：宽度随斧的画幅放大，仍贴地（底边 -4）、与判定盒同位同尺寸。
const SLASH_ZONE_OFFSET := Vector2(22.0 * BOSS_SCALE, -18.0)   # (44,-18)
const SLASH_ZONE_SIZE := Vector2(36.0 * BOSS_SCALE, 28.0)      # 72×28
const SLASH_ZONE_COLOR := Color(1.0, 0.42, 0.18, 0.95)
## 挥斧的出手距离：斧的判定变宽后同比放宽，读招空间不缩水。
const SLASH_TRIGGER_RANGE := 78.0 * BOSS_SCALE
## 二阶段开场的吼叫：这段时间里不开新的斩 / 射，让玩家看清相变。
const PHASE_ROAR_TIME := 0.6

# --- 炉膛终局（phase 2 finale，<=20% HP 的一次性高潮） ---------------------------
## 框架测试锁死本 Boss 的 Kit 为 2 阶段，所以终局做成「等价高潮」：不改阶段刻度，
## 在 <=20% 生命时触发一次炉膛终局演出，并解锁三招终局招（震地波 / 抓取处决 / 炉膛火柱）。
## 三招都进二阶段攻击表（windup >= 0.35s，契约可读性），由本脚本的终局状态机逐条执行；
## 同一时刻只有一条预警（斩 / 射 / 终局招互斥）。
const FINAL_STAND_RATIO := 0.20
const FINAL_FIRST_DELAY := 1.6
const FINAL_COOLDOWN := 3.0
## 震地波：举斧砸地，两道火浪沿地面向两侧推进（跳跃可躲）。
const WAVE_WINDUP := 0.60
const WAVE_ACTIVE := 0.20
const WAVE_RECOVERY := 0.55
const WAVE_DAMAGE := 2
const WAVE_SIZE := Vector2(24.0, 22.0)
const WAVE_SPEED := 210.0
const WAVE_REACH := 240.0
const WAVE_TRIGGER_RANGE := 260.0
const WAVE_ZONE_COLOR := Color(1.0, 0.52, 0.20, 0.95)
## 抓取处决：0.9s 的「斩」预警，红光框盖住身前，被抓住 = 3 点重击。
const GRAB_WINDUP := 0.90
const GRAB_ACTIVE := 0.18
const GRAB_RECOVERY := 0.70
const GRAB_DAMAGE := 3
const GRAB_ZONE_OFFSET := Vector2(46.0, -22.0)
const GRAB_ZONE_SIZE := Vector2(60.0, 44.0)
const GRAB_TRIGGER_RANGE := 120.0
const GRAB_COLOR := Color(1.0, 0.86, 0.55, 0.98)
## 炉膛火柱：场地里的炉口喷火（每招一条落点预警，柱子从地面冲到胸高）。
const PILLAR_WINDUP := 0.55
const PILLAR_ACTIVE := 0.30
const PILLAR_RECOVERY := 0.60
const PILLAR_DAMAGE := 1
const PILLAR_SIZE := Vector2(26.0, 86.0)
const PILLAR_SPACING := 140.0
const PILLAR_COLOR := Color(1.0, 0.55, 0.22, 0.95)
## 背光 / 接地阴影的调色（art-spec 调色板族：Ember / Toxic Glow / Rust Shadow）
## 与加法背光 alpha 上限（特效不遮挡：再亮就把剪影洗白）都在 BossPresence 里。

## 竞技场横向边界（世界 x）。-INF / INF = 不限制：第一章的竞技场边界由东翼铺地承担，
## 这里只给 BossArena / 夹具一个统一的读取口（契约 §4.1）。
@export var arena_left: float = -INF
@export var arena_right: float = INF

var _enraged := false
var _slash_next := false
var _slash_cd := 0.0
var _intro_announced := false
var _slash_phase: SlashPhase = SlashPhase.NONE
var _slash_timer := 0.0
var _slash_box: Hitbox
var _roar_left := 0.0
var _presence: BossPresence
## Boss 框架（契约 §4.1）：攻击表 / 阶段 / 场地事件的数据与观测。
var _boss_kit: BossKit
var _boss_director: BossDirector
# --- 炉膛终局状态 ---
enum FinalPhase { NONE, WINDUP, ACTIVE, RECOVERY }
var _final_stand := false
var _final_phase: FinalPhase = FinalPhase.NONE
var _final_id: StringName = &""
var _final_timer := 0.0
var _final_cd := 0.0
var _final_marker: CombatMarker
var _final_box: Hitbox
var _pillar_cursor := 0
var _pillar_spots: Array[float] = []
var _pillar_target := 0.0


func is_enraged() -> bool:
	return _enraged


## 2× 画幅下的身体净空：横向半宽 + 骑士半宽，竖向要跳过胸口。
func body_clearance() -> Vector2:
	return Vector2(BOSS_BODY_SIZE.x * 0.5 + 7.0, BOSS_BODY_SIZE.y)


## 画出来的脚底相对节点原点的 y（测试 / 诊断用）：0 表示脚踩在地面上。
func drawn_feet_offset() -> float:
	if _anim == null:
		return 0.0
	return _anim.position.y + 33.0 * _anim.scale.y


func _enemy_ready() -> void:
	super._enemy_ready()
	hit_material = &"boss"
	health.max_hp = 13
	health.heal_full()
	health.changed.connect(_on_hp_changed)
	shoot_interval = 2.0
	aggro_range = 360.0
	if _anim != null:
		if CharFrames.available(BOSS_CHAR, "attack"):
			var frames := CharFrames.anim(BOSS_CHAR, "attack")
			_anim.register("slash", frames, float(frames.size()) / (SLASH_WINDUP + SLASH_ACTIVE), false, BOSS_EXEC_POS)
		if CharFrames.available(BOSS_CHAR, "skill"):
			_anim.register("skill", CharFrames.anim(BOSS_CHAR, "skill"), 10.0, false, BOSS_EXEC_POS)
	_apply_body_lift()
	_build_presence()
	_build_boss_framework()


## 受击白闪的收尾色：不是纯白，而是本相位的「可读暗剪影」色，闪完仍有层次。
func _flash_restore_color() -> Color:
	return _body_lift()


func _body_lift() -> Color:
	return BODY_LIFT_HOT if _enraged else BODY_LIFT


## 把暗帧抬进可读区间。作用在 Visual 上（子节点 anim 的 modulate 留给格挡 / 前摇染色）。
func _apply_body_lift() -> void:
	if visual != null:
		visual.modulate = _body_lift()


## 原创闭面葬甲、碑盾和裂刃巨斧；基线兼容原有2倍画幅。
func _build_visual() -> void:
	_indicator = shield
	_anim = _build_frame_anim(BOSS_CHAR, [
		["idle", "", 8.0, true, BOSS_EXEC_POS],
		["block", "idle2", 8.0, true, BOSS_EXEC_POS],
		# 蓄力施法 5 帧铺满整个 charge_time，最后一帧正好是释放。
		["charge", "summon", 5.0 / maxf(charge_time, 0.1), false, BOSS_EXEC_POS],
	])
	if _anim == null:
		return
	# 整数 2 倍：每个源像素变成 2×2 世界像素，脚点仍在 Visual 原点。
	_anim.scale = Vector2(BOSS_SCALE, BOSS_SCALE)
	_anim.play("idle")
	# 原图面朝左；Visual 的 scale.x=1 约定为面朝右（盾在 +x 侧），先水平翻转。
	_anim.flip_h = true
	visual.add_child(_anim)
	visual.move_child(_anim, 0)
	_hide_placeholder_rects(visual)
	shield.visible = false
	_indicator = _anim


## 与 2× 画幅同步的躯干 / 受击盒（每只 Boss 单独的 Shape，不动共享资源）。
func _fit_silhouette() -> void:
	var body := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if body != null:
		var rect := RectangleShape2D.new()
		rect.size = BOSS_BODY_SIZE
		body.shape = rect
		body.position = Vector2(0.0, -BOSS_BODY_SIZE.y * 0.5)
	if hurtbox == null:
		return
	var hurt_shape := hurtbox.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if hurt_shape == null:
		return
	var hurt_rect := RectangleShape2D.new()
	hurt_rect.size = BOSS_HURT_SIZE
	hurt_shape.shape = hurt_rect
	hurtbox.position = Vector2(0.0, -BOSS_HURT_SIZE.y * 0.5)


## Boss 血条只在骑士跨进拱门（或先手打到他）时出现；以前在第一帧就弹出来，
## 玩家还在余烬高台上就顶着一条 Boss 血条。
func announce() -> void:
	if _intro_announced:
		return
	_intro_announced = true
	# 先发「开场开始」（音乐 / 演出据此起势），紧接着才是 Boss 血条。
	GameEvents.boss_intro_started.emit(BOSS_TITLE)
	GameEvents.boss_appeared.emit(BOSS_TITLE, health.current, health.max_hp)
	# 框架侧：开战场地事件（舞台灯 / 机关）由 kit 的 arena_events 统一登记。
	if _boss_director != null:
		_boss_director.notify_intro()


func is_announced() -> bool:
	return _intro_announced


func _on_hp_changed(current: int, maximum: int) -> void:
	announce()
	GameEvents.boss_hp_changed.emit(current, maximum)
	# 阶段语义不变：生命 <= 一半且还没狂暴时进入二阶段（原逻辑的唯一分支）。
	if not _enraged and maximum > 0 and current > 0 and current <= maximum / 2:
		_enter_phase_two()
	# 20% 终局高潮：一次性门口（不改 Kit 阶段，HUD 仍是 2 相刻度）。
	if not _final_stand and maximum > 0 and current > 0 \
			and float(current) / float(maximum) <= FINAL_STAND_RATIO:
		_enter_final_stand()
	_sync_boss_framework(current, maximum)


## 炉膛终局：<=20% 生命的一次性高潮。演出是可跳过的（不进 Director，只走
## Juice / announcement / 背光，不锁输入）；随后解锁震地波 / 抓取处决 / 炉膛火柱。
func _enter_final_stand() -> void:
	_final_stand = true
	_final_phase = FinalPhase.NONE
	_final_cd = FINAL_FIRST_DELAY
	shoot_interval = 0.85
	Juice.boss_phase_beat(global_position + Vector2(0.0, -30.0), Color(1.0, 0.45, 0.16))
	Juice.shake(4.0, 260)
	Sfx.play_at(&"boss_roar", global_position, 0.03, -1.0)
	Fx.attach_heat_lick(visual)
	var lick := visual.get_node_or_null(Fx.HEAT_LICK_NAME)
	if lick is Node2D:
		(lick as Node2D).position = Vector2(34.0, -58.0)
	if _presence != null:
		_presence.set_hot(true)
		_presence.surge(1.4)
	if visual != null and is_inside_tree() and get_tree() != null:
		var tint := create_tween()
		tint.tween_property(visual, "modulate", BODY_LIFT_HOT, 0.3)
	else:
		_apply_body_lift()
	GameEvents.announcement.emit("炉膛裂了。他不再收斧。")
	_build_pillar_spots()


## 终局招的炉口位置：沿竞技场中线摆三处，Boss 站的那格除外（避免脚下立刻喷）。
func _build_pillar_spots() -> void:
	_pillar_spots.clear()
	var center := global_position.x
	var bounds := boss_arena_bounds()
	var usable := is_finite(bounds.x) and is_finite(bounds.y) and bounds.y > bounds.x
	var candidates := [center - PILLAR_SPACING, center, center + PILLAR_SPACING]
	for x in candidates:
		if usable and (x < bounds.x + 24.0 or x > bounds.y - 24.0):
			continue
		if absf(x - center) < 40.0:
			continue
		_pillar_spots.append(x)
	if _pillar_spots.is_empty():
		_pillar_spots.append(center)


## 二阶段：相变演出（短慢动作 + 震屏 + 圆环 + 受 Settings 缩放的闪色 + 吼叫）、
## 余烬从斧上升起（一直挂着，远处也能认出他变了），背光转红热，随后一小段吼叫
## 硬直再开新招。不改输入锁 / 暂停 —— 镜头与慢放分别由 Director / Juice 负责。
func _enter_phase_two() -> void:
	_enraged = true
	shoot_interval = 1.15
	_roar_left = PHASE_ROAR_TIME
	Juice.boss_phase_beat(global_position + Vector2(0.0, -30.0), Palette.EMBER)
	Fx.attach_heat_lick(visual)
	# Fx 里斧上余烬写的是 1× 位置；2× 画幅把它挪到斧头附近，别从斗篷中间冒。
	var lick := visual.get_node_or_null(Fx.HEAT_LICK_NAME)
	if lick is Node2D:
		(lick as Node2D).position = Vector2(34.0, -58.0)
	if _presence != null:
		_presence.set_hot(true)
		_presence.surge(1.15)
	# 相变时身体也往炉火色偏：同一条剪影，但一眼看出「他烧起来了」。
	if visual != null and is_inside_tree() and get_tree() != null:
		var tint := create_tween()
		tint.tween_property(visual, "modulate", BODY_LIFT_HOT, 0.35)
	else:
		_apply_body_lift()
	GameEvents.announcement.emit("炉渣在他的斧上重新沸腾")
	GameEvents.boss_phase_changed.emit(BOSS_TITLE, 2)


## 守芯者站在拱门后的灯下，不在门前踱步：Boss 的位置是竞技场构图的中心，
## 2× 剪影漂到两侧火膛上会把「门 → 他 → 残芯」这条轴读乱。靠近才抬头。
func _tick_patrol(delta: float) -> void:
	_set_blocking(false)
	velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
	var player := knight()
	if player != null and global_position.distance_to(player.global_position) < aggro_range:
		_enter_block(player)


func _tick_block(delta: float) -> void:
	if _roar_left > 0.0:
		# 吼叫中：站定举盾，不开新招。
		_roar_left = maxf(0.0, _roar_left - delta)
		velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
		_set_blocking(true)
		return
	if _final_stand:
		# 终局：三招轮转优先于斩 / 射；每招一条预警，执行期间不再起别的招。
		_final_cd = maxf(0.0, _final_cd - delta)
		if _final_cd <= 0.0:
			_begin_final_move()
			return
	_slash_cd = maxf(0.0, _slash_cd - delta)
	var player := knight()
	if player != null and _slash_cd <= 0.0 \
			and global_position.distance_to(player.global_position) < SLASH_TRIGGER_RANGE:
		_begin_slash()
		return
	super._tick_block(delta)


func _tick_state(delta: float) -> void:
	if _dead:
		return
	if _final_phase != FinalPhase.NONE:
		_tick_final(delta)
		return
	if _slash_phase == SlashPhase.NONE:
		super._tick_state(delta)
		return
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	_slash_timer -= delta
	if _slash_timer > 0.0:
		return
	if _slash_phase == SlashPhase.ACTIVE:
		_clear_slash_box()
		_slash_phase = SlashPhase.RECOVERY
		_slash_timer = SLASH_RECOVERY
		_set_blocking(false)
		_kill_flicker()
		_refresh_indicator()
		# 收斧的 0.65 秒就是破绽：盾放下 + 头顶金箭头亮满整个窗口。
		show_opening(SLASH_RECOVERY)
	else:
		_slash_phase = SlashPhase.NONE
		_state = State.BLOCK
		_slash_cd = 1.0 if _final_stand else (1.6 if _enraged else 2.1)
		# 二阶段「斩 → 射」连招：收斧后紧跟一发弹，不再等满一个射击间隔。
		_shoot_timer = CombatRules.EXECUTIONER_P2_FOLLOWUP if _enraged else shoot_interval
		_set_blocking(true)
		hide_opening()


# --- 炉膛终局（等价 phase 2 finale） -----------------------------------------
## 终局招轮转：近身优先抓取处决，其次轮换震地波 / 炉膛火柱。三招互斥，
## 起手时才开始一条预警，收招后才允许下一招 -> 同刻最多一条预警。
func _begin_final_move() -> void:
	var player := knight()
	var dist := global_position.distance_to(player.global_position) if player != null else INF
	var choice: StringName
	if dist <= GRAB_TRIGGER_RANGE:
		choice = &"execution_grab"
	elif _pillar_cursor % 2 == 1:
		choice = &"furnace_pillar"
	else:
		choice = &"ground_wave"
	_pillar_cursor += 1
	_final_id = choice
	_final_phase = FinalPhase.WINDUP
	_final_cd = 0.0
	_set_blocking(true)
	velocity.x = move_toward(velocity.x, 0.0, 500.0 * get_physics_process_delta_time())
	var windup := WAVE_WINDUP
	var telegraph := &"executioner"
	match String(choice):
		"execution_grab":
			windup = GRAB_WINDUP
			telegraph = &"executioner"
			_flicker_slash()
			if _anim != null and _anim.has_anim("slash"):
				_anim.play("slash", true)
			Sfx.play_at(&"boss_axe_swing", global_position, 0.04, 1.0)
		"furnace_pillar":
			windup = PILLAR_WINDUP
			telegraph = &"boss_arena_fire"
			_pillar_target = _next_pillar_x()
			if _anim != null and _anim.has_anim("charge"):
				_anim.play("charge", true)
			Sfx.play_at(&"boss_roar", global_position, 0.06, -8.0)
		_:
			windup = WAVE_WINDUP
			telegraph = &"executioner"
			if _anim != null and _anim.has_anim("slash"):
				_anim.play("slash", true)
			Sfx.play_at(&"boss_axe_swing", global_position, 0.04, -2.0)
	_final_timer = windup
	begin_telegraph(telegraph, windup)
	_spawn_final_warning(windup)


func _next_pillar_x() -> float:
	if _pillar_spots.is_empty():
		_build_pillar_spots()
	var x: float = _pillar_spots[_pillar_cursor % _pillar_spots.size()]
	return x


func _spawn_final_warning(windup: float) -> void:
	var facing := float(_shield_facing)
	match String(_final_id):
		"execution_grab":
			_final_marker = CombatMarker.spawn(self, CombatMarker.Kind.ZONE,
					Vector2(facing * GRAB_ZONE_OFFSET.x, GRAB_ZONE_OFFSET.y),
					windup, GRAB_COLOR,
					{"rect": Rect2(-GRAB_ZONE_SIZE * 0.5, GRAB_ZONE_SIZE)})
		"furnace_pillar":
			_final_marker = CombatMarker.spawn(self, CombatMarker.Kind.ZONE,
					Vector2(_pillar_target - global_position.x, -PILLAR_SIZE.y * 0.5),
					windup, PILLAR_COLOR,
					{"rect": Rect2(-PILLAR_SIZE * 0.5, PILLAR_SIZE)})
		_:
			_final_marker = CombatMarker.spawn(self, CombatMarker.Kind.RING,
					Vector2(0.0, -6.0), windup, WAVE_ZONE_COLOR,
					{"radius_from": 34.0, "radius_to": 10.0})


func _tick_final(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * delta)
	_final_timer -= delta
	if _final_timer > 0.0:
		return
	match _final_phase:
		FinalPhase.WINDUP:
			_final_phase = FinalPhase.ACTIVE
			_final_timer = WAVE_ACTIVE
			_dismiss_final_marker()
			_execute_final_move()
		FinalPhase.ACTIVE:
			_clear_final_box()
			_final_phase = FinalPhase.RECOVERY
			_final_timer = GRAB_RECOVERY
			_set_blocking(false)
			# 抓取 / 震地波落空后的收招也是可打的破绽窗口。
			show_opening(GRAB_RECOVERY)
		_:
			_final_phase = FinalPhase.NONE
			_final_id = &""
			hide_opening()
			_set_blocking(true)
			_final_cd = FINAL_COOLDOWN
			_final_timer = 0.0


func _execute_final_move() -> void:
	var facing := float(_shield_facing)
	match String(_final_id):
		"execution_grab":
			var box := Hitbox.new()
			box.damage = GRAB_DAMAGE
			box.team = &"enemy"
			box.blow = &"heavy"
			var shape := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = GRAB_ZONE_SIZE
			shape.shape = rect
			box.add_child(shape)
			_effects().add_child(box)
			box.global_position = global_position + Vector2(facing * GRAB_ZONE_OFFSET.x, GRAB_ZONE_OFFSET.y)
			box.arm(Vector2(facing * 170.0, -40.0))
			_final_box = box
			Sfx.play_at(&"boss_axe_slam", box.global_position, 0.02, 2.0)
			Fx.dust_puff(box.global_position + Vector2(0.0, 18.0), -PI * 0.5)
			Juice.shake(4.0, 200)
			GameEvents.announcement.emit("处决落空 —— 他的斧劈进了地砖")
		"furnace_pillar":
			var pillar := FurnacePillar.new()
			pillar.size = PILLAR_SIZE
			pillar.damage = PILLAR_DAMAGE
			pillar.lifetime = PILLAR_ACTIVE + 0.35
			pillar.position = Vector2(_pillar_target, global_position.y)
			_effects().add_child(pillar)
			Sfx.play_at(&"boss_axe_slam", Vector2(_pillar_target, global_position.y), 0.03, -1.0)
			Juice.shake(2.5, 180)
		_:
			# 震地波：两道火浪沿地面向左右推进，跳跃可躲。
			for dir: float in [-1.0, 1.0]:
				var wave := FurnaceWave.new()
				wave.direction = dir
				wave.speed = WAVE_SPEED
				wave.travel = WAVE_REACH
				wave.damage = WAVE_DAMAGE
				wave.size = WAVE_SIZE
				wave.position = global_position + Vector2(dir * 34.0, -WAVE_SIZE.y * 0.5)
				_effects().add_child(wave)
			Sfx.play_at(&"boss_axe_slam", global_position, 0.02, 1.0)
			Juice.shake(5.0, 240)
			Fx.dust_puff(global_position + Vector2(0.0, -4.0), -PI * 0.5)


func _dismiss_final_marker() -> void:
	if _final_marker != null and is_instance_valid(_final_marker):
		_final_marker.dismiss()
	_final_marker = null


func _clear_final_box() -> void:
	if _final_box != null and is_instance_valid(_final_box):
		_final_box.disarm()
		_final_box.queue_free()
	_final_box = null


func _effects() -> Node:
	var host := GameContext.world_effects(self)
	if host == null:
		host = get_parent()
	return host


func _clear_slash_box() -> void:
	if is_instance_valid(_slash_box):
		_slash_box.disarm()
		_slash_box.queue_free()
	_slash_box = null


func _enter_stagger() -> void:
	_slash_next = false
	_slash_phase = SlashPhase.NONE
	_clear_slash_box()
	_interrupt_final_stand()
	super._enter_stagger()


func _interrupt_for_poise() -> void:
	_slash_next = false
	_slash_phase = SlashPhase.NONE
	_clear_slash_box()
	_interrupt_final_stand()
	_state = State.STAGGER
	_timer = 0.0  # EnemyBase holds the recovery; the shield resumes afterwards.
	_set_blocking(false)
	_kill_flicker()


## 被打断（硬直 / 死亡）时终局招立刻收口，不留悬空判定与预警。
func _interrupt_final_stand() -> void:
	_final_phase = FinalPhase.NONE
	_final_id = &""
	_final_timer = 0.0
	_final_cd = maxf(_final_cd, 0.6)
	_dismiss_final_marker()
	_clear_final_box()
	hide_opening()


func _begin_slash() -> void:
	_slash_next = true
	_state = State.CHARGE
	_timer = SLASH_WINDUP
	_set_blocking(true)
	_flicker_slash()
	if _anim != null and _anim.has_anim("slash"):
		_anim.play("slash", true)
	# 读招：余烬脉冲（见 _flicker_slash）+ 地面落点红框，框在前摇期间越闪越急，
	# 判定盒与框同位同尺寸。
	begin_telegraph(&"executioner", SLASH_WINDUP)
	CombatMarker.spawn(self, CombatMarker.Kind.ZONE,
			Vector2(float(_shield_facing) * SLASH_ZONE_OFFSET.x, SLASH_ZONE_OFFSET.y),
			SLASH_WINDUP, SLASH_ZONE_COLOR,
			{"rect": Rect2(-SLASH_ZONE_SIZE * 0.5, SLASH_ZONE_SIZE)})
	_notify_framework_attack(&"slash")


func _update_anim() -> void:
	if _anim != null and _anim.has_anim("slash"):
		# Explicitly align the raised blade, contact and return poses to combat.
		if _slash_next:
			_anim.pin_frame("slash", clampi(int((1.0 - _timer / SLASH_WINDUP) * 3.0), 0, 2))
			return
		if _slash_phase == SlashPhase.ACTIVE:
			_anim.pin_frame("slash", 4)
			return
		if _slash_phase == SlashPhase.RECOVERY:
			_anim.pin_frame("slash", 6 if _slash_timer > SLASH_RECOVERY * 0.5 else 7)
			return
	super._update_anim()


func _tick_charge(delta: float) -> void:
	if _dead:
		return
	if not _slash_next:
		super._tick_charge(delta)
		return
	velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
	_timer -= delta
	if _timer <= 0.0:
		_do_slash()
		_slash_next = false
		_slash_phase = SlashPhase.ACTIVE
		_slash_timer = SLASH_ACTIVE


## 挥斧前摇：余烬脉冲，和射弹蓄力的毒橙闪区分开，0.52s 窗更可读。
func _flicker_slash() -> void:
	if _indicator == null:
		return
	_kill_flicker()
	_flicker_tween = create_tween()
	_flicker_tween.tween_property(_indicator, "modulate", Palette.EMBER, 0.16)
	_flicker_tween.tween_property(_indicator, "modulate", Color(1.45, 0.72, 0.38), 0.36)


func _do_slash() -> void:
	if _dead:
		return
	var box := Hitbox.new()
	_slash_box = box
	box.damage = 2
	box.team = &"enemy"
	box.knockback = Vector2(float(_shield_facing) * 110.0, -28.0)
	box.monitoring = true
	box.collision_layer = 8
	box.collision_mask = 32
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = SLASH_ZONE_SIZE
	shape.shape = rect
	box.add_child(shape)
	box.blow = &"heavy"
	get_parent().add_child(box)
	box.global_position = global_position + Vector2(float(_shield_facing) * SLASH_ZONE_OFFSET.x, SLASH_ZONE_OFFSET.y)
	box.arm(Vector2(float(_shield_facing) * 110.0, -28.0))
	# 一阶段是挥砍声，二阶段是砸地声 + 一阵尘与震（只加手感，判定盒不变）。
	if _enraged:
		Sfx.play_at(CombatRules.sfx_key(&"boss_axe_slam"), box.global_position)
		Fx.dust_puff(box.global_position + Vector2(0.0, 14.0), -PI * 0.5)
		Juice.shake(2.5, 140)
	else:
		Sfx.play_at(CombatRules.sfx_key(&"boss_axe_swing"), box.global_position)


## 射弹出膛点随 2× 画幅抬高 / 前移；二阶段仍是「主射 + 瞄准弹」两发。
func _fire() -> void:
	if _dead or _slash_phase != SlashPhase.NONE:
		return
	_notify_framework_attack(&"bolt")
	var player := knight()
	var host := GameContext.world_effects(self)
	if host == null:
		host = get_tree().current_scene
	var origin := global_position + Vector2(float(_shield_facing) * 36.0, -60.0)
	var target := Vector2(float(_shield_facing) * 120.0, -36.0) + global_position
	if player != null:
		target = player.global_position + Vector2(0.0, -24.0)
	var proj := PROJECTILE_SCENE.instantiate() as Projectile
	host.add_child(proj)
	proj.setup(origin, target - origin, projectile_speed, &"enemy", self)
	Sfx.play(&"spit")
	if not _enraged:
		return
	if _anim != null and _anim.has_anim("skill"):
		_anim.play("skill", true)
	var aimed := PROJECTILE_SCENE.instantiate() as Projectile
	host.add_child(aimed)
	var muzzle := global_position + Vector2(float(_shield_facing) * 32.0, -76.0)
	var aim := Vector2(float(_shield_facing) * 120.0, -40.0)
	if player != null:
		aim = player.global_position + Vector2(0.0, -40.0) - muzzle
	aimed.setup(muzzle, aim, projectile_speed * 0.92, &"enemy", self)


func _on_died() -> void:
	_slash_next = false
	_slash_phase = SlashPhase.NONE
	_clear_slash_box()
	_interrupt_final_stand()
	if _boss_director != null:
		_boss_director.notify_death()
	if _presence != null:
		_presence.extinguish()
	slain.emit()
	# 死亡演出钩子：慢动作 + 大震屏 + 双圈 + 碎屑 + 音效；并收掉 Boss 血条
	# （此前刽子手倒下时 HUD 的血条没人通知）。
	Juice.boss_death_beat(global_position + Vector2(0.0, -24.0))
	GameEvents.boss_defeated.emit()
	# 尸体帧同样按 2× 播放（Fx 的一次性帧动画只有 1× 基线，这里自己挂一份）。
	_spawn_death_corpse()
	# 以下是 EnemyBase._death_burst 的收尾（掉落 / 关判定 / 锈屑 / 播报 / 音效 / 释放），
	# 只是跳过了它的帧动画分支，免得 1× 尸体和 2× 尸体同时出现。
	_try_drop_equipment()
	_disable_combat()
	Fx.rust_debris(global_position)
	Fx.hit_sparks(global_position)
	GameEvents.announcement.emit("刽子手跪进炉灰里")
	Sfx.play_at(CombatRules.sfx_key(&"enemy_die"), global_position)
	queue_free()


func _spawn_death_corpse() -> void:
	var frames := CharFrames.anim(BOSS_CHAR, "death")
	if frames.is_empty():
		return
	var host := GameContext.world_effects(self)
	if host == null:
		host = get_parent()
	if host == null:
		return
	var corpse := BossCorpseFrames.new(frames, 14.0, BOSS_SCALE, _shield_facing == 1)
	corpse.position = global_position + Vector2(
			13.0 if _shield_facing == 1 else -13.0, BOSS_DEATH_BASELINE)
	host.add_child(corpse)


# --- presentation -----------------------------------------------------------

## 进场那一拍：背光涌一下（门砸下 + 炉火亮起）。由东翼在 boss_intro_started 时调用。
func presentation_surge() -> void:
	if _presence != null:
		_presence.surge(1.0)


func presence_hot() -> bool:
	return _presence != null and _presence.is_hot()


## 背光当前实际 alpha（测试读；headless 下也算出来）。
func presence_alpha() -> float:
	return _presence.glow_alpha() if _presence != null else 0.0


func _build_presence() -> void:
	if _presence != null:
		return
	_presence = BossPresence.new()
	_presence.name = "BossPresence"
	add_child(_presence)


## 加法背光 + 接地阴影。背光画在本体之后（z=-1，与地面同层、在石板之上），
## 剪影把光挡住，边缘就亮一圈；接地阴影把脚钉在地面上。headless 也会建节点
## （只是不渲染），测试可以直接读 alpha / 位置。
class BossPresence extends Node2D:
	const GLOW_PATH := "res://assets/env/glow_soft.png"
	const OUTER_SIZE := Vector2(3.2, 3.6)
	const INNER_SIZE := Vector2(1.7, 1.9)
	const OUTER_ALPHA := 0.32
	const INNER_ALPHA := 0.24
	const HOT_BOOST := 1.2
	## art-spec 调色板族：Ember（暖炉光）/ Toxic Glow 偏红（斧上余烬的炽相）。
	const WARM := Color(1.0, 0.55, 0.24)
	const HOT := Color(1.0, 0.30, 0.12)
	## 冷色正面补光：和身后暖背光拉开冷暖，给暗袍子一点「月光侧」的内部层次。
	## 骑士永远比 Boss 亮，但 Boss 不再是一块纯黑。
	const COOL := Color(0.55, 0.74, 0.98)
	const COOL_HOT := Color(0.85, 0.72, 0.62)
	## 加法背光 alpha 上限：再亮就把角色剪影、前摇与台缘洗白。
	const ALPHA_CAP := 0.46
	## 身前补光：炉渣从袍子底下透出来，让暗剪影读得出兜帽 / 甲片层次。
	const FILL_RADIUS := 58.0
	const FILL_ENERGY := 1.8
	const FILL_HOT_ENERGY := 2.2
	const COOL_RADIUS := 56.0
	const COOL_ENERGY := 1.1
	const COOL_HOT_ENERGY := 0.35

	var _outer: Sprite2D
	var _inner: Sprite2D
	var _fill: WorldLight
	var _cool: WorldLight
	var _hot := false
	var _surge_amount := 0.0
	var _t := 0.0

	func _ready() -> void:
		z_as_relative = true
		_outer = _make_glow("Backlight", OUTER_SIZE, Vector2(0.0, -62.0), WARM, OUTER_ALPHA)
		_inner = _make_glow("CoreGlow", INNER_SIZE, Vector2(0.0, -70.0), WARM, INNER_ALPHA)
		var shadow := BossGroundShadow.new()
		shadow.name = "ContactShadow"
		shadow.position = Vector2(0.0, -1.0)
		add_child(shadow)
		# 身前暖补光：炉渣从袍子底下透出来，只照亮袍子和脚边石板。
		_fill = _make_light("PresenceFill", WARM, FILL_RADIUS, FILL_ENERGY, Vector2(0.0, -22.0))
		# 正面冷补光：给暗袍子一条冷侧光，兜帽 / 斧柄的层次才读得出来。
		_cool = _make_light("PresenceCool", COOL, COOL_RADIUS, COOL_ENERGY, Vector2(0.0, -44.0))

	func _make_light(light_name: String, tint: Color, radius: float, energy: float, at: Vector2) -> WorldLight:
		var light := WorldLight.new()
		light.name = light_name
		light.follow = &"authored"
		light.authored_radius = radius
		light.radius_cap = radius
		light.color = tint
		light.lit = true
		light.set_base_energy(energy)
		light.position = at
		add_child(light)
		# WorldLight._ready() 会打开阴影；这两盏只照身边，不需要遮挡计算。
		light.shadow_enabled = false
		light.apply(true)
		return light

	func _make_glow(glow_name: String, size: Vector2, at: Vector2, tint: Color, alpha: float) -> Sprite2D:
		var spr := Sprite2D.new()
		spr.name = glow_name
		if ResourceLoader.exists(GLOW_PATH):
			spr.texture = load(GLOW_PATH) as Texture2D
		spr.centered = true
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		spr.scale = size
		spr.position = at
		# 与石板同一层、在地面之后画：加法光在玩法层之下，不盖骑士 / 前摇。
		spr.z_index = -1
		spr.material = Fx.additive_mat()
		spr.modulate = Color(tint.r, tint.g, tint.b, minf(alpha, ALPHA_CAP))
		add_child(spr)
		return spr

	func _process(delta: float) -> void:
		_t += delta
		var pulse := 1.0 + 0.06 * sin(_t * 2.6)
		var boost := 1.0 + _surge_amount * 0.9
		if _outer != null:
			_outer.modulate.a = minf(_base_alpha(OUTER_ALPHA) * pulse * boost, ALPHA_CAP)
		if _inner != null:
			_inner.modulate.a = minf(_base_alpha(INNER_ALPHA) * pulse * boost, ALPHA_CAP)
		if _fill != null:
			_fill.set_base_energy(_fill_energy() * (0.94 + 0.06 * sin(_t * 3.1)))
		if _cool != null:
			_cool.set_base_energy(_cool_energy() * (0.92 + 0.08 * sin(_t * 2.2 + 1.3)))

	func _fill_energy() -> float:
		return FILL_HOT_ENERGY if _hot else FILL_ENERGY

	func _cool_energy() -> float:
		return COOL_HOT_ENERGY if _hot else COOL_ENERGY

	func _base_alpha(base: float) -> float:
		var a := base * (HOT_BOOST if _hot else 1.0)
		return minf(a, ALPHA_CAP)

	func _apply_tint(tint: Color) -> void:
		if _outer != null:
			_outer.modulate = Color(tint.r, tint.g, tint.b, _base_alpha(OUTER_ALPHA))
		if _inner != null:
			_inner.modulate = Color(tint.r, tint.g, tint.b, _base_alpha(INNER_ALPHA))
		if _fill != null:
			_fill.color = tint.lerp(Color(1.0, 0.72, 0.4), 0.28)

	func set_hot(hot: bool) -> void:
		if _hot == hot:
			return
		_hot = hot
		_apply_tint(HOT if hot else WARM)
		if _fill != null:
			_fill.set_base_energy(_fill_energy())
		if _cool != null:
			_cool.color = COOL_HOT if hot else COOL
			_cool.set_base_energy(_cool_energy())

	func is_hot() -> bool:
		return _hot

	## 一次进场的涌光：背光先顶到上限，再落回本相位的亮度。
	func surge(strength: float = 1.0) -> void:
		_surge_amount = maxf(_surge_amount, strength)
		if not is_inside_tree() or get_tree() == null:
			return
		var tween := create_tween()
		tween.tween_method(_set_surge, _surge_amount, 0.16, 0.22)
		tween.tween_method(_set_surge, 0.16, 0.0, 0.85)

	func _set_surge(value: float) -> void:
		_surge_amount = maxf(value, 0.0)

	## 倒地：背光立刻收掉，别让一团火留在尸体上。
	func extinguish() -> void:
		_surge_amount = 0.0
		if _outer != null:
			_outer.modulate.a = 0.0
		if _inner != null:
			_inner.modulate.a = 0.0
		if _fill != null:
			_fill.lit = false
			_fill.apply(true)
		if _cool != null:
			_cool.lit = false
			_cool.apply(true)
		set_process(false)

	func glow_alpha() -> float:
		return _outer.modulate.a if _outer != null else 0.0


## 接地阴影：脚下的软黑椭圆，只有几档点阵椭圆，跟着脚点走。画在石板之上
## （与地面同 z、后画），本体之下。
class BossGroundShadow extends Node2D:
	const HALF_WIDTH := 34.0
	const LAYERS := [
		[34.0, 8.0, 0.22],
		[24.0, 6.0, 0.16],
		[14.0, 3.5, 0.12],
	]

	func _ready() -> void:
		z_index = -1

	func _draw() -> void:
		for layer in LAYERS:
			_draw_ellipse(float(layer[0]), float(layer[1]), Color(0.04, 0.03, 0.05, float(layer[2])))

	func _draw_ellipse(rx: float, ry: float, color: Color) -> void:
		var points := PackedVector2Array()
		for i in 16:
			var ang := TAU * float(i) / 16.0
			points.append(Vector2(roundf(cos(ang) * rx), roundf(sin(ang) * ry)))
		draw_colored_polygon(points, color)


## 2× 死亡帧：和 Fx.OneShotFrames 同样播完自毁，但按 Boss 的画幅缩放。
class BossCorpseFrames extends Sprite2D:
	var _frames: Array[Texture2D] = []
	var _fps := 14.0
	var _age := 0.0

	func _init(frames: Array[Texture2D], fps: float, scale_factor: int, flip: bool) -> void:
		_frames = frames
		_fps = maxf(fps, 0.001)
		texture = _frames[0]
		centered = true
		scale = Vector2(scale_factor, scale_factor)
		flip_h = flip
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		z_index = 1

	func _process(delta: float) -> void:
		_age += delta
		var idx := int(_age * _fps)
		if idx >= _frames.size():
			queue_free()
			return
		if texture != _frames[idx]:
			texture = _frames[idx]


## 震地波：贴地的一道火浪，向一侧推进；跳跃可躲。自带 Hitbox，走完射程自毁。
class FurnaceWave extends Node2D:
	var direction := 1.0
	var speed := 210.0
	var travel := 240.0
	var damage := 2
	var size := Vector2(24.0, 22.0)
	var _moved := 0.0
	var _box: Hitbox

	func _ready() -> void:
		z_index = 5
		material = Fx.additive_mat()
		_box = Hitbox.new()
		_box.damage = damage
		_box.team = &"enemy"
		_box.blow = &"heavy"
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = size
		shape.shape = rect
		_box.add_child(shape)
		add_child(_box)
		_box.arm(Vector2(direction * 120.0, -70.0))
		set_process(true)

	func _physics_process(delta: float) -> void:
		var step := speed * delta
		position.x += direction * step
		_moved += step
		if _moved >= travel:
			queue_free()

	func _draw() -> void:
		var flick := 0.75 + 0.25 * sin(float(Time.get_ticks_msec()) * 0.03)
		var w := size.x
		var h := size.y
		for i in 4:
			var t := float(i) / 3.0
			var row_y := -h * t
			var row_h := maxf(3.0, h * 0.34)
			draw_rect(Rect2(Vector2(roundf(-w * 0.5), roundf(row_y)), Vector2(roundf(w), roundf(row_h))),
					Color(1.0, 0.42 + 0.3 * t, 0.14, 0.75 * flick * (1.0 - t * 0.35)))


## 炉膛火柱：地面炉口喷火，贴地一条高判定。预警由 Boss 画，柱子自带判定。
class FurnacePillar extends Node2D:
	var size := Vector2(26.0, 86.0)
	var damage := 1
	var lifetime := 0.65
	var _age := 0.0
	var _box: Hitbox

	func _ready() -> void:
		z_index = 6
		material = Fx.additive_mat()
		_box = Hitbox.new()
		_box.damage = damage
		_box.team = &"enemy"
		_box.blow = &"light"
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = size
		shape.shape = rect
		_box.add_child(shape)
		add_child(_box)
		_box.position = Vector2(0.0, -size.y * 0.5)
		_box.arm(Vector2(0.0, -90.0))
		Fx.dust_puff(global_position + Vector2(0.0, -4.0), -PI * 0.5)
		set_process(true)

	func _process(delta: float) -> void:
		_age += delta
		if _age >= lifetime:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var k := clampf(_age / maxf(lifetime, 0.01), 0.0, 1.0)
		var height := size.y * clampf(_age / 0.18, 0.0, 1.0)
		var a := clampf(1.0 - k, 0.0, 1.0) * 0.7
		for i in 5:
			var t := float(i) / 4.0
			var row_y := -height * t
			var row_w := size.x * (0.9 - 0.35 * t)
			draw_rect(Rect2(Vector2(roundf(-row_w * 0.5), roundf(row_y)), Vector2(roundf(row_w), 5)),
					Color(1.0, 0.52 + 0.25 * (1.0 - t), 0.16, a * (1.0 - t * 0.4)))


# --- boss framework (M3) -----------------------------------------------------
## 结构迁移（契约 §4.1）：这场 Boss 的「可被框架读到的东西」收敛到一份 BossKit，
## 由 BossDirector 以协助模式挂载 —— 只观测（阶段 / 招式 / 场地事件 / 死亡），不接管
## 现有状态机，因此斩 / 射 / 吼 / 冷却 / 台词 / 演出时序与全部现有测试语义保持不变。
## 未来新招（bosses-a）只需改 _boss_kit_config() 的攻击表，再由导演层驾驶出招。

## 这场 Boss 的 Kit（延迟构建；默认实现安全，表为空也不会报错）。
func boss_kit() -> BossKit:
	if _boss_kit == null:
		_boss_kit = BossKit.new(_boss_kit_config())
	return _boss_kit


## 挂在本 Boss 下的导演层（协助模式；无则返回 null）。
func boss_director() -> BossDirector:
	return _boss_director


## 竞技场边界（世界 x）：BossArena / 夹具读取；未配置时表示不限制。
func boss_arena_bounds() -> Vector2:
	return Vector2(arena_left, arena_right)


func _build_boss_framework() -> void:
	if _boss_kit == null:
		_boss_kit = BossKit.new(_boss_kit_config())
	if _boss_director == null:
		_boss_director = BossDirector.attach(self, _boss_kit, false)
	if _boss_director != null and health != null:
		_boss_director.set_hp(health.current, health.max_hp)


## HP -> 框架同步。死亡只通知一次（notify_death 幂等），免得 0 HP 被算成「最高阶段」。
func _sync_boss_framework(current: int, maximum: int) -> void:
	if _boss_director == null:
		return
	if current <= 0:
		_boss_director.notify_death()
	else:
		_boss_director.set_hp(current, maximum)


func _notify_framework_attack(id: StringName) -> void:
	if _boss_director != null:
		_boss_director.notify_attack_started(id)


## 攻击表数据源。数值全部引用本脚本既有的常量，和实现逐项同源：
##   slash —— 0.52s 余烬脉冲 + 地面落点红框；判定盒 = SLASH_ZONE_SIZE，与画幅同位同尺寸。
##   bolt  —— 沿用齿轮盾卫的 0.5s 蓄力暗号；二阶段射弹加密由 cooldown_by_phase 表达。
##   ground_wave / execution_grab / furnace_pillar —— 20% 终局的等价 phase 2 finale 三招
##   （见 _enter_final_stand）：震地波两道火浪 / 0.9s「斩」预警的抓取处决 / 炉膛火柱落点。
##   三招只进表给框架观测与可读性校验；本 Boss 仍是 2 阶段，由本脚本的终局状态机执行。
## 二阶段「斩后紧跟一发」（EXECUTIONER_P2_FOLLOWUP）是斩的连段，不是独立可选招，
## 所以不进攻击表（它共享斩的前摇与预警，不违反「同刻最多一条预警」）。
func _boss_kit_config() -> Dictionary:
	return {
		"id": &"executioner",
		"title": BOSS_TITLE,
		"subtitle": "铸渣残躯",
		"max_phases": 2,
		"phase_thresholds": [1.0, 0.5],
		"min_interval": 0.8,
		"attacks": [
			{
				"id": &"slash", "phase": 1, "weight": 2.0,
				"cooldown": 2.1, "cooldown_by_phase": [2.1, 1.6],
				"min_range": 0.0, "max_range": SLASH_TRIGGER_RANGE,
				"windup": SLASH_WINDUP, "active": SLASH_ACTIVE, "recovery": SLASH_RECOVERY,
				"telegraph": &"executioner",
				"hitbox": {"offset": SLASH_ZONE_OFFSET, "size": SLASH_ZONE_SIZE},
			},
			{
				"id": &"bolt", "phase": 1, "weight": 1.0,
				"cooldown": 2.0, "cooldown_by_phase": [2.0, 1.15],
				"min_range": 0.0, "max_range": 360.0,
				"windup": 0.5, "active": 0.1, "recovery": 0.3,
				"telegraph": &"gear_shield",
				"hitbox": {},
			},
			{
				"id": &"ground_wave", "phase": 2, "weight": 1.6,
				"cooldown": 3.0, "min_range": 0.0, "max_range": WAVE_TRIGGER_RANGE,
				"windup": WAVE_WINDUP, "active": WAVE_ACTIVE, "recovery": WAVE_RECOVERY,
				"telegraph": &"executioner",
				"hitbox": {},
			},
			{
				"id": &"execution_grab", "phase": 2, "weight": 1.4,
				"cooldown": 4.0, "min_range": 0.0, "max_range": GRAB_TRIGGER_RANGE,
				"windup": GRAB_WINDUP, "active": GRAB_ACTIVE, "recovery": GRAB_RECOVERY,
				"telegraph": &"executioner",
				"hitbox": {"offset": GRAB_ZONE_OFFSET, "size": GRAB_ZONE_SIZE},
			},
			{
				"id": &"furnace_pillar", "phase": 2, "weight": 1.2,
				"cooldown": 4.0, "min_range": 0.0, "max_range": 0.0,
				"windup": PILLAR_WINDUP, "active": PILLAR_ACTIVE, "recovery": PILLAR_RECOVERY,
				"telegraph": &"boss_arena_fire",
				"hitbox": {},
			},
		],
		"arena_events": [
			{"id": &"arena_surge", "at_phase": 1, "once": true},
			{"id": &"arena_hot", "at_phase": 2, "once": true},
			{"id": &"arena_dim", "at_phase": 0, "once": true},
		],
	}

