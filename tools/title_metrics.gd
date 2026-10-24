extends Node
## 标题屏布局度量：把 TitleScreen 实例化后打印每个有名块的全局矩形、
## 相互间距、与屏幕边缘/中线的关系。替代肉眼截图审查的几何探针。
##   godot --headless --path . res://scenes/tools/TitleMetrics.tscn

const TITLE := preload("res://scenes/ui/TitleScreen.tscn")

const SCREEN := Vector2(1280.0, 720.0)
const CENTER_X := 640.0


func _ready() -> void:
	await get_tree().process_frame
	var title = TITLE.instantiate()
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(title)
	# 等一帧让 _ready 建完全部子节点，再等几帧让 reset_size 落定。
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	print("=== TitleScreen layout @%dx%d ===" % [SCREEN.x, SCREEN.y])

	# 顶层 CanvasItem 的矩形（跳过全屏黑底/暗角这类背景层）。
	var named: Array[Dictionary] = []
	for child in title.get_children():
		var c := child as Control
		if c == null:
			continue
		var r := c.get_global_rect()
		var skip := c.name in ["WindowBackdrop"]
		named.append({
			"name": String(c.name),
			"rect": r,
			"skip": skip,
		})
	named.sort_custom(func(a, b): return String(a["name"]) < String(b["name"]))

	for e in named:
		var r: Rect2 = e["rect"]
		var tag := " [bg]" if e["skip"] else ""
		var off := ""
		if not e["skip"]:
			if r.position.x < 0.0 or r.position.y < 0.0:
				off += " NEG-ORIGIN"
			if r.end.x > SCREEN.x + 0.5 or r.end.y > SCREEN.y + 0.5:
				off += " OVERFLOW"
		print("%-18s x=%6.1f y=%6.1f w=%6.1f h=%6.1f%s%s" % [
				e["name"], r.position.x, r.position.y, r.size.x, r.size.y, tag, off])

	# 菜单行：逐行矩形 + 右端。
	var menu := title.get_node_or_null("Menu") as VBoxContainer
	if menu != null:
		print("--- menu rows ---")
		var i := 0
		for child in menu.get_children():
			var item := child as Control
			if item == null or not (item is MenuItem):
				continue
			var r := item.get_global_rect()
			print("row %d %-10s x=%6.1f y=%6.1f w=%6.1f h=%4.1f right=%6.1f mid=%s" % [
					i, item.name, r.position.x, r.position.y, r.size.x, r.size.y,
					r.end.x, "越中线!" if r.end.x > CENTER_X else ""])
			i += 1

	# 档案面板与菜单的左右关系。
	var dossier := title.find_child("Dossier", true, false) as Control
	var menu_rect: Rect2 = menu.get_global_rect() if menu != null else Rect2()
	if dossier != null:
		var d := dossier.get_global_rect()
		print("--- balance ---")
		print("menu left=%6.1f  dossier right=%6.1f" % [menu_rect.position.x, d.end.x])
		print("gap between menu right and dossier left = %6.1f" % [d.position.x - menu_rect.end.x])
		print("dossier h=%6.1f menu h=%6.1f" % [d.size.y, menu_rect.size.y])
		var top_gap := absf(d.position.y - menu_rect.position.y)
		print("top aligned? menu_y=%6.1f dossier_y=%6.1f delta=%6.1f" % [
				menu_rect.position.y, d.position.y, top_gap])

	# 字标/墓志/署名带。
	for path in ["Masthead", "Inscription", "CreditBand", "UpdateNotice"]:
		var n := title.find_child(path, true, false) as Control
		if n != null:
			var r := n.get_global_rect()
			print("%-12s x=%6.1f y=%6.1f w=%6.1f h=%6.1f" % [path, r.position.x, r.position.y, r.size.x, r.size.y])

	print("=== done ===")
	get_tree().quit(0)
