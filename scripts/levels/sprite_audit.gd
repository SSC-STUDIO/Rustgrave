class_name SpriteAudit
extends RefCounted
## 贴图放置审计：补上 LevelSanity 管不到的几类装饰贴图问题。
##   · floating / sunk  悬空或沉地（grounded 组之外的原生 Sprite2D 也查，
##     例如 level01 东翼 _plant_* 直接摆的那些）
##   · hanging   挂点上方 8px 内没有实体可挂（vine/chain 的 hang_top 锚点）
##   · wall-clip 装饰 AABB 嵌入实心 ≥25%（effective z ≤ -3 的墙挂件 /
##     WALL_PLATE_KEYS 是有意贴在墙后的，豁免）
##   · overlap   同一有效 z 的装饰两两重叠 ≥ 较小面积的 30%
##   · oob       中心越出镜头界 ±24px，或底边低于世界底线 480
##   · z-order   有效 z（父链累加）不在该类装饰的分层约定区间内
## 只读几何，不改任何节点。配套 tools/sprite_audit_probe.gd 批量跑全部场景。

## 与 chapter_layout.gd:618 / prop_fit_test.gd:190 同源：这些键是墙，不是路上的道具。
const WALL_PLATE_KEYS: Array[String] = ["window", "gargoyle", "altar", "skull_column",
		"column", "brick_house", "ruin_tower"]
## 装饰会被种进这些文件夹（chapter_layout.gd decor_layer() / level01 东翼 CathedralDecor）。
const DECOR_FOLDERS: Array[String] = ["Decor", "CathedralDecor", "Waymarks"]
const EMBED_DEPTH := 4.0            # == LevelSanity.BODY_EMBED_DEPTH
const EMBED_RATIO := 0.25           # == LevelSanity.BODY_EMBED_RATIO
const OVERLAP_RATIO := 0.30         # == LevelSanity.PROP_OVERLAP_RATIO
const BOUNDS_PAD := 24.0            # == LevelSanity.BOUNDS_PAD
const WORLD_FLOOR_MAX := 480.0      # == LevelSanity.WORLD_FLOOR_MAX
## 墙式建筑构件（prop_key 或贴图 basename）：塔身上的门洞、桥/墙顶的石栏本来
## 就嵌在结构里，wall-clip 豁免（z 层级检查不受影响）。
const WALL_CLIP_EXEMPT: Array[String] = ["door_arch_wall", "balustrade_wall", "balustrade_town"]
## 挂点上方多少像素内必须有实体可挂。
const HANG_PROBE_ABOVE := 8.0
## 标题画面：全屏氛围层允许出血（prop_fit_test.gd FULL_BLEED 先例）。
const TITLE_BOUNDS_PAD := 32.0
const TITLE_BLEED: Array[String] = ["vignette", "glow", "beam", "steam", "pit_river"]
## 标题分层贴图的锚点（贴图 basename → 期望左上角，来自 title_world.gd 常量）。
const TITLE_ANCHORS := {
	"bridge": TitleWorld.BRIDGE_POS,
	"mass_left": TitleWorld.MASS_LEFT_POS,
	"mass_right": TitleWorld.MASS_RIGHT_POS,
	"beam": TitleWorld.BEAM_POS,
	"forge_mouth": TitleWorld.MASS_RIGHT_POS + TitleWorld.MOUTH_IN_MASS,
}
## 各类装饰的有效 z 约定区间（decor_layer z=-2；墙挂件自身 z=-3 再叠 Decor 得 -5；
## 火把自身 z=-1 叠 Decor 得 -3；Waymarks 层 z=2）。
const Z_EXPECT := {
	"wall_plate": Vector2i(-6, -3),
	# 壁炬在 Decor 层下是 -3；落地炉膛（ArenaHearth/NaveHearth）直接插在
	# 场景层是 -1——炉膛是立在地面上的实体，画在平台层合理。
	"torch": Vector2i(-4, -1),
	"hanging": Vector2i(-3, -1),
	"grounded_decor": Vector2i(-3, -1),
	"waymark": Vector2i(2, 2),
	"decor": Vector2i(-6, -1),
}


## ------------------------------------------------------------------- entry --

## 对搭好的关卡 host 跑全部贴图检查，返回 finding 字典数组（空即通过）。
static func findings(host: Node, camera_limits: Rect2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tops := LevelSanity.top_segments(host)
	var entries := LevelSanity.solid_entries(host)
	var units := decor_units(host)
	var boxes := {}
	var ezs := {}
	for unit in units:
		boxes[unit] = _unit_aabb(unit)
		ezs[unit] = effective_z(unit)
	for unit in units:
		var box: Rect2 = boxes[unit]
		_check_ground(unit, box, tops, entries, out)
		_check_hanging(unit, entries, out)
		_check_wall_clip(unit, box, entries, out)
		_check_bounds(unit, box, camera_limits, out)
		_check_z_order(unit, ezs[unit], out)
	_check_decor_overlap(units, boxes, ezs, out)
	return out


## ------------------------------------------------------------------- units --

## 「装饰单元」：接地/悬挂 meta 携带者、grounded 组成员，以及装饰文件夹的
## 直接子节点（level01 东翼的原生 Sprite2D 靠这条兜住）。嵌套在另一个单元
## 内部的节点（如 foliage 的 pivot 与内层 sprite）只算一次。
static func decor_units(host: Node) -> Array[Node2D]:
	var cands: Array[Node2D] = []
	for node in LevelSanity._descendants(host):
		if node is Node2D and _is_decor_candidate(node as Node2D):
			cands.append(node as Node2D)
	var out: Array[Node2D] = []
	for unit in cands:
		var nested := false
		var cursor := unit.get_parent()
		while cursor != null and cursor != host:
			if cands.has(cursor):
				nested = true
				break
			cursor = cursor.get_parent()
		if not nested and _has_visible_texture(unit):
			out.append(unit)
	return out


static func _is_decor_candidate(node: Node2D) -> bool:
	if node.is_in_group("grounded") or node.has_meta("feet") \
			or node.has_meta("hang_top") or node.has_meta("prop_key"):
		return true
	var parent := node.get_parent()
	return parent != null and DECOR_FOLDERS.has(String(parent.name))


## 单元得真的带贴图才算数：WarmWash 这类氛围光节点没有纹理精灵，
## 兜底 16×16 框会刷出一片假的 floating。
static func _has_visible_texture(unit: Node2D) -> bool:
	return _texture_name(unit) != ""


## 有效 z：沿父链累加 z_index（遇到 z_as_relative=false 的祖先为止）。
## ChapterLayout 把装饰放在 z=-2 的 Decor 层下，只看节点自身 z_index 会判错。
static func effective_z(node: Node2D) -> int:
	var z := 0
	var cursor: Node = node
	while cursor != null:
		var ci := cursor as CanvasItem
		if ci != null:
			z += ci.z_index
			if not ci.z_as_relative:
				break
		cursor = cursor.get_parent()
	return z


static func _category(unit: Node2D) -> String:
	if unit.has_meta("hang_top"):
		return "hanging"
	var key := String(unit.get_meta("prop_key", ""))
	if key != "" and WALL_PLATE_KEYS.has(key):
		return "wall_plate"
	if unit is TorchLight:
		return "torch"
	var parent := unit.get_parent()
	var pname := String(parent.name) if parent != null else ""
	if pname == "Waymarks":
		return "waymark"
	if pname == "CathedralDecor":
		return "wall_plate"  # 东翼大教堂：整层 z=-3，全是墙后挂件
	if unit.is_in_group("grounded") or unit.has_meta("feet") or key != "":
		return "grounded_decor"
	return "decor"


## 脚点：优先登记的 feet meta（父空间 → 全局），其次 LevelSanity 的类表 /
## 精灵矩形兜底，纯容器（如 Ruin_*）用 AABB 底边中点。
static func _unit_feet(unit: Node2D, box: Rect2) -> Vector2:
	if unit.has_meta("feet"):
		var parent := unit.get_parent() as Node2D
		var f: Vector2 = unit.get_meta("feet")
		return parent.to_global(f) if parent != null else f
	if unit.has_meta("hang_top"):
		return Vector2.INF
	if unit is Sprite2D or unit.has_method("feet_point") or _has_class_feet(unit):
		return LevelSanity.feet_of(unit)
	if box.has_area():
		return Vector2(box.get_center().x, box.end.y)
	return LevelSanity.feet_of(unit)


static func _has_class_feet(node: Node) -> bool:
	var script := node.get_script() as Script
	while script != null:
		if LevelSanity.FEET_BY_CLASS.has(script.get_global_name()):
			return true
		script = script.get_base_script()
	return false


## ------------------------------------------------------------------ checks --

## 顶边挂在实体下沿的单元（没打 hang_top meta 的天花藤蔓/链条走这里）：
## 顶边中点上探 2px 落在某个实心里，且 sprite 从该实体下沿垂出来。
## 整个埋进实心的（grave_cross 94% 那种）不算悬挂。
static func _hanging_from(box: Rect2, entries: Array[Dictionary]) -> String:
	if not box.has_area():
		return ""
	var probe := Vector2(box.get_center().x, box.position.y - 2.0)
	for e in entries:
		var r := e["rect"] as Rect2
		if r.grow(-1.0).has_point(probe) and r.end.y <= box.position.y + 12.0:
			return String(e["name"])
	return ""


static func _check_ground(unit: Node2D, box: Rect2, tops: Array[LevelSanity.TopSeg],
		entries: Array[Dictionary], out: Array[Dictionary]) -> void:
	if unit.has_meta("hang_top"):
		return
	var feet := _unit_feet(unit, box)
	if feet == Vector2.INF:
		return
	if LevelSanity.standing_on(tops, feet) != null:
		return
	if _hanging_from(box, entries) != "":
		return  # 站不在台上、但挂在顶上的：是藤蔓/链条，不是悬空
	var near := _nearest_seg(tops, feet)
	var cat := "floating"
	var detail := "no platform top within -3..+8px under feet"
	var suggestion := ""
	if near != null:
		var dy := feet.y - near.y
		detail = "%s; nearest %s y=%d (dy=%+.0f)" % [detail, near.owner_name, int(near.y), dy]
		suggestion = "set feet y=%d (%s)" % [int(near.y), near.owner_name]
		if dy > LevelSanity.FOOT_SLACK_DOWN:
			cat = "sunk"
	else:
		detail = "%s; no walkable top near x=%d" % [detail, int(feet.x)]
	out.append(_finding(cat, unit, "feet=(%d,%d) %s" % [int(feet.x), int(feet.y), detail], suggestion))


static func _nearest_seg(tops: Array[LevelSanity.TopSeg], feet: Vector2) -> LevelSanity.TopSeg:
	var best: LevelSanity.TopSeg = null
	var best_d := INF
	for seg in tops:
		if feet.x < seg.x0 - LevelSanity.FOOT_X_PAD or feet.x > seg.x1 + LevelSanity.FOOT_X_PAD:
			continue
		var d := absf(feet.y - seg.y)
		if d < best_d:
			best_d = d
			best = seg
	if best != null:
		return best
	# 脚下横向没有任何台面：退而求其次，找整体最近的一条供参考。
	for seg in tops:
		var dx := maxf(0.0, maxf(seg.x0 - feet.x, feet.x - seg.x1))
		var d := absf(feet.y - seg.y) + dx
		if d < best_d:
			best_d = d
			best = seg
	return best


static func _check_hanging(unit: Node2D, entries: Array[Dictionary],
		out: Array[Dictionary]) -> void:
	if not unit.has_meta("hang_top"):
		return
	var ht: Vector2 = unit.get_meta("hang_top")
	var parent := unit.get_parent() as Node2D
	var g := parent.to_global(ht) if parent != null else ht
	var anchor := LevelSanity._entry_at(entries, g + Vector2(0.0, -HANG_PROBE_ABOVE))
	if anchor == "":
		out.append(_finding("hanging", unit,
				"hang_top=(%d,%d) has no solid within %dpx above" % [int(g.x), int(g.y), int(HANG_PROBE_ABOVE)],
				"move top under a platform/ceiling edge"))


static func _is_wall_clip_exempt(unit: Node2D) -> bool:
	return WALL_CLIP_EXEMPT.has(String(unit.get_meta("prop_key", ""))) \
			or WALL_CLIP_EXEMPT.has(_texture_name(unit).get_basename())


static func _check_wall_clip(unit: Node2D, box: Rect2, entries: Array[Dictionary],
		out: Array[Dictionary]) -> void:
	if not box.has_area():
		return
	if _category(unit) == "hanging":
		return  # 悬挂件贴着结构往下垂，不算穿墙
	if effective_z(unit) <= -3 or WALL_PLATE_KEYS.has(String(unit.get_meta("prop_key", ""))):
		return  # 墙后挂件：有意的
	if _is_wall_clip_exempt(unit):
		return  # 门洞 / 石栏：嵌在塔身、桥板里是设计
	var hung_from := _hanging_from(box, entries)  # 藤蔓/链条嵌进自己挂着的天花板不算穿墙
	var worst := ""
	var worst_ratio := 0.0
	for e in entries:
		if String(e["name"]) == hung_from:
			continue
		var r := e["rect"] as Rect2
		var ov := LevelSanity._overlap(box, r)
		if ov.x <= EMBED_DEPTH or ov.y <= EMBED_DEPTH:
			continue
		var ratio := (ov.x * ov.y) / maxf(box.get_area(), 1.0)
		if ratio >= EMBED_RATIO and ratio > worst_ratio:
			worst_ratio = ratio
			worst = String(e["name"])
	if worst != "":
		out.append(_finding("wall-clip", unit,
				"AABB %s overlaps %s %.0f%%" % [_rect_str(box), worst, worst_ratio * 100.0],
				"move it clear, or set z=-3 if it is wall dressing"))


static func _check_decor_overlap(units: Array[Node2D], boxes: Dictionary, ezs: Dictionary,
		out: Array[Dictionary]) -> void:
	for i in units.size():
		var a := units[i]
		if _category(a) == "hanging":
			continue
		var box_a: Rect2 = boxes[a]
		if not box_a.has_area():
			continue
		for j in range(i + 1, units.size()):
			var b := units[j]
			if ezs[a] != ezs[b] or _category(b) == "hanging":
				continue
			var box_b: Rect2 = boxes[b]
			if not box_b.has_area():
				continue
			# 光晕叠光晕、树叶套树身、碎石叠遗迹底板都是正常组合：
			# 一方完全含住另一方不算重叠问题。
			if box_a.encloses(box_b) or box_b.encloses(box_a):
				continue
			if "glow" in _texture_name(a) or "glow" in _texture_name(b):
				continue
			var ov := LevelSanity._overlap(box_a, box_b)
			if ov.x <= 2.0 or ov.y <= 2.0:
				continue
			var min_area := minf(box_a.get_area(), box_b.get_area())
			if min_area <= 0.0:
				continue
			var ratio := (ov.x * ov.y) / min_area
			# 墙裙层（z≤-3）的互叠是布景手法：废墟里栏杆脚边的碎石、立面后的塔影。
			# 但同一张贴图叠掉一半以上是重复种植，仍然报。
			if int(ezs[a]) <= -3 and not (_texture_name(a) == _texture_name(b) and ratio >= 0.5):
				continue
			if ratio >= OVERLAP_RATIO:
				out.append(_finding("overlap", a,
						"overlaps %s (%s) %.0f%% at same effective z=%d; other at (%d,%d)" % [_label(b),
								_texture_name(b), ratio * 100.0, int(ezs[a]),
								int(roundf(b.global_position.x)), int(roundf(b.global_position.y))],
						"separate them, or layer via different z"))


static func _check_bounds(unit: Node2D, box: Rect2, limits: Rect2,
		out: Array[Dictionary]) -> void:
	if limits.has_area() and box.has_area():
		var c := box.get_center()
		if c.x < limits.position.x - BOUNDS_PAD or c.x > limits.end.x + BOUNDS_PAD:
			out.append(_finding("oob", unit,
					"center x=%d outside camera limits [%d..%d]±%d" % [int(c.x),
							int(limits.position.x), int(limits.end.x), int(BOUNDS_PAD)],
					"move inside the level bounds"))
	if box.has_area() and box.end.y > WORLD_FLOOR_MAX:
		out.append(_finding("oob", unit,
				"bottom y=%d below world floor %d" % [int(box.end.y), int(WORLD_FLOOR_MAX)],
				"raise it above y=%d" % int(WORLD_FLOOR_MAX)))


static func _check_z_order(unit: Node2D, ez: int, out: Array[Dictionary]) -> void:
	var cat := _category(unit)
	var expect: Vector2i = Z_EXPECT[cat]
	if ez < expect.x or ez > expect.y:
		out.append(_finding("z-order", unit,
				"effective z=%d, expected %d..%d for %s" % [ez, expect.x, expect.y, cat],
				"fix z_index (or its layer's); whitelist if intentional"))


## ------------------------------------------------------------------ title --

## 标题活景：分层贴图是否越出 640×360（氛围层白名单除外），锚点层的实际
## 位置是否还对得上 title_world.gd 的常量（容差含指针视差 ±9px / 呼吸）。
static func check_title(world: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var bounds := Rect2(Vector2.ZERO, TitleWorld.WORLD).grow(TITLE_BOUNDS_PAD)
	var by_base := {}
	for node in LevelSanity._descendants(world):
		if not (node is Sprite2D):
			continue
		var spr := node as Sprite2D
		if spr.texture == null:
			continue
		var base := spr.texture.resource_path.get_file().get_basename()
		if base == "":
			continue
		if not by_base.has(base):
			by_base[base] = spr
		var box := _sprite_aabb(spr)
		if not box.has_area():
			continue
		if not box.intersects(bounds):
			out.append(_finding("oob", spr,
					"fully outside 640x360 (+%dpx pad): aabb=%s" % [int(TITLE_BOUNDS_PAD), _rect_str(box)],
					"check its position constant in title_world.gd / companion script"))
		elif not TITLE_BLEED.has(base) and not bounds.encloses(box):
			out.append(_finding("bleed", spr,
					"bleeds past world edge beyond %dpx pad: aabb=%s" % [int(TITLE_BOUNDS_PAD), _rect_str(box)],
					"fix position, or add to TITLE_BLEED if intentional"))
	for base in TITLE_ANCHORS:
		if not by_base.has(base):
			out.append(_finding("missing", world as Node2D,
					"expected layer '%s.png' not found in the tree" % base,
					"was it renamed or dropped from title_world.gd?"))
			continue
		var spr := by_base[base] as Sprite2D
		var expected: Vector2 = TITLE_ANCHORS[base]
		var actual := spr.global_position
		# 视差层（_layer 的 depth）随指针/呼吸漂移，容差放宽；bridge 是直接钉死的。
		var tol := 2.0 if base == "bridge" else 12.0
		if (actual - expected).length() > tol:
			out.append(_finding("anchor", spr,
					"at (%d,%d), expected (%d,%d) ±%.0f" % [int(actual.x), int(actual.y),
							int(expected.x), int(expected.y), tol],
					"realign the position constant"))
	return out


## ------------------------------------------------------------------ helpers --

## 单元 AABB：单元本身是 Sprite2D 时 LevelSanity.node_aabb 只看「子节点」会
## 退回 16×16 幻影框，必须直接量这个 sprite；容器（Ruin_* / 火把）走原逻辑。
static func _unit_aabb(unit: Node2D) -> Rect2:
	if unit is Sprite2D and (unit as Sprite2D).texture != null:
		return _sprite_aabb(unit as Sprite2D)
	return LevelSanity.node_aabb(unit)


## ---------------------------------------------------------------- whitelist --

## 逐条复核后确认「有意为之」的摆放（2026-10-24 全量审计）：
## [category, texture, x, y]，坐标 ±8px 容差；挪过位置会重新被报，逼着重审。
##   level01  树贴教学台缘（树冠探出台缘是构图）。栏杆脚的碎石 / 栏后石像 /
##            祭坛废墟前的栏杆属废墟层叠布景，已被「墙裙层互叠」规则覆盖
##   level02  苔拱门套着碎石堆（门洞框景）
##   level05  台阶/吊台缘的断梁、碎石、石板（废墟倚靠）
##   level06  墓丘上的栏杆与十字碑（半埋在坟丘里是墓园主题）；树旁卧石
##   level07  钟楼梯段栏杆脚的碎石
##   level08  熔渣废墟的机械残骸堆（断梁/坏机/石板互倚）
##   level09  墙顶石栏后的灌木
const AUDIT_WHITELIST := {
	"level01": [
		["wall-clip", "tree-2_46.png", 226, 320],
	],
	"level02": [
		["overlap", "moss_arch.png", 2658, 272],
	],
	"level05": [
		["wall-clip", "girder_l.png", 1023, 285],
		["wall-clip", "rubble_dry_c.png", 1835, 287],
		["wall-clip", "slab.png", 3704, 272],
	],
	"level06": [
		["wall-clip", "balustrade.png", 2772, 268],
		["wall-clip", "grave_cross.png", 2826, 255],
		["overlap", "tree-1_48.png", 2036, 320],
		["overlap", "balustrade.png", 2772, 268],
	],
	"level07": [
		["overlap", "balustrade.png", 480, -932],
	],
	"level08": [
		["wall-clip", "girder_l.png", 1151, 285],
		["overlap", "rubble_dry_c.png", 859, 287],
		["overlap", "slab.png", 1056, 272],
		["overlap", "girder_l.png", 1151, 285],
		["overlap", "rubble_dry.png", 3643, 281],
	],
	"level09": [
		["overlap", "balustrade_wall.png", 2656, 268],
	],
}
const WHITELIST_POS_TOLERANCE := 8.0


static func is_whitelisted(scene_id: String, finding: Dictionary) -> bool:
	if not AUDIT_WHITELIST.has(scene_id):
		return false
	var pos: Array = finding["pos"]
	if pos.size() != 2:
		return false
	for entry in AUDIT_WHITELIST[scene_id]:
		if entry[0] == finding["category"] and entry[1] == finding["texture"] \
				and absf(float(entry[2]) - float(pos[0])) <= WHITELIST_POS_TOLERANCE \
				and absf(float(entry[3]) - float(pos[1])) <= WHITELIST_POS_TOLERANCE:
			return true
	return false


## 报告的 finding 里剔掉白名单；返回 (保留下来的) 未豁免项。
static func filter_whitelisted(scene_id: String, found: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in found:
		if not is_whitelisted(scene_id, f):
			out.append(f)
	return out


static func _sprite_aabb(spr: Sprite2D) -> Rect2:
	var r := spr.get_rect()
	var xf := spr.get_global_transform()
	var box := Rect2()
	var any := false
	for p in [xf * r.position, xf * Vector2(r.end.x, r.position.y), xf * r.end,
			xf * Vector2(r.position.x, r.end.y)]:
		box = Rect2(p, Vector2.ZERO) if not any else box.expand(p)
		any = true
	return box


static func _finding(cat: String, unit: Node2D, detail: String, suggestion: String) -> Dictionary:
	return {
		"category": cat,
		"node": _label(unit),
		"texture": _texture_name(unit),
		"pos": [int(roundf(unit.global_position.x)), int(roundf(unit.global_position.y))],
		"z": effective_z(unit),
		"detail": detail,
		"suggestion": suggestion,
	}


static func _label(node: Node) -> String:
	var p := node.get_parent()
	return "%s/%s" % [String(p.name), String(node.name)] if p != null else String(node.name)


static func _texture_name(unit: Node2D) -> String:
	if unit is Sprite2D and (unit as Sprite2D).texture != null:
		return (unit as Sprite2D).texture.resource_path.get_file()
	for c in LevelSanity._descendants(unit):
		if c is Sprite2D and not (c is LightPool) and (c as Sprite2D).texture != null:
			return (c as Sprite2D).texture.resource_path.get_file()
	return ""


static func _rect_str(r: Rect2) -> String:
	return "(%d,%d %dx%d)" % [int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y)]
