class_name RustCoreInventory
extends Node
## Sword sockets + a small pouch. Inserting a core unlocks its ability_id.

signal pouch_changed
signal sockets_changed

@export var socket_count: int = 2

var pouch: Array = []
var sockets: Array = []


func _ready() -> void:
	sockets.clear()
	for _i in socket_count:
		sockets.append(null)


func add_to_pouch(core: RustCore) -> void:
	pouch.append(core)
	pouch_changed.emit()
	GameEvents.core_acquired.emit(core)
	GameEvents.announcement.emit("获得锈核：%s" % core.display_name)


func insert_into_socket(index: int) -> bool:
	if index < 0 or index >= sockets.size():
		return false
	if pouch.is_empty():
		GameEvents.announcement.emit("背包里没有锈核")
		return false
	if sockets[index] != null:
		pouch.append(sockets[index])
	var core: RustCore = pouch.pop_front()
	sockets[index] = core
	sockets_changed.emit()
	pouch_changed.emit()
	GameEvents.sockets_changed.emit()
	GameEvents.core_inserted.emit(core, index)
	GameEvents.ability_unlocked.emit(core.ability_id)
	Sfx.play(&"insert")
	var voice := _first_voice(core.ability_id)
	if voice != "":
		GameEvents.announcement.emit(voice)
	else:
		GameEvents.announcement.emit(
			"嵌核 %d：%s（%s）" % [index + 1, core.display_name, AbilityIds.display_name(core.ability_id)]
		)
	return true


func insert_first_available() -> bool:
	for i in sockets.size():
		if sockets[i] == null:
			return insert_into_socket(i)
	# All full — replace socket 0.
	return insert_into_socket(0)


func has_ability(ability_id: StringName) -> bool:
	for core in sockets:
		if core != null and (core as RustCore).ability_id == ability_id:
			return true
	return false


func has_pair(a: StringName, b: StringName) -> bool:
	return has_ability(a) and has_ability(b)


func socket_core(index: int) -> RustCore:
	if index < 0 or index >= sockets.size():
		return null
	return sockets[index]


## 每种能力第一次入座时说一句职称。之后回到普通嵌核播报，不再锁操作。
func _first_voice(ability_id: StringName) -> String:
	var key := "voice_%s" % String(ability_id)
	if SaveData.has_flag(key):
		return ""
	var line := ""
	match ability_id:
		AbilityIds.HEAT_FORGE:
			line = "窑匠：把火留在刃上。门会自己让开。"
		AbilityIds.HOOKSHOT_TETHER:
			line = "系索匠：你很重。让世界过来。"
		AbilityIds.EMBER_STEP:
			line = "余烬步：灰还能再跳一次。别问它从谁身上来。"
		_:
			return ""
	SaveData.mark_flag(key)
	return line
