class_name AmbientLighting
extends Node2D
## 场景氛围灯：给关卡补上"火把暖池 / 毒液荧光 / 月光冷填"这些局部光源。
##
## 设计原则：
## - 光源服务于信息传递：重要路径、交互物、危险区域
## - 光不遮挡玩法：保持角色、敌人、平台轮廓清晰
## - 锈蚀气质：暖色火光、冷色月光、毒液荧光
## - 性能约束：限制同屏光源数量
##
## 实现在 `WorldLight` 上（follow = &"authored"）：它自带程序化径向贴图、
## 现成的 ADD/阴影/半径换算。**不要**退回去手搓裸 PointLight2D —— 没有
## texture 的 PointLight2D 一声不响地什么都不画。

## 光源类型
enum LightType {
	TORCH,        # 火把：暖橙色，轻微闪烁
	EMBER,        # 余烬：暗红色，呼吸式闪烁
	TOXIC,        # 毒液荧光：毒绿色，稳定发光
	MOONBEAM,     # 月光束：冷白色，柔和稳定
	FURNACE,      # 炉火：亮橙黄，剧烈跳动
	SPOTLIGHT,    # 聚光：白色，照亮关键区域
}

## 光源配置：color/energy/radius 直接给 WorldLight，flicker_* 由本节点驱动。
const LIGHT_CONFIGS := {
	LightType.TORCH: {
		"color": Color(1.0, 0.75, 0.29),      # 暖橙（与主题accent对齐）
		"energy": 0.8,
		"radius": 128.0,
		"flicker_amount": 0.15,
		"flicker_speed": 3.2,
	},
	LightType.EMBER: {
		"color": Color(0.91, 0.69, 0.56),     # 余烬灰（art-spec Ember Ash）
		"energy": 0.6,
		"radius": 96.0,
		"flicker_amount": 0.25,
		"flicker_speed": 1.8,
	},
	LightType.TOXIC: {
		"color": Color(1.0, 0.55, 0.0),       # 毒素辉光（art-spec Toxic Glow）
		"energy": 0.7,
		"radius": 112.0,
		"flicker_amount": 0.08,
		"flicker_speed": 2.5,
	},
	LightType.MOONBEAM: {
		"color": Color(0.5, 0.67, 0.63),      # 雾青（art-spec Fog Teal）
		"energy": 0.5,
		"radius": 192.0,
		"flicker_amount": 0.0,
		"flicker_speed": 0.0,
	},
	LightType.FURNACE: {
		"color": Color(1.0, 0.76, 0.29),      # 炉心辉光（art-spec Ember）
		"energy": 1.2,
		"radius": 160.0,
		"flicker_amount": 0.35,
		"flicker_speed": 5.0,
	},
	LightType.SPOTLIGHT: {
		"color": Color(0.89, 0.86, 0.8),      # 暖白（theme body text）
		"energy": 0.9,
		"radius": 144.0,
		"flicker_amount": 0.0,
		"flicker_speed": 0.0,
	},
}

## 同屏光源上限：性能约束
const MAX_LIGHTS := 12

var _lights: Array[WorldLight] = []
var _time := 0.0


func _ready() -> void:
	set_process(true)


## 闪烁只改"基础亮度"：WorldLight 自己的 apply() 会把 _base_energy 写进 energy，
## 这里每帧把 base 推到新值，就不会和它的每帧 apply 抢同一个字段。
func _process(delta: float) -> void:
	_time += delta
	for light in _lights:
		if not is_instance_valid(light):
			continue
		var flicker: Dictionary = light.get_meta(&"flicker", {}) as Dictionary
		var amount: float = float(flicker.get("amount", 0.0))
		if amount <= 0.0:
			continue
		var speed: float = float(flicker.get("speed", 0.0))
		if speed <= 0.0:
			light.set_base_energy(float(flicker.get("base", 1.0)))
			continue
		var noise := sin(_time * speed + light.position.x * 0.01) * 0.5 + 0.5
		light.set_base_energy(float(flicker.get("base", 1.0)) * (1.0 - amount * noise))


## 添加光源到指定位置
func add_light(pos: Vector2, type: LightType) -> WorldLight:
	if _lights.size() >= MAX_LIGHTS:
		push_warning("AmbientLighting: MAX_LIGHTS reached, not adding new light")
		return null

	var config: Dictionary = LIGHT_CONFIGS[type]
	var light := WorldLight.new()
	light.position = pos
	light.color = config["color"]
	light.follow = &"authored"
	light.authored_radius = float(config["radius"])
	light.flicker = false
	light.lit = true
	light.set_base_energy(float(config["energy"]))

	# 闪烁参数留给 _process 驱动：一个字典一次 get_meta，而不是三次
	# （每盏灯每帧三次元数据查询在十几盏灯的关卡上是可测的开销）。
	light.set_meta(&"flicker", {
		"base": float(config["energy"]),
		"amount": float(config["flicker_amount"]),
		"speed": float(config["flicker_speed"]),
	})

	add_child(light)
	# WorldLight._ready() 会把阴影打开；氛围灯不想为这点光算遮挡。
	light.shadow_enabled = false
	_lights.append(light)
	return light


## 把灯锚定到真实地标（余烬巢 / 毒池 / 门 / Boss 门 / 炉心 …）：
## 灯位 = 地标节点的全局位置 + offset，不再把坐标写死在关卡里（缺陷 P2-1：
## 光池落在空处）。地标不在树里/已释放时返回 null，调用方跳过即可。
func add_light_on(anchor: Node2D, offset: Vector2, type: LightType) -> WorldLight:
	if anchor == null or not is_instance_valid(anchor):
		return null
	var at := anchor.global_position + offset
	if is_inside_tree():
		at = to_local(at)
	return add_light(at, type)


## 批量添加光源：用于关卡初始化
func add_lights(light_data: Array) -> void:
	for data in light_data:
		if data.size() < 2:
			continue
		var pos: Vector2 = data[0]
		var type: LightType = data[1]
		add_light(pos, type)


## 移除光源
func remove_light(light: WorldLight) -> void:
	if not is_instance_valid(light):
		return
	_lights.erase(light)
	light.queue_free()


## 清空所有光源
func clear_lights() -> void:
	for light in _lights:
		if is_instance_valid(light):
			light.queue_free()
	_lights.clear()


func light_count() -> int:
	return _lights.size()


## 快捷方法：为关卡创建一个氛围灯宿主
static func create_for_level(level: Node2D) -> AmbientLighting:
	var lighting := AmbientLighting.new()
	lighting.name = "AmbientLighting"
	level.add_child(lighting)
	return lighting
