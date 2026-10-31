class_name TruthFragmentPickup
extends Interactable
## 禁区支线尽头的【真名残片】交互终端。
##
## 拾取效果：
##   1. 点亮对应 `truth_1..5` 与 `branch0X_done` 存档旗标（若集齐 5 枚自动解锁 `true_ending_unlocked`）；
##   2. 抛出 `GameEvents.truth_fragment_acquired(fragment_id)` 驱动真伊尔原声实时演出；
##   3. 自动持久化玩家装备、锈核与剧情进度；
##   4. 在正式游玩时延时弹出树状节点选关图（测试环境可通过 `auto_open_map = false` 抑制弹窗）。

signal collected(fragment_id: String)

const BODY_SIZE := Vector2(32.0, 40.0)
const BODY_OFFSET := Vector2(-16.0, -40.0)

@export var fragment_id: String = "truth_1"
@export var branch_id: String = "branch01"
@export var auto_open_map: bool = true

var _taken: bool = false
var _pulse: float = 0.0


func _ready() -> void:
	super._ready()
	z_index = 2
	prompt = "E 拾取真名残片"
	ensure_sprite("res://assets/env/statue_keeper.png", BODY_SIZE, BODY_OFFSET, Color("#9BE4FF"), Rect2(0, 0, 32, 40))
	if SaveData.has_flag(fragment_id):
		_set_collected_visual()


func feet_point() -> Vector2:
	return global_position


func can_interact(_actor: Node) -> bool:
	return not _taken


func get_prompt(_actor: Node) -> String:
	var spec := NarrativeCatalog.fragment_spec(fragment_id)
	var title := String(spec.get("title", "真名残片"))
	return "E 回收 · %s" % title


func interact(actor: Node) -> void:
	if _taken:
		return
	_taken = true
	SaveData.mark_flag(fragment_id)
	if branch_id != "":
		SaveData.mark_node_cleared(branch_id)
	if NarrativeCatalog.all_fragments_collected(SaveData.flags):
		SaveData.unlock_node("stage08_true")
		SaveData.mark_flag("true_ending_unlocked")
	SaveData.persist_story(actor)
	SaveData.save_equipment(actor)

	Sfx.play(&"core_get")
	Juice.flash(Color(0.75, 0.94, 1.0, 1.0), 0.28, 0.22)
	Juice.shake(3.0, 180)
	_set_collected_visual()

	GameEvents.interact_prompt.emit("")
	GameEvents.truth_fragment_acquired.emit(fragment_id)
	collected.emit(fragment_id)

	if auto_open_map and not Director.is_test_runner():
		_open_node_map_later()


func _set_collected_visual() -> void:
	_taken = true
	var fill := get_node_or_null("Fill") as CanvasItem
	if fill != null:
		fill.modulate = Color(0.55, 0.72, 0.82, 0.65)
	queue_redraw()


func _open_node_map_later() -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(2.2).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	var ui := GameContext.ui_host(self)
	if ui == null:
		return
	var pause := ui.find_child("PauseMenu", true, false) as PauseMenu
	if pause != null and not pause.is_open():
		pause.open()
		if pause.is_open():
			pause.call("_on_chosen", PauseMenu.ID_MAP)


func _process(delta: float) -> void:
	if _taken:
		return
	_pulse += delta * 3.6
	queue_redraw()


func _draw() -> void:
	if _taken:
		return
	var glow_y := -BODY_SIZE.y - 10.0 + sin(_pulse) * 2.5
	var center := Vector2(0.0, glow_y)
	draw_circle(center, 9.0, Color(0.61, 0.89, 1.0, 0.22))
	var pts := PackedVector2Array([
		center + Vector2(0.0, -6.0),
		center + Vector2(5.0, 0.0),
		center + Vector2(0.0, 6.0),
		center + Vector2(-5.0, 0.0),
	])
	draw_colored_polygon(pts, Color("#C9F2FF"))
