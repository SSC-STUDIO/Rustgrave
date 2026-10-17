class_name ScrapPile
extends Interactable
## Lootable scrap. Yields a Kiln Core (Heat Forge) in the test arena.

var _looted: bool = false

const SCRAP_TEX_PATH := "res://assets/env/rubble_a.png"


func _ready() -> void:
	super._ready()
	add_to_group("persistent")
	prompt = "E 搜刮废料堆"
	# 取墓碑下半段（27x24 原生区域）：断碑残块当废料堆，不再整图压扁。
	ensure_sprite(SCRAP_TEX_PATH, Vector2(27, 24), Vector2(-4, -6), Palette.RUST_DARK, Rect2(0, 15, 27, 24))


func can_interact(_actor: Node) -> bool:
	return not _looted


func interact(actor: Node) -> void:
	if _looted:
		return
	if actor is Player:
		_looted = true
		prompt = ""
		(actor as Player).collect_core(AbilityCatalog.kiln_core())
		modulate.a = 0.4
		GameEvents.announcement.emit("废料堆里摸到窑核")
		# Same save-at-pickup rule as CorePickup: looted flag and pouch land together.
		SaveData.persist_progress(actor)


func get_persistent_state() -> Dictionary:
	return {"looted": _looted}


func apply_persistent_state(state: Dictionary) -> void:
	if bool(state.get("looted", false)):
		_looted = true
		prompt = ""
		modulate.a = 0.4
