# 炉风先驱原创像素制作

`tools/gen_original_bell_bosses.py` 的 `emberwind_herald()` 从整数像素簇绘制机械鸟：长喙冠、分节钢翼、五片镜眼尾羽、炉灯胸腔和折钩爪。它没有人的头盔/披风/手臂，也没有读取图片、描图或下载角色帧。灰卫的剧情身份和攻击ID保留，以独立鸟形机关甲呈现。

`assets/characters/original_emberwind_herald/` 包含68张192×144透明PNG，原生1倍最近邻：待机、俯冲、推风、羽刃、上升气流各6帧，倒地4帧，全部有冷态/过热态。二阶段钢翼开缝透热；倒地收翼有机械颤动。`authorship.json` 记录源稿、无外部输入、色板和逐帧像素哈希。

真实攻击步骤控制0–1前摇、2–3判定、4–5收招；朝向直接跟随战斗方向。真实钩锁落地使用折翼帧，单独对齐地面，死亡同样播放原创折翼帧。身体、受击、攻击判定和时序不改。

`screenshots/acceptance/overhaul-v3/original-bosses/herald-tests-death/` 为12/12、0引擎错误，覆盖原战斗、世界风区坐标与新帧/真实步骤/钩锁着地。真实level09b BossFixture记录5张图、0引擎错误，已检查一/二阶段画面。原夹具机位偏左，`scenes/tools/HeraldArtReview.tscn` 另驱动真实姿势选择器和钩锁落地，保存冷/热六动作共12张1280×720完整轮廓图，报告0引擎错误；已查看推风与过热折翼图。证据为 `herald-portraits/{report.json,stdout-complete.log,stderr-complete.log}`。取景摆位/注入状态不计作输入通关。

作者/权利：本项目原创绘制源稿与输出，供项目使用，无外部来源URL。
