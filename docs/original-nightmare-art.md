# 梦魇原创炉骨战马

`tools/art/gen_original_executioner_nightmare.py --only nightmare` 从整数像素簇绘制53张独立透明PNG：待机8、奔跑8、蓄势5、喘息6、嘶鸣6、震地6、热浪6、倒地8。原始坐标、陶骨色板、关节与碎片都保留在源稿里，没有读取外部图片或既有马的帧。

剪影是无骑手的陶骨遗骸：长颈骨面、可见肋骨与腹内炉心、鬃上的葬名片、分节尾骨和两组交错屈腿。它与重甲双足的第一章Boss在体型、材质、轮廓和步态上均独立。`NightmareBoss` 读取 `assets/characters/original_nightmare/`；真实AI状态选择对应动作，蓄势姿势按战斗计时钉帧，死亡播放原创坍塌。128×96画布、1倍像素密度、原有身体与攻击时序保留。

验证：`screenshots/acceptance/overhaul-v3/original-bosses/nightmare-tests/`，14/14项、347断言、0引擎错误。真实level10的BossFixture输出6张图，位于 `nightmare-render/userdata/Godot/app_userdata/Rustgrave/boss_fixture/level10_auto/`，0引擎错误；已查看第三阶段，骨架/腹炉/蹄点与玩家清晰可分。取景使用直接减血和摆位，是表现检查，不是正常输入通关。

来源/权利：本项目原创程序像素绘制，无外部输入或来源URL；源稿与输出随代码交付供项目使用。逐帧哈希、尺寸与色板见目录内authorship.json。
