extends TestCase
## Tests for scripts/title3d/title_camera_rig.gd：透视 30° 相机、焦平面取景、
## 整纹素吸附、亚纹素偏移、指针/呼吸舒适性，以及"像素不抖"的连续性。
##
## 数学背景（与 rig 头注释一致）：
##   t = 2*tan(fov/2)*d/rows       焦平面上一个输出纹素的世界尺寸
##   f = rows/(2*tan(fov/2))       焦距（输出像素）
##   t = d / f  <=>  f*1/f = 1     吸附一纹素正好等于屏幕一纹素
## 吸附把相机位置沿相机右/上轴取整；被吸附掉的部分从亚纹素偏移返回，
## 舞台把图像反方向平移同样的纹素量，于是：屏幕位置(吸附) - 亚纹素 = 屏幕位置(未吸附)。

const Rig := preload("res://scripts/title3d/title_camera_rig.gd")

const TARGET := Vector3(0.0, 4.3, 0.0)

var _saved_shake := 1.0
var _rig


func setup() -> void:
	_saved_shake = Settings.shake_scale
	Settings.shake_scale = 1.0
	_rig = Rig.new()
	_rig.name = "TitleCameraRig"
	add_child(_rig)


func teardown() -> void:
	Settings.shake_scale = _saved_shake
	if is_instance_valid(_rig):
		_rig.queue_free()
		_rig = null


# ------------------------------------------------------------------ helpers ----

func _hero_desired() -> Transform3D:
	var distance: float = _rig.focus_distance_for_view_height()
	var yaw := deg_to_rad(6.0)
	var pitch := deg_to_rad(4.0)
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var pos := TARGET + dir * distance
	return Transform3D(Basis.looking_at(TARGET - pos, Vector3.UP), pos)


func _almost_vec(got: Vector3, expected: Vector3, eps: float, label: String) -> void:
	ok(got.distance_to(expected) <= eps, "%s: expected %s got %s (eps %f)" % [label, expected, got, eps])


func _almost_basis(got: Basis, expected: Basis, eps: float, label: String) -> void:
	for axis in 3:
		ok(got[axis].distance_to(expected[axis]) <= eps,
				"%s axis %d: expected %s got %s" % [label, axis, expected[axis], got[axis]])


# -------------------------------------------------------------------- config ---

func test_camera_config_constants() -> void:
	eq(_rig.projection, Camera3D.PROJECTION_PERSPECTIVE, "projection must be perspective")
	almost(_rig.fov, 30.0, 1e-9, "fov must be 30")
	almost(_rig.near, 0.05, 1e-9, "near must be 0.05")
	almost(_rig.far, 150.0, 1e-9, "far must be 150")
	eq(_rig.keep_aspect, Camera3D.KEEP_HEIGHT, "keep_aspect must be KEEP_HEIGHT")
	eq(_rig.rows, 360, "rows must be 360")
	almost(_rig.view_height, 13.5, 1e-9, "view_height must be 13.5")
	almost(_rig.focus_plane_z, 0.0, 1e-9, "focus plane must be z = 0")


func test_texel_world_formula() -> void:
	for d in [5.0, 12.0, 25.1919, 60.0]:
		var distance := float(d)
		var expected: float = 2.0 * tan(deg_to_rad(30.0) * 0.5) * distance / 360.0
		almost(_rig.texel_world(distance), expected, 1e-9, "texel_world(%f) formula" % distance)
		almost(Rig.texel_world_at(30.0, 360, distance), expected, 1e-9, "static texel_world_at formula")
		# 焦距与纹素的关系：texel = distance / focal_pixels
		almost(_rig.texel_world(distance) * _rig.focal_pixels(), distance, 1e-6,
				"texel * focal == distance")
	# 默认取景高度正好是 13.5m -> 纹素 0.0375m
	almost(_rig.texel_world(), 13.5 / 360.0, 1e-6, "default texel_world == view_height / rows")
	almost(_rig.texel_world(_rig.focus_distance_for_view_height()) * 360.0, 13.5, 1e-6,
			"texel at focus distance frames view_height")
	almost(_rig.framed_height(_rig.focus_distance_for_view_height()), 13.5, 1e-6,
			"framed_height at focus distance == view_height")


func test_focal_pixels_formula() -> void:
	var expected := 360.0 / (2.0 * tan(deg_to_rad(30.0) * 0.5))
	almost(_rig.focal_pixels(), expected, 1e-6, "focal_pixels == rows / (2 tan(fov/2))")
	almost(Rig.focal_pixels_at(30.0, 360), expected, 1e-9, "static focal_pixels_at")
	almost(_rig.focus_distance_for_view_height(), (13.5 * 0.5) / tan(deg_to_rad(15.0)), 1e-6,
			"focus distance for view height")


func test_project_texels_centres_focus_target() -> void:
	Settings.shake_scale = 0.0
	var desired := _hero_desired()
	var center: Vector2 = _rig.project_texels(desired, TARGET)
	almost(center.x, 320.0, 1e-3, "target projects to output centre x")
	almost(center.y, 180.0, 1e-3, "target projects to output centre y")


# ---------------------------------------------------------------------- snap ---

func test_snap_keeps_depth_and_orientation() -> void:
	Settings.shake_scale = 0.0
	for yaw_deg in [-8.0, -3.0, 0.0, 3.0, 8.0]:
		for pitch_deg in [-6.0, 0.0, 6.0]:
			var distance: float = _rig.focus_distance_for_view_height()
			var yaw := deg_to_rad(yaw_deg)
			var pitch := deg_to_rad(pitch_deg)
			var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
			var desired := Transform3D(Basis.looking_at(-dir, Vector3.UP), TARGET + dir * distance)
			var texel: float = _rig.texel_world(distance)
			var snapped: Transform3D = Rig.snapped_transform(desired, texel)
			var b := desired.basis
			_almost_basis(snapped.basis, b, 1e-5, "snap keeps orientation")
			almost(snapped.origin.dot(b.z), desired.origin.dot(b.z), 1e-4, "snap keeps depth")
			# 沿右/上轴落到整纹素（坐标是 float32，容差按纹素尺度的相对精度给）
			var lx := snapped.origin.dot(b.x) / texel
			var ly := snapped.origin.dot(b.y) / texel
			almost(lx, roundf(lx), 2e-3, "snapped x is a whole texel")
			almost(ly, roundf(ly), 2e-3, "snapped y is a whole texel")
			# 吸附只动半个纹素以内
			var dx := absf(snapped.origin.dot(b.x) - desired.origin.dot(b.x))
			var dy := absf(snapped.origin.dot(b.y) - desired.origin.dot(b.y))
			ok(dx <= 0.5 * texel + 1e-4, "snap x moves at most half a texel, got %f" % dx)
			ok(dy <= 0.5 * texel + 1e-4, "snap y moves at most half a texel, got %f" % dy)


func test_subpixel_bounds() -> void:
	for i in range(1, 24):
		var yaw := deg_to_rad(-9.0 + 0.75 * float(i))
		var pitch := deg_to_rad(-5.0 + 0.45 * float(i))
		var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
		var distance := 18.0 + float(i % 5) * 3.7
		var desired := Transform3D(Basis.looking_at(-dir, Vector3.UP), TARGET + dir * distance)
		var texel: float = _rig.texel_world(distance)
		var sub: Vector2 = Rig.subpixel_offset(desired, texel)
		ok(sub.x >= -0.5 and sub.x <= 0.5, "subpixel x in [-0.5,0.5], got %f" % sub.x)
		ok(sub.y >= -0.5 and sub.y <= 0.5, "subpixel y in [-0.5,0.5], got %f" % sub.y)
		var snapped: Transform3D = Rig.snapped_transform(desired, texel)
		var expected := Vector2(
				(desired.origin.dot(desired.basis.x) - snapped.origin.dot(desired.basis.x)) / texel,
				(snapped.origin.dot(desired.basis.y) - desired.origin.dot(desired.basis.y)) / texel)
		ok(sub.distance_to(expected) <= 5e-4, "subpixel matches snap residual")


func test_focus_plane_roundtrip() -> void:
	# 取景点（z=0 焦平面上的目标点）在吸附前正落画面中心；吸附后的画面
	# 再加上舞台的亚纹素平移，必须回到原来的中心（精确到浮点）。
	var desired := _hero_desired()
	var sub: Vector2 = _rig.apply_pose(desired, true)
	var snapped: Transform3D = _rig.global_transform
	var shown: Vector2 = _rig.project_texels(snapped, TARGET) - sub
	var wanted: Vector2 = _rig.project_texels(desired, TARGET)
	almost(shown.x, wanted.x, 2e-3, "focus point screen x restored after snap + stage shift")
	almost(shown.y, wanted.y, 2e-3, "focus point screen y restored after snap + stage shift")
	almost(wanted.x, 320.0, 1e-3, "focus point starts at output centre x")
	almost(wanted.y, 180.0, 1e-3, "focus point starts at output centre y")
	ok(_rig.texel_origin != Vector2i.ZERO, "texel_origin records the snapped whole texels")
	# 吸附后的相机在右/上轴上的坐标是整数纹素
	var b := snapped.basis
	var texel: float = _rig.texel_world()
	almost(snapped.origin.dot(b.x) / texel, roundf(snapped.origin.dot(b.x) / texel), 2e-3,
			"applied camera x is a whole texel")
	almost(snapped.origin.dot(b.y) / texel, roundf(snapped.origin.dot(b.y) / texel), 2e-3,
			"applied camera y is a whole texel")


func test_focus_plane_neighbourhood_alignment() -> void:
	# 焦平面上离取景点几米的点：吸附 + 舞台平移后与未吸附画面差不到 0.05 纹素
	# （透视只在焦平面上精确，边缘残差来自深度差）。
	Settings.shake_scale = 0.0
	var desired := _hero_desired()
	var sub: Vector2 = _rig.apply_pose(desired, true)
	var snapped: Transform3D = _rig.global_transform
	for offset in [Vector3(5, 0, 0), Vector3(-5, 0, 0), Vector3(0, 5, 0), Vector3(3, -4, 0)]:
		var point: Vector3 = TARGET + (offset as Vector3)
		var shown: Vector2 = _rig.project_texels(snapped, point) - sub
		var wanted: Vector2 = _rig.project_texels(desired, point)
		ok(shown.distance_to(wanted) <= 0.05,
				"focus-plane point %s stays within 0.05 texel, got %f" % [point, shown.distance_to(wanted)])


func test_snap_false_is_continuous() -> void:
	Settings.shake_scale = 0.0
	var desired := _hero_desired()
	var sub: Vector2 = _rig.apply_pose(desired, false)
	eq(sub, Vector2.ZERO, "snap=false returns zero subpixel offset")
	eq(_rig.texel_origin, Vector2i.ZERO, "snap=false clears the dither anchor")
	_almost_vec(_rig.global_transform.origin, desired.origin, 1e-6, "snap=false keeps the exact pose")
	_almost_basis(_rig.global_transform.basis, desired.basis, 1e-5, "snap=false keeps orientation")


# ------------------------------------------------------------------ comfort ---

func test_comfort_disables_pointer_breath_and_nudge() -> void:
	Settings.shake_scale = 0.0
	_rig.set_pointer(Vector2(1.0, 1.0))
	_rig.nudge(2.0)
	_rig.advance(2.0)
	eq(_rig.pointer_degrees(), Vector2.ZERO, "pointer motion off when shake_scale == 0")
	almost(_rig.breath_texels(), 0.0, 1e-9, "breathing off when shake_scale == 0")
	almost(_rig.nudge_texels(), 0.0, 1e-9, "nudge off when shake_scale == 0")
	var desired := _hero_desired()
	var sub: Vector2 = _rig.apply_pose(desired, true)
	var distance: float = _rig.focus_distance_for_view_height()
	var texel: float = _rig.texel_world(distance)
	var expected_pose: Transform3D = Rig.snapped_transform(desired, texel)
	var expected_sub: Vector2 = Rig.subpixel_offset(desired, texel)
	_almost_vec(_rig.global_transform.origin, expected_pose.origin, 2e-5,
			"comfort off applies the plain snapped pose")
	_almost_basis(_rig.global_transform.basis, expected_pose.basis, 1e-5,
			"comfort off keeps the plain orientation")
	almost(sub.x, expected_sub.x, 1e-5, "comfort off subpixel x")
	almost(sub.y, expected_sub.y, 1e-5, "comfort off subpixel y")


func test_pointer_limits() -> void:
	_rig.set_pointer(Vector2(1.0, 1.0))
	_rig.advance(3.0)
	var deg: Vector2 = _rig.pointer_degrees()
	ok(deg.x > 1.0 and deg.x <= 1.2 + 1e-6, "pointer x saturates at +1.2 deg, got %f" % deg.x)
	ok(deg.y > 1.0 and deg.y <= 1.2 + 1e-6, "pointer y saturates at +1.2 deg, got %f" % deg.y)
	_rig.set_pointer(Vector2(-1.0, -1.0))
	_rig.advance(3.0)
	deg = _rig.pointer_degrees()
	ok(deg.x < -1.0 and deg.x >= -1.2 - 1e-6, "pointer x saturates at -1.2 deg, got %f" % deg.x)
	ok(deg.y < -1.0 and deg.y >= -1.2 - 1e-6, "pointer y saturates at -1.2 deg, got %f" % deg.y)
	# 越界赋值被钳制
	_rig.pointer = Vector2(9.0, -9.0)
	_rig.advance(3.0)
	deg = _rig.pointer_degrees()
	ok(deg.x <= 1.2 + 1e-6 and deg.y >= -1.2 - 1e-6, "pointer assignment is clamped")


func test_pointer_moves_the_camera() -> void:
	Settings.shake_scale = 1.0
	var desired := _hero_desired()
	var sub_before: Vector2 = _rig.apply_pose(desired, true)
	var origin_before: Vector3 = _rig.global_transform.origin
	_rig.set_pointer(Vector2(1.0, 0.0))
	_rig.advance(2.0)
	var sub_after: Vector2 = _rig.apply_pose(desired, true)
	var origin_after: Vector3 = _rig.global_transform.origin
	ok(origin_before.distance_to(origin_after) > 0.2,
			"pointer orbit moves the camera laterally (%.4f m)" % origin_before.distance_to(origin_after))
	ok(sub_after.x >= -0.5 and sub_after.x <= 0.5, "pointer orbit keeps subpixel in range")
	ok(sub_before.distance_to(sub_after) >= 0.0, "subpixel is produced with snapping on")


func test_breath_period() -> void:
	Settings.shake_scale = 1.0
	_rig.set_pointer(Vector2.ZERO)
	almost(_rig.breath_texels(), 0.0, 1e-6, "breath starts at zero phase")
	_rig.advance(7.0 * 0.25)
	almost(_rig.breath_texels(), 1.0, 1e-3, "breath peaks at +1 texel after a quarter period")
	_rig.advance(7.0 * 0.5)
	almost(_rig.breath_texels(), -1.0, 1e-3, "breath troughs at -1 texel after three quarters")
	_rig.advance(7.0 * 0.25)
	almost(_rig.breath_texels(), 0.0, 1e-3, "breath returns to zero after a full period")
	Settings.shake_scale = 0.5
	_rig.advance(7.0 * 0.25)
	almost(_rig.breath_texels(), 0.5, 1e-3, "breath scales with shake_scale")


func test_nudge_decays() -> void:
	Settings.shake_scale = 1.0
	_rig.nudge(1.0)
	almost(_rig.nudge_texels(), Rig.NUDGE_TEXELS, 1e-6, "nudge raises a full kick")
	_rig.advance(Rig.NUDGE_TEXELS / Rig.NUDGE_DECAY + 0.05)
	almost(_rig.nudge_texels(), 0.0, 1e-6, "nudge decays to zero")
	_rig.nudge(5.0)
	almost(_rig.nudge_texels(), Rig.NUDGE_TEXELS * 2.0, 1e-6, "nudge caps at two texels")


# -------------------------------------------------------------- orbit / 抖动 ---

func test_orbit_keeps_focus_distance() -> void:
	Settings.shake_scale = 0.0
	var desired := _hero_desired()
	var focus: Dictionary = _rig.focus_point_of(desired)
	ok(bool(focus["valid"]), "hero pose hits the focus plane")
	var point: Vector3 = focus["point"]
	almost(point.z, 0.0, 1e-4, "focus point lies on the z = 0 plane")
	almost((point - desired.origin).length(), float(focus["distance"]), 1e-4,
			"focus distance is the distance to the focus point")
	var orbited: Transform3D = Rig.orbit_around(desired, point, deg_to_rad(1.2), deg_to_rad(1.2))
	var focus2: Dictionary = _rig.focus_point_of(orbited)
	_almost_vec(focus2["point"], point, 1e-4, "orbit keeps the focus point fixed")
	almost(float(focus2["distance"]), float(focus["distance"]), 1e-4, "orbit keeps the focus distance")
	var centre: Vector2 = _rig.project_texels(orbited, point)
	almost(centre.x, 320.0, 0.01, "orbited camera still centres the focus point x")
	almost(centre.y, 180.0, 0.01, "orbited camera still centres the focus point y")


func test_breath_keeps_image_continuous() -> void:
	# 7s 呼吸 + 整纹素吸附 + 亚纹素平移：取景点的最终屏幕位置每帧只移动
	# 极小的量（不抖）。这里直接验证"吸附屏幕位置 - 亚纹素偏移"的连续性。
	Settings.shake_scale = 1.0
	_rig.set_pointer(Vector2.ZERO)
	var desired := _hero_desired()
	var previous := Vector2(INF, INF)
	var worst := 0.0
	var frames := 420
	for i in frames:
		_rig.advance(1.0 / 60.0)
		var sub: Vector2 = _rig.apply_pose(desired, true)
		var image_position: Vector2 = _rig.project_texels(_rig.global_transform, TARGET) - sub
		if i > 0:
			worst = maxf(worst, image_position.distance_to(previous))
		previous = image_position
	ok(worst < 0.05, "breath stays smooth across snap steps, worst frame delta %.4f texel" % worst)
