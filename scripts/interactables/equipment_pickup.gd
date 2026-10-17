class_name EquipmentPickup
extends Interactable
## 场景/敌人掉落的装备拾取物。
## 继承 Interactable (collision_layer = 64, collision_mask = 2)。
## 交互时将装备加入玩家背包（或槽位为空时自动穿戴）、播报获取提示、在 SaveData 中标记已消耗并销毁节点。

@export var item: EquipmentItem = null
@export var item_id: StringName = &""
@export var float_amplitude: float = 5.0
@export var float_duration: float = 0.6

# 兼容 MockEquipmentPickup 属性访问
var item_name: String:
	get:
		if item != null:
			return item.display_name
		return _item_name
	set(val):
		_item_name = val

var _item_name: String = ""


func _ready() -> void:
	super._ready()
	add_to_group("persistent")

	# 检查存档消耗记录（防止跨场景/重载时重复刷出）
	if SaveData.is_consumed(String(get_path())):
		queue_free()
		return

	_resolve_item_fallback()
	_update_prompt()
	_setup_visual()
	_bob()


func _resolve_item_fallback() -> void:
	if item == null:
		if item_id != &"" and ResourceLoader.exists("res://scripts/data/equipment_catalog.gd"):
			var catalog: GDScript = load("res://scripts/data/equipment_catalog.gd")
			if catalog != null and catalog.has_method("for_id"):
				item = catalog.call("for_id", item_id)
		if item == null and ResourceLoader.exists("res://scripts/data/equipment_catalog.gd"):
			var catalog: GDScript = load("res://scripts/data/equipment_catalog.gd")
			if catalog != null and catalog.has_method("broken_sword"):
				item = catalog.call("broken_sword")


func _update_prompt() -> void:
	var name_str: String = item.display_name if item != null else (_item_name if _item_name != "" else "装备")
	prompt = "E 拾取 %s" % name_str


func _setup_visual() -> void:
	# 视装备部位赋予不同色调
	var tint: Color = Palette.EMBER
	if item != null:
		match item.slot_type:
			&"weapon":
				tint = Palette.EMBER
			&"armor":
				tint = Palette.TEAL
			&"trinket":
				tint = Palette.RUST_LIGHT
	ensure_sprite("res://assets/env/rust_core.png", Vector2(14, 14), Vector2(-7, -7), tint)
	var spr := get_node_or_null("Fill") as CanvasItem
	if spr:
		spr.modulate = Color(1.2, 1.2, 1.2)


func _bob() -> void:
	var base_y: float = position.y
	var tween: Tween = create_tween().set_loops()
	tween.tween_property(self, "position:y", base_y - float_amplitude, float_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position:y", base_y, float_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func interact(actor: Node) -> void:
	if not actor is Player:
		return
	var player := actor as Player
	_resolve_item_fallback()

	# 寻找玩家身上的装备背包组件
	var equip_inv: Node = null
	if "equipment_inventory" in player and player.equipment_inventory != null:
		equip_inv = player.equipment_inventory
	elif "equipment" in player and player.equipment != null:
		equip_inv = player.equipment
	elif player.has_node("EquipmentInventory"):
		equip_inv = player.get_node("EquipmentInventory")

	if equip_inv != null:
		var target: Variant = item if item != null else (item_id if item_id != &"" else &"broken_sword")
		var added: bool = false
		if equip_inv.has_method("add_to_bag"):
			added = equip_inv.call("add_to_bag", target)
		if not added and equip_inv.has_method("equip_item"):
			# If bag is full or failed, try auto-equipping if matching slot is empty
			var resolved: Variant = equip_inv.call("_resolve_item", target) if equip_inv.has_method("_resolve_item") else target
			var slot: StringName = equip_inv.call("_get_item_slot", resolved) if equip_inv.has_method("_get_item_slot") else &""
			if slot != &"" and equip_inv.call("get_equipped", slot) == null:
				added = equip_inv.call("equip_item", resolved, slot)
		if not added:
			GameEvents.announcement.emit("装备背包已满")
			return

	# 标记消耗并播报
	SaveData.mark_consumed(String(get_path()))
	var name_str: String = item.display_name if item != null else (_item_name if _item_name != "" else "装备")
	GameEvents.announcement.emit("获得装备：%s" % name_str)

	# 视听反馈
	Sfx.play_at(&"pickup", global_position)
	Fx.rust_debris(global_position)

	queue_free()


## --- persistence ---------------------------------------------------------
func get_persistent_state() -> Dictionary:
	return {}


func apply_persistent_state(_state: Dictionary) -> void:
	pass
