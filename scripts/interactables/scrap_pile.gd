class_name ScrapPile
extends Interactable
## Lootable scrap. Yields a Kiln Core (Heat Forge) in the test arena.

@export var equipment_item: EquipmentItem = null
@export var equipment_id: StringName = &""
@export var drop_as_pickup: bool = false

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
		var player := actor as Player

		# 1. 优先处理装备掉落/获取
		if equipment_item != null or equipment_id != &"":
			var item: EquipmentItem = equipment_item
			if item == null and equipment_id != &"" and ResourceLoader.exists("res://scripts/data/equipment_catalog.gd"):
				var catalog: GDScript = load("res://scripts/data/equipment_catalog.gd")
				if catalog != null and catalog.has_method("for_id"):
					item = catalog.call("for_id", equipment_id)

			if item != null:
				if drop_as_pickup:
					var pickup_scene: PackedScene = load("res://scenes/interactables/EquipmentPickup.tscn")
					if pickup_scene != null:
						var pickup = pickup_scene.instantiate()
						pickup.name = "ScrapEquip_%s" % name
						pickup.item = item
						pickup.position = position + Vector2(16.0, -6.0)
						var parent_node := get_parent()
						if parent_node != null:
							parent_node.add_child(pickup)
						GameEvents.announcement.emit("废料堆崩塌，掉出装备！")
				else:
					var equip_inv: Node = null
					if "equipment_inventory" in player and player.equipment_inventory != null:
						equip_inv = player.equipment_inventory
					elif "equipment" in player and player.equipment != null:
						equip_inv = player.equipment
					elif player.has_node("EquipmentInventory"):
						equip_inv = player.get_node("EquipmentInventory")

					if equip_inv != null and equip_inv.has_method("add_to_bag"):
						var added: bool = equip_inv.call("add_to_bag", item)
						if not added:
							GameEvents.announcement.emit("装备背包已满，无法搜刮")
							return
					GameEvents.announcement.emit("废料堆里摸到装备：%s" % item.display_name)
		else:
			# 2. 默认保持原逻辑（掉落窑核），保证 interactables_test 100% 回归通过
			player.collect_core(AbilityCatalog.kiln_core())
			GameEvents.announcement.emit("废料堆里摸到窑核")

		_looted = true
		prompt = ""
		modulate.a = 0.4
		# Same save-at-pickup rule as CorePickup: looted flag and pouch land together.
		SaveData.persist_progress(actor)


func get_persistent_state() -> Dictionary:
	return {"looted": _looted}


func apply_persistent_state(state: Dictionary) -> void:
	if bool(state.get("looted", false)):
		_looted = true
		prompt = ""
		modulate.a = 0.4
