class_name MobaRun
extends RefCounted
## The 3D arena has its own viewport and session. It never starts the retired
## 2.5D match or loads through GamePresentation's 2D world viewport.

const SCENE := "res://scenes/moba/RenderSpike.tscn"
const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"

static var _active := false
static var _leaving := false
static var _owner: Node = null
static var _saved_menu_hold := false


static func active() -> bool:
	return _active


static func start(change_scene: Callable = Callable()) -> bool:
	if _active or GameContext.tree() == null or not ResourceLoader.exists(SCENE):
		return false
	_begin()
	_release_input()
	if not _request_scene(SCENE, 0.45, change_scene):
		abandon()
		return false
	return true


## Also supports opening the standalone 3D scene directly in the editor.
static func attach(owner: Node) -> void:
	if not _active:
		_begin()
	_owner = owner
	# TitleScreen releases its clock hold when it leaves the tree. Reassert the
	# arena's hold after that exit without changing the campaign time/weather.
	WorldClock.menu_hold = true


static func detach(owner: Node) -> void:
	if owner != _owner:
		return
	abandon()


static func exit_to_title(change_scene: Callable = Callable()) -> bool:
	if not _active or _leaving:
		return false
	_leaving = true
	_release_input()
	if not _request_scene(TITLE_SCENE, 0.35, change_scene):
		_leaving = false
		return false
	# Keep the save guard until the 3D scene actually leaves the tree.
	return true


static func abandon() -> void:
	if _active:
		WorldClock.menu_hold = _saved_menu_hold
	_active = false
	_leaving = false
	_owner = null


static func _begin() -> void:
	_saved_menu_hold = WorldClock.menu_hold
	_active = true
	_leaving = false
	WorldClock.menu_hold = true


static func _release_input() -> void:
	var tree := GameContext.tree()
	if tree != null:
		tree.paused = false
	Director.choice_hold = false
	Director.resume()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


static func _request_scene(path: String, duration: float, change_scene: Callable) -> bool:
	if change_scene.is_valid():
		var result: Variant = change_scene.call(path, duration)
		if result is bool:
			return result
		if result is int:
			return result == OK
		return result == null
	Director.fade_to(path, duration)
	return true
