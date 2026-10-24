# 绞盘守渠人原创像素制作

`tools/gen_original_choir_warden.py` 中的 `warden()` 从整数像素簇绘制潜水头盔、压力表、双水平绞筒、链锚和重靴；无图片输入、描图或外站素材。38张透明PNG落在 `assets/characters/original_capstan_warden/`，包括待机6、格挡4、蓄力6、扫链6、泄压4、受伤3、破防4、死亡7。每帧尺寸128×112、1倍最近邻；authorship.json记录源稿、色板和像素哈希。

实际Boss已停止读取盾卫帧。绞盘直接画在原创帧内，旧圆轮轭不再叠画；原泄压阀仍是可打的战斗弱点。真实前摇计时控制蓄力姿势，有效链扫固定专属扫击帧，破防、泄压和死亡也都使用专属动作。身体/受击框、攻击ID和存档逻辑保留。

验证：`screenshots/acceptance/overhaul-v3/original-bosses/capstan-tests/` 12/12、186断言、0引擎错误。1280×720真实level02b的BossFixture保存5张图于 `capstan-render/userdata/Godot/app_userdata/Rustgrave/boss_fixture/level02b_auto/`，0引擎错误；已查看一阶段，潜水甲、水平绞筒、独立泄压阀、链锚与玩家区分清楚。取景摆位/扣血不计作输入通关。

作者/权利：本项目原创，源稿与输出供项目使用，无外部来源URL。共同生成器还包括独立唱诗班绘制，后续单独接入并验收。
