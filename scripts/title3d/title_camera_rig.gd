class_name TitleCameraRig
extends Camera3D
## 3D 标题相机：透视 FOV 30°，在焦平面 z=0（骑士脚底所在深度平面）上按
## 640x360 输出纹素取景，并把相机位置吸附到整纹素网格。
##
## 取景契约：
##   - rows = 360 是最终输出纹理的竖向纹素数（PixelStage.internal_size.y），
##     view_height = 13.5m 是焦平面上的取景高度；所以
##     texel = 2*tan(fov/2)*focus_distance/rows = view_height/rows = 0.0375m
##     是焦平面上一个输出纹素的世界尺寸。
##   - 相机位置沿相机右/上轴（basis.x / basis.y）吸附到整纹素网格，保留
##     depth 与朝向，和 scripts/moba/view/pixel_camera.gd 同一套"投影后取整"法。
##     残留的亚纹素偏移（输出纹素，x 右 / y 下）由 apply_pose() 返回，调用方交给
##     PixelStage.set_camera_offset()；舞台按整数物理像素平移低分辨率图像，
##     画面运动连续而几何永远落在纹素网格上（像素不抖）。
##   - 透视相机只在焦平面上精确对齐：yaw/pitch 都是小角度（<= 8°），画面
##     边缘的取整残差 < 0.02 输出纹素。
##   - 舒适性：Settings.shake_scale == 0 时指针视差 / 呼吸 / nudge 全部关闭
##     （每帧读设置，滑杆拖动立即生效；不在构造时缓存）。
##
## 集成约定（TitleWorld3D 已经在用）：
##   rig.advance(dt) -> rig.apply_pose(desired, snap) -> stage.set_camera_offset(sub, texel)
## apply_pose() 同时更新 texel_origin（给舞台的 dither 锚点，可代替自己算）。
##
## 注意：共享 PixelStage 的 SubViewport 在 640x360 之外还有 MARGIN*2 的扩展
## 纹素，相机 FOV 实际映射到 364 行；默认严格按规格用 rows(=360) 计算
## texel_world（与 TitleLayout.WORLD_PER_TEXEL 一致）。若集成方要按渲染像素
## 精确对齐，可把 margin_texels 设为 PixelStage.MARGIN（2）。

const OUTPUT_COLUMNS := 640
const DEFAULT_ROWS := 360
const DEFAULT_FOV := 30.0
const DEFAULT_VIEW_HEIGHT := 13.5
const DEFAULT_FOCUS_PLANE_Z := 0.0

## 指针微轨的最大角度（度）。2D 标题的 ±9 / ±4.5 纹素视差在这里换算成
## yaw / pitch 小轨道（指针 x/y 各 ±1.2°）。
const POINTER_MAX_DEG := 1.2
## 指针平滑（1/s，指数趋近；和 2D 的 POINTER_EASE 同一量级）。
const POINTER_EASE := 4.5
## 呼吸：周期 7s、振幅 ±1 输出纹素（和 2D 标题的镜头呼吸一致）。
const BREATH_PERIOD := 7.0
const BREATH_TEXELS := 1.0
## 菜单焦点 nudge：1.6 输出纹素的前推，按 NUDGE_DECAY 线性衰减。
const NUDGE_TEXELS := 1.6
const NUDGE_DECAY := 3.2
## 视轴和焦平面夹角太小（或打不到平面）时不做微轨，只保留静止位姿。
const FOCUS_MIN_FORWARD := 0.05
const FOCUS_MIN_DISTANCE := 0.5

## 输出纹理的竖向纹素数（标题固定 360；从 PixelStage.internal_size 取）。
var rows := DEFAULT_ROWS
## 每个纹素四周额外渲染的纹素数（PixelStage.MARGIN）；0 = 严格按规格公式。
var margin_texels := 0
## 焦平面取景高度（米）。rows * view_height / rows = 纹素世界尺寸。
var view_height := DEFAULT_VIEW_HEIGHT
## 最近一次 apply_pose() 推出的相机到焦平面的视轴距离（米）。texel_world()
## 不带参数时用它，所以调用顺序是 apply_pose() -> texel_world()。
var focus_distance := 0.0
## 焦平面所在 z（骑士脚底平面；吸附只在这个平面上精确）。
var focus_plane_z := DEFAULT_FOCUS_PLANE_Z
## 指针位置，-1..1（屏幕方向：x 右为正，y 下为正）。直接赋值即可，越界会被
## 使用处钳制；set_pointer() 是带钳制的别名。
var pointer := Vector2.ZERO
## 最近一次 apply_pose() 吸附到的整纹素坐标（PixelStage 的 dither 锚点，
## 与 pixel_camera.gd 的 Vector2i(ix, -iy) 同约定）。snap=false 时为零。
var texel_origin := Vector2i.ZERO
## 绑定后的像素舞台（只用来读 internal_size，不主动写 offset）。
var stage: Node = null

var _pointer_smooth := Vector2.ZERO
var _time := 0.0
var _nudge := 0.0


func _init() -> void:
	projection = Camera3D.PROJECTION_PERSPECTIVE
	fov = DEFAULT_FOV
	near = 0.05
	far = 150.0
	keep_aspect = Camera3D.KEEP_HEIGHT
	process_priority = 100
	focus_distance = focus_distance_for_view_height()


func _ready() -> void:
	if is_inside_tree():
		make_current()


# ---------------------------------------------------------------- 静态纯函数 ----

## 焦平面上一个纹素的世界尺寸：2*tan(fov/2)*distance/rows。
static func texel_world_at(fov_deg: float, row_count: int, distance: float) -> float:
	var r := float(maxi(row_count, 1))
	var safe_fov := clampf(fov_deg, 1.0, 179.0)
	return 2.0 * tan(deg_to_rad(safe_fov) * 0.5) * distance / r


## 焦距（输出像素）：rows / (2*tan(fov/2))。k=1 时 texel_world == distance/focal。
static func focal_pixels_at(fov_deg: float, row_count: int) -> float:
	var r := float(maxi(row_count, 1))
	var safe_fov := clampf(fov_deg, 1.0, 179.0)
	return r / (2.0 * tan(deg_to_rad(safe_fov) * 0.5))


## 把相机位置在相机右/上轴上的坐标取整到整纹素（保留 depth 与朝向）。
## 与 scripts/moba/view/pixel_camera.gd 的 lx/ly/roundf 数学一致。
static func snap_components(desired: Transform3D, texel: float) -> Vector2i:
	if texel <= 0.0:
		return Vector2i.ZERO
	var b := desired.basis
	var lx := desired.origin.dot(b.x) / texel
	var ly := desired.origin.dot(b.y) / texel
	return Vector2i(int(roundf(lx)), int(roundf(ly)))


## 吸附后的相机位姿（纯函数）：相机位置沿 basis.x / basis.y 落到整纹素网格，
## 沿 basis.z 的 depth 与整个朝向保持不变。
static func snapped_transform(desired: Transform3D, texel: float) -> Transform3D:
	if texel <= 0.0:
		return desired
	var b := desired.basis
	var c := snap_components(desired, texel)
	var depth := desired.origin.dot(b.z)
	var origin := b.x * (float(c.x) * texel) + b.y * (float(c.y) * texel) + b.z * depth
	return Transform3D(b, origin)


## 亚纹素偏移（输出纹素，x 右 / y 下），交给 PixelStage.set_camera_offset()。
## 约定：舞台把图像按这个向量反方向平移，于是吸附后的画面与未吸附画面重合。
static func subpixel_offset(desired: Transform3D, texel: float) -> Vector2:
	if texel <= 0.0:
		return Vector2.ZERO
	var b := desired.basis
	var lx := desired.origin.dot(b.x) / texel
	var ly := desired.origin.dot(b.y) / texel
	return Vector2(clampf(lx - roundf(lx), -0.5, 0.5), clampf(roundf(ly) - ly, -0.5, 0.5))


## 绕焦平面上的取景点 orbit：先绕世界 Y yaw，再绕当前相机右轴 pitch。
## 相机位置与朝向一起转，所以取景点始终留在画面中心，取景距离也不变
## （指针微轨用它，texel_world 因此稳定）。
static func orbit_around(desired: Transform3D, focus_point: Vector3, yaw: float,
		pitch: float) -> Transform3D:
	if is_zero_approx(yaw) and is_zero_approx(pitch):
		return desired
	var turn := Basis(Vector3.UP, yaw)
	var right := (turn * desired.basis.x).normalized()
	var rot := Basis(right, pitch) * turn
	var origin := focus_point + rot * (desired.origin - focus_point)
	return Transform3D(rot * desired.basis, origin)


# ------------------------------------------------------------------ 取景参数 ----

## 焦平面上一个纹素的世界尺寸（默认用最近一次 apply_pose 的取景距离）。
func texel_world(distance: float = -1.0) -> float:
	var d := focus_distance if distance < 0.0 else distance
	return texel_world_at(fov, _effective_rows(), d)


## 焦距（输出像素）。焦距与纹素世界尺寸满足 texel_world(d) == d / focal_pixels()。
func focal_pixels() -> float:
	return focal_pixels_at(fov, _effective_rows())


## 让焦平面上取景高度正好是 view_height 的相机距离：view_height/(2*tan(fov/2))。
func focus_distance_for_view_height() -> float:
	return view_height / (2.0 * tan(deg_to_rad(clampf(fov, 1.0, 179.0)) * 0.5))


## 距离 distance 处焦平面上的取景高度（米）。
func framed_height(distance: float = -1.0) -> float:
	var d := focus_distance if distance < 0.0 else distance
	return d * 2.0 * tan(deg_to_rad(clampf(fov, 1.0, 179.0)) * 0.5)


## 舒适性缩放：0 = 指针/呼吸/nudge 全关（每帧读，不在构造时缓存）。
func comfort_scale() -> float:
	return clampf(float(Settings.shake_scale), 0.0, 1.0)


## 绑定像素舞台：只读 internal_size 校正 rows，不主动写 offset（由调用方写）。
func set_stage(value: Node) -> void:
	stage = value
	if stage == null:
		return
	var size = stage.get("internal_size")
	if size is Vector2i and (size as Vector2i).y > 0:
		rows = (size as Vector2i).y


## 可选：让吸附网格对齐共享舞台的 SubViewport（其中包含 MARGIN*2 扩展纹素）。
func set_stage_margin(extra_texels: int) -> void:
	margin_texels = maxi(extra_texels, 0)


# ------------------------------------------------------------------ 微轨输入 ----

## 指针位置（-1..1，屏幕方向）。等价于给 pointer 赋值并钳制。
func set_pointer(norm: Vector2) -> void:
	pointer = Vector2(clampf(norm.x, -1.0, 1.0), clampf(norm.y, -1.0, 1.0))


## 菜单焦点 / 确认：向焦平面推近 amount*NUDGE_TEXELS 个输出纹素，随后衰减。
func nudge(amount := 1.0) -> void:
	var kick := NUDGE_TEXELS * clampf(amount, 0.0, 2.0)
	_nudge = minf(maxf(_nudge, kick), NUDGE_TEXELS * 2.0)


## 当前指针微轨角度（度，已乘舒适性缩放）：x = yaw，y = pitch（pitch 正 = 相机下潜）。
func pointer_degrees() -> Vector2:
	var s := comfort_scale()
	return Vector2(_pointer_smooth.x * POINTER_MAX_DEG * s, _pointer_smooth.y * POINTER_MAX_DEG * s)


## 当前呼吸偏移（输出纹素，已乘舒适性缩放）。
func breath_texels() -> float:
	return sin(_time * TAU / BREATH_PERIOD) * BREATH_TEXELS * comfort_scale()


## 当前 nudge 剩余幅度（输出纹素，已乘舒适性缩放）。
func nudge_texels() -> float:
	return _nudge * comfort_scale()


## 推进内部时钟（呼吸相位）、指针平滑与 nudge 衰减。确定性：没有 Timer/Tween。
func advance(dt: float) -> void:
	var step := maxf(dt, 0.0)
	_time += step
	var target := Vector2(clampf(pointer.x, -1.0, 1.0), clampf(pointer.y, -1.0, 1.0))
	if step <= 0.0:
		_pointer_smooth = target
	else:
		_pointer_smooth = _pointer_smooth.lerp(target, 1.0 - exp(-POINTER_EASE * step))
		_nudge = maxf(0.0, _nudge - step * NUDGE_DECAY)


# ---------------------------------------------------------------- 位姿应用 ----

## 视轴与焦平面 z=focus_plane_z 的交点（微轨的旋转中心）和视轴距离。
## 返回 {valid, point, distance}；valid=false 时 point/distance 是兜底值。
func focus_point_of(desired: Transform3D) -> Dictionary:
	var forward := -desired.basis.z.normalized()
	var fallback := maxf(focus_distance, FOCUS_MIN_DISTANCE)
	if forward.z > -FOCUS_MIN_FORWARD:
		return {"valid": false, "point": desired.origin + forward * fallback, "distance": fallback}
	var d := (focus_plane_z - desired.origin.z) / forward.z
	if d < FOCUS_MIN_DISTANCE or d > far:
		return {"valid": false, "point": desired.origin + forward * fallback, "distance": fallback}
	return {"valid": true, "point": desired.origin + forward * d, "distance": d}


## 在期望位姿上叠加指针微轨 / 呼吸 / nudge（未吸附）。舒适性为 0 时原样返回。
func micro_pose(desired: Transform3D) -> Transform3D:
	if comfort_scale() <= 0.0:
		return desired
	var focus := focus_point_of(desired)
	var pose := desired
	if bool(focus["valid"]):
		var deg := pointer_degrees()
		pose = orbit_around(desired, focus["point"], deg_to_rad(deg.x), deg_to_rad(deg.y))
	else:
		# 视轴打不到焦平面（例如朝上看）：退化成原地朝向微轨，不做轨道位移。
		var deg := pointer_degrees()
		pose.basis = desired.basis * Basis(Vector3.UP, deg_to_rad(deg.x)) \
				* Basis(Vector3.RIGHT, deg_to_rad(deg.y))
	var texel := texel_world(float(focus["distance"]))
	pose.origin += pose.basis.y * (breath_texels() * texel)
	pose.origin -= pose.basis.z * (nudge_texels() * texel)
	return pose


## 应用一帧位姿：叠加微轨、按焦平面取景距离吸附，写入 global_transform。
## snap=false 时保留连续运动（开屏俯冲等快速镜头允许不吸附），返回 ZERO。
## 返回的亚纹素偏移（输出纹素，x 右 / y 下）交给 PixelStage.set_camera_offset()。
func apply_pose(desired: Transform3D, snap := true) -> Vector2:
	var pose := micro_pose(desired)
	var focus := focus_point_of(pose)
	if bool(focus["valid"]):
		focus_distance = float(focus["distance"])
	var texel := texel_world(focus_distance)
	if not snap:
		global_transform = pose
		texel_origin = Vector2i.ZERO
		return Vector2.ZERO
	var components := snap_components(pose, texel)
	global_transform = snapped_transform(pose, texel)
	texel_origin = Vector2i(components.x, -components.y)
	return subpixel_offset(pose, texel)


## 把相机位姿取出（供测试/调试；apply_pose 后它就是被吸附的 global_transform）。
func pose() -> Transform3D:
	return global_transform


## 把世界点投到 640x360 输出纹素坐标（左上原点，y 向下）。仅测试/取景调试用。
func project_texels(desired: Transform3D, point: Vector3) -> Vector2:
	var b := desired.basis
	var local := point - desired.origin
	var depth := -local.dot(b.z)
	if depth <= 1e-6:
		return Vector2(INF, INF)
	var focal := focal_pixels()
	return Vector2(
			float(OUTPUT_COLUMNS) * 0.5 + focal * local.dot(b.x) / depth,
			float(maxi(rows, 1)) * 0.5 - focal * local.dot(b.y) / depth)


## 一份可读的内部状态（测试与调试）。
func debug_state() -> Dictionary:
	return {
		"texel_world": texel_world(),
		"focal_pixels": focal_pixels(),
		"focus_distance": focus_distance,
		"pointer_degrees": pointer_degrees(),
		"breath_texels": breath_texels(),
		"nudge_texels": nudge_texels(),
		"comfort": comfort_scale(),
		"time": _time,
	}


func _effective_rows() -> int:
	return maxi(rows, 1) + margin_texels * 2
