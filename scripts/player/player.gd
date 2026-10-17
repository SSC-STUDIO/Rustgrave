class_name Player
extends CharacterBody2D
## Ember-Knight root. Movement, combat, toxin, and cores live on child nodes.

@onready var controller: PlayerController = $PlayerController
@onready var health: Health = $Health
@onready var toxin: ToxinMeter = $ToxinMeter
@onready var inventory: RustCoreInventory = $RustCoreInventory
@onready var melee: MeleeCombat = $MeleeCombat
@onready var sensor: InteractionSensor = $InteractionSensor
@onready var visual: Node2D = $Visual
@onready var greatsword: Greatsword = get_node_or_null("Visual/Greatsword")
@onready var hookshot: HookshotTether = $HookshotTether
@onready var resonance: Resonance = $Resonance
@onready var stats: CharacterStats = $CharacterStats
@onready var equipment: EquipmentInventory = get_node_or_null("EquipmentInventory")
@onready var equipment_inventory: EquipmentInventory = get_node_or_null("EquipmentInventory")

@export var auto_equip_starter: bool = true

## Director sets this during a cutscene. Input is ignored; gravity still applies.
var cutscene_locked: bool = false

const P_STAND_PATH := "res://assets/kenney_clean/player/p1_stand.png"
const P_JUMP_PATH := "res://assets/kenney_clean/player/p1_jump.png"
const P_HURT_PATH := "res://assets/kenney_clean/player/p1_hurt.png"
const KENNEY_SPRITE_OFFSET := Vector2(0.0, -13.0)
## 行走的代码 bob（仅 Kenney 单帧回退路径）：地面移动时 ~2px 的 Y 向 sin 摆动。
const WALK_BOB_AMPLITUDE := 1.5
const WALK_BOB_FREQ := 7.0

## Fantasy Knight 像素帧动画（assets/characters/player_fantasy_knight/，朝右）。
## 画布统一 120x80、脚底贴画布底边；身体中心在画布 x≈54.5 → 补偿 +6px。
## centered=true 时 (6, -40) 让脚底落在节点原点、身体对准碰撞体中线。
const KNIGHT_CHAR := "player_fantasy_knight"
const KNIGHT_POS := Vector2(6.0, -40.0)
## 三段连击对应的动作名。姿势按阶段钉帧，不把整段挥砍平均摊进很少的帧里。
const KNIGHT_ATTACK_ANIMS := ["attack1", "attack2", "attack_combo"]
## 受击帧短暂覆盖运动动画的时长。
const HURT_POSE_SECONDS := 0.18
## 判定帧前冲（世界单位/秒），克制到不破坏沉重移动手感。
const SLASH_LUNGE := 78.0
const AFTERIMAGE_LIFE := 0.16
## 受击红闪（纯表现）：与 CombatRules.PLAYER_HURT["flash_ms"] 的 90 ms 同一拍。
## 以前是 120 ms，屏幕闪已经结束、身上的红还在，读起来像两次受击。
const HIT_FLASH_COLOR := Color(1.9, 0.35, 0.35)
const HIT_FLASH_SECONDS := 0.09
## 落地速度达到这个值算「重落地」：换重音效、扬尘加一团。
const HEAVY_LAND_SPEED := 300.0
## 火带 / 冲击波的存活时间。同屏数量受 CombatRules.BUDGET 限制。
const FIRE_TRAIL_LIFE := 1.2
const BLAST_LIFE := 0.18
## 窑匠 + 余烬步双槽在共鸣窗口里的终结冲击波：比一刀更重，值得为弹反而打。
const BLAST_SIZE := Vector2(56, 22)
const BLAST_DAMAGE := 2

var _sprites: Dictionary = {}
var _sprite_root: Sprite2D
var _anim: FrameAnimSprite
var _attack_anim: String = "attack1"
var _hurt_timer: float = 0.0
var _hit_flash_tween: Tween
var _was_on_floor := true
var _melee_active_prev := false
var _bob_t: float = 0.0
var _moving_prev := false
## 临时节点预算：按生成顺序记着，超出上限就收掉最老的（见 CombatRules.BUDGET）。
var _afterimages: Array = []
var _fire_trails: Array = []
var _blasts: Array = []
var _band_seen: StringName = &"cold"
var _hp_seen: int = 0
var _floor_skin: String = ""
var _pulse_t: float = 0.0

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	# Default true freezes the body at wall-floor corners (sticky walls).
	floor_block_on_wall = false
	_hp_seen = health.current
	_band_seen = toxin.band()
	health.changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	toxin.overflow_tick.connect(_on_toxin_overflow)
	GameEvents.player_health_changed.emit(health.current, health.max_hp)
	GameEvents.toxin_changed.emit(toxin.toxin, toxin.max_toxin)
	GameEvents.hit.connect(_on_game_hit)
	GameEvents.dash_performed.connect(_on_dash_performed)
	inventory.sockets_changed.connect(_refresh_heat_lick)
	_refresh_heat_lick()
	if stats != null:
		stats.stats_changed.connect(_on_stats_changed)
		_on_stats_changed()
	if equipment == null:
		equipment = get_node_or_null("EquipmentInventory")
	if equipment_inventory == null:
		equipment_inventory = equipment
	if equipment != null:
		equipment.equipment_changed.connect(_on_equipment_changed)
		if _should_auto_equip_starter() and equipment.is_completely_unequipped():
			initialize_starter_equipment()
		else:
			_on_equipment_changed()
	GameEvents.swing_started.connect(_on_swing_started)
	if not _setup_knight_anim():
		_setup_kenney_sprite()
	# 主题标识：余烬骑士周身漂浮的橙色余烬（Fx 内部自带 headless 守卫）。
	Fx.attach_ember(self)


func _physics_process(delta: float) -> void:
	if health.is_invincible() and health.current <= 0:
		return
	controller.extra_jumps_unlocked = inventory.has_ability(AbilityIds.EMBER_STEP)
	if cutscene_locked:
		_tick_cutscene_idle(delta)
		return
	health.invincible = controller.is_invincible()
	var move_scale := CombatRules.SWING_MOVE_SCALE if melee.is_busy() else 1.0
	controller.physics_tick(self, delta, move_scale)
	if not is_on_floor() and melee.is_busy() and melee.phase_name() == "active" and velocity.y > 40.0:
		velocity.y = move_toward(velocity.y, 40.0, 320.0 * delta)
	if hookshot.is_active():
		# 钩索接管速度（在 controller 之后、move_and_slide 之前）。
		hookshot.apply_tether_velocity(self)
	var fall_speed := velocity.y
	move_and_slide()
	controller.settle_after_slide(self)
	var face := float(controller.facing)
	visual.scale.x = face
	melee.scale.x = face
	# 落地扬尘：从明显下落转为触地时在脚边 puff 一团灰；重落地换重音效、多一团尘。
	if is_on_floor() and not _was_on_floor and fall_speed > 60.0:
		Fx.dust_puff(global_position + Vector2(0.0, -2.0))
		if fall_speed >= HEAVY_LAND_SPEED:
			Fx.dust_puff(global_position + Vector2(0.0, -2.0), PI)
			Sfx.play_at(CombatRules.sfx_key(&"land_heavy"), global_position, 0.06, -3.0)
		else:
			Sfx.play_at(&"land", global_position, 0.06, -5.0)
		if WorldClock.rain_opacity() >= 0.25:
			Sfx.play(&"splash", 0.12, -12.0)
	_was_on_floor = is_on_floor()
	_poll_floor_skin()
	_update_visual(delta)
	_poll_slash_arc(face)
	_poll_toxin_band()
	_poll_interact()
	_poll_sockets()
	_poll_hookshot()


func _on_dash_performed() -> void:
	var face := float(controller.facing)
	Fx.dust_puff(global_position, 0.0 if face > 0.0 else PI)
	_spawn_afterimages(face)


func _refresh_heat_lick() -> void:
	if inventory.has_ability(AbilityIds.HEAT_FORGE):
		Fx.attach_heat_lick(visual)
	else:
		Fx.detach_heat_lick(visual)


## Fantasy Knight 逐帧动画（主路径）。素材缺失（如未导入）返回 false，
## 交给 Kenney 单帧回退；两者都缺时保留场景内 ColorRect 占位。
func _setup_knight_anim() -> bool:
	if not CharFrames.available(KNIGHT_CHAR):
		return false
	_anim = FrameAnimSprite.new()
	_anim.name = "KnightSprite"
	# 动作表：帧目录 / fps / 是否循环（画布统一 → 基线相同）。
	var table := [
		["idle", 10.0, true], ["run", 12.0, true],
		["jump", 10.0, false], ["fall", 10.0, true],
		["dash", 14.0, true], ["hurt", 10.0, false],
		["death", 10.0, false], ["turn", 14.0, false],
		["attack1", 14.0, false], ["attack2", 14.0, false],
		["attack_combo", 14.0, false],
	]
	for row in table:
		_anim.register(row[0], CharFrames.anim(KNIGHT_CHAR, row[0]), row[1], row[2], KNIGHT_POS)
	_anim.play("idle")
	visual.add_child(_anim)
	_sprite_root = _anim  # 残像/白闪等表现直接复用同一 Sprite。
	# 骑士帧自带剑与盔甲：隐藏所有占位色块和程序化多边形剑。
	for c in visual.get_children():
		if c == _anim:
			continue
		if c is ColorRect or c is Polygon2D:
			c.visible = false
	return true


## 挥砍姿势：前摇停在起手，长刀临门才抬剑；有效帧是斩下；后摇按进度收到末帧。
static func attack_frame_index(frame_count: int, phase: String, progress: float) -> int:
	var count := maxi(frame_count, 1)
	if count == 1:
		return 0
	var last := count - 1
	var strike := 1 if count <= 3 else clampi(int(round(float(last) * 0.45)), 1, last - 1)
	var p := clampf(progress, 0.0, 1.0)
	match phase:
		"windup":
			if strike > 1 and p >= 0.72:
				return 1
			return 0
		"active":
			return strike
		"recovery":
			var start := mini(strike + 1, last)
			return start + int(round(p * float(last - start)))
		_:
			return 0


## 按挥砍段位选攻击动画。帧由 _pin_attack_pose 按阶段钉住。
func _on_swing_started(combo_index: int) -> void:
	if _anim == null:
		return
	var idx := clampi(combo_index, 0, KNIGHT_ATTACK_ANIMS.size() - 1)
	_attack_anim = KNIGHT_ATTACK_ANIMS[idx]
	_anim.pin_frame(_attack_anim, attack_frame_index(
			_attack_frame_count(), "windup", 0.0))


func _setup_kenney_sprite() -> void:
	if not ResourceLoader.exists(P_STAND_PATH):
		return
	# Hide placeholder ColorRects but keep them for headless fallback.
	for c in visual.get_children():
		if c is SwordVisual:
			continue  # 锯齿巨剑与 Kenney 素材同屏，不随占位符隐藏
		if c is ColorRect or c is Polygon2D:
			c.visible = false
	_sprite_root = Sprite2D.new()
	_sprite_root.name = "KenneySprite"
	_sprite_root.centered = true
	_sprite_root.position = KENNEY_SPRITE_OFFSET
	_sprite_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visual.add_child(_sprite_root)
	_sprites["stand"] = load(P_STAND_PATH) as Texture2D
	if ResourceLoader.exists(P_JUMP_PATH):
		_sprites["jump"] = load(P_JUMP_PATH) as Texture2D
	if ResourceLoader.exists(P_HURT_PATH):
		_sprites["hurt"] = load(P_HURT_PATH) as Texture2D
	_sprite_root.texture = _sprites["stand"]
	_sprite_root.modulate = Color(1, 1, 1, 1)


func _update_visual(delta: float) -> void:
	if _hurt_timer > 0.0:
		_hurt_timer = maxf(0.0, _hurt_timer - delta)
	elif _sprite_root != null and (_hit_flash_tween == null or not _hit_flash_tween.is_valid()):
		# 身体染色读毒素档位：温（淡橙）→ 炽（深橙 + 飘灰）→ 满溢（发红脉动，掉血的警示）。
		var tier := CombatRules.toxin_tier(toxin.band())
		var tint: Color = tier["tint"]
		if bool(tier["warn"]):
			_pulse_t += delta
			tint = tint.lerp(Color(1.0, 0.5, 0.45), 0.5 + 0.5 * sin(_pulse_t * TAU * 1.8))
		_sprite_root.modulate = tint
		if float(tier["ember_chance"]) > 0.0 and randf() < float(tier["ember_chance"]) * delta * 60.0:
			Fx.dust_puff(global_position + Vector2(randf_range(-6.0, 6.0), -16.0))
	_poll_stride_audio(delta)
	if greatsword != null:
		# 巨剑由自己算姿态/淡出；Player 只把状态喂给它，从不反向读它。
		greatsword.tick(self, delta)
	if _anim != null:
		_update_knight_anim()
		return
	_update_kenney_sprite(delta)


## Same ground-move threshold as the run/bob visuals. No physics writes.
func _poll_stride_audio(delta: float) -> void:
	var moving := is_on_floor() \
		and not controller.is_dashing() \
		and not melee.is_busy() \
		and health.current > 0 \
		and absf(velocity.x) > 12.0
	Sfx.tick_stride(moving, WorldClock.rain_opacity() >= 0.35, delta, _stride_surface())


## 脚下台面的 skin（SolidPlatform.skin）。只在音频包提供 surface_for_skin 时才取，
## 避免白白轮询；取不到就保持旧值，默认走 stone。
func _poll_floor_skin() -> void:
	if not is_on_floor() or not Sfx.has_method(&"surface_for_skin"):
		return
	for i in get_slide_collision_count():
		var floor_body: Object = get_slide_collision(i).get_collider()
		if floor_body == null:
			continue
		var skin: Variant = floor_body.get(&"skin")
		if skin is String and skin != "":
			_floor_skin = skin
			return


func _stride_surface() -> StringName:
	if _floor_skin == "" or not Sfx.has_method(&"surface_for_skin"):
		return &"stone"
	var surface: Variant = Sfx.call(&"surface_for_skin", _floor_skin)
	if surface is StringName or surface is String:
		return StringName(surface)
	return &"stone"


## 状态优先级：死亡 > 挥砍 > dash > 受击帧 > 空中(升/降) > 跑动 > 待机。
func _update_knight_anim() -> void:
	if health.current <= 0:
		_anim.play("death")
		return
	if melee.is_busy():
		_pin_attack_pose()
		return
	if controller.is_dashing():
		_anim.play("dash")
		return
	if _hurt_timer > 0.0:
		_anim.play("hurt")
		return
	if not is_on_floor():
		_anim.play("jump" if velocity.y < 0.0 else "fall")
		return
	_anim.play("run" if absf(velocity.x) > 12.0 else "idle")


func _attack_frame_count() -> int:
	var frames := CharFrames.anim(KNIGHT_CHAR, _attack_anim)
	return maxi(frames.size(), 1)


func _pin_attack_pose() -> void:
	if _anim == null or not _anim.has_anim(_attack_anim):
		return
	_anim.pin_frame(_attack_anim, attack_frame_index(
			_attack_frame_count(), melee.phase_name(), melee.phase_progress()))


func _update_kenney_sprite(delta: float) -> void:
	if _sprite_root == null:
		return
	var tex: Texture2D = _sprites.get("stand") as Texture2D
	var is_slashing := melee.phase_name() != "idle"
	if health.current <= 0:
		tex = _sprites.get("hurt", tex) as Texture2D
	elif controller.is_dashing() or not is_on_floor():
		tex = _sprites.get("jump", tex) as Texture2D
	if tex != null and _sprite_root.texture != tex:
		_sprite_root.texture = tex
	# 行走 bob：地面移动时给精灵 Y 方向 sin 摆动，恢复到 stand 时直接归零。
	var moving := is_on_floor() and not is_slashing and absf(velocity.x) > 12.0
	if moving:
		_bob_t += delta
		var base_y := KENNEY_SPRITE_OFFSET.y
		_sprite_root.position.y = base_y + sin(_bob_t * WALK_BOB_FREQ * TAU) * WALK_BOB_AMPLITUDE
		_moving_prev = true
	elif _moving_prev:
		_sprite_root.position.y = KENNEY_SPRITE_OFFSET.y
		_moving_prev = false


## 检测 MeleeCombat 进入 ACTIVE 的上升沿，生成一次性挥砍弧光（纯视觉）。
func _poll_slash_arc(face: float) -> void:
	var active_now := melee.phase_name() == "active"
	if active_now and not _melee_active_prev:
		velocity.x += face * SLASH_LUNGE
		_spawn_afterimages(face)
		if SlashArc.sheet_available():
			var arc := SlashArc.new()
			arc.flip_h = face < 0.0
			arc.position = Vector2(24.0 * face, -22.0)
			# 剑光读毒素档位：颜色越烫越亮、弧越大，满溢时闪烁——奖励与风险都看得见。
			var tier := CombatRules.toxin_tier(toxin.band())
			if _anim != null:
				# 骑士帧自带剑痕：弧光降级为辅助拖影（缩小压暗），避免双重剑光；
				# 弹反炸亮由 SlashArc._on_parried 覆盖 modulate/scale，反馈保留。
				var arc_scale := float(tier["arc_scale"])
				arc.scale = Vector2(arc_scale, arc_scale)
				arc.modulate = tier["arc_color"]
				arc.position = Vector2(20.0 * face, -18.0)
			arc.flicker = bool(tier["flicker"])
			add_child(arc)
	_melee_active_prev = active_now


## 残像：同屏上限 CombatRules.BUDGET[afterimages]，超出收掉最老的。tween 绑在残像自己身上。
func _spawn_afterimages(_face: float) -> void:
	if _sprite_root == null or _sprite_root.texture == null:
		return
	for i in 2:
		var ghost := Sprite2D.new()
		ghost.texture = _sprite_root.texture
		ghost.centered = true
		ghost.texture_filter = _sprite_root.texture_filter
		ghost.global_position = _sprite_root.global_position + Vector2(-8.0 * float(i + 1) * visual.scale.x, 0)
		ghost.scale = _sprite_root.scale * visual.scale
		ghost.modulate = Color(1.0, 0.75, 0.45, 0.42 - 0.12 * float(i))
		ghost.z_index = visual.z_index - 1
		get_parent().add_child(ghost)
		_track(_afterimages, ghost, int(CombatRules.BUDGET[&"afterimages"]))
		var tw := ghost.create_tween()
		tw.tween_property(ghost, "modulate:a", 0.0, AFTERIMAGE_LIFE)
		tw.tween_callback(ghost.queue_free)


## 记录一个临时节点；超出 cap 就收掉最老的。先剔除已被释放的。
func _track(list: Array, node: Node, cap: int) -> void:
	for i in range(list.size() - 1, -1, -1):
		if not is_instance_valid(list[i]) or (list[i] as Node).is_queued_for_deletion():
			list.remove_at(i)
	list.append(node)
	while list.size() > cap:
		var oldest: Node = list.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func tracked_afterimages() -> int:
	return _afterimages.size()


## 毒素换档提示：升档一圈圆环，进满溢再响一声警示；降档不打扰。
func _poll_toxin_band() -> void:
	var band := toxin.band()
	if band == _band_seen:
		return
	var rising := CombatRules.TOXIN_TIERS.keys().find(band) > CombatRules.TOXIN_TIERS.keys().find(_band_seen)
	_band_seen = band
	if not rising:
		return
	Fx.burst(&"ring", global_position + Vector2(0.0, -14.0))
	if bool(CombatRules.toxin_tier(band)["warn"]):
		Sfx.play(CombatRules.sfx_key(&"toxin_warn"))


## 受击红闪：target 为本玩家时把精灵短暂染红后 tween 回白。
func _on_game_hit(_attacker: Node, target: Node, _amount: int) -> void:
	if target != self or _sprite_root == null:
		return
	# 存活且不在挥砍锁定时，短暂切到受击帧。挥砍中不换姿势，改在身上打一簇火花。
	if health.current > 0 and not melee.is_busy():
		_hurt_timer = HURT_POSE_SECONDS
	elif health.current > 0:
		Fx.hit_sparks(global_position + Vector2(0.0, -18.0))
	if _hit_flash_tween != null and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()
	_sprite_root.modulate = HIT_FLASH_COLOR
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(_sprite_root, "modulate", Color.WHITE, HIT_FLASH_SECONDS)


func is_invincible() -> bool:
	return controller.is_invincible() or health.is_invincible()


func collect_core(core: RustCore) -> void:
	inventory.add_to_pouch(core)
	Sfx.play(&"pickup")


func _tick_cutscene_idle(delta: float) -> void:
	# 过场里按下的跳 / 冲刺不许在过场结束后冒出来。
	controller.clear_buffers()
	if not is_on_floor():
		velocity.y += float(ProjectSettings.get_setting("physics/2d/default_gravity")) * delta
	velocity.x = move_toward(velocity.x, 0.0, 420.0 * delta)
	move_and_slide()
	controller.settle_after_slide(self)
	visual.scale.x = float(controller.facing)
	_update_visual(delta)


func on_melee_active(combo_index: int) -> void:
	var pot := toxin.potency()
	if pot >= 0.85 and inventory.has_ability(AbilityIds.HEAT_FORGE):
		_spawn_fire_trail()
	# 双槽冲击波只在共鸣窗口点亮，避免嵌核后每段三连都白嫖。
	if combo_index >= 2 and resonance.is_active() \
			and inventory.has_pair(AbilityIds.HEAT_FORGE, AbilityIds.EMBER_STEP):
		_spawn_blast()


## 临时伤害体统一出口：挂到世界特效节点、限量、寿命由绑在自己身上的 tween 收口
## （节点先被释放时 tween 随之消失，不会遗留计时器）。
func _spawn_temp_hitbox(size: Vector2, origin: Vector2, blow: StringName, life: float,
		knock: Vector2, budget: Array, cap: int, dmg: int = 1) -> Hitbox:
	# 玩家自己的临时伤害体（火带 + 冲击波）合计上限：满了先收最老的火带。
	_enforce_player_hitbox_cap()
	var box := Hitbox.new()
	box.damage = dmg
	box.team = &"player"
	box.blow = blow
	box.knockback = knock
	box.monitoring = true
	box.collision_layer = 8
	box.collision_mask = 32
	var box_shape := CollisionShape2D.new()
	var box_rect := RectangleShape2D.new()
	box_rect.size = size
	box_shape.shape = box_rect
	box.add_child(box_shape)
	var host: Node = GameContext.world_effects(self)
	if host == null:
		host = get_parent()
	host.add_child(box)
	box.global_position = origin
	box.monitoring = true
	_track(budget, box, cap)
	var tw := box.create_tween()
	tw.tween_interval(life)
	tw.tween_callback(box.queue_free)
	return box


## 火带 + 冲击波合计不超过 PLAYER_HITBOX_CAP：超出时先收最老的火带，再收冲击波。
func _enforce_player_hitbox_cap() -> void:
	for list in [_fire_trails, _blasts]:
		for i in range((list as Array).size() - 1, -1, -1):
			if not is_instance_valid(list[i]) or (list[i] as Node).is_queued_for_deletion():
				(list as Array).remove_at(i)
	while _fire_trails.size() + _blasts.size() >= CombatRules.PLAYER_HITBOX_CAP:
		var victim: Node = _fire_trails.pop_front() if not _fire_trails.is_empty() else _blasts.pop_front()
		if is_instance_valid(victim):
			victim.queue_free()


func player_hitbox_count() -> int:
	return _fire_trails.size() + _blasts.size()


func _spawn_fire_trail() -> void:
	var face := float(controller.facing)
	var origin := global_position + Vector2(face * 28.0, -4.0)
	Fx.dust_puff(global_position + Vector2(face * 18.0, -2.0), face)
	_spawn_temp_hitbox(Vector2(42, 10), origin, &"light", FIRE_TRAIL_LIFE, Vector2.ZERO,
			_fire_trails, int(CombatRules.BUDGET[&"fire_trails"]))


func _spawn_blast() -> void:
	var face := float(controller.facing)
	var origin := global_position + Vector2(face * 22.0, -8.0)
	Fx.dust_puff(origin, face)
	Fx.hit_sparks(origin)
	Fx.burst(&"ring", origin)
	Sfx.play_at(CombatRules.sfx_key(&"swing_heavy"), origin, 0.06, -4.0)
	var blast := _spawn_temp_hitbox(BLAST_SIZE, origin, &"heavy", BLAST_LIFE,
			Vector2(face * 80.0, -30.0), _blasts,
			int(CombatRules.BUDGET[&"blasts"]), BLAST_DAMAGE)
	if blast != null:
		# 共鸣终结击的视觉边界：外框就是 56x22 判定盒本身，玩家能看见哪一段会吃到。
		var wave := BlastWave.new()
		wave.size = BLAST_SIZE
		wave.life = BLAST_LIFE
		blast.add_child(wave)
	for node in get_tree().get_nodes_in_group("pressure_plate"):
		if node is PressurePlate and (node as Node2D).global_position.distance_to(origin) < 56.0:
			(node as PressurePlate).slam()


func _poll_interact() -> void:
	if cutscene_locked:
		return
	var focus := sensor.get_focus()
	if focus:
		GameEvents.interact_prompt.emit(focus.get_prompt(self))
	else:
		GameEvents.interact_prompt.emit("")
	if focus and Input.is_action_just_pressed("interact"):
		focus.interact(self)


func _poll_sockets() -> void:
	if cutscene_locked:
		return
	if Input.is_action_just_pressed("socket_1"):
		inventory.insert_into_socket(0)
	elif Input.is_action_just_pressed("socket_2"):
		inventory.insert_into_socket(1)


func _poll_hookshot() -> void:
	if cutscene_locked:
		return
	if not Input.is_action_just_pressed("hookshot"):
		return
	if not inventory.has_ability(AbilityIds.HOOKSHOT_TETHER):
		GameEvents.announcement.emit("需要系核（钩锁）— 击败喷吐者可得")
		return
	if hookshot.is_active():
		return
	if not hookshot.try_fire(self):
		GameEvents.announcement.emit("范围内没有可钩住的锚点")


func _on_health_changed(current: int, maximum: int) -> void:
	GameEvents.player_health_changed.emit(current, maximum)
	# 回血（巢 / 净化祠 / 章节交接）响一声；读档恢复与受伤不响。
	if current > _hp_seen and _hp_seen > 0:
		Sfx.play(CombatRules.sfx_key(&"heal"))
	_hp_seen = current


func _on_stats_changed() -> void:
	if stats != null and health != null:
		health.set_max_hp(stats.get_effective_max_hp())


func _on_equipment_changed() -> void:
	if stats != null and equipment != null:
		stats.recalculate(equipment.get_all_equipped(), equipment.get_active_set_bonuses())


func initialize_starter_equipment(force: bool = false) -> bool:
	if equipment != null:
		return equipment.initialize_starter_kit(force)
	return false


func _should_auto_equip_starter() -> bool:
	if not auto_equip_starter:
		return false
	if get_tree() != null and get_tree().current_scene != null:
		var scene_name := get_tree().current_scene.name
		if "Test" in scene_name or "test" in scene_name:
			return false
	return true


func take_mitigated_damage(amount: int, attacker: Node = null) -> bool:
	return health.take_damage(amount, attacker)


func _on_toxin_overflow() -> void:
	# 过场锁死时不能走开：满溢伤害会把人钉死在毒池/台词里。
	if cutscene_locked:
		return
	# 每一次满溢掉血前都先出声：不看血条也知道是毒在烧。
	Sfx.play(CombatRules.sfx_key(&"toxin_warn"))
	health.take_damage(1, self)


func _on_died() -> void:
	Sfx.play(CombatRules.sfx_key(&"death"))
	if Director.playing:
		Director.abort()
	if _anim != null:
		_anim.play("death")  # 物理停摆后由 _process 继续播完倒地
	set_physics_process(false)
	GameEvents.player_died.emit()
	GameEvents.announcement.emit("余烬熄灭…")
	var wait := Timer.new()
	wait.one_shot = true
	wait.wait_time = 1.15
	add_child(wait)
	wait.start()
	await wait.timeout
	if not is_instance_valid(self) or get_tree() == null:
		return
	var nest := _resolve_lit_nest()
	var reload := GameContext.world_scene_path(self)
	if reload == "" and get_tree().current_scene != null:
		reload = get_tree().current_scene.scene_file_path
	if reload == "":
		return
	if nest != null:
		GameEvents.player_respawned.emit()
		SaveData.respawn(reload, nest.global_position)
	else:
		Director.fade_to(reload)


## 存档里的巢路径可能是场景相对路径或旧的绝对 NodePath。
func _resolve_lit_nest() -> Node2D:
	var nest_path := SaveData.last_lit_nest()
	if nest_path == "" or get_tree() == null:
		return null
	var scene := GameContext.world_root(self)
	if scene == null:
		scene = get_tree().current_scene
	if scene == null:
		return null
	var nest := SaveData.resolve_saved_node(scene, nest_path)
	if nest is Node2D and is_instance_valid(nest):
		return nest as Node2D
	return null


## 共鸣终结击的可视边界：自绘的横向冲击波，外框与 BLAST_SIZE 判定盒同尺寸。
## 挂在冲击波 Hitbox 身上，随它一起释放；加法混合、不参与任何判定。
class BlastWave extends Node2D:
	var size := Vector2.ZERO
	var life := 0.18
	var color := Color(1.65, 0.82, 0.38)
	var _age := 0.0

	func _ready() -> void:
		z_index = 11
		material = Fx.additive_mat()

	func _process(delta: float) -> void:
		_age += delta
		if _age >= life:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var k := clampf(_age / maxf(life, 0.001), 0.0, 1.0)
		var fade := 1.0 - k
		var half := size * 0.5
		# 外框 = 判定盒的真实边界；内芯是一条收束的亮线；两端竖向收口。
		draw_rect(Rect2(-half, size), _tint(0.75 * fade), false, 1.0)
		var core := size * Vector2(0.78, 0.42)
		draw_rect(Rect2(-core * 0.5, core), Color(1.0, 0.95, 0.86, 0.85 * fade), false, 1.0)
		for side in [-1.0, 1.0]:
			var x: float = side * (half.x - 1.0)
			draw_line(Vector2(x, -half.y * 0.7), Vector2(x, half.y * 0.7), _tint(0.9 * fade), 1.0)

	func _tint(alpha: float) -> Color:
		return Color(color.r, color.g, color.b, clampf(alpha, 0.0, 1.0))
