# 炉约刽子手原创像素制作

`tools/art/gen_original_executioner_nightmare.py --only executioner` 从整数像素线段和色块绘制38张透明PNG，不读取参考图、外站素材或旧角色。源稿保留闭面葬甲、裂刃巨斧、碑形小盾和撕裂礼披风的全部轮廓与关节。

实际角色读取 `assets/characters/original_executioner/`：待机6、举盾4、蓄力6、挥斧8、炉火技能6、倒地8。盾卫继续使用自己的既有素材。刽子手保留100×100画布、整数2倍缩放和脚底基线，碰撞、受击、攻击ID、伤害和时序没有随美术更换。新帧已经有金属高光，身体提亮倍率降至1.12/1.08/1.03，二阶段暖化，避免沿用旧暗素材的高倍率导致过曝。

挥斧使用真实前摇计时选择举刃帧、有效判定期间固定接触帧4、完整收招期间显示回收帧6/7；渲染时钟不会自行播过攻击接触点。尸体也使用专属帧，保留2倍画幅。

源图总览：`screenshots/acceptance/overhaul-v3/original-bosses/source-previews/executioner.png`。自动化保护检查来源独立性、透明边、动作变化、脚底和真实挥斧/尸体接线；真实场景截图和验证结果在完成后记入验收记录，取景夹具不代表正常输入通关。

作者/来源：本项目原创程序像素绘制；无外部输入或来源URL。项目内部使用，源稿及全部输出随代码交付。

验证：`original-bosses/executioner-tests-final/` 的10/10（235断言）通过、0引擎错误；覆盖旧战斗/终局与新增美术。1280×720真实level01 BossFixture的5张图保存于 `original-bosses/executioner-render/userdata/Godot/app_userdata/Rustgrave/boss_fixture/level01_auto/`，报告0引擎错误；已查看phase1/phase2，脚下贴台面，巨斧/碑盾和装甲细节可读。夹具通过直接减血构图，不计作输入通关。
