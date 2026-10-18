extends RefCounted
## UI 过渡动效库：标题屏开屏、界面开关场共用的一套节奏。
##
## 三条设计约束（都来自现有代码的既有约定，不是新规矩）：
##   1. 像素字体 / 9-slice 面板一律不做非整数倍缩放——糊。所以过渡只用
##      位移 + 透明度 + 颜色压暗，唯一例外的整卡淡入淡出也是 1:1 像素。
##   2. 每段动画都要能被"瞬间到达"：测试是同步推进的，动画不许把断言卡死。
##      所以每个入口都先 instant() 落位，再 tween 补中间帧。
##   3. 总时长压在 0.3~0.5 秒一档：标题屏开屏 < 1.2s，弹窗开关 < 0.25s，
##      慢一档就从"有设计感"变成"等着"。

const Ornaments := preload("res://scripts/ui/ui_ornament.gd")

## --- 开屏：从黑场里浮出来 ------------------------------------------------

## 序幕：先黑着，再让整幅画面从黑色里渗出来。keyart/字标/菜单各自带一点
## 阶梯延迟，像灯一盏盏点着，而不是整块一起亮。
const BOOT_CURTAIN := 0.30
const BOOT_FADE := 0.55
const BOOT_STAGGER := 0.07

## 菜单架的逐行渗入沿用标题屏原有的 INTRO_* 节奏（row stagger 0.045s），
## 这里只统一"更早开始、与场景同步淡入"的时序。
const RAIL_STAGGER := 0.045
const RAIL_DURATION := 0.22

## --- 弹窗：从下面那层"弹"出来 ---------------------------------------------

## 卡片位移（像素）：18px 起步，足够看出方向又不至于晃眼；像素艺术不做缩放。
const MODAL_LIFT := 18.0
const MODAL_IN := 0.17
## 退场比入场快半拍：弹窗是"啪一下出现、退回去反而利落"。
const MODAL_OUT := 0.12
## 纱幕压暗：原来 play_intro 只做 0.12s 透明度淡入，且卡片立即可见。
## 现在卡片跟着纱幕一起从"透明 + 下移 18px"合到位。
const VEIL_IN := 0.17
const VEIL_OUT := 0.11

## 弹性缓动：轻微过冲一点点，让"弹出来"有手感。像素位置过冲 <1px 不糊。
const POP_TRANS := Tween.TRANS_BACK
const POP_EASE := Tween.EASE_OUT


## 让一批子节点错峰淡入。nodes 里放 Control / CanvasItem，delay_step 为步长。
## tween 已 set_parallel(true) 时逐条 tween_property 即错峰；返回总时长供调用方
## 决定何时恢复输入。
static func stagger_in(nodes: Array, delay_step: float, duration: float,
		from_alpha: float = 0.0) -> float:
	var delay := 0.0
	for n in nodes:
		if not (n is CanvasItem):
			continue
		var item := n as CanvasItem
		item.modulate.a = from_alpha
		var tw := item.create_tween()
		tw.tween_property(item, "modulate:a", 1.0, duration) \
				.set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		delay += delay_step
	return delay + duration


## 瞬时把一批节点落到位（跳过动画）：开屏第一帧、测试、以及玩家中断动画时用。
static func snap_visible(nodes: Array, alpha: float = 1.0) -> void:
	for n in nodes:
		if not (n is CanvasItem):
			continue
		var item := n as CanvasItem
		item.modulate.a = alpha
		item.visible = alpha > 0.0


## 弹窗入场：纱幕淡下、卡片从下方 18px 合到位（带回弹）。
## root 为整层（纱幕+卡片都在其下），card 是那张花边面板。
static func modal_in(root: CanvasItem, card: CanvasItem, veil: CanvasItem,
		body_nodes: Array = []) -> Tween:
	if root == null or not root.is_inside_tree():
		return null
	root.visible = true
	if DisplayServer.get_name() == "headless":
		# 测试同步推进：直接落终态，不留半透明中间帧。
		if veil != null:
			veil.modulate.a = 1.0
		if card != null:
			card.modulate.a = 1.0
		for n in body_nodes:
			if n is CanvasItem:
				(n as CanvasItem).modulate.a = 1.0
		return null
	var tw := root.create_tween()
	tw.set_parallel(true)
	if veil != null:
		veil.modulate.a = 0.0
		tw.tween_property(veil, "modulate:a", 1.0, VEIL_IN) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if card != null:
		card.modulate.a = 0.0
		var lift: Vector2 = card.position
		card.position = lift + Vector2(0.0, MODAL_LIFT)
		tw.tween_property(card, "modulate:a", 1.0, MODAL_IN) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "position", lift, MODAL_IN) \
				.set_trans(POP_TRANS).set_ease(POP_EASE)
	var delay := MODAL_IN * 0.6
	for n in body_nodes:
		if not (n is CanvasItem):
			continue
		var item := n as CanvasItem
		item.modulate.a = 0.0
		tw.tween_property(item, "modulate:a", 1.0, MODAL_IN * 0.8) \
				.set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		delay += 0.03
	return tw


## 弹窗退场：卡片往下沉回去 + 纱幕一起收掉。on_done 在动画结束后回调
## （调用方负责在那里真正 visible = false，保证"退完才消失"而不是闪断）。
## headless 下与 Director.fade_to 同一约定：直接落终态再回调，测试同步可断言。
static func modal_out(root: CanvasItem, card: CanvasItem, veil: CanvasItem,
		on_done: Callable = Callable()) -> Tween:
	if root == null or not root.is_inside_tree():
		if on_done.is_valid():
			on_done.call()
		return null
	if DisplayServer.get_name() == "headless":
		if on_done.is_valid():
			on_done.call()
		return null
	var tw := root.create_tween()
	tw.set_parallel(true)
	if veil != null:
		veil.modulate.a = 1.0
		tw.tween_property(veil, "modulate:a", 0.0, VEIL_OUT) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if card != null:
		card.modulate.a = 1.0
		var drop: Vector2 = card.position
		tw.tween_property(card, "modulate:a", 0.0, MODAL_OUT) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(card, "position", drop + Vector2(0.0, MODAL_LIFT), MODAL_OUT) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if on_done.is_valid():
		tw.tween_callback(on_done).set_delay(maxf(MODAL_OUT, VEIL_OUT))
	return tw


## 中途打断（玩家又按了一次开关、或场景切换）：tween 杀掉、位置落回起点。
static func modal_reset(root: CanvasItem, card: CanvasItem, veil: CanvasItem,
		card_home: Vector2, veil_alpha: float) -> void:
	if root != null and root.has_meta("_tween"):
		var tw: Tween = root.get_meta("_tween")
		if tw != null and tw.is_valid():
			tw.kill()
		root.remove_meta("_tween")
	if veil != null:
		veil.modulate.a = veil_alpha
	if card != null:
		card.modulate.a = 1.0
		card.position = card_home
