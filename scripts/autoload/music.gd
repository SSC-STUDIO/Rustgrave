extends Node
## Music director autoload. Owns the `Music` bus: which bed plays for the current
## place (theme), how tense it is (state), and one-shot stingers.
## Do not give this script a class_name — the autoload name is the API.
##
## CONTRACT (other scripts call only these; the audio work package implements them):
##   Music.set_theme(&"graveyard")   place identity: title, graveyard, undercroft, town,
##                                   cathedral, workshop, bell_tower, slag, ramparts, core
##   Music.set_state(&"danger")      calm | danger | boss | ending | silent
##   Music.stinger(&"boss_intro")    chapter, boss_intro, boss_down, ability, death, rest, ending_*
##   Music.duck(-9.0, 0.6)           temporary dip (dialogue, pause) in dB over seconds
## Every method is safe to call at any time, including headless and before assets exist.

signal theme_changed(theme_id: StringName)
signal state_changed(state_id: StringName)

var theme_id: StringName = &""
var state_id: StringName = &"calm"


func set_theme(id: StringName) -> void:
	if id == theme_id:
		return
	theme_id = id
	theme_changed.emit(id)


func set_state(id: StringName) -> void:
	if id == state_id:
		return
	state_id = id
	state_changed.emit(id)


func stinger(_id: StringName) -> void:
	pass


func duck(_amount_db: float, _seconds: float) -> void:
	pass
