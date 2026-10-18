extends Node
## 诊断用探针（非测试、非门禁）：抓标题屏开屏 + 设置弹窗开关场的中间帧。
##   godot --path . --windowed --resolution 1280x720 res://scenes/tools/TransitionProbe.tscn
## 产出 screenshots/peek/transition-*.png 与每帧的透明度/位置打印。

const OUT := "res://screenshots/peek/transition"
const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("TransitionProbe needs a render target")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var win := get_tree().root
	win.mode = Window.MODE_WINDOWED
	win.position = Vector2i(-12000, -12000)
	win.size = Vector2i(1280, 720)
	Engine.max_fps = 60
	SaveData.save_path = OUT + "/probe-save.cfg"
	SaveData.delete_save()
	SaveData.ending = ""
	Music.set_theme(&"title")

	var packed := load(TITLE_SCENE) as PackedScene
	var title := packed.instantiate()
	add_child(title)

	# 开屏：黑幕全压 → keyart 渗 → 字标 → 菜单逐行 → 收尾。
	await get_tree().create_timer(0.12).timeout
	_dump(title, "boot-0.12s (curtain still up)")
	await _capture("01-boot-curtain")
	await get_tree().create_timer(0.45).timeout
	_dump(title, "boot-0.57s (keyart in, masthead rising)")
	await _capture("02-boot-keyart")
	await get_tree().create_timer(0.35).timeout
	_dump(title, "boot-0.92s (rail crawling)")
	await _capture("03-boot-rail")
	await get_tree().create_timer(1.0).timeout
	_dump(title, "boot-1.92s (settled)")
	await _capture("04-boot-settled")
	ok(title.intro_playing() == false, "intro finished before settings opens")

	# 设置弹窗：滑入 → 静止 → 退场沉回。
	var settings: CanvasLayer = _find_layer(title, "SettingsScreen")
	title._on_chosen(&"settings")
	await get_tree().create_timer(0.05).timeout
	_dump(title, "settings +0.05s (card lifting)")
	await _capture("05-settings-in-early")
	await get_tree().create_timer(0.30).timeout
	_dump(title, "settings +0.35s (card home)")
	await _capture("06-settings-open")
	settings.close()
	await get_tree().create_timer(0.04).timeout
	_dump(title, "settings +0.04s after close (card sinking)")
	await _capture("07-settings-out-early")
	await get_tree().create_timer(0.30).timeout
	_dump(title, "settings +0.34s after close (gone)")
	await _capture("08-settings-closed")
	get_tree().quit(0)


func _dump(title: Node, tag: String) -> void:
	print("=== PROBE ", tag, " ===")
	var keyart := title.find_child("Keyart", true, false) as CanvasItem
	var masthead := title.find_child("Masthead", true, false) as CanvasItem
	var curtain := title.find_child("BootCurtain", true, false) as CanvasItem
	var settings := _find_layer(title, "SettingsScreen")
	if keyart != null:
		print("  keyart   alpha=%.3f" % keyart.modulate.a)
	if masthead != null:
		print("  masthead alpha=%.3f" % masthead.modulate.a)
	if curtain != null:
		print("  curtain  alpha=%.3f" % curtain.modulate.a)
	if settings != null:
		print("  settings visible=%s class=%s" % [settings.visible, settings.get_class()])
		var card := settings.find_child("Card", true, false) as Control
		var veil := settings.find_child("Veil", true, false) as CanvasItem
		if card != null:
			print("  card     alpha=%.3f pos=%s" % [card.modulate.a, str(card.position)])
		if veil != null:
			print("  veil     alpha=%.3f" % veil.modulate.a)


func _find_layer(root: Node, wanted: String) -> CanvasLayer:
	for child in root.get_children():
		if String(child.name) == wanted:
			return child as CanvasLayer
	# 类名缓存未同步时节点名是 @CanvasLayer@NNN：按脚本类名兜底。
		var script: Script = child.get_script()
		if script != null and String(script.get_global_name()) == wanted:
			return child as CanvasLayer
	return null


func ok(cond: bool, msg: String) -> void:
	print("  [%s] %s" % ["OK" if cond else "BAD", msg])


func _capture(id: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT, id]))
