extends TestCase
## 临时探针：把 level01 的"埋住/净空"判定过程打出来，用来定标。用完即删。

func test_probe_level01_blockers() -> void:
	var packed := load(GameContext.LEVELS["level01"]) as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await flush(3)
	Director.abort()
	var entries := LevelSanity.solid_entries(level)
	var tops := LevelSanity.top_segments(level)
	print("PROBE entries=", entries.size(), " tops=", tops.size())
	for e in entries:
		var n := String(e["name"])
		if n == "TeachTerrace" or n == "GroundLeft" or n.contains("PitStep") or n == "PitClimbLeft":
			print("  ENTRY ", n, " kind=", e["kind"], " rect=", e["rect"])
	for seg in tops:
		if seg.owner_name == "GroundLeft" or seg.owner_name == "PitStepLow":
			print("  SEG ", seg.owner_name, " y=", seg.y, " x=", seg.x0, "..", seg.x1)
			var probe_y := seg.y - 4.0
			var x := seg.x0
			while x <= seg.x1:
				var who := LevelSanity._entry_at(entries, Vector2(x, probe_y))
				if who != "":
					var r := LevelSanity._entry_rect(entries, who)
					print("    x=", x, " probe_y=", probe_y, " blocker=", who, " rect=", r,
							" buried_test=", r.position.y >= seg.y + 4.0)
				x += 8.0
			var x2 := seg.x0
			while x2 <= seg.x1:
				var who2 := LevelSanity._entry_at(entries, Vector2(x2, seg.y - LevelSanity.HEADROOM_MIN))
				if who2 != "" and not LevelSanity._same_owner(seg, who2):
					var r2 := LevelSanity._entry_rect(entries, who2)
					print("    HR x=", x2, " blocker=", who2, " rect=", r2,
							" step_over=", r2.position.y >= seg.y - LevelSanity.JUMP_RISE_MAX)
				x2 += 8.0
	print("PROBE check() ->")
	for p in LevelSanity.check(level, Rect2(0, -800, 1600, 1200)):
		print("    ", p)
	level.free()
