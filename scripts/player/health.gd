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
	current = maxi(0, current - amount)
	_hit_iframe = hit_iframe_time
	changed.emit(current, max_hp)
	GameEvents.hit.emit(attacker, get_parent(), amount)
	if current <= 0 and not _dead:
		_dead = true
		died.emit()
	return true


func heal_full() -> void:
	current = max_hp
	_dead = false
	changed.emit(current, max_hp)
