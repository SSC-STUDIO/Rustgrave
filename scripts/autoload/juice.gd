extends Node
## Juice autoload: hit-stop, slow-mo, screen-flash, and camera-shake effects.
## All triggers arrive through the GameEvents signal bus so gameplay modules
## stay decoupled from presentation. Timers use wall-clock milliseconds so
## restoring Engine.time_scale is immune to time_scale itself.
##
## 命中反馈走 CombatRules.HIT_FEEL 矩阵（材质 x 出手分量）：这里只取行并执行，
## 不再散落魔法数字。震屏 / 闪屏在落手那一刻读 Settings 的 shake_scale /
## flash_scale（从不缓存），闪屏另有透明度上限，保证不盖住骑士剪影和敌人前摇。

const PRIORITY_HIT := 1
const PRIORITY_PARRY := 2
const PRIORITY_DEATH := 3

## Headless runs never build the overlay nor touch audio-visual state,
## but time-scale effects still resolve deterministically for logic tests.
var _headless := false

var _restore_at_ms: int = 0
var _priority: int = 0

var _flash_layer: CanvasLayer
var _flash_rect: ColorRect
var _flash_tween: Tween

var _shake_intensity := 0.0
var _shake_start_ms := 0
var _shake_end_ms := 0
var _shake_cam: GameCamera = null
## 上次找不到相机后不再每帧扫编组，直到下一次 shake()。
var _shake_lookup_failed := false

## 最近一次实际落手的震屏像素 / 闪屏透明度（已乘 Settings、已套上限）。
## headless 下也会更新，测试和诊断读它。
var last_shake_px := 0.0
var last_flash_alpha := 0.0
## 最近一次 feel() 取到的矩阵行（测试读）。
var last_feel: Dictionary = {}


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _headless:
		_build_flash_layer()
		# 窗口标题只设一次（以前每帧都写，Win32 每帧一次 SetWindowText）。
		DisplayServer.window_set_title("Rustgrave")
	GameEvents.hit.connect(_on_hit)
	GameEvents.parried.connect(_on_parried)
	GameEvents.player_died.connect(_on_player_died)


func _process(_delta: float) -> void:
	if Engine.time_scale != 1.0 and Time.get_ticks_msec() >= _restore_at_ms:
		Engine.time_scale = 1.0
		_priority = 0
	if not _headless:
		_update_shake_offset()


func hit_stop(duration_ms: int, time_scale: float = 0.05) -> void:
	_apply(duration_ms, time_scale, PRIORITY_HIT)


func slow_mo(duration_ms: int, time_scale: float = 0.25, priority: int = PRIORITY_PARRY) -> void:
	_apply(duration_ms, time_scale, priority)


## Random decaying camera shake in pixels, wall-clock timed so it runs
## identically through hit-stop and slow-mo. Presentation only: it writes
## GameCamera.shake_offset, never gameplay positions. Headless never touches
## a camera. The amplitude is multiplied by Settings.shake_scale right here.
func shake(intensity_px: float, duration_ms: int) -> void:
	var scaled := CombatRules.shake_px(intensity_px, Settings.shake_scale)
	last_shake_px = scaled
	if _headless or scaled <= 0.0:
		return
	var now := Time.get_ticks_msec()
	if scaled < _shake_intensity and now + duration_ms <= _shake_end_ms:
		return  # A weaker jolt never cuts a stronger ongoing one short.
	_shake_intensity = scaled
	_shake_start_ms = now
	_shake_end_ms = now + maxi(duration_ms, 0)
	_shake_lookup_failed = false


func _apply(duration_ms: int, time_scale: float, priority: int) -> void:
	if priority < _priority and Engine.time_scale != 1.0:
		return  # Never downgrade an ongoing strong effect.
	var now := Time.get_ticks_msec()
	if priority == _priority and now + duration_ms <= _restore_at_ms:
		return  # Already frozen at least as long.
	Engine.time_scale = clampf(time_scale, 0.01, 1.0)
	_restore_at_ms = now + duration_ms
	_priority = priority


## 全屏闪色。alpha 先过 CombatRules.FLASH_ALPHA_CAP 再乘 Settings.flash_scale；
## 只有玩家死亡的压暗允许 uncapped（骑士此时已倒下）。
func flash(color: Color, duration_ms: int, uncapped: bool = false) -> void:
	var alpha := clampf(color.a * Settings.flash_scale, 0.0, 1.0) if uncapped \
			else CombatRules.flash_alpha(color.a, Settings.flash_scale)
	last_flash_alpha = alpha
	if _headless or _flash_rect == null or alpha <= 0.0:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_rect.color = Color(color.r, color.g, color.b, 1.0)
	_flash_rect.modulate.a = alpha
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_rect, "modulate:a", 0.0, maxf(0.03, duration_ms / 1000.0))


## 命中反馈入口：按材质 x 出手分量取矩阵行，一次性触发顿帧 / 震屏 / 火花 / 音效。
## 返回所取的行（测试与调用方读）。pos 为世界坐标，dir 为火花朝向（弧度）。
func feel(material: StringName, weight: StringName, pos: Vector2 = Vector2.ZERO,
		dir: float = 0.0) -> Dictionary:
	var row := CombatRules.feel(material, weight)
	last_feel = row
	hit_stop(int(row["stop_ms"]), float(row["stop_scale"]))
	shake(float(row["shake_px"]), int(row["shake_ms"]))
	Fx.hit_effect(StringName(row["spark"]), StringName(row["debris"]), bool(row["ring"]), pos, dir)
	Sfx.play_at(CombatRules.sfx_key(StringName(row["sfx"])), pos)
	return row


## 盾面挡下一击（没有扣血，所以没有 GameEvents.hit）：由盾卫的 block_check 直接调。
## broke = 弹反把盾击碎的那一下，用最重的盾行。
func block_feel(attacker: Node, pos: Vector2, broke: bool = false) -> Dictionary:
	var weight: StringName = &"finisher" if broke else CombatRules.weight_for(attacker, 1, false)
	return feel(&"shield", weight, pos, _facing_angle(attacker, pos))


## 首领相变的一次性演出：短慢动作 + 震屏 + 圆环 + 受 Settings 缩放的闪色 + 吼叫。
func boss_phase_beat(pos: Vector2, tint: Color = Color(1.0, 0.78, 0.45)) -> void:
	var row := CombatRules.BOSS_PHASE_FEEL
	slow_mo(int(row["slow_ms"]), float(row["slow_scale"]))
	shake(float(row["shake_px"]), int(row["shake_ms"]))
	flash(Color(tint.r, tint.g, tint.b, float(row["flash_alpha"])), int(row["flash_ms"]))
	Fx.hit_sparks(pos)
	Fx.burst(&"ring", pos)
	Sfx.play_at(CombatRules.sfx_key(StringName(row["sfx"])), pos, 0.04)


## 首领倒下的演出钩子：长一点的慢动作 + 大震屏 + 双圈 + 碎屑 + 音效。
func boss_death_beat(pos: Vector2) -> void:
	var row := CombatRules.BOSS_DEATH_FEEL
	slow_mo(int(row["slow_ms"]), float(row["slow_scale"]), PRIORITY_DEATH)
	shake(float(row["shake_px"]), int(row["shake_ms"]))
	flash(Color(1.0, 0.95, 0.85, float(row["flash_alpha"])), int(row["flash_ms"]))
	Fx.hit_sparks(pos)
	Fx.burst(&"ring", pos)
	Fx.burst(&"ring", pos + Vector2(0.0, -10.0))
	Fx.rust_debris(pos)
	Sfx.play_at(CombatRules.sfx_key(StringName(row["sfx"])), pos, 0.04)
	Sfx.play_at(CombatRules.sfx_key(&"boss_roar"), pos, 0.04)


func _build_flash_layer() -> void:
	_flash_layer = CanvasLayer.new()
	_flash_layer.layer = 90
	add_child(_flash_layer)
	_flash_rect = ColorRect.new()
	_flash_rect.name = "Flash"
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.modulate.a = 0.0
	_flash_layer.add_child(_flash_rect)
	WorldClock.isolate_ui_layer(_flash_layer)
	# isolate 只该洗 RGB；再钉一次 alpha，避免以后隔离逻辑改回 Color.WHITE。
	_flash_rect.modulate.a = 0.0


func _update_shake_offset() -> void:
	if _shake_intensity <= 0.0:
		return
	var cam := _shake_camera()
	if cam == null:
		return
	var now := Time.get_ticks_msec()
	if now >= _shake_end_ms:
		_shake_intensity = 0.0
		cam.shake_offset = Vector2.ZERO
		return
	var span := maxf(1.0, float(_shake_end_ms - _shake_start_ms))
	var energy := float(_shake_end_ms - now) / span
	var jitter := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	cam.shake_offset = jitter * (_shake_intensity * energy)


## The active camera registers itself in the "game_camera" group. Cache it
## and rebind when a scene reload invalidates the old reference.
func _shake_camera() -> GameCamera:
	if _shake_cam != null and is_instance_valid(_shake_cam) and _shake_cam.is_inside_tree():
		return _shake_cam
	_shake_cam = null
	if _shake_lookup_failed:
		return null
	for node in get_tree().get_nodes_in_group("game_camera"):
		var cam := node as GameCamera
		if cam == null:
			continue
		if cam.is_current():
			_shake_cam = cam
			break
		if _shake_cam == null:
			_shake_cam = cam
	_shake_lookup_failed = _shake_cam == null
	return _shake_cam


func _on_hit(attacker: Node, target: Node, amount: int) -> void:
	if attacker == null or target == null:
		return
	if target.is_in_group("player"):
		var row := CombatRules.PLAYER_HURT
		Sfx.play(CombatRules.sfx_key(StringName(row["sfx"])))
		flash(row["flash"], int(row["flash_ms"]))
		hit_stop(int(row["stop_ms"]), float(row["stop_scale"]))
		shake(float(row["shake_px"]), int(row["shake_ms"]))
		return
	var killed := false
	var hp := target.get_node_or_null("Health") as Health
	if hp != null:
		killed = hp.current <= 0
	var weight := CombatRules.weight_for(attacker, amount, killed)
	var pos := hit_point(target)
	feel(CombatRules.material_of(target), weight, pos, _facing_angle(attacker, pos))


func _on_parried(projectile: Node, _by_actor: Node) -> void:
	var row := CombatRules.PARRY_FEEL
	slow_mo(CombatRules.PARRY_SLOWMO_MS, CombatRules.PARRY_SLOWMO_SCALE)
	flash(row["flash"], int(row["flash_ms"]))
	shake(float(row["shake_px"]), int(row["shake_ms"]))
	if projectile is Node2D:
		Fx.hit_sparks((projectile as Node2D).global_position)


func _on_player_died() -> void:
	flash(Color(0.09, 0.06, 0.05, 0.9), 700, true)
	slow_mo(650, 0.15)
	shake(6.0, 500)


## 命中点：优先取受击体的 Hurtbox 中心（脚底原点会把火花埋进地面）。
func hit_point(target: Node) -> Vector2:
	var hurt := target.get_node_or_null("Hurtbox") as Node2D
	if hurt != null:
		return hurt.global_position
	if target is Node2D:
		return (target as Node2D).global_position + Vector2(0.0, -12.0)
	return Vector2.ZERO


## 火花朝向：从攻击者指向命中点的水平方向（0 = 向右，PI = 向左）。
func _facing_angle(attacker: Node, pos: Vector2) -> float:
	if attacker is Projectile:
		return (attacker as Projectile).velocity.angle()
	if attacker is Node2D:
		return 0.0 if pos.x >= (attacker as Node2D).global_position.x else PI
	return 0.0
