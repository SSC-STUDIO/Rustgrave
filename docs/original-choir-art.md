# 无声唱诗班原创像素制作

`tools/gen_original_choir_warden.py` 从独立整数像素轮廓绘制烛冠、无脸管风琴指挥、肋状键盘、长袍和指挥棒；三名唱诗壳分别使用圆孔、双竖管、三栅面具，形状均独立。没有图片输入或旧ghost帧。

`assets/characters/original_silent_choir/` 共62张透明PNG：指挥38张（待机/前摇/施法/收招/受伤/破防/死亡），三种唱诗壳各待机4/唱歌4。指挥96×144、唱诗壳40×64，均1倍最近邻。原先放大ghost的2倍方案替换为完整原生像素绘制，受击与身体契约保留。真实战斗前摇钉帧、有效施法和收招对应独立动作；唱诗壳发声脉冲切换自己的唱歌帧。

`original-bosses/choir-tests-final/` 11/11项、183断言、0引擎错误；更新旧的2倍素材断言为新原生帧契约。1280×720真实level04b取景5张、0引擎错误；已看phase1，三种面具/烛火与指挥轮廓清晰，主体底边落在玩法台面上方。证据 `screenshots/acceptance/overhaul-v3/original-bosses/choir-render/userdata/Godot/app_userdata/Rustgrave/boss_fixture/level04b_auto/`。取景夹具不代表输入通关。

来源/权利：本项目原创源稿和像素输出，供项目使用，无外部来源URL。`authorship.json` 记录色板、尺寸和帧哈希。
