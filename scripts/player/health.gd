class_name Health
extends Node
## Simple hit-point pool with a short i-frame latch after a successful hit.

signal changed(current: int, maximum: int)
signal died

@export var max_hp: int = 5
@export var hit_iframe_time: float = CombatRules.HIT_IFRAMES

var current: int
var invincible: bool = false
## AI 打 AI 时为 true：不发 GameEvents.hit，避免满屏顿帧。玩家打出或受到的伤害仍会发。
var quiet: bool = false
var _hit_iframe: float = 0.0
var _dead: bool = false


func _ready() -> void:
	current = max_hp
	changed.emit(current, max_hp)


func _process(delta: float) -> void:
	if _hit_iframe > 0.0:
		_hit_iframe = maxf(0.0, _hit_iframe - delta)


func is_invincible() -> bool:
	return invincible or _hit_iframe > 0.0 or _dead


func take_damage(amount: int, attacker: Node = null) -> bool:
	if amount <= 0 or is_invincible():
		return false
	var effective_damage := amount
	var host := get_parent()
	var incoming := 1.0
	if host is Player:
		incoming = clampf(float(Settings.value(&"assist_incoming", 1.0)), 0.5, 1.5)
		if not is_equal_approx(incoming, 1.0):
			effective_damage = int(round(float(amount) * incoming))
	if host is Player and "stats" in host and host.stats != null and host.stats.has_method(&"get_defense_reduction"):
		effective_damage -= host.stats.get_defense_reduction()
	# 默认倍率仍至少扣 1 点，和改辅助选项之前一样。调低之后允许四舍五入到 0。
	effective_damage = maxi(1, effective_damage) if is_equal_approx(incoming, 1.0) else maxi(0, effective_damage)
	if effective_damage <= 0:
		return false
	current = maxi(0, current - effective_damage)
	_hit_iframe = hit_iframe_time
	changed.emit(current, max_hp)
	if _should_broadcast_hit(attacker):
		GameEvents.hit.emit(attacker, get_parent(), effective_damage)
	if current <= 0 and not _dead:
		_dead = true
		died.emit()
	return true


func grant_iframes(seconds: float) -> void:
	_hit_iframe = maxf(_hit_iframe, maxf(0.0, seconds))


func _should_broadcast_hit(attacker: Node) -> bool:
	if not quiet:
		return true
	var host := get_parent()
	if host is Player:
		return true
	return _attacker_is_player(attacker)


func _attacker_is_player(attacker: Node) -> bool:
	var cursor: Node = attacker
	var guard := 0
	while cursor != null and guard < 8:
		if cursor is Player or cursor.is_in_group("player"):
			return true
		cursor = cursor.get_parent()
		guard += 1
	return false


## Dynamically adjust max_hp pool with strict resurrection latch protection
## and exploit-free health preservation.
func set_max_hp(new_max: int) -> void:
	new_max = maxi(1, new_max)
	if new_max == max_hp:
		return
	max_hp = new_max
	if _dead or current <= 0:
		current = 0
		_dead = true
	else:
		current = clampi(current, 1, max_hp)
	changed.emit(current, max_hp)


func heal_full() -> void:
	current = max_hp
	_dead = false
	changed.emit(current, max_hp)


## 定量回血（奖励位回退、未来消耗品）。不会复活已死亡单位；返回实际回复量。
func heal(amount: int) -> int:
	if amount <= 0 or _dead or current >= max_hp:
		return 0
	var before := current
	current = clampi(current + amount, 0, max_hp)
	changed.emit(current, max_hp)
	return current - before
