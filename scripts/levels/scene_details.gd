class_name SceneDetails
extends Node
## 场景细节系统：添加符合「锈蚀陵墓」气质的环境细节。
##
## 设计原则：
## - 讲述世界历史：损坏机械、废弃设施、生活痕迹
## - 不干扰玩法：细节在背景层或远离路径，不遮挡判定
## - 统一像素密度：所有细节遵守art-spec的16px基准
## - 性能约束：使用简单精灵，避免过多粒子

## 细节元素类型
enum DetailType {
	PIPE_H,          # 锈蚀水平管道
	PIPE_V,          # 锈蚀垂直管道
	CHAIN,           # 悬挂锁链
	GEAR_BROKEN,     # 损坏齿轮
	LANTERN_DIM,     # 暗淡提灯
	RUBBLE_SMALL,    # 小碎石堆
	RUBBLE_LARGE,    # 大碎石堆
	CRACK_FLOOR,     # 地面裂缝
	MOSS_PATCH,      # 苔藓斑块
	RUST_STAIN,      # 锈迹
}

## 使用art-spec定义的调色板
const RUST_DARK := Color(0.545, 0.271, 0.075)    # #8B4513
const RUST_LIGHT := Color(0.804, 0.361, 0.361)   # #CD5C5C
const TOXIC_GLOW := Color(1.0, 0.549, 0.0)       # #FF8C00
const TEAL_DEEP := Color(0.165, 0.251, 0.251)    # #2A4040
const IRON := Color(0.369, 0.353, 0.337)         # #5E5A56
const VOID := Color(0.102, 0.078, 0.071)         # #1A1412

## 元素尺寸（像素）：遵守16px基准
const DETAIL_SIZES := {
	DetailType.PIPE_H: Vector2(64, 8),
	DetailType.PIPE_V: Vector2(8, 64),
	DetailType.CHAIN: Vector2(8, 32),
	DetailType.GEAR_BROKEN: Vector2(24, 24),
	DetailType.LANTERN_DIM: Vector2(16, 24),
	DetailType.RUBBLE_SMALL: Vector2(16, 16),
	DetailType.RUBBLE_LARGE: Vector2(32, 24),
	DetailType.CRACK_FLOOR: Vector2(48, 8),
	DetailType.MOSS_PATCH: Vector2(24, 16),
	DetailType.RUST_STAIN: Vector2(32, 32),
}


## 为指定父节点生成场景细节
static func populate(parent: Node2D, detail_data: Array) -> void:
	for data in detail_data:
		if data.size() < 2:
			continue
		var pos: Vector2 = data[0]
		var type: DetailType = data[1]
		var depth: float = data[2] if data.size() > 2 else 1.0
		_create_detail(parent, pos, type, depth)


## 创建单个细节元素（占位实现，使用ColorRect）
static func _create_detail(parent: Node2D, pos: Vector2, type: DetailType, depth: float) -> void:
	var size: Vector2 = DETAIL_SIZES[type]
	var rect := ColorRect.new()
	rect.position = pos
	rect.size = size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 根据类型设置颜色和调制
	var color := IRON
	match type:
		DetailType.PIPE_H, DetailType.PIPE_V:
			color = RUST_DARK
		DetailType.CHAIN:
			color = IRON
		DetailType.GEAR_BROKEN:
			color = RUST_LIGHT
		DetailType.LANTERN_DIM:
			color = TOXIC_GLOW
			color.a = 0.6
		DetailType.RUBBLE_SMALL, DetailType.RUBBLE_LARGE:
			color = IRON
			color.a = 0.8
		DetailType.CRACK_FLOOR:
			color = VOID
			color.a = 0.7
		DetailType.MOSS_PATCH:
			color = TEAL_DEEP
			color.a = 0.8
		DetailType.RUST_STAIN:
			color = RUST_DARK
			color.a = 0.5

	rect.color = color
	rect.modulate.a *= depth  # 深度影响透明度

	parent.add_child(rect)


## Level01专用：墓园场景细节布局
static func populate_level01(parent: Node2D) -> void:
	var details := [
		# 西侧区域：废弃管道和锈迹
		[Vector2(24, 280), DetailType.PIPE_H, 0.6],
		[Vector2(64, 240), DetailType.RUST_STAIN, 0.4],
		[Vector2(120, 305), DetailType.CRACK_FLOOR, 0.7],

		# 教学区域：提示性细节
		[Vector2(180, 260), DetailType.LANTERN_DIM, 0.8],
		[Vector2(280, 310), DetailType.RUBBLE_SMALL, 0.9],

		# 毒坑区域：苔藓和锈蚀
		[Vector2(420, 310), DetailType.MOSS_PATCH, 0.8],
		[Vector2(520, 290), DetailType.RUST_STAIN, 0.5],
		[Vector2(580, 305), DetailType.CRACK_FLOOR, 0.7],

		# 中段：机械遗骸
		[Vector2(720, 280), DetailType.GEAR_BROKEN, 0.7],
		[Vector2(840, 240), DetailType.PIPE_V, 0.5],
		[Vector2(920, 310), DetailType.RUBBLE_LARGE, 0.8],

		# 决斗台前：氛围营造
		[Vector2(1100, 260), DetailType.LANTERN_DIM, 0.8],
		[Vector2(1280, 305), DetailType.CRACK_FLOOR, 0.7],
		[Vector2(1400, 290), DetailType.CHAIN, 0.6],

		# 东翼入口：强调过渡
		[Vector2(1520, 280), DetailType.RUST_STAIN, 0.6],
		[Vector2(1600, 310), DetailType.RUBBLE_SMALL, 0.9],
	]

	populate(parent, details)


## Level01专用：添加环境光照
static func add_level01_lighting(lighting: AmbientLighting) -> void:
	var lights := [
		# 余烬巢：暖色主光源
		[Vector2(118, 280), AmbientLighting.LightType.EMBER],

		# 教学区：聚光引导
		[Vector2(228, 240), AmbientLighting.LightType.SPOTLIGHT],

		# 毒坑：毒液荧光
		[Vector2(480, 320), AmbientLighting.LightType.TOXIC],

		# 中段：火把照明路径
		[Vector2(880, 260), AmbientLighting.LightType.TORCH],

		# 决斗台：重点照明
		[Vector2(1360, 240), AmbientLighting.LightType.TORCH],

		# 东翼入口：月光束
		[Vector2(1600, 200), AmbientLighting.LightType.MOONBEAM],
	]

	lighting.add_lights(lights)
