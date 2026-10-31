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


## 每层只持有一条过渡，重新打开或跳过时旧回调也随之取消。
static func _cancel(root: CanvasItem) -> void:
	if root != null and root.has_meta("_tween"):
		var previous: Tween = root.get_meta("_tween")
		if previous != null and previous.is_valid():
			previous.kill()
		root.remove_meta("_tween")


static func _home(card: CanvasItem) -> Vector2:
	if card == null:
		return Vector2.ZERO
	if not card.has_meta("_modal_home"):
		card.set_meta("_modal_home", card.position.round())
	return card.get_meta("_modal_home")


static func _tween(root: CanvasItem) -> Tween:
	var tw := root.create_tween().set_parallel(true)
	var generation := int(root.get_meta("_transition_generation", 0)) + 1
	root.set_meta("_transition_generation", generation)
	root.set_meta("_tween", tw)
	tw.finished.connect(func() -> void:
		if is_instance_valid(root) and int(root.get_meta("_transition_generation", 0)) == generation:
			root.remove_meta("_tween")
	)
	return tw


## 连中间帧也落整像素；终态直接赋 home，避免反复开关积累位移。
static func _move(tw: Tween, card: CanvasItem, from: Vector2, to: Vector2,
		duration: float, delay: float = 0.0, transition: int = Tween.TRANS_QUAD,
		ease: int = Tween.EASE_OUT) -> void:
	tw.tween_method(func(p: Vector2) -> void:
		if is_instance_valid(card):
			card.position = p.round(), from, to, duration) \
			.set_delay(delay).set_trans(transition).set_ease(ease)


static func _snap_in(card: CanvasItem, veil: CanvasItem, dressing: CanvasItem,
		body_nodes: Array) -> void:
	if card != null:
		card.position = _home(card)
		card.modulate.a = 1.0
	if veil != null:
		veil.modulate.a = 1.0
	if dressing != null:
		dressing.modulate.a = 1.0
		if dressing.has_method("snap"):
			dressing.call("snap")
	snap_visible(body_nodes)


## force_tween 让 headless 回归也能覆盖真实的动画中断与退场回调。
static func modal_in(root: CanvasItem, card: CanvasItem, veil: CanvasItem,
		body_nodes: Array = [], force_tween: bool = false) -> Tween:
	return _enter(-1, root, card, veil, null, body_nodes, force_tween)


static func modal_out(root: CanvasItem, card: CanvasItem, veil: CanvasItem,
		on_done: Callable = Callable(), force_tween: bool = false) -> Tween:
	return _leave(-1, root, card, veil, null, on_done, force_tween)


## 外壳在布局完成后提供稳定落点；中断不得把过渡中位置记作新原点。
static func modal_reset(root: CanvasItem, card: CanvasItem, veil: CanvasItem,
		card_home: Vector2, veil_alpha: float) -> void:
	_cancel(root)
	if veil != null:
		veil.modulate.a = veil_alpha
	if card != null:
		card.set_meta("_modal_home", card_home.round())
		card.modulate.a = 1.0
		card.position = card_home.round()


static func object_in(kind: int, root: CanvasItem, card: CanvasItem, veil: CanvasItem,
		dressing: CanvasItem = null, body_nodes: Array = [], force_tween: bool = false) -> Tween:
	return _enter(kind, root, card, veil, dressing, body_nodes, force_tween)


static func object_out(kind: int, root: CanvasItem, card: CanvasItem, veil: CanvasItem,
		dressing: CanvasItem = null, on_done: Callable = Callable(), force_tween: bool = false) -> Tween:
	return _leave(kind, root, card, veil, dressing, on_done, force_tween)


static func _enter(kind: int, root: CanvasItem, card: CanvasItem, veil: CanvasItem,
		dressing: CanvasItem, body_nodes: Array, force_tween: bool) -> Tween:
	if root == null or not root.is_inside_tree():
		return null
	_cancel(root)
	root.visible = true
	var home := _home(card)
	if DisplayServer.get_name() == "headless" and not force_tween:
		_snap_in(card, veil, dressing, body_nodes)
		return null

	var tw := _tween(root)
	if veil != null:
		veil.modulate.a = 0.0
		tw.tween_property(veil, "modulate:a", 1.0, VEIL_IN)
	var duration := MODAL_IN
	var offset := Vector2(0.0, MODAL_LIFT)
	match kind:
		0: # 吊牌：链条落下后小幅回弹。
			duration = 0.24
			offset.y = -56.0
		1, 4: # 账簿 / 随身手札从桌沿滑上。
			duration = 0.20
			offset.y = 32.0
		2: # 墙上铁板落到四角固定点。
			duration = 0.20
			offset.y = -36.0
		5: # 信笺轻轻落下。
			duration = 0.20
			offset.y = -30.0
	if card != null:
		card.modulate.a = 0.0
		card.position = home + offset
		tw.tween_property(card, "modulate:a", 1.0, minf(duration, 0.14))
		if kind == 0:
			_move(tw, card, home + offset, home + Vector2(0.0, 4.0), 0.16,
					0.0, Tween.TRANS_QUAD, Tween.EASE_IN)
			_move(tw, card, home + Vector2(0.0, 4.0), home, 0.08, 0.16)
		else:
			_move(tw, card, home + offset, home, duration)
	if dressing != null:
		dressing.modulate.a = 0.0
		tw.tween_property(dressing, "modulate:a", 1.0, 0.14)
		if dressing.has_method("play_spring_settle"):
			# The board first lands and rebounds, then its suspended mass settles.
			dressing.call("play_spring_settle", force_tween, duration)
		elif kind == 2 and dressing.has_method("play_open"):
			# Empty corner seats become real nails only after the plate reaches
			# its wall position; each impact then receives its own short sparks.
			dressing.call("play_open", duration)
		elif dressing.has_method("play_open"):
			dressing.call("play_open")
	var delay := duration * 0.6
	for n in body_nodes:
		if n is CanvasItem:
			n.modulate.a = 0.0
			tw.tween_property(n, "modulate:a", 1.0, MODAL_IN * 0.8).set_delay(delay)
			delay += 0.03
	return tw


static func _leave(kind: int, root: CanvasItem, card: CanvasItem, veil: CanvasItem,
		dressing: CanvasItem, on_done: Callable, force_tween: bool) -> Tween:
	if root == null or not root.is_inside_tree():
		if on_done.is_valid():
			on_done.call()
		return null
	_cancel(root)
	var home := _home(card)
	if dressing != null and dressing.has_method("snap"):
		dressing.call("snap")
	if DisplayServer.get_name() == "headless" and not force_tween:
		if card != null:
			card.position = home
		if on_done.is_valid():
			on_done.call()
		return null

	var tw := _tween(root)
	if kind == 5 and dressing != null and dressing.has_method("fold_pose"):
		# Replace the flat sheet with three folding silhouettes. Keep the sealed
		# envelope visible before withdrawing it; no text or card scaling occurs.
		if card != null:
			card.position = home
			card.modulate.a = 0.0
		dressing.modulate.a = 1.0
		dressing.call("play_close")
		var fold_time := float(dressing.call("fold_duration"))
		var withdraw_time := float(dressing.call("withdraw_duration"))
		tw.tween_property(dressing, "fold_progress", 1.0, fold_time)
		tw.tween_property(dressing, "withdraw", 1.0, withdraw_time).set_delay(fold_time)
		tw.tween_property(dressing, "modulate:a", 0.0, 0.08).set_delay(fold_time + 0.06)
		if veil != null:
			tw.tween_property(veil, "modulate:a", 0.0, VEIL_OUT).set_delay(fold_time)
		tw.tween_callback(func() -> void:
			if is_instance_valid(card):
				card.position = home
			if on_done.is_valid():
				on_done.call()
		).set_delay(fold_time + withdraw_time)
		return tw
	if veil != null:
		tw.tween_property(veil, "modulate:a", 0.0, VEIL_OUT)
	var offset := Vector2(0.0, MODAL_LIFT)
	if kind == 0 or kind == 2:
		offset.y = -48.0
	elif kind == 1 or kind == 4:
		offset.y = 32.0
	if card != null:
		tw.tween_property(card, "modulate:a", 0.0, MODAL_OUT)
		_move(tw, card, card.position, home + offset, 0.13,
				0.0, Tween.TRANS_QUAD, Tween.EASE_IN)
	if dressing != null:
		tw.tween_property(dressing, "modulate:a", 0.0, 0.10)
		if dressing.has_method("play_close"):
			dressing.call("play_close")
	tw.tween_callback(func() -> void:
		if card != null and is_instance_valid(card):
			card.position = home
		if on_done.is_valid():
			on_done.call()
	).set_delay(0.14)
	return tw
