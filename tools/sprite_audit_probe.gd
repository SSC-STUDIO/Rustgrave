extends Node
## 批量贴图放置审计：遍历全部战役关卡 + 竞技场 + 标题活景，跑 LevelSanity（既有
## 几何门禁）和 SpriteAudit（装饰贴图四类问题），把结果写成报告。
##   godot --headless --path . res://scenes/tools/SpriteAuditProbe.tscn [-- --out=res://reports --only=level04 --gate]
## --out  报告输出目录（默认 res://reports）
## --only 只扫一个场景（level04 / arena_duel / title_world）
## --gate 有 finding 时退出码为 1（给 CI 用）

const TITLE_SCENE := "res://scenes/ui/TitleWorld.tscn"
const REPORT_TXT := "sprite_audit_report.txt"
const REPORT_JSON := "sprite_audit_report.json"

var _out_dir := "res://reports"
var _only := ""
var _gate := false
var _report: Array[Dictionary] = []


func _ready() -> void:
	_parse_args()
	_isolate_save()
	await _scan_levels()
	await _scan_modes()
	await _scan_title()
	var total := _write_report()
	print("[SPRITE AUDIT] DONE total=%d report=%s" % [total, _out_dir.path_join(REPORT_TXT)])
	get_tree().quit(1 if (_gate and total > 0) else 0)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr("--only=".length())
		elif a.begins_with("--out="):
			_out_dir = a.substr("--out=".length())
		elif a == "--gate":
			_gate = true


## 与 decor_dump_probe.gd 同款存档隔离：不让开场演出/读档干扰几何。
func _isolate_save() -> void:
	SaveData.save_path = "user://sprite_audit.cfg"
	SaveData.delete_save()
	SaveData.flags.clear()
	SaveData.mark_flag("opening_seen")
	SaveData.mark_flag("wake")
	SaveData.pending_spawn = Vector2.INF
	SaveData.entering_from_checkpoint = false
	SaveData.ending = ""
	Director.abort()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _camera_limits() -> Rect2:
	var cam := get_tree().get_first_node_in_group("game_camera") as Camera2D
	if cam == null:
		return Rect2()
	return Rect2(Vector2(cam.limit_left, cam.limit_top),
			Vector2(cam.limit_right - cam.limit_left, cam.limit_bottom - cam.limit_top))


func _audit_scene(label: String, path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		_report.append({"scene": label, "path": path, "findings": [{
			"category": "load", "node": "", "texture": "", "pos": [], "z": 0,
			"detail": "scene failed to load", "suggestion": ""}]})
		return
	var level := packed.instantiate()
	add_child(level)
	await _frames(3)
	Director.abort()
	var limits := _camera_limits()
	var found: Array[Dictionary] = []
	for p in LevelSanity.check(level, limits):
		found.append({"category": "sanity", "node": "", "texture": "", "pos": [], "z": 0,
				"detail": p, "suggestion": ""})
	found.append_array(SpriteAudit.findings(level, limits))
	var kept := SpriteAudit.filter_whitelisted(label, found)
	var exempt := found.size() - kept.size()
	_report.append({"scene": label, "path": path, "findings": kept, "exempted": exempt})
	print("[SPRITE AUDIT] scene=%s findings=%d exempted=%d" % [label, kept.size(), exempt])
	level.free()
	await _frames(1)


func _scan_levels() -> void:
	for id in GameContext.LEVEL_ORDER:
		if _only != "" and id != _only:
			continue
		await _audit_scene(id, String(GameContext.LEVELS[id]))


func _scan_modes() -> void:
	for path in GameContext.MODE_SCENES:
		var label := String(path).get_file().get_basename().to_snake_case()
		if _only != "" and label != _only:
			continue
		await _audit_scene(label, String(path))


func _scan_title() -> void:
	if _only != "" and _only != "title_world":
		return
	TitleWorld.forced_state = {}
	var vp := SubViewport.new()
	vp.size = Vector2i(TitleWorld.WORLD)
	vp.world_2d = World2D.new()
	vp.disable_3d = true
	vp.snap_2d_transforms_to_pixel = true
	add_child(vp)
	var world := (load(TITLE_SCENE) as PackedScene).instantiate()
	vp.add_child(world)
	await _frames(3)
	var found := SpriteAudit.filter_whitelisted("title_world", SpriteAudit.check_title(world))
	_report.append({"scene": "title_world", "path": TITLE_SCENE, "findings": found, "exempted": 0})
	print("[SPRITE AUDIT] scene=title_world findings=%d" % found.size())
	vp.free()
	await _frames(1)


func _write_report() -> int:
	var total := 0
	var exempted := 0
	var lines: Array[String] = ["Rustgrave 贴图放置审计报告", ""]
	for entry in _report:
		var found: Array = entry["findings"]
		total += found.size()
		exempted += int(entry.get("exempted", 0))
		lines.append("== %s — %s ==" % [entry["scene"], entry["path"]])
		if found.is_empty():
			lines.append("  [OK]")
		for f in found:
			var pos: Array = f["pos"]
			var pos_str := "(%d,%d)" % [int(pos[0]), int(pos[1])] if pos.size() == 2 else "-"
			var line_str := "  [%s] %s %s %s z=%d :: %s" % [f["category"], f["node"],
					f["texture"], pos_str, int(f["z"]), f["detail"]]
			if String(f["suggestion"]) != "":
				line_str += "  -> %s" % f["suggestion"]
			lines.append(line_str)
		lines.append("")
	lines.append("TOTAL: %d findings across %d scenes (%d whitelisted intentional)" % [total, _report.size(), exempted])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var txt := FileAccess.open(_out_dir.path_join(REPORT_TXT), FileAccess.WRITE)
	if txt != null:
		txt.store_string("\n".join(lines) + "\n")
		txt.close()
	var js := FileAccess.open(_out_dir.path_join(REPORT_JSON), FileAccess.WRITE)
	if js != null:
		js.store_string(JSON.stringify({"findings": _report, "total": total}, "  "))
		js.close()
	return total
