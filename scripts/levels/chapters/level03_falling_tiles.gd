extends CyclicHazard
## 屋檐松瓦：复用工具箱时序、safe_window、受击与暂停；瓦片外观和坠落判定专属。

const DROP_HEIGHT := 104.0
const FALL_SECONDS := 0.2
const TILE_HEIGHT := 28.0

func _init() -> void:
	skin = "bell"
	reach = TILE_HEIGHT
	thick = 40.0
	rest_time = 2.8
	telegraph_time = 0.9
	active_time = 0.5
	hint_id = &""

func _ready() -> void:
	super._ready()
	# 相位可能正好落在碎瓦残片期；出生时也不能让无害残片武装一帧。
	if _state == State.ACTIVE and _active_k() * active_time >= FALL_SECONDS:
		_set_armed(false)
	set_meta("chapter_mechanic", "falling_tiles")
	var hint := HintArea.new()
	hint.name = "TileHint"
	hint.hint_id = &"level03_falling_tiles"
	hint.text = "先看落尘，等瓦落定再过；冲刺也能穿过落点"
	hint.position = Vector2(-64, -24)
	hint.size = Vector2(96, 48)
	add_child(hint)

func fall_bottom() -> float:
	var elapsed := _active_k() * active_time
	var k := clampf(elapsed / FALL_SECONDS, 0.0, 1.0)
	return -DROP_HEIGHT * (1.0 - k * k)

## 审计用完整扫掠区；实际Hitbox跟随瓦片，空中瓦不会先伤到地上骑士。
func local_hit_rect() -> Rect2:
	return Rect2(-thick * 0.5, -DROP_HEIGHT - TILE_HEIGHT, thick, DROP_HEIGHT + TILE_HEIGHT)

func _apply_shape() -> void:
	if _shapes.is_empty():
		return
	var shape := _shapes[0]
	var rect := shape.shape as RectangleShape2D
	rect.size = Vector2(thick, TILE_HEIGHT)
	shape.position = Vector2(0, fall_bottom() - TILE_HEIGHT * 0.5)

func _on_warn() -> void:
	CombatMarker.spawn(self, CombatMarker.Kind.ZONE, Vector2(0, -2), telegraph_time,
		Color(0.95, 0.64, 0.38, 0.8), {"rect": Rect2(-thick * 0.5, -3, thick, 6)})
	HazardFx.play("collapse", "warn", global_position, -9.0)

func _on_active() -> void:
	_set_armed(true)
	_apply_shape()
	HazardFx.play("collapse", "fire", global_position, -7.0)
	fired.emit()

func _draw() -> void:
	if not _on_screen or _state == State.REST:
		return
	var warn := _state == State.WARN
	var y := -DROP_HEIGHT + roundf(sin(_vt * 36.0)) if warn else fall_bottom()
	var alpha := 0.6 if warn else 1.0
	var elapsed := _active_k() * active_time
	if not warn and elapsed >= FALL_SECONDS:
		var fade := 1.0 - (elapsed - FALL_SECONDS) / (active_time - FALL_SECONDS)
		for i in 5:
			var x := (float(i) - 2.0) * 9.0
			_px(Rect2(x, -4.0 - float(i % 2) * 3.0, 6, 3), Color(0.64, 0.38, 0.26, fade))
		return
	for i in 4:
		var x := (float(i) - 2.0) * 10.0
		var offset := float(i % 2) * 7.0
		_px(Rect2(x, y - TILE_HEIGHT + offset, 10, 16), Color(0.56, 0.3, 0.23, alpha))
		_px(Rect2(x, y - TILE_HEIGHT + offset, 10, 2), Color(0.85, 0.6, 0.39, alpha))
	if warn:
		var k := _warn_k()
		_px(Rect2(-thick * 0.5, -2, thick, 2), Color(0.98, 0.69, 0.42, 0.4 + k * 0.6))
		for i in 5:
			var life := fposmod(_vt * 1.6 + float(i) * 0.23, 1.0)
			_px(Rect2(float(i - 2) * 7.0, -DROP_HEIGHT + life * DROP_HEIGHT, 2, 2), Color(0.8, 0.65, 0.5, k))

func tick(delta: float) -> void:
	super.tick(delta)
	if not _is_frozen() and _state == State.ACTIVE and _active_k() * active_time >= FALL_SECONDS:
		_set_armed(false)
