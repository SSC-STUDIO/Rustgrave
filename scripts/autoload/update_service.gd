extends Node
## UpdateService autoload: asks the release server whether a newer build exists.
## Do not give this script a class_name — the autoload name is the API.
##
## CONTRACT used by other packages:
##   current_version() -> String          the build's own version (from ProjectSettings)
##   check_async() -> void                kicks off a check; result arrives via signals
##   status() -> StringName               &"idle" | &"checking" | &"available" | &"current" | &"error" | &"skipped"
##   available() -> bool                  true when a newer version was found
##   entry() -> Dictionary                parsed manifest (empty when nothing found)
##   notes() -> String                    release notes for the newer version
##   download_page() -> String            where to send the player
##   skip_version() -> void               remember "not now" for this exact version
##   skipped(v: String) -> bool
##
## Signals: checked(status, entry) — one emission per finished check.
##
## Everything degrades to silence: no network, timeout, bad JSON, unreachable host,
## or a manifest older than the running build all leave the game exactly as it was.
## The web build never checks (the page is already the newest copy).
## Setting RUSTGRAVE_NO_UPDATE_CHECK in the environment also disables the check —
## the test suite does this so no case depends on the network.

signal checked(status: StringName, entry: Dictionary)

const MANIFEST_URL := "http://39.103.57.85/download/rustgrave/update.json"
## Seconds before an unanswered check is abandoned (also bounds the retry timer).
const TIMEOUT := 8.0

var _status := &"idle"
var _entry: Dictionary = {}
var _skipped_version := ""
var _request: HTTPRequest
var _checking := false
## "" = production URL; tests override to reach a local manifest file.
var _manifest_override := ""
## True whenever the network path must stay closed: the suite runs with
## RUSTGRAVE_NO_UPDATE_CHECK set, and only update_service_test re-arms it.
var _offline := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Web builds ship as a page the server already updated — checking from them
	# would either 404 or fight the browser cache for no gain.
	if OS.get_name() == "Web":
		_status = &"current"
		return
	# The suite sets RUSTGRAVE_NO_UPDATE_CHECK so no case hangs on the network;
	# only update_service_test's explicit opt-in reaches it again.
	_offline = OS.get_environment("RUSTGRAVE_NO_UPDATE_CHECK") != ""
	if _offline:
		_status = &"current"
		return
	_request = HTTPRequest.new()
	_request.timeout = TIMEOUT
	_request.name = "UpdateRequest"
	add_child(_request)
	_request.request_completed.connect(_on_request_completed)


## The build's own version, read from ProjectSettings at runtime so a stale
## constant can never disagree with the exported binary.
func current_version() -> String:
	var v := String(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	return v if v != "" else "0.0.0"


func status() -> StringName:
	return _status


func available() -> bool:
	return _status == &"available"


func entry() -> Dictionary:
	return _entry


func notes() -> String:
	return String(_entry.get("notes_zh", ""))


func download_page() -> String:
	return String(_entry.get("download_page", ""))


func skipped(v: String) -> bool:
	return v != "" and v == _skipped_version


## Remember "not now" for one exact version. The next release is a new prompt.
func skip_version() -> void:
	var v := String(_entry.get("version", ""))
	if v == "":
		return
	_skipped_version = v
	_status = &"skipped"
	checked.emit(_status, _entry)


## Start a check. No-op while one is already in flight or on the web build.
func check_async() -> void:
	if _checking or _status == &"current" or _offline:
		return
	_checking = true
	_status = &"checking"
	# Plain HTTP on purpose: the box has no trusted certificate for this IP
	# today, and a dead https check must not cost the player their prompt.
	var err := _request.request(_url())
	if err != OK:
		_fail()


## Where the manifest comes from. Production is the constant; tests point it at
## a local file so the HTTP path itself is exercised without the network.
func _url() -> String:
	return _manifest_override if _manifest_override != "" else MANIFEST_URL


## Test seam: "" restores the production URL.
func set_manifest_url_for_test(url: String) -> void:
	_manifest_override = url


## Test seam: adjust timeout for quick failure testing.
func set_timeout_for_test(seconds: float) -> void:
	if _request != null:
		_request.timeout = seconds


## Test seam: back to a pristine pre-check state. The singleton is shared by
## every case in the suite, so each one starts from here. The kill switch is
## re-armed here so only update_service_test's own opt-out (`_arm_for_test`)
## can reach the network, and every other case stays offline.
func reset_for_test() -> void:
	_manifest_override = ""
	_status = &"idle"
	_entry = {}
	_skipped_version = ""
	_checking = false
	_offline = true


## Test seam: opt back in to network checks (update_service_test calls this
## after reset_for_test; the HTTP cases then run against a local server).
func _arm_for_test() -> void:
	_offline = false
	if _request == null and OS.get_name() != "Web":
		_request = HTTPRequest.new()
		_request.timeout = TIMEOUT
		_request.name = "UpdateRequest"
		add_child(_request)
		_request.request_completed.connect(_on_request_completed)


## Test seam: pretend the player already skipped this version.
func set_skipped_for_test(v: String) -> void:
	_skipped_version = v


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_checking = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail()
		return
	handle_manifest_bytes(body)


## Parse one manifest body and move the state machine. Split out from the HTTP
## callback so the decision logic (JSON, version compare, skip memory) is testable
## without a server; the request path itself is covered by the local-server case.
func handle_manifest_bytes(body: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		_fail()
		return
	var manifest := parsed as Dictionary
	var remote := String(manifest.get("version", ""))
	if remote == "" or not is_newer_static(remote, current_version()):
		_entry = {}
		_status = &"current"
		checked.emit(_status, {})
		return
	_entry = manifest
	if skipped(remote):
		_status = &"skipped"
	else:
		_status = &"available"
	checked.emit(_status, _entry)


func _fail() -> void:
	_checking = false
	_entry = {}
	_status = &"error"
	checked.emit(_status, {})


## Semantic-ish compare: "1.10.0" beats "1.9.9" (plain string compare would not).
## Non-numeric parts fall back to lexicographic order so odd tags never crash.
static func is_newer_static(remote: String, local: String) -> bool:
	var r := remote.split(".")
	var l := local.split(".")
	for i in maxi(r.size(), l.size()):
		var rs := String(r[i]) if i < r.size() else "0"
		var ls := String(l[i]) if i < l.size() else "0"
		if rs.is_valid_int() and ls.is_valid_int():
			if rs.to_int() != ls.to_int():
				return rs.to_int() > ls.to_int()
		elif rs != ls:
			return rs > ls
	return false
