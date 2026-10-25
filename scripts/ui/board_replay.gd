extends RefCounted
## 分镜回放接线：暂停菜单「故事」页与标题「回看余烬」页共用。
##
## 回放走 Director.board().play_board(id, {"replay": true})：
##   · replay 不写「看过」旗标、不受 Director 暂停影响，Enter 推进、Esc 跳过整段；
##   · 回放时播放器升到层 24（平时分镜在层 13），盖过暂停菜单 / 标题的覆盖层；调用方仍在
##     `started` 里先把自己藏起来，在 `finished` 里再恢复（藏与恢复由调用方决定，这里只管接线）；
##   · 已经有一段分镜在播（Director 自己的 board 步骤）时拒绝回放，免得打断主线。
##
## 本文件不写 class_name：调用方按 preload 取用（避开 .godot 类缓存）。

signal started(id: String)
signal finished(id: String, completed: bool)

const Boards := preload("res://scripts/data/storyboards.gd")

var playing := false
var current_id := ""


## 这段分镜现在能不能回放（有数据、播放器在、没有别的分镜在播）。
static func available(id: String) -> bool:
	if id == "" or not Boards.has(id):
		return false
	return Director.board() != null and not Director.board_active()


## 开始回放。成功返回 true（此后 `finished` 一定会发一次）；失败返回 false，什么都没改。
func start(id: String) -> bool:
	if playing or not available(id):
		return false
	var board: Object = Director.board()
	if not board.is_connected(&"board_finished", _on_board_finished):
		board.connect(&"board_finished", _on_board_finished)
	if not bool(board.call(&"play_board", id, {"replay": true})):
		return false
	playing = true
	current_id = id
	started.emit(id)
	return true


## 外部强停（页面被收起 / 场景被换）：播放器立刻收起，`finished(id, false)` 照发。
func abort() -> void:
	if not playing:
		return
	var board: Object = Director.board()
	if board != null:
		board.call(&"abort")
	# 播放器没有按约发 board_finished（例如已被别处收掉）时，自己收尾。
	if playing:
		_on_board_finished(current_id, false)


func _on_board_finished(id: String, completed: bool) -> void:
	if not playing:
		return
	playing = false
	current_id = ""
	finished.emit(id, completed)
