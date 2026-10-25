class_name ToxinMeter
extends Node
## Orange sludge fills this meter. At full, the host starts taking overflow damage.
## Toxin is also dirty fuel: potency() drives combat/mobility bonuses.

signal overflow_tick

const BAND_WARM := 30.0
const BAND_HOT := 60.0

@export var max_toxin: float = 100.0
@export var drain_per_second: float = 8.0
@export var overflow_interval: float = CombatRules.OVERFLOW_TICK

var toxin: float = 0.0
var _overflow_clock: float = 0.0
var _exposing: bool = false


## 0 = cold, 0.5 = warm, 0.85 = hot, 1.0 = overflow. Overflow keeps the bonus.
func potency() -> float:
	if toxin >= max_toxin - 0.01:
		return 1.0
	if toxin >= BAND_HOT:
		return 0.85
	if toxin >= BAND_WARM:
		return 0.5
	return 0.0


func band() -> StringName:
	return band_for(toxin, max_toxin)


## HUD / 读档共用同一套档位，避免百分比和战斗加成各算各的。
static func band_for(current: float, maximum: float) -> StringName:
	if maximum <= 0.0:
		return &"cold"
	if current >= maximum - 0.01:
		return &"overflow"
	if current >= BAND_HOT:
		return &"hot"
	if current >= BAND_WARM:
		return &"warm"
	return &"cold"


func band_label() -> String:
	return band_label_for(band())


static func band_label_for(id: StringName) -> String:
	match id:
		&"overflow":
			return "溢"
		&"hot":
			return "炽"
		&"warm":
			return "温"
		_:
			return "冷"


var stats: Object = null


func _get_toxin_resistance() -> float:
	var s: Object = stats
	if s == null:
		var p := get_parent()
		if p != null and "stats" in p:
			s = p.stats
	if s != null and s.has_method(&"get_toxin_resistance"):
		return clampf(float(s.get_toxin_resistance()), 0.0, 0.8)
	return 0.0


func _get_toxin_decay_bonus() -> float:
	var s: Object = stats
	if s == null:
		var p := get_parent()
		if p != null and "stats" in p:
			s = p.stats
	if s != null and s.has_method(&"get_toxin_decay_bonus"):
		return float(s.get_toxin_decay_bonus())
	return 0.0


func _process(delta: float) -> void:
	if not _exposing and toxin > 0.0:
		var decay_bonus := _get_toxin_decay_bonus()
		var effective_drain := drain_per_second * maxf(0.0, 1.0 + decay_bonus)
		toxin = maxf(0.0, toxin - effective_drain * delta)
		GameEvents.toxin_changed.emit(toxin, max_toxin)

	if toxin >= max_toxin - 0.01:
		_overflow_clock += delta
		if _overflow_clock >= overflow_interval:
			_overflow_clock = 0.0
			overflow_tick.emit()
	else:
		_overflow_clock = 0.0

	_exposing = false


func expose(amount: float) -> void:
	_exposing = true
	var res := _get_toxin_resistance()
	var effective_amount := amount * (1.0 - res) * CombatRules.toxin_fill_multiplier() if amount > 0.0 else amount
	toxin = clampf(toxin + effective_amount, 0.0, max_toxin)
	GameEvents.toxin_changed.emit(toxin, max_toxin)


func purify(fraction: float) -> void:
	toxin = maxf(0.0, toxin - max_toxin * fraction)
	GameEvents.toxin_changed.emit(toxin, max_toxin)


func is_full() -> bool:
	return toxin >= max_toxin - 0.01
