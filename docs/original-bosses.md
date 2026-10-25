# 七位Boss原创美术

七位Boss现在各有独立轮廓、装备、色板和逐帧动作，运行时全部读取各自的 `assets/characters/original_*` 目录。旧盾卫、ghost和horse不再供Boss使用。绘制源稿均在仓库内，以整数像素簇、关节和轮廓自行绘制，没有图片输入、描图或下载角色帧。原故事身份与战斗判定保留。

| Boss | 独立设计 | 帧数 | 绘制源稿 / 说明 |
| --- | --- | ---: | --- |
| 刽子手 | 闭面葬甲、碑盾、裂斧、破布；真实斩击钉帧 | 38 | `tools/art/gen_original_executioner_nightmare.py`；`original-executioner-art.md` |
| 空钟 | 双链悬挂裂钟、姓名铭板、独立八角钟舌弱点 | 72 | `tools/gen_original_bell_bosses.py`；`original-hollow-bell-art.md` |
| 绞盘守渠人 | 压力潜水甲、水平双绞筒、链锚、独立泄压阀 | 40 | `tools/gen_original_choir_warden.py`；`original-capstan-art.md` |
| 无声唱诗班 | 无脸管风琴指挥、烛冠肋键、三种独立唱诗面具 | 60 | `tools/gen_original_choir_warden.py`；`original-choir-art.md` |
| 铸钟人 | 四层铸模重甲、背炉、铸钳和独立分节锤 | 128 | `tools/gen_original_bell_bosses.py`；`original-bell-founder-art.md` |
| 炉风先驱 | 长喙冠、分节钢翼、五镜眼尾羽、炉灯胸腔 | 68 | `tools/gen_original_bell_bosses.py`；`original-herald-art.md` |
| 梦魇 | 窑骨骸马、外露炉心、名牌鬃、独立四足步态 | 53 | `tools/art/gen_original_executioner_nightmare.py`；`original-nightmare-art.md` |

总计459张透明像素PNG。空钟的钟舌、铸钟人的锤与三名唱诗壳按独立图层计帧。空钟、铸钟人和炉风先驱的冷/热态除配色外还有开裂、护板/翼片和炉缝变化。前摇、判定、收招与倒地动作由真实战斗状态选择；轮廓变化不改变身体、攻击和弱点判定。

## 可复现与实际画面

运行 bundled Python 的 `tools/art/review_original_bosses.py --reproduce`，在隔离暂存目录重新绘制全部源稿，并与交付PNG逐像素比较。本轮459/459一致，所有帧为二值透明度，跨Boss没有完全相同的像素帧。哈希和计数只证明交付完整性；原创性依据是可编辑绘制源稿与逐个轮廓审阅。

本地证据根为 `screenshots/acceptance/overhaul-v3/original-bosses/`：

- `seven-original-bosses.png`：七位造型对照，卡片各自放大，不表示游戏内体型比例。
- `original-assets-review.json`：459帧像素哈希、源稿重现与透明度结果。
- `executioner-tests-final`、`nightmare-tests`、`capstan-tests`、`choir-tests-final`、`herald-tests-death`：针对实际战斗状态和美术集成的通过报告。空钟/铸钟人报告保留于 `screenshots/acceptance/original-bells/{hollow,founder}-tests/`。
- 各 `*-render`：真实章节BossFixture。使者另有 `herald-portraits/` 12张1280×720全轮廓动作图，含真实钩锁折翼。
- `bell-evidence-import.json`：空钟/铸钟人图像与报告从独立绘制工作区复制的来源、原提交和整合提交。

以上取景包含摆位、注入伤害或直接选择真实攻击步骤，是视觉/战斗夹具。完整正常输入战役的结论以 `overhaul-v3.md` 和 `acceptance.md` 的独立报告为准。来源及项目使用权见 `assets/external/CREDITS.md`。
