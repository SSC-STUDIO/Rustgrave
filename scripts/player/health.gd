class_name Health
extends Node
## Simple hit-point pool with a short i-frame latch after a successful hit.

signal changed(current: int, maximum: int)
signal died

@export var max_hp: int = 5
@export var hit_iframe_time: float = CombatRules.HIT_IFRAMES

var current: int
var invincible: bool = false
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
	if host is Player:
		effective_damage = CombatRules.incoming_damage(amount)
	if host is Player and "stats" in host and host.stats != null and host.stats.has_method(&"get_defense_reduction"):
		effective_damage = maxi(1, effective_damage - host.stats.get_defense_reduction())
	current = maxi(0, current - effective_damage)
	_hit_iframe = hit_iframe_time
	changed.emit(current, max_hp)
	GameEvents.hit.emit(attacker, get_parent(), effective_damage)
	if current <= 0 and not _dead:
		_dead = true
		died.emit()
	return true


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
