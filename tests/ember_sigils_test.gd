extends TestCase
## 余烬印记（EmberSigils + TitleSigilRing）：炉厅记得你来过。
##
## 覆盖：记录存储的往返与上限、「多久之前」的人话、关卡 id 反查章名、
## 生产写入的 headless 闸门、印记环的接线与显现、标题屏集成——
## 私人墓志 / 行尾魂注 / 档案卡印记行。
## 测试一律走 append_raw + 临时 store_path（record_visit 在 headless 下是空操作，
## 这里再把 recording_enabled 关上，窗口化跑套件也不会污染生产记录）。

const TITLE_SCENE := "res://scenes/ui/TitleScreen.tscn"
const STORE := "user://ember_sigils_test.cfg"


func setup() -> void:
	EmberSigils.store_path = STORE
	EmberSigils.recording_enabled = false
	EmberSigils.clear()
	TitleWorld.forced_state = {}


func teardown() -> void:
	EmberSigils.clear()
	EmberSigils.recording_enabled = true
	EmberSigils.store_path = EmberSigils.DEFAULT_STORE
	TitleWorld.forced_state = {}


func test_store_roundtrip_caps_and_kinds() -> void:
	eq(EmberSigils.visit_count(), 0, "新仓库是空的")
	var rec := EmberSigils.append_raw(100, "new", "stage01")
	eq(int(rec.d), 100, "记录带着天戳")
	eq(String(rec.k), "new")
	EmberSigils.append_raw(105, "continue", "stage02")
	eq(EmberSigils.visit_count(), 2)
	EmberSigils.append_raw(106, "death", "stage02")
	eq(EmberSigils.deaths.size(), 1, "殁痕单独记")
	eq(String(EmberSigils.last_death().c), "stage02", "最近一次殁于 stage02")
	# 从同一份文件重载，数据还在。
	EmberSigils.load_store()
	eq(EmberSigils.visit_count(), 2, "重载后点燃记录还在")
	eq(EmberSigils.deaths.size(), 1, "重载后殁痕还在")
	# visits 只保留最近 MAX_VISITS 条。
	for i in EmberSigils.MAX_VISITS + 8:
		EmberSigils.append_raw(200 + i, "continue", "stage01")
	eq(EmberSigils.visit_count(), EmberSigils.MAX_VISITS, "超出上限后截断")
	ok(int(EmberSigils.visits[0].d) == 208, "最老的先被挤出去")
	EmberSigils.clear()
	eq(EmberSigils.visit_count(), 0, "clear 之后是空的")


func test_ago_text_is_human() -> void:
	eq(EmberSigils.ago_text(0), "今天")
	eq(EmberSigils.ago_text(1), "昨天")
	eq(EmberSigils.ago_text(7), "7 天前")
	eq(EmberSigils.ago_text(29), "29 天前")
	eq(EmberSigils.ago_text(75), "2 个月前")


func test_chapter_label_lookup() -> void:
	eq(EmberSigils.chapter_label_of(""), "", "空 id 给空名")
	eq(EmberSigils.chapter_label_of("stage01"), "腐液墓园", "主线章名")
	eq(EmberSigils.chapter_label_of("nope"), "", "认不出的 id 不硬编")


func test_production_recording_is_gated_off_in_automation() -> void:
	# recording_enabled=false（本套件 setup 关掉）或 headless 时都不写。
	ok(EmberSigils.record_visit("new", "stage01").is_empty(), "闸门关上时返回空")
	eq(EmberSigils.visit_count(), 0, "什么都没记")


func test_ring_holds_records_and_reveals() -> void:
	var ring := TitleSigilRing.new()
	add_child(ring)
	ok(not ring.has_marks(), "没喂记录时环是空的")
	eq(ring.tick_count(), 0)
	# 空环不画（draw 里直接 return，不报错即可）。
	ring.queue_redraw()
	var visits: Array[Dictionary] = [
		{"d": EmberSigils.today() - 40, "label": "腐液墓园"},
		{"d": EmberSigils.today(), "label": "沉钟水渠"},
	]
	ring.configure(visits, [{"d": EmberSigils.today() - 1, "label": "腐液墓园"}])
	ok(ring.has_marks())
	eq(ring.tick_count(), 2, "两枚点燃刻度")
	ring.wake(0.0)
	ring.skip_reveal()
	almost(ring.reveal, 1.0, 0.001, "skip_reveal 后整环全亮")
	# 超过 MAX_TICKS 的记录只留最近的。
	var many: Array[Dictionary] = []
	for i in TitleSigilRing.MAX_TICKS + 5:
		many.append({"d": EmberSigils.today() - i, "label": ""})
	ring.configure(many, [])
	eq(ring.tick_count(), TitleSigilRing.MAX_TICKS, "刻度封顶 64")
	ring.queue_free()


func test_title_wires_ring_epitaph_ghosts_and_dossier() -> void:
	var today := EmberSigils.today()
	EmberSigils.append_raw(today - 2, "new", "stage01")
	EmberSigils.append_raw(today - 1, "continue", "stage02")
	EmberSigils.append_raw(today, "death", "stage01")
	var packed := load(TITLE_SCENE) as PackedScene
	var title := packed.instantiate() as TitleScreen
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	var ring := title.find_child("SigilRing", true, false) as TitleSigilRing
	ok(ring != null, "印记环挂在标题屏上")
	if ring != null:
		eq(ring.tick_count(), 2, "环上有两枚点燃刻度")
	# 墓志轮换表：第一句永远是 EPITAPH，私人句子接在经典句后面。
	var lines := title._ep_lines
	eq(String(lines[0]), TitleScreen.EPITAPH, "第一句不变")
	var has_count := false
	var has_death := false
	for line in lines:
		if String(line).contains("你已点燃 2 次"):
			has_count = true
		if String(line).contains("上次殁于腐液墓园"):
			has_death = true
	ok(has_count, "私人墓志写了点燃次数")
	ok(has_death, "私人墓志写了上次殁于哪里")
	# 行尾魂注：六行有（「继续旅程」让给行内小注）。
	var ghosts := 0
	for child in title.get_node("Menu").get_children():
		var item := child as MenuItem
		if item != null and item.ghost != "":
			ghosts += 1
	eq(ghosts, 6, "六行带英文魂注")
	# 档案卡的印记行：与存档无关的账。
	var sigil := title.find_child("DossierSigil", true, false) as Label
	ok(sigil != null, "档案卡有印记行")
	if sigil != null:
		ok(sigil.text.contains("第 2 次点燃"), "印记行写着第 2 次点燃：%s" % sigil.text)
		ok(sigil.text.contains("殁于腐液墓园"), "印记行写着殁于哪里：%s" % sigil.text)
	title.queue_free()
	await get_tree().process_frame


func test_title_stays_quiet_without_any_sigils() -> void:
	# 冷启动：没有记录时环不画、墓志不加私人句、档案卡写占位。
	var packed := load(TITLE_SCENE) as PackedScene
	var title := packed.instantiate() as TitleScreen
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	var ring := title.find_child("SigilRing", true, false) as TitleSigilRing
	ok(ring != null and not ring.has_marks(), "冷启动环是空的")
	eq(int(title._ep_lines.size()), 1 + ChapterText.TITLE_LINES.size(),
			"没有记录就不加私人墓志")
	var sigil := title.find_child("DossierSigil", true, false) as Label
	ok(sigil != null and sigil.text.contains("尚无印记"), "档案卡印记行有占位")
	title.queue_free()
	await get_tree().process_frame
