extends Node
## Test runner root for res://tests/run_tests.tscn.
## Run headless:
##   godot --headless --path "<project>" res://tests/run_tests.tscn
## Exit code 0 = all green, 1 = failures. Autoloads (GameEvents) are live
## because we launch a scene through normal project startup.

const CASES_DIR := "res://tests"
const ERROR_COLLECTOR := preload("res://tests/error_collector.gd")
var _errors
var _active_test := "startup"
## Some scene tests idle ~15s of physics on purpose (checkpoint safety). Leave headroom.
const PER_TEST_MS := 30000
var _deadline_ms := 0


func _enter_tree() -> void:
	_errors = ERROR_COLLECTOR.new()
	OS.add_logger(_errors)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_deadline_ms = Time.get_ticks_msec() + PER_TEST_MS


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > _deadline_ms:
		printerr("[FAIL] timed out: ", _active_test)
		get_tree().quit(1)


func _exit_tree() -> void:
	if _errors != null:
		OS.remove_logger(_errors)


func _ready() -> void:
	await get_tree().process_frame
	var total := 0
	var failed := 0
	for path in _case_paths():
		_active_test = path
		_deadline_ms = Time.get_ticks_msec() + PER_TEST_MS
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failed += 1
			total += 1
			printerr("[FAIL] could not load test: ", path)
			continue
		var methods: Array[String] = _test_methods(script)
		if methods.is_empty():
			failed += 1
			total += 1
			printerr("[FAIL] no test methods: ", path)
		for method in methods:
			total += 1
			var errors_before: int = _errors.errors().size()
			_active_test = "%s.%s" % [path, method]
			_deadline_ms = Time.get_ticks_msec() + PER_TEST_MS
			var case: TestCase = script.new()
			case.name = "%s.%s" % [path.get_file().get_basename(), method]
			add_child(case)
			case.setup()
			await case.call(method)
			case.teardown()
			var f: int = case.failure_count() + _errors.errors().size() - errors_before
			failed += 1 if f > 0 else 0
			print("[%s] %s (%d asserts)" % ["PASS" if f == 0 else "FAIL", case.name, case._case_passed])
			for msg in case.failures():
				print("     - ", msg)
			case.queue_free()
			await get_tree().process_frame
	# Let deferred cleanup run before deciding the suite status.
	await get_tree().process_frame
	var engine_errors: PackedStringArray = _errors.errors()
	for message in engine_errors:
		printerr("[ENGINE ERROR] ", message)
	if total == 0:
		printerr("[FAIL] no tests discovered")
	print("=".repeat(48))
	var success := failed == 0 and total > 0 and engine_errors.is_empty()
	print("%s — %d/%d passed; %d engine errors" % ["OK" if success else "FAILED", total - failed, total, engine_errors.size()])
	get_tree().quit(0 if success else 1)


func _case_paths() -> PackedStringArray:
	var paths: PackedStringArray = []
	var dir := DirAccess.open(CASES_DIR)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with("_test.gd"):
			paths.append(CASES_DIR + "/" + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case-filter="):
			var pattern := arg.trim_prefix("--case-filter=")
			var matching: PackedStringArray = []
			for path in paths:
				if pattern in path:
					matching.append(path)
			paths = matching
	return paths


func _test_methods(script: GDScript) -> Array[String]:
	var probe: TestCase = script.new()
	var names: Array[String] = []
	for info in probe.get_method_list():
		if String(info["name"]).begins_with("test_") and int(info["args"].size()) == 0:
			names.append(info["name"])
	probe.free()
	names.sort()
	return names
