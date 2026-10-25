class_name Resonance
extends Node
## 弹反炼出的短暂共鸣：2 秒窗口，不加第三条资源条。
## 钩索冷却减半、余烬步可再跳、双槽组合技在窗口里点亮。

signal started
signal ended

const DURATION := CombatRules.PARRY_RESONANCE

var _time: float = 0.0


func is_active() -> bool:
	return _time > 0.0


func is_resonating() -> bool:
	return is_active()


func remaining() -> float:
	return _time


func pulse() -> void:
	var was := _time > 0.0
	_time = DURATION
	if not was:
		started.emit()
		GameEvents.resonance_changed.emit(true)


func _process(delta: float) -> void:
	var player := get_parent() as Player
	if Director.is_input_locked() or (player != null and player.cutscene_locked):
		return
	if _time <= 0.0:
		return
	_time = maxf(0.0, _time - delta)
	if _time <= 0.0:
		ended.emit()
		GameEvents.resonance_changed.emit(false)
