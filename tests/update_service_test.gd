extends TestCase
## UpdateService：语义版本比对、manifest 解析与状态机、跳过版本、真实 HTTP 链路。
## 决策逻辑（JSON / 版本比较 / 跳过记忆）直接喂字节，不依赖网络；
## 拉起本地一次性 HTTP 服务器的用例验证 check_async 的完整请求路径。
##
## 套件整体带 RUSTGRAVE_NO_UPDATE_CHECK 跑（run_tests.ps1 设置），所以每个用例
## setup 里显式 _arm_for_test() 重新打开网络——只对本文件打开的本地服务器生效，
## 别的用例打开标题屏时 UpdateService 仍保持离线。

const NEWER_MANIFEST := '{"version":"9.9.9","notes_zh":"· 一条更新\\n· 又一条","download_page":"http://example.invalid/dl"}'
const OLDER_MANIFEST := '{"version":"0.0.1","notes_zh":"旧版","download_page":"http://example.invalid/old"}'
const EMPTY_MANIFEST := '{"notes_zh":"没有版本号"}'

const SERVER_SCRIPT := "res://tools/test_manifest_server.js"
const SERVER_PORT := 38117


func setup() -> void:
	UpdateService.reset_for_test()
	UpdateService._arm_for_test()


func teardown() -> void:
	UpdateService.reset_for_test()
	_kill_server()


# ===========================================================================
# 1. 版本比对
# ===========================================================================

func test_version_compare_major_minor_patch() -> void:
	# 语义化：逐段数字比，1.10.0 胜过 1.9.9（字符串比会判反）。
	ok(UpdateService.is_newer_static("1.10.0", "1.9.9"), "minor 段按数字比")
	ok(UpdateService.is_newer_static("2.0.0", "1.99.99"), "major 段优先")
	ok(UpdateService.is_newer_static("1.0.1", "1.0.0"), "patch 段")
	ok(UpdateService.is_newer_static("0.2.0", "0.1.0"), "零点几也算新版")
	ok(not UpdateService.is_newer_static("0.1.0", "0.1.0"), "同版本不算新")
	ok(not UpdateService.is_newer_static("0.1.0", "0.2.0"), "旧版不算新")
	ok(not UpdateService.is_newer_static("1.9.9", "1.10.0"), "反向同样成立")


func test_version_compare_unequal_segment_counts() -> void:
	# 段数不齐：缺的段当 0。"1.2" 对 "1.2.0" 是同版本。
	ok(UpdateService.is_newer_static("1.2.1", "1.2"), "多一段算新")
	ok(not UpdateService.is_newer_static("1.2", "1.2.0"), "缺段补 0")
	ok(not UpdateService.is_newer_static("1.2", "1.2.1"), "缺段补 0（反）")


func test_version_compare_non_numeric_falls_back() -> void:
	# 非数字段（预发布标签之类）退化成字符串比，不炸。
	ok(UpdateService.is_newer_static("1.0.0-beta.2", "1.0.0-beta.1"), "预发布标签按字符串")
	# 注意这里如实记录现状：把 "0-rc" 当一整段字符串比，"0" < "0-rc"，
	# 所以正式版不"胜过" rc。语义化版本的 prerelease 比较没实现，
	# 而发布通道只发正式版，这个盲点不影响实际使用。
	ok(not UpdateService.is_newer_static("1.0.0", "1.0.0-rc.1"), "正式版与 rc 视为同代（已知盲点）")


# ===========================================================================
# 2. manifest 解析与状态机
# ===========================================================================

func test_manifest_newer_reports_available() -> void:
	var got: Array = []
	UpdateService.checked.connect(func(status, _entry): got.append(status))
	UpdateService.handle_manifest_bytes(NEWER_MANIFEST.to_utf8_buffer())
	eq(got.size(), 1, "发一次信号")
	eq(got[0], &"available", "更新的 manifest -> available")
	ok(UpdateService.available(), "available() 为真")
	eq(UpdateService.notes(), "· 一条更新\n· 又一条", "更新日志透传")
	eq(UpdateService.download_page(), "http://example.invalid/dl", "下载页透传")
	eq(UpdateService.entry().get("version"), "9.9.9", "manifest 存档")


func test_manifest_older_reports_current() -> void:
	var got: Array = []
	UpdateService.checked.connect(func(status, _entry): got.append(status))
	UpdateService.handle_manifest_bytes(OLDER_MANIFEST.to_utf8_buffer())
	eq(got[0], &"current", "manifest 比构建旧 -> current")
	ok(not UpdateService.available(), "不提示更新")
	ok(UpdateService.entry().is_empty(), "不缓存旧 manifest")


func test_manifest_non_object_reports_error() -> void:
	# 合法 JSON 但不是对象（数组/字符串/null）：无法当 manifest 用 -> error。
	# 不断言"坏 JSON"字面量：parse_string 对畸形输入会往 stderr 打一条
	# 引擎 ERROR，而套件的 ErrorCollector 会把任何引擎错误计成失败
	# （见 tests/error_collector.gd）——那是套件契约，不是这条路径的问题。
	# 数组和畸形 JSON 在 _handle_manifest_bytes 里走同一个 not-Dictionary 分支。
	for body in ["[1,2]", "\"just a string\"", "null"]:
		var got: Array = []
		UpdateService.checked.connect(func(status, _entry): got.append(status))
		UpdateService.handle_manifest_bytes(body.to_utf8_buffer())
		eq(got[0], &"error", "非对象 manifest (%s) -> error" % body)
		ok(not UpdateService.available(), "非对象不提示更新")
		UpdateService.reset_for_test()


func test_manifest_missing_version_reports_current() -> void:
	# 缺 version 字段：无法比较就不提示，按"已是最新"处理。
	# 宁可漏提示一次，也不能把坏 manifest 当成更新弹给玩家。
	var got: Array = []
	UpdateService.checked.connect(func(status, _entry): got.append(status))
	UpdateService.handle_manifest_bytes(EMPTY_MANIFEST.to_utf8_buffer())
	eq(got[0], &"current", "缺 version 字段 -> current（不提示）")
	ok(not UpdateService.available(), "不误报更新")


func test_manifest_skipped_version_reports_skipped() -> void:
	# 玩家已经跳过 9.9.9：再来同一版只报 skipped，不当成新提示。
	var got: Array = []
	UpdateService.checked.connect(func(status, _entry): got.append(status))
	UpdateService.set_skipped_for_test("9.9.9")
	UpdateService.handle_manifest_bytes(NEWER_MANIFEST.to_utf8_buffer())
	eq(got.back(), &"skipped", "跳过过的版本 -> skipped")
	ok(not UpdateService.available(), "skipped 不算 available")


# ===========================================================================
# 3. 跳过版本
# ===========================================================================

func test_skip_version_suppresses_prompt_for_that_release() -> void:
	var got: Array = []
	UpdateService.checked.connect(func(status, _entry): got.append(status))
	UpdateService.handle_manifest_bytes(NEWER_MANIFEST.to_utf8_buffer())
	eq(UpdateService.status(), &"available", "跳过前是 available")

	UpdateService.skip_version()
	eq(UpdateService.status(), &"skipped", "跳过 -> skipped")
	ok(UpdateService.skipped("9.9.9"), "记下跳过的版本号")
	ok(not UpdateService.available(), "跳过之后不再算 available")


func test_skipped_version_is_not_remembered_for_a_later_release() -> void:
	# 跳过 9.9.9 不影响将来的 10.0.0：只按版本号精确匹配。
	UpdateService.handle_manifest_bytes(NEWER_MANIFEST.to_utf8_buffer())
	UpdateService.skip_version()
	ok(UpdateService.skipped("9.9.9"), "9.9.9 被跳过")
	ok(not UpdateService.skipped("10.0.0"), "10.0.0 没被跳过")
	ok(not UpdateService.skipped(""), "空串不算跳过")


func test_skip_without_entry_is_a_noop() -> void:
	# 没有已发现的版本时跳过：不该写进"跳过"名单，否则会把
	# 一个空串当成版本号记住，后面任何真版本都被误跳过。
	UpdateService.skip_version()
	ok(not UpdateService.skipped(""), "空 entry 跳过无效")
	eq(UpdateService.status(), &"idle", "状态不动")


# ===========================================================================
# 4. 真实 HTTP 链路（本地一次性 server；没有 node 就跑不了，如实标记）
# ===========================================================================

## check_async 走完：HTTPRequest 发出、收到 200、解析、emit。这一条
## 验证的是请求路径本身，前面的用例只验证解析后的决策。
func test_check_async_pulls_the_manifest_over_http() -> void:
	if not await _spawn_server(NEWER_MANIFEST):
		push_warning("SKIP: no node runtime for the manifest server")
		return
	var got: Array = []
	UpdateService.checked.connect(func(status, _entry): got.append(status))
	UpdateService.set_manifest_url_for_test("http://127.0.0.1:%d/update.json" % SERVER_PORT)
	UpdateService.check_async()
	var status := await _wait_for_signal(got)
	_kill_server()
	eq(status, &"available", "本地 server 返回更新 manifest -> available")
	ok(UpdateService.available(), "available() 为真")
	eq(UpdateService.notes(), "· 一条更新\n· 又一条", "日志经 HTTP 链路透传")


## 404 / 连不上都得安静地变成 error，不能崩、不能假装有更新。
func test_check_async_unreachable_reports_error() -> void:
	UpdateService.set_timeout_for_test(0.25)
	# 端口 1 没人监听（上一用例的 server 已在 teardown 杀掉；用 1 而不是
	# 复用端口，避免"上一轮 server 没死透"把断言变成 available）。
	UpdateService.set_manifest_url_for_test("http://127.0.0.1:1/update.json")
	var got: Array = []
	UpdateService.checked.connect(func(status, _entry): got.append(status))
	UpdateService.check_async()
	var status := await _wait_for_signal(got)
	eq(status, &"error", "连不上 -> error")
	ok(not UpdateService.available(), "不误报更新")


## 一次检查在飞时，第二次直接吃掉：标题屏连点两次不该发两个请求。
func test_check_async_ignores_concurrent_second_call() -> void:
	if not await _spawn_server(NEWER_MANIFEST):
		push_warning("SKIP: no node runtime for the manifest server")
		return
	var count := 0
	UpdateService.checked.connect(func(_status, _entry): count += 1)
	UpdateService.set_manifest_url_for_test("http://127.0.0.1:%d/update.json" % SERVER_PORT)
	UpdateService.check_async()
	UpdateService.check_async()  # 第一次还没回来，这次应该被吃掉
	await _wait_for_signal([])
	_kill_server()
	eq(count, 1, "并发第二次 check 不重复发信号")


# ===========================================================================
# helpers
# ===========================================================================

var _server_pid := -1
const READY_PATH := "user://__manifest_server_ready__"


func _spawn_server(body: String) -> bool:
	_kill_server()
	var ready := ProjectSettings.globalize_path(READY_PATH)
	if FileAccess.file_exists(ready):
		DirAccess.remove_absolute(ready)
	var script := ProjectSettings.globalize_path(SERVER_SCRIPT)
	var pid := OS.create_process("node", [script, body, "/update.json", "12",
			str(SERVER_PORT), ready], false)
	if pid < 0:
		return false
	_server_pid = pid
	# 轮询 ready 文件：node 起到 listen 有几毫秒，不能假定一 spawn 就能连。
	for _i in 60:
		await flush(1)
		if FileAccess.file_exists(ready):
			return true
	_kill_server()
	return false


## 杀掉本轮起的 node（按 pid，不碰机器上别的 node 进程）。
func _kill_server() -> void:
	if _server_pid > 0:
		OS.kill(_server_pid)
		_server_pid = -1
	var ready := ProjectSettings.globalize_path(READY_PATH)
	if FileAccess.file_exists(ready):
		DirAccess.remove_absolute(ready)


## 等 checked 信号落地（HTTPRequest 是异步的，最多等 30 步 / 1.5 秒）。
func _wait_for_signal(got: Array) -> StringName:
	for _i in 30:
		await get_tree().create_timer(0.05).timeout
		if not got.is_empty():
			var last: Variant = got.back()
			return StringName(last[0] if last is Array else str(last))
	return UpdateService.status()
