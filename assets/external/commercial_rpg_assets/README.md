# 可商用 RPG 装备与像素素材包汇总说明 (Commercial RPG & Equipment Assets)

本项目已从公开合规开源美术平台（OpenGameArt / Kenney.nl）收录并整理了以下三大**完全支持商业化运作（Commercial Use Permitted）**的像素风格 RPG 装备、物品与图标素材包。

全部素材存放在本目录（`assets/external/commercial_rpg_assets/`）下，已完成解压与分类整理。

---

## 目录结构速览

```
assets/external/commercial_rpg_assets/
├── README.md                      # 本说明文档（许可协议与使用指南）
├── shade_16x16_rpg_icons/        # 【Pack 1】Shade 16x16 丰富 RPG 图标套件 (CC0)
│   └── 16x16 Assorted RPG Icons/
│       ├── armours.png            # 150+ 款护甲、胸甲、护胫等防具设计图
│       ├── weapons.png            # 9 种武器基础原型 × 8 种颜色变体 (单手剑、巨剑、短刃等)
│       ├── potions.png            # 15 款药水设计 × 20+ 颜色方案 (治疗、毒抗、解毒瓶等)
│       ├── consumables.png        # 30 款消耗品设计 × 22+ 颜色方案
│       ├── books.png              # 12 款书卷/卷轴 × 14 种颜色
│       ├── chests.png             # 50+ 种宝箱、废料箱与金属收纳盒
│       └── all-assets-preview.png # 预览图
│
├── kyrise_16x16_rpg_icons/        # 【Pack 2】Kyrise 经典 16x16 RPG 图标包 V1.2 (CC-BY 4.0)
│   └── Kyrise's 16x16 RPG Icon Pack - V1.2/
│       ├── icons/
│       │   ├── 16x16/             # 48+ 款独立切好的 16×16 PNG 原生图标 (武器/防具/饰品/材料)
│       │   ├── 32x32/             # 2x 整数倍放大无损版
│       │   └── 48x48/             # 3x 整数倍放大无损版
│       ├── spritesheet/           # 合并雪碧图
│       └── read me.txt            # 作者原版许可说明与致谢
│
└── kenney_roguelike_rpg/          # 【Pack 3】Kenney Roguelike/RPG 1700+ 图标与瓦片集 (CC0)
    ├── Spritesheet/
    │   ├── roguelikeSheet_transparent.png  # 透明底像素图集 (武器、护甲、齿轮、饰品、地块)
    │   └── spritesheetInfo.txt    # 瓦片索引偏移数据
    └── License.txt                # CC0 协议全文
```

---

## 素材包许可协议与版权详情 (Licenses & Permissions)

### 1. Shade's 16x16 Assorted RPG Icons
- **作者**：Shade ([Itch.io 个人主页](https://merchant-shade.itch.io/))
- **来源**：[OpenGameArt.org - 16x16 Assorted RPG Icons](https://opengameart.org/content/16x16-assorted-rpg-icons)
- **开源协议**：**Creative Commons Zero (CC0 1.0 Universal - 公共领域)**
- **商用许可**：**完全允许商用（Commercially or Not）**，无需支付版税，允许任意修改、二创与打包发布。
- **署名要求**：**非强制（No need to give credit）**。作者在页面明确声明：“Feel free to use this for your game (commercially or not)... No need to give me credit.”
- **特色内容**：包含超过 150 种独特的胸甲/轻重装护甲方案（非常适合《Rustgrave》余烬骑士的粗铁重甲、轻便装甲等防具槽需求），以及各色金属剑刃、废料箱与药水试剂。

---

### 2. Kyrise's Free 16x16 RPG Icon Pack (V1.2)
- **作者**：Kyrise ([Itch.io 页面](https://kyrise.itch.io/kyrises-free-16x16-rpg-icon-pack))
- **来源**：[OpenGameArt.org - Kyrise's Free 16x16 RPG Icon Pack](https://opengameart.org/content/kyrises-free-16x16-rpg-icon-pack)
- **开源协议**：**Creative Commons Attribution 4.0 International (CC BY 4.0)**
- **商用许可**：**完全允许商用**，允许自由复制、分发、修改与商业化嵌入。
- **署名要求**：**需在游戏制作名单中注明作者出处**。
  - **建议署名格式**：
    > Kyrise's 16x16 RPG Icon Pack by Kyrise (https://kyrise.itch.io/) licensed under CC BY 4.0
- **特色内容**：
  - 拥有单独导出的独立 16×16、32×32、48×48 PNG 文件，每个图标自带 1px 黑色像素描边，非常适合 Godot UI 纹理贴图。
  - 饰品与戒指资源极其丰富：包含单戒（Ring）、护身符（Amulet/Necklace）、水晶（Crystal）、宝石（Gem）、金属锭（Ingot）与钥匙，可直接作为装备系统的两枚「饰品」插槽图标。

---

### 3. Kenney's Roguelike/RPG Pack (1,700+ Tiles)
- **作者**：Kenney ([Kenney.nl](https://kenney.nl/))
- **来源**：[OpenGameArt.org - Roguelike/RPG pack](https://opengameart.org/content/roguelikerpg-pack-1700-tiles) 与 [Kenney.nl 官方资产库](https://kenney.nl/assets/roguelike-rpg-pack)
- **开源协议**：**Creative Commons Zero (CC0 1.0 Universal - 公共领域)**
- **商用许可**：**完全免费商用，零版税，无任何限制**。
- **署名要求**：**非强制（Not mandatory）**。
- **特色内容**：
  - 工业齿轮、机械构件、铁矿石、断剑与工具瓦片，与《Rustgrave》机械文明地下陵墓废土风格天然吻合。
  - 亦包含小盾牌、铁靴、手套、头盔等部位图标。

---

## 在《Rustgrave》中的应用推荐建议

1. **装备系统图标映射**（`scripts/data/equipment_catalog.gd` & `CharacterEquipmentPanel`）：
   - **武器槽（Weapon）**：
     - 初始「破损巨剑」：使用 `shade_16x16_rpg_icons/weapons.png` 或 `kyrise_16x16_rpg_icons` 中的粗糙铁剑。
     - 进阶武器「锯齿齿轮剑 / 熔火重刃」：选取高阶钢剑并搭配 palette 色彩滤镜。
   - **护甲槽（Armor）**：
     - 初始「粗铁胸甲」：使用 `shade_16x16_rpg_icons/armours.png` 中灰铁质感胸甲。
     - 进阶防具「锻炉隔热铠 / 废料合金重甲」：使用金褐色与带重装铆钉的护甲。
   - **饰品槽（Trinket 1 & 2）**：
     - 初始「锈蚀怀表 / 齿轮护符」：直接采用 `kyrise_16x16_rpg_icons/icons/16x16/` 中的项链与戒指单体切图。
     - 毒抗饰品「滤芯挂坠 / 余烬指环」：采用绿色毒液护符或赤色火系宝石。

2. **色板适配提示（Palette Tuning）**：
   - 《Rustgrave》使用暗调 16 色锈蚀调色板（`scripts/data/palette.gd`）。
   - 如需让外部图标与游戏原生像素美学完全融为一体，可在导入 Godot 时挂载 CanvasItemShader（参考 `assets/shaders/`）或通过 Python 离线脚本将图标调色映射至游戏 16 色。
