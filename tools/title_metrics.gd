extends Node
## 标题屏布局度量：把 TitleScreen 实例化后打印每个有名块在 1280x720 设计空间里的矩形、
## 相互是否重叠、与屏幕边缘 / 中线的关系，再按 1920x1080 与 21:9 窗口各量一遍物理像素。
## 替代肉眼截图审查的几何探针（灯标版式：左下刻字菜单 / 右侧短注 / 底部墓志 + 页脚）。
##   godot --headless --path . res://scenes/tools/TitleMetrics.tscn

const TITLE := preload("res://scenes/ui/TitleScreen.tscn")

const SCREEN := Vector2(1280.0, 720.0)
const CENTER_X := 640.0
## 必须互不重叠的区块（节点名）。
const BLOCKS := ["Masthead", "Subtitle", "Menu", "JourneyColumn", "Epitaph", "CreditBand", "UpdateNotice"]
const WINDOWS := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080)]


func _ready() -> void:
	await get_tree().process_frame
	var title: TitleScreen = TITLE.instantiate()
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(title)
	# 等一帧让 _ready 建完全部子节点，再等几帧让 reset_size 落定。
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	title._skip_intro()
	var notice := title.find_child("UpdateNotice", true, false) as Control
	if notice != null:
		notice.visible = true
	await get_tree().process_frame

	print("=== TitleScreen layout @%dx%d (design space) ===" % [SCREEN.x, SCREEN.y])
	var problems := 0

	# 顶层有名块（跳过全屏背景层）。
	var rects := {}
	for block in BLOCKS:
		var node := title.find_child(block, true, false) as Control
		if node == null:
			print("%-14s MISSING" % block)
			problems += 1
			continue
		var r := title.design_rect(node)
		rects[block] = r
		var flag := ""
		if r.position.x < -0.5 or r.position.y < -0.5 or r.end.x > SCREEN.x + 0.5 or r.end.y > SCREEN.y + 0.5:
			flag = " OVERFLOW"
			problems += 1
		print("%-14s x=%7.1f y=%7.1f w=%7.1f h=%7.1f  right=%7.1f bottom=%7.1f%s" % [
				block, r.position.x, r.position.y, r.size.x, r.size.y, r.end.x, r.end.y, flag])

	# 菜单行：逐行矩形 + 右端。
	var menu := title.get_node_or_null("Menu") as MenuList
	if menu != null:
		print("--- menu rows ---")
		var i := 0
		for item in menu.items():
			var r := title.design_rect(item as Control)
			var over := " 越中线!" if r.end.x > CENTER_X else ""
			if over != "":
				problems += 1
			print("row %d %-10s x=%6.1f y=%6.1f w=%6.1f h=%4.1f right=%6.1f%s" % [
					i, String((item as MenuItem).id), r.position.x, r.position.y, r.size.x, r.size.y, r.end.x, over])
			i += 1
		var quit := menu.items()[menu.items().size() - 1] as Control
		var epitaph := rects.get("Epitaph", Rect2()) as Rect2
		print("quit centre y=%.1f  epitaph centre y=%.1f  (must match within 2px: %s)" % [
				title.design_rect(quit).get_center().y, epitaph.get_center().y,
				"ok" if absf(title.design_rect(quit).get_center().y - epitaph.get_center().y) <= 2.0 else "BAD"])

	# 重叠检查（设计空间）。
	print("--- overlaps (design space) ---")
	var names := rects.keys()
	for a in names.size():
		for b in range(a + 1, names.size()):
			var ra: Rect2 = rects[names[a]]
			var rb: Rect2 = rects[names[b]]
			if ra.grow(-0.6).intersects(rb.grow(-0.6)):
				print("OVERLAP %s x %s  %s vs %s" % [names[a], names[b], ra, rb])
				problems += 1
	print("overlap check done")

	# 展开的档案卡不能压到字标 / 菜单 / 墓志。
	var dossier := title.find_child("Dossier", true, false) as Control
	if dossier != null:
		var d := title.design_rect(dossier)
		print("dossier card  x=%6.1f y=%6.1f w=%6.1f h=%6.1f" % [d.position.x, d.position.y, d.size.x, d.size.y])
		for other in ["Subtitle", "Menu", "Epitaph", "CreditBand"]:
			if rects.has(other) and d.grow(-0.6).intersects(rects[other]):
				print("OVERLAP Dossier x %s" % other)
				problems += 1

	# 三种窗口的物理像素：每块都在内容矩形内。
	for win in WINDOWS:
		var metrics := PresentationMetrics.calculate(win)
		var xf: Transform2D = metrics["ui_transform"]
		title.position = xf.origin
		title.scale = xf.get_scale()
		await get_tree().process_frame
		var root_scale := Vector2(win) / Vector2(PresentationMetrics.UI_SIZE)
		var content: Rect2 = metrics["physical_rect"]
		var bad := 0
		for block in BLOCKS:
			var node := title.find_child(block, true, false) as Control
			if node == null:
				continue
			var gxf := node.get_global_transform()
			var a: Vector2 = gxf * Vector2.ZERO
			var b: Vector2 = gxf * node.size
			var phys := Rect2(a * root_scale, (b - a) * root_scale).abs()
			if not content.grow(0.6).encloses(phys):
				print("  %s outside the content rect @%s: %s vs %s" % [block, win, phys, content])
				bad += 1
		problems += bad
		print("window %s  scale=%d  content=%s  blocks outside: %d" % [win, int(metrics["scale"]), content, bad])

	print("=== done: %d problem(s) ===" % problems)
	get_tree().quit(0 if problems == 0 else 1)
