extends CanvasLayer
## Director-owned presentation, below captions and above the world/HUD.
## Uses the Director clock: pause/suspend freezes blends, particles and prompts.

const Tableau := preload("res://scripts/ui/cinematic_tableau.gd")
const SHOTS := {
	"relic": ["剑先锈了", "I   /   铁 中 的 声 音", 0],
	"grave": ["无名者之墓", "II   /   被 遗 弃 的 偶", 1],
	"furnace": ["火还在下面", "III   /   最 后 一 点 余 烬", 2],
}

var front
var back
var skip_button: Button
var active_shot := ""
var _blend := 1.0
var _leaving := false
var _hint_age := 0.0
var _card_left := 0.0


func _ready() -> void:
	name = "CinematicPresentation"
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	WorldClock.isolate_ui_layer(self)
	PresentationMetrics.bind_layer(self)
	back = _make_canvas()
	front = _make_canvas()
	var prompt_layer := CanvasLayer.new()
	prompt_layer.layer = 16
	add_child(prompt_layer)
	WorldClock.isolate_ui_layer(prompt_layer)
	PresentationMetrics.bind_layer(prompt_layer)
	skip_button = Button.new()
	skip_button.name = "SkipCinematic"
	skip_button.text = "Enter · 继续"
	skip_button.position = Vector2(958, 610)
	skip_button.size = Vector2(286, 48)
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.visible = false
	skip_button.pressed.connect(Director.skip_step)
	prompt_layer.add_child(skip_button)
	Director.step_started.connect(_on_step)
	Director.finished.connect(_on_finished)


func _make_canvas() -> Control:
	var canvas := Tableau.new()
	canvas.size = Vector2(1280, 720)
	canvas.visible = false
	add_child(canvas)
	return canvas


func show_shot(id: String, title: String = "", subtitle: String = "") -> void:
	if not SHOTS.has(id) and id != "chapter" and id != "boss":
		return
	# Swap two bounded canvases, preserving the outgoing frame during a dissolve.
	var previous = back
	back = front
	front = previous
	front.move_to_front()
	front.shot = id
	front.age = 0.0
	front.number = 0
	front.heading = title
	front.subheading = subtitle
	if SHOTS.has(id):
		var data: Array = SHOTS[id]
		front.heading = data[0]
		front.subheading = data[1]
		front.number = data[2]
	front.visible = true
	front.modulate.a = 0.0
	active_shot = id
	_blend = 0.0
	_leaving = false
	_card_left = 2.6 if id == "boss" else 0.0
	front.queue_redraw()


func dismiss(immediate: bool = false) -> void:
	active_shot = ""
	_card_left = 0.0
	_leaving = true
	_blend = 0.0
	back.visible = false
	if immediate:
		front.visible = false
		_leaving = false


func _on_step(_index: int, step: Dictionary) -> void:
	var kind := String(step.get("kind", step.get("op", "")))
	if kind == "tableau":
		var id := String(step.get("id", ""))
		if id == "world":
			dismiss()
		else:
			show_shot(id, String(step.get("title", "")), String(step.get("subtitle", "")))


func _on_finished() -> void:
	dismiss(Director.is_aborting())
	skip_button.visible = false
	_hint_age = 0.0


func _process(delta: float) -> void:
	var frozen := Director.is_suspended() or get_tree().paused
	skip_button.visible = Director.playing and not frozen and _hint_age > 0.65
	if frozen:
		return
	if Director.playing:
		_hint_age += delta
		var touch := DisplayServer.is_touchscreen_available()
		if Director.skips_whole_script():
			skip_button.text = "点此跳过开场" if touch else "Enter · 跳过开场"
		else:
			skip_button.text = "点此继续" if touch else "Enter · 继续"
	else:
		_hint_age = 0.0
	if front.visible:
		front.age += delta
		front.queue_redraw()
	if back.visible:
		back.age += delta
		back.queue_redraw()
	_blend = minf(1.0, _blend + delta / 0.6)
	var amount := smoothstep(0.0, 1.0, _blend)
	front.modulate.a = 1.0 - amount if _leaving else amount
	back.modulate.a = 1.0
	if _blend >= 1.0:
		back.visible = false
		if _leaving:
			front.visible = false
			_leaving = false
	if _card_left > 0.0:
		_card_left -= delta
		if _card_left <= 0.0:
			dismiss()
