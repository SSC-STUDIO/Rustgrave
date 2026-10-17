class_name CorePickup
extends Interactable
## World drop for a Rust-Core.
## 场景摆放时在检查器里直接给 `core` 赋 .tres 资源；运行时掉落（敌人战利品）
## 不赋值则回退为钩锁核。

@export var core: RustCore


func _ready() -> void:
	super._ready()
	add_to_group("persistent")
	if core == null:
		core = AbilityCatalog.tether_core()
	prompt = "E 拾取 %s" % core.display_name
	ensure_sprite("res://assets/env/rust_core.png", Vector2(12, 12), Vector2(-1, -1), core.tint)
	var spr := get_node_or_null("Fill") as CanvasItem
	if spr:
		spr.modulate = Color(1, 1, 1)
	_bob()


func interact(actor: Node) -> void:
	if actor is Player and core:
		(actor as Player).collect_core(core)
		SaveData.mark_consumed(String(get_path()))
		# Save-at-pickup: the pouch and the consumed record hit the disk together, so a
		# death before the next nest can neither lose the core nor duplicate it.
		SaveData.persist_progress(actor)
		queue_free()


## --- persistence ---------------------------------------------------------
func get_persistent_state() -> Dictionary:
	# Handled through the consumed path list by apply_consumed; this hook keeps
	# us out of the world-state dictionary (node is freed once picked up).
	return {}


func apply_persistent_state(_state: Dictionary) -> void:
	pass


## 上下浮动（自我包含）：场景摆放与敌人掉落共用，提示这是可拾取物。
func _bob() -> void:
	var base_y := position.y
	var tween := create_tween().set_loops()
	tween.tween_property(self, "position:y", base_y - 6.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position:y", base_y, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
