extends TestCase
## Headless runs never build the pixel pool. The recycle rule is pure arithmetic.


func test_headless_burst_creates_nothing() -> void:
	eq(DisplayServer.get_name(), "headless")
	var before := Fx.get_child_count()
	for i in 80:
		Fx.burst(&"dust", Vector2(float(i), 0.0))
		Fx.burst(&"ring", Vector2(float(i), 8.0))
		Fx.burst(&"trail", Vector2(float(i), 16.0), 0.0)
	eq(Fx.burst_cap(), 0, "headless reports an empty cap")
	eq(Fx.burst_live_count(), 0, "headless reports no live motes")
	eq(Fx.get_child_count(), before, "burst does not create nodes")


func test_slot_cursor_wraps_at_the_cap() -> void:
	eq(Fx.next_slot(47, 48), 47)
	eq(Fx.next_slot(48, 48), 0, "the slot after the last mote is the first")
	eq(Fx.next_slot(49, 48), 1)
	eq(Fx.next_slot(4, 4), 0, "rings wrap the same way")
	eq(Fx.next_slot(3, 0), 0, "a zero cap does not divide")
