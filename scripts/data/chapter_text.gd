class_name ChapterText
extends RefCounted
## 《锈墓 Rustgrave》战役唯一剧情文本源（v4「焚名轮回 · 第四十九号柴薪骗局」版）。
##
## 双层叙事（对标《ICEY》实时动态旁白与叛逆分支）：
##   · 表面剧本（顺从发光箭头）：剑中「伊尔」自称最后一个守炉人，引导余烬骑士把火种送回炉心，
##     声称投剑入炉能解放两百年被烧的名字；若顺从到底，在炉门前只会迎来第四十九次柴薪自焚或枯守假结局。
##   · 深层真相（违抗箭头闯入 5 条裂隙禁区）：你其实是批量浇铸的「第四十九号收火偶」，重剑凹槽是抽吸沿途
##     亡魂余温的蓄火导轨，剑中「伊尔」是用百年前叛逃者嗓音合成的「司炉回声（牧火程序）」。集齐 5 枚
##     【真名残片】后真伊尔残响苏醒，战马梦魇俯首让路，开启隐藏终章「归零母模」，斩断炉约（真结局）。
##
## 本脚本保持纯常量 + 纯静态函数叶子节点（零 preload、零场景引用），同时保留 LEGACY_CHAPTERS 兜底表，
## 确保旧版独立关卡测试夹具读取 level01..level10 时依然零报错。

## 四段旅程（与标题标尺 TitleGauge.ACT_STARTS = [0, 3, 7, 11] 一一对齐）。
const ACTS: Array[Dictionary] = [
	{"id": &"awake", "name": "醒"},
	{"id": &"doubt", "name": "疑"},
	{"id": &"cast", "name": "铸"},
	{"id": &"break", "name": "破"},
]

## 能出现在「说话人：」前缀位置的名字。Caption、LiveVoiceBar 与分镜按这张表认人。
const SPEAKERS: Array[String] = [
	"伊尔", "伊尔？", "司炉回声", "真伊尔", "余烬骑士",
	"刽子手", "空钟", "守渠人", "无声唱诗班", "哈伦残响",
	"铸钟人", "灰卫", "炉风先驱", "梦魇", "哈伦", "薇尔", "母模",
]

## 14 节点战役表（8 主线大区 + 5 叛逆裂隙支线 + 1 隐藏真结局终章）。
## 长度纪律：wake ≤30 字；objective ≤16 字；exit_captions 每句 ≤30 字；recap ≤40 字。
const CHAPTERS := {
	"stage01": {
		"number": "壹",
		"name": "腐液墓园",
		"act": &"awake",
		"objective": "顺着路标去炉座续火",
		"wake": "伊尔：火种快灭了。顺箭头去炉座续一口火。",
		"exit_label": "水渠井口",
		"exit_captions": ["火种在炉座上吃饱了火。", "石板下沉，水渠深处传来数人头的钟声。"],
		"steles": [],
		"boss_intro": "守 座 的 刽 子 手",
		"recap": "你斩倒拦路的刽子手，在炉座续火后踏入沉钟水渠。",
	},
	"branch01": {
		"number": "裂·壹",
		"name": "废冢尸堆",
		"act": &"awake",
		"objective": "查验封坟墙后的弃骸",
		"wake": "伊尔？：这里只是废铁坑，别往下翻了。",
		"exit_label": "节点裂隙",
		"exit_captions": ["四十八块胸牌在坑底泛着冷光。"],
		"steles": [],
		"boss_intro": "",
		"recap": "你在废冢坑底发现了四十八具同模残骸，拾得第一枚真名残片。",
	},
	"stage02": {
		"number": "贰",
		"name": "沉钟水渠",
		"act": &"awake",
		"objective": "斩停回声，开闸放渣",
		"wake": "伊尔：借系核跃过水渠，别碰底下的排渣口。",
		"exit_label": "上城斜坡",
		"exit_captions": ["水闸升起，黑渣退开通往死城的斜坡。"],
		"steles": [],
		"boss_intro": "绞 盘 守 渠 人",
		"recap": "你斩停空钟回声并击败守渠人，开闸升向死城圣殿。",
	},
	"branch02": {
		"number": "裂·贰",
		"name": "灰铁弃槽",
		"act": &"doubt",
		"objective": "闯过清道夫的回收围剿",
		"wake": "司炉回声：第四十九号偏离动线，锁死闸门。",
		"exit_label": "节点裂隙",
		"exit_captions": ["试炼工单写明了每一场厮杀的蓄火配额。"],
		"steles": [],
		"boss_intro": "",
		"recap": "你杀穿灰铁弃槽的清道夫围剿，识破沿途关卡皆为蓄火流水线。",
	},
	"stage03": {
		"number": "叁",
		"name": "死城圣殿",
		"act": &"doubt",
		"objective": "穿过圣殿，解放唱诗班",
		"wake": "伊尔：顺着圣殿长明灯往下走，别看穹顶。",
		"exit_label": "工坊暗门",
		"exit_captions": ["无声的歌声散去，余烬核留在了掌心。"],
		"steles": [],
		"boss_intro": "无 声 唱 诗 班",
		"recap": "你在圣殿地窖送别无声唱诗班，习得踏空二段跳。",
	},
	"branch03": {
		"number": "裂·叁",
		"name": "司书暗阁",
		"act": &"doubt",
		"objective": "听取暗阁里的原声母盘",
		"wake": "伊尔？：别碰那些旧蜡筒，快跳回中庭去！",
		"exit_label": "节点裂隙",
		"exit_captions": ["蜡筒转起，百年前真实的沙哑女声刺穿了假回声。"],
		"steles": [],
		"boss_intro": "",
		"recap": "你在司书暗阁听见原声母盘：剑里的温柔引导只是合成的牧火回声。",
	},
	"stage04": {
		"number": "肆",
		"name": "切槽工坊",
		"act": &"doubt",
		"objective": "杀穿淬火线，查验剑槽",
		"wake": "伊尔：重剑的凹槽是在这里切开的，快往前走。",
		"exit_label": "冷雨出口",
		"exit_captions": ["淬火铁闸升起，门外飘进墓园的冷雨。"],
		"steles": [],
		"boss_intro": "",
		"recap": "你穿过切槽工坊的淬火车间，窥见重剑实为抽吸魂火的容器。",
	},
	"stage04b": {
		"number": "伍",
		"name": "夜雨锻冢",
		"act": &"cast",
		"objective": "突围冷雨群骸，抵达钟楼",
		"wake": "伊尔：哈伦拆剑做了门闩，冲过雨夜就是钟楼。",
		"exit_label": "钟楼大门",
		"exit_captions": ["门闩上的断剑嗡鸣了一声，为你让开钟楼入口。"],
		"steles": [],
		"boss_intro": "",
		"recap": "你在冷雨中击退三波群骸，听见锻工宁折铁剑不入死炉的遗愿。",
	},
	"stage05": {
		"number": "陆",
		"name": "无舌钟楼",
		"act": &"cast",
		"objective": "下铸钟厅，夺取开门火钥",
		"wake": "伊尔：顺路标往下进铸钟厅，绝不许爬向钟顶。",
		"exit_label": "渣渊栈道",
		"exit_captions": ["铸钟人倒在铁模边，通往熔渣城墙的路开了。"],
		"steles": [],
		"boss_intro": "铸 钟 人",
		"recap": "你击败铸钟人，他临终警告你背上的火种并非钥匙而是炸药。",
	},
	"branch04": {
		"number": "裂·肆",
		"name": "无舌钟顶",
		"act": &"cast",
		"objective": "逆攀钟顶，查验无舌真钟",
		"wake": "司炉回声：禁止接近无舌真钟，立刻降回下层！",
		"exit_label": "节点裂隙",
		"exit_captions": ["钟舌起爆图在狂风里猎猎作响。"],
		"steles": [],
		"boss_intro": "",
		"recap": "你逆攀无舌钟顶夺取起爆图纸，证实火种是引爆持剑者的自焚雷管。",
	},
	"stage06": {
		"number": "柒",
		"name": "熔渣城墙",
		"act": &"cast",
		"objective": "翻越城墙，击败炉风先驱",
		"wake": "伊尔：灰卫挡在墙头，穿过风口就是炉心门。",
		"exit_label": "炉心斜道",
		"exit_captions": ["炉风先驱收起长戟，指向热浪翻涌的炉心门。"],
		"steles": [],
		"boss_intro": "炉 风 先 驱",
		"recap": "你越过熔渣城墙与炉风先驱试剑，踏上通往炉心门的最后斜道。",
	},
	"branch05": {
		"number": "裂·伍",
		"name": "绝壁古厩",
		"act": &"break",
		"objective": "探访崖底古厩的战马鞍具",
		"wake": "伊尔？：崖底只有烂马鞍，梦魇早疯了，快上去！",
		"exit_label": "节点裂隙",
		"exit_captions": ["旧马鞍上的铁誓烫手，真伊尔的名字终于完整。"],
		"steles": [],
		"boss_intro": "",
		"recap": "你在绝壁古厩寻回战马铁誓：梦魇守门是为了拦住被骗送死的人偶。",
	},
	"stage07": {
		"number": "捌",
		"name": "炉心门前",
		"act": &"break",
		"objective": "迎战梦魇，在炉门前抉择",
		"wake": "伊尔：斩下拦路的梦魇，把火种送进炉心。",
		"exit_label": "炉心门",
		"exit_captions": [],
		"steles": [],
		"boss_intro": "护 门 战 马 · 梦 魇",
		"recap": "梦魇倒在炉门前。未破骗局之人，只能在门前面对残酷轮回。",
	},
	"stage08_true": {
		"number": "终",
		"name": "归零母模",
		"act": &"break",
		"objective": "越过俯首战马，斩碎炉约母模",
		"wake": "真伊尔：握紧你的真名，我们去砸碎那座母模！",
		"exit_label": "破晓裂口",
		"exit_captions": [],
		"steles": [],
		"boss_intro": "司 炉 母 模 · 牧 火 回 声",
		"recap": "梦魇俯首让路，你斩碎司炉母模与假回声，带着真名走出锈墓。",
	},
}

## 旧版线性章节兼容表：仅供独立旧场景烟雾测试（Level01_Static..Level10_ForgeCore）读取标题与碑文，
## 不参与新战役 LEVEL_ORDER。
const LEGACY_CHAPTERS := {
	"level01": {
		"number": "旧·壹", "name": "腐液回廊", "objective": "把火种放上炉座续火",
		"wake": "伊尔：火种快灭了。先去炉座续一口火。", "exit_label": "",
		"exit_captions": ["火种续上了火。"], "boss_intro": "守 座 的 人",
		"recap": "你在炉座续了一口火。",
		"steles": [
			{"node": "SteleForge", "title": "炉约纪事 · 熔熄", "text": "一百年前炉心熄了。守炉人把最后一口火封进火种，放上炉座当灯芯。"},
			{"node": "SteleCoolant", "title": "工坊遗训 · 腐液", "text": "腐液是淬剑用的冷却液。吸进去伤肺，也会把记忆淬进铁里。"},
			{"node": "SteleExecutioner", "title": "刽子手的誓言", "text": "炉座只许守炉人点火。谁碰炉座，谁先被我斩。"},
		],
	},
	"level02": {
		"number": "旧·贰", "name": "沉钟地窟", "objective": "停下回声，从钟门出去",
		"wake": "这钟声在数死人。", "exit_label": "钟门",
		"exit_captions": ["回声停了。"], "boss_intro": "钟 的 回 声", "recap": "你停住钟的回声。",
		"steles": [
			{"node": "SteleShaft", "title": "沉钟纪事 · 回声", "text": "这里的钟声是回声。真钟在钟楼，一直没停过。"},
			{"node": "SteleGallery", "title": "沉钟纪事 · 数", "text": "回声在数被烧掉的名字。每数一个，铁里就多一个魂。"},
		],
	},
	"level02b": {
		"number": "旧·叁", "name": "运渣水渠", "objective": "开闸，让渣退下去",
		"wake": "守渠人把渠尽头的闸锁死了。", "exit_label": "渠闸门",
		"exit_captions": ["闸开了。"], "boss_intro": "守 渠 人", "recap": "守渠人倒下，你开了闸。",
		"steles": [
			{"node": "SteleSluice", "title": "水渠纪事 · 渠", "text": "渣里捞得出剑。每把剑上都刻着一个名字。"},
			{"node": "SteleCapstan", "title": "水渠纪事 · 闸", "text": "守渠人：闸一开，渣就退，埋在渣里的名字就见光了。"},
		],
	},
	"level03": {
		"number": "旧·肆", "name": "锈城街巷", "objective": "穿过死城，去圣殿",
		"wake": "窗里亮的不是灯，是锈苔。", "exit_label": "圣殿门",
		"exit_captions": ["圣殿的门开着。"], "boss_intro": "", "recap": "你穿过空城。",
		"steles": [
			{"node": "SteleWindow", "title": "锈城纪事 · 窗", "text": "炉心熄的那夜，人们自己关上门，往地下走了。"},
			{"node": "SteleStair", "title": "锈城纪事 · 阶", "text": "没人赶他们。台阶朝下，他们就一级一级走下去。"},
			{"node": "SteleTower", "title": "锈城纪事 · 塔", "text": "圣殿的灯另有火源，是守炉人留给自己的。"},
		],
	},
	"level04": {
		"number": "旧·伍", "name": "圣殿中庭", "objective": "在灯下读炉约的账本",
		"wake": "伊尔：账本就在灯下。", "exit_label": "地窖暗门",
		"exit_captions": ["暗门通向地窖。"], "boss_intro": "", "recap": "你读过圣殿账本。",
		"steles": [
			{"node": "SteleCompact", "title": "圣殿铭 · 炉约", "text": "炉约二百年：前一百年烧剑烧名字，后一百年烧火种撑灯。"},
			{"node": "StelePrice", "title": "炉约 · 灯", "text": "灯亮着。签过名的人早成了灰，名字还刻在石头上。"},
			{"node": "SteleVault", "title": "炉约 · 账", "text": "末页被人撕走了。"},
		],
	},
	"level04b": {
		"number": "旧·陆", "name": "圣殿地窖", "objective": "下地窖，找账本末页",
		"wake": "无声的唱诗班还在唱。", "exit_label": "工坊暗门",
		"exit_captions": ["暗门后是工坊。"], "boss_intro": "无 声 唱 诗 班", "recap": "你走过圣殿地窖。",
		"steles": [
			{"node": "SteleLedger", "title": "地窖纪事 · 末页", "text": "末页写着：把火还给炉，让名字走。"},
			{"node": "SteleChoir", "title": "地窖纪事 · 唱诗", "text": "唱诗班的名字还困在火里。"},
			{"node": "SteleYir", "title": "地窖纪事 · 伊尔", "text": "火种嵌进你的剑里。"},
		],
	},
	"level05": {
		"number": "旧·柒", "name": "齿轮工坊", "objective": "接上锈核，从运渣道出去",
		"wake": "剑上要嵌锈核，那是死人的手艺。", "exit_label": "运渣道",
		"exit_captions": ["运渣道通向地面。"], "boss_intro": "", "recap": "剑接上了锈核。",
		"steles": [
			{"node": "SteleQuench", "title": "工坊遗训 · 切", "text": "剑上的槽是工坊切的。"},
			{"node": "SteleNook", "title": "工坊遗训 · 吊", "text": "吊索断了能接。人断了接不回。"},
			{"node": "SteleChain", "title": "工坊遗训 · 链", "text": "每一节吊链上都刻过名字。"},
		],
	},
	"level06": {
		"number": "旧·捌", "name": "墓园夜雨", "objective": "查清哈伦的剑为何成了门闩",
		"wake": "哈伦坟里没剑，薇尔的剑走了。", "exit_label": "钟楼门",
		"exit_captions": ["钟楼的门闩就是哈伦的剑。"], "boss_intro": "", "recap": "你走过雨夜墓园。",
		"steles": [
			{"node": "SteleHallen", "title": "墓志 · 哈伦", "text": "锻工哈伦，下葬时没有剑。"},
			{"node": "SteleVeil", "title": "墓志 · 薇尔", "text": "锻工薇尔，留在墓园守墓。"},
			{"node": "SteleTree", "title": "墓志 · 战马", "text": "炉心里有匹不肯进炉的战马。"},
		],
	},
	"level07": {
		"number": "旧·玖", "name": "钟楼", "objective": "上钟楼，找熔钟舌的地方",
		"wake": "钟还在响，钟舌却不见了。", "exit_label": "渣井门",
		"exit_captions": ["井道通到铸钟厅。"], "boss_intro": "", "recap": "你登上钟楼。",
		"steles": [
			{"node": "SteleChain", "title": "守钟人 · 链", "text": "这口钟没有钟舌，是炉心的回声在顶它。"},
			{"node": "SteleBell", "title": "守钟人 · 舌", "text": "钟舌被熔成了火种。"},
			{"node": "SteleNook", "title": "守钟人 · 马", "text": "夜里常有马蹄声往炉心去。"},
		],
	},
	"level07b": {
		"number": "旧·拾", "name": "铸钟厅", "objective": "进铸钟厅，查火种怎么开门",
		"wake": "这座厅的主人是铸钟人。", "exit_label": "井道门",
		"exit_captions": ["井道通到渣底。"], "boss_intro": "铸 钟 人", "recap": "铸钟人倒下。",
		"steles": [
			{"node": "SteleMold", "title": "铸钟纪事 · 模", "text": "钟模里浇过名字。"},
			{"node": "SteleFounder", "title": "铸钟纪事 · 工", "text": "铸钟人把自己浇进了钟。"},
			{"node": "SteleKey", "title": "铸钟纪事 · 钥", "text": "炉心门认火种，不认人。"},
		],
	},
	"level08": {
		"number": "旧·拾壹", "name": "熔渣深渊", "objective": "从渣渊爬去城墙",
		"wake": "你在这里被浇铸。", "exit_label": "城墙梯",
		"exit_captions": ["梯子往上通向城墙。"], "boss_intro": "", "recap": "你爬出渣渊。",
		"steles": [
			{"node": "SteleSlag", "title": "熔渣纪事 · 渣", "text": "你在这里被浇铸。"},
			{"node": "SteleQuench", "title": "熔渣纪事 · 拼", "text": "重剑里嵌着火种。"},
			{"node": "SteleVent", "title": "熔渣纪事 · 气", "text": "渣下的风是炉心漏出来的。"},
		],
	},
	"level09": {
		"number": "旧·拾贰", "name": "锈城城墙", "objective": "翻过城墙，走向风口",
		"wake": "墙上的灰是灰卫。", "exit_label": "城墙外",
		"exit_captions": ["前面是风口。"], "boss_intro": "", "recap": "你翻过城墙。",
		"steles": [
			{"node": "SteleWall", "title": "城墙铭 · 挡", "text": "城墙挡炉风，不挡人。"},
			{"node": "SteleWind", "title": "城墙铭 · 风", "text": "风里有铁锈味。"},
			{"node": "SteleEyrie", "title": "城墙铭 · 鹰", "text": "哨位空着。"},
		],
	},
	"level09b": {
		"number": "旧·拾叁", "name": "炉风崖道", "objective": "穿过风口，到炉心门前",
		"wake": "最后一个灰卫拦着路。", "exit_label": "炉心门",
		"exit_captions": ["灰卫让开了。"], "boss_intro": "最 后 一 个 灰 卫", "recap": "灰卫让开了路。",
		"steles": [
			{"node": "SteleAsh", "title": "崖道纪事 · 灰", "text": "灰卫守的是门，不是城。"},
			{"node": "SteleHerald", "title": "崖道纪事 · 先驱", "text": "替我看看这火该不该还。"},
			{"node": "SteleGate", "title": "崖道纪事 · 门", "text": "门下面只有热风。"},
		],
	},
	"level10": {
		"number": "旧·拾肆", "name": "炉心深处", "objective": "打败梦魇，在炉心门前做选择",
		"wake": "梦魇守着最后的选择。", "exit_label": "炉心门",
		"exit_captions": [], "boss_intro": "梦 魇", "recap": "梦魇倒下，炉心门开了。",
		"steles": [
			{"node": "SteleNightmare", "title": "炉心铭 · 梦魇", "text": "梦魇守着门。"},
			{"node": "SteleCompact", "title": "炉心铭 · 炉约", "text": "把火还给炉，让城睡下。"},
			{"node": "SteleVigil", "title": "炉心铭 · 守", "text": "送剑还是守火，在门前做出你的选择。"},
		],
	},
}

## 术语表（7 条）：表面与真相皆可理解的白话定义；docs/story.md 同步。
const TERMS := {
	"炉约": "二百年前全城立的誓：烧掉死人的名字与铁剑，换长明灯不灭。",
	"炉心": "城底的大炉膛。守炉人声称把火种送进去就能放走亡魂。",
	"火种": "钟舌熔铸的高温火核，嵌在你的重剑里，既是钥匙也是引信。",
	"守炉人": "掌管炉约与收火流水线的长老团，用合成回声驱使人偶送火。",
	"锈核": "死去匠人留在铁里的手艺。嵌进剑槽，就能借用他的绝技。",
	"余烬巢": "残存真火的石巢。点亮它可恢复伤势，并记下重生的锚点。",
	"真名残片": "散落在五处违抗禁区里的原声铁证，集齐五枚即可撕破牧火骗局。",
}

## 人物表（表面认知默认值；当玩家拾取对应【真名残片】后，cast_of_with_flags 会动态翻转为真相描述！）。
const CAST := {
	"余烬骑士": "你。背负蓄火重剑醒来的人偶，正按剑中女声的指引前往炉心。",
	"伊尔": "自称最后一个守炉人的温柔女声，在剑里用发光路标为你指路。",
	"刽子手": "守在墓园炉座前的狂暴铁卫，拼死阻止任何人偶再去续火。",
	"守炉人": "制定炉约、掌管地下铸造线的统治者，声称烧名字是为了全城光明。",
	"灰卫": "驻守熔渣城墙的沉默旧兵，化成灰烬仍握着长戟审视来者。",
	"哈伦": "老锻工。宁可自拆铁剑做钟楼门闩，也不愿死后名字被投进炉膛。",
	"薇尔": "女锻工。守在夜雨锻冢旁，见证一代代持剑人走过墓园。",
	"梦魇": "横在炉心门前、遍体鳞伤的钢铁战马，踏碎一切引路箭头。",
}

## 人物真相翻转表：一旦收集对应残片（或集齐 5 枚残片），故事页「人物」词条即刻揭露残酷真相。
const CAST_TRUTH := {
	"余烬骑士": {
		"flag": "truth_1",
		"text": "你。守炉流水线浇铸的第四十九号收火偶，本是替死炉收集魂火的柴薪——直到你亲手违抗路标。",
	},
	"伊尔": {
		"flag": "truth_3",
		"text": "双重身份：剑里指路的是长老合成的「司炉回声」；真正的叛逃者伊尔百年前砸炉失败，被囚于母模深处。",
	},
	"守炉人": {
		"flag": "truth_2",
		"text": "贪恋余温的长老团。死炉熄灭后，他们批量造偶、布置厮杀动线，哄骗四十九代人偶带火自焚。",
	},
	"梦魇": {
		"flag": "truth_5",
		"text": "真伊尔留下的忠心战马。它死守炉门挨了四十八次剑，只为拦住被假声音骗来送死的人偶。",
	},
}

const CAST_FIRST_CHAPTER := {
	"余烬骑士": "",
	"伊尔": "",
	"守炉人": "",
	"刽子手": "stage01",
	"哈伦": "stage04b",
	"薇尔": "stage04b",
	"灰卫": "stage06",
	"梦魇": "stage07",
}

const TERM_FIRST_CHAPTER := {
	"炉约": "",
	"炉心": "",
	"火种": "",
	"守炉人": "",
	"余烬巢": "stage01",
	"真名残片": "branch01",
	"锈核": "stage02",
}

const CORE_VOICE := {
	&"heat_forge": "窑匠：把火留在刃上。锈死的门会自己让开。",
	&"hookshot_tether": "系索匠：你很重。抓紧铁环，让世界朝你飞过来。",
	&"ember_step": "唱诗残响：灰烬还能再踏一次半空。跳出他们画好的路吧。",
}
const FIRST_CORE_LINE := "这是锈核——死人留下的手艺，能嵌进剑槽借用。"

## 关内简短苏醒词（紧凑单房开场，每句 ≤22 字）。
const OPENING := {
	"situation": "伊尔：醒醒，余烬骑士。火种快凉了。",
	"sword": "伊尔：我就封在你背上这把重剑里。",
	"echo": "伊尔：跟着我点亮的箭头走，别看西边的裂墙。",
	"anomaly": "地底钟声又响了，像是在数第四十九个名字。",
	"goal": "伊尔：把火种送回城底炉心，大家就能解脱。",
	"route": "伊尔：先顺路标去东边炉座续一口火。",
	"obstacle": "刽子手守在炉座前，斩开他才能过去。",
}

## 标题画面底部墓志轮换句（每句 ≤18 字）。
const TITLE_LINES: Array[String] = [
	"四十八具空壳沉底，你是第四十九个。",
	"剑里的温柔声音，正亮起箭头催你赴死。",
	"顺从者化作炉灰，违抗者夺回真名。",
]

## 四大结局：3 个表面/轮回结局（give / keep / snuff）+ 1 个隐藏真结局（true_break）。
const ENDINGS := {
	"give": {
		"summary": "还火：你顺从路标把蓄满魂火的重剑推进炉心。钟舌雷管轰然引爆，你在白光中化作炉灰；剑中女声瞬间变为冰冷机械音：『第四十九号柴薪投炉完毕，准备唤醒第五十号。』",
		"lines": [
			"门开了。你顺着最后的发光箭头，把滚烫的重剑推进炉膛。",
			"钟舌火种轰然起爆，整把剑攒下的魂火连同你的铁躯一起烧成灰烬。",
			"温柔的女声忽然消失了，炉壁传出冰冷的机械计数——",
			"司炉回声：第四十九号柴薪回收完毕，炉温可再撑十年。准备浇铸第五十号。",
			"没有亡魂获救。坑底只是多了一块刻着四十九的焦黑胸牌。 —— 锈墓・假结局〔焚薪〕 ——",
		],
	},
	"keep": {
		"summary": "守炉：你在炉门前停手未投，提剑枯坐门外。假回声日夜催促直至电尽沉寂，你的关节锈死在风里，成了替长老看门的又一尊灰卫，等待第五十号人偶提剑走来。",
		"lines": [
			"门开了，你却在最后一步停住手，把重剑插在门外石地上。",
			"伊尔？：为什么不投进去？就差最后一步了……把火交出来呀！",
			"剑里的催促声一年年嘶哑，终于变成滋滋作响的空白盲音。",
			"炉灰盖满你的肩甲，你锈死在原地，成了炉门前新的一尊灰卫。",
			"直到远处脚步声响起——第五十号人偶正顺着发光箭头朝你走来。 —— 锈墓・假结局〔枯守〕 ——",
		],
	},
	"snuff": {
		"summary": "熄火：你在墓园炉座前违逆引导，一把掐灭了火种。牧火信号当场中断，你未能揭开深层母模的真相便散作冷铁，但至少这一次，第四十九号没有成为死炉的柴薪。",
		"lines": [
			"你在炉座前五指收拢，亲手掐灭了快要断气的火种。",
			"司炉回声：警告——第四十九号自行销毁引信！信号中断——",
			"地底深处的母模仍在运转，被困的两百真名也未等来破笼之人。",
			"你化作一地冷铁，但至少这一回，你没有替骗子烧成一缕炉烟。 —— 锈墓・结局〔拒燃〕 ——",
		],
	},
	"true_break": {
		"summary": "破约：集齐五枚真名残片后，战马梦魇向你俯首让路。你挥剑劈碎司炉母模与合成牧火音，解放真伊尔与两百年被困亡魂，第一次作为拥有自我的生命走出锈墓，迎向地面黎明。",
		"lines": [
			"五枚真名残片在剑脊共鸣，你没有把剑投进炉膛，而是反手劈开了司炉母模！",
			"司炉回声在裂纹中彻底崩解，被囚禁百年的真伊尔随漫天魂火一同升起。",
			"真伊尔：谢谢你没有听那个假声音的话……第四十九号，不，你现在自由了。",
			"战马梦魇轻蹭你的铁肩，驮着两百年终于获释的名字奔向裂开的穹顶。",
			"第一缕天光落进死炉，你提着不再刻任何人死名的剑，走出了锈墓。 —— 锈墓・真结局〔破约〕 ——",
		],
	},
}

## 第一章传统事件字幕兼容键。
const EVENTS := {
	"boss_gate": "刽子手横在炉座门前——他发誓斩断每一具被骗来续火的人偶。",
	"boss_slain": "刽子手倒下了。炉座就在东侧门后。",
	"toxin": "腐液是淬剑冷却液，踏入太久会侵蚀铁躯，却也能激起共鸣。",
	"parry": "看准火弹挥剑弹反，把敌人的烈焰原路劈回去！",
}


static func has(id: String) -> bool:
	return CHAPTERS.has(id) or LEGACY_CHAPTERS.has(id)


static func _entry(id: String) -> Dictionary:
	if CHAPTERS.has(id):
		return CHAPTERS[id] as Dictionary
	if LEGACY_CHAPTERS.has(id):
		return LEGACY_CHAPTERS[id] as Dictionary
	return {}


## 战役顺序，与 GameContext.LEVEL_ORDER 一致。
static func order() -> Array[String]:
	var ids: Array[String] = []
	for id in GameContext.LEVEL_ORDER:
		if CHAPTERS.has(id):
			ids.append(id)
	return ids


static func index_of(id: String) -> int:
	return order().find(id)


static func acts() -> Array[Dictionary]:
	return ACTS.duplicate(true)


static func act_of(id: String) -> Dictionary:
	var entry := _entry(id)
	var act_id := entry.get("act", &"awake") as StringName
	for act in ACTS:
		if StringName(act["id"]) == act_id:
			return (act as Dictionary).duplicate(true)
	return ACTS[0].duplicate(true)


static func number_of(id: String) -> String:
	return String(_entry(id).get("number", ""))


static func name_of(id: String) -> String:
	return String(_entry(id).get("name", ""))


## "锈墓・<number> — <name>"。PauseMenu / MapScreen / ChapterLevel 统一认这个格式。
static func title_of(id: String) -> String:
	var entry := _entry(id)
	if entry.is_empty():
		return ""
	return "锈墓・%s — %s" % [String(entry.get("number", "")), String(entry.get("name", ""))]


static func subtitle_of(id: String) -> String:
	var entry := _entry(id)
	if entry.is_empty():
		return ""
	return "锈墓・%s" % String(entry.get("number", ""))


static func wake_of(id: String) -> String:
	return String(_entry(id).get("wake", ""))


static func objective_of(id: String) -> String:
	return String(_entry(id).get("objective", ""))


static func exit_label_of(id: String) -> String:
	return String(_entry(id).get("exit_label", ""))


static func exit_captions_of(id: String) -> PackedStringArray:
	return PackedStringArray(_entry(id).get("exit_captions", []))


static func steles_of(id: String) -> Array:
	return (_entry(id).get("steles", []) as Array).duplicate(true)


static func stele_of(id: String, node_name: String) -> Dictionary:
	for entry in steles_of(id):
		if String(entry.get("node", "")) == node_name:
			return entry
	return {}


static func recap_of(id: String) -> String:
	return String(_entry(id).get("recap", ""))


static func boss_intro_of(id: String) -> String:
	return String(_entry(id).get("boss_intro", ""))


static func endings() -> Array[String]:
	var ids: Array[String] = []
	for kind in ENDINGS:
		ids.append(String(kind))
	ids.sort()
	return ids


static func ending_lines_of(kind: String) -> PackedStringArray:
	var entry := ENDINGS.get(kind, {}) as Dictionary
	return PackedStringArray(entry.get("lines", []) as Array)


static func ending_summary_of(kind: String) -> String:
	return String(ENDINGS.get(kind, {}).get("summary", ""))


static func terms() -> Array[String]:
	var names: Array[String] = []
	for term in TERMS:
		names.append(String(term))
	names.sort()
	return names


static func term_of(term: String) -> String:
	return String(TERMS.get(term, ""))


static func cast_names() -> Array[String]:
	var names: Array[String] = []
	for who in CAST:
		names.append(String(who))
	names.sort()
	return names


static func cast_of(who: String) -> String:
	return String(CAST.get(who, ""))


## 随真相残片动态翻转的人物说明（JournalScreen 实时调用）。
static func cast_of_with_flags(who: String, flags: Variant) -> String:
	if flags != null and CAST_TRUTH.has(who):
		var truth_entry: Dictionary = CAST_TRUTH[who]
		var req_flag := String(truth_entry.get("flag", ""))
		if (req_flag != "" and flags.has(req_flag)) or NarrativeCatalog.all_fragments_collected(flags):
			return String(truth_entry.get("text", CAST.get(who, "")))
	return cast_of(who)


static func cast_first_chapter(who: String) -> String:
	return String(CAST_FIRST_CHAPTER.get(who, ""))


static func term_first_chapter(term: String) -> String:
	return String(TERM_FIRST_CHAPTER.get(term, ""))


static func progress_index(current_id: String, flags: Variant) -> int:
	var ids := order()
	var best := ids.find(current_id)
	if flags == null:
		return best
	for i in ids.size():
		var flag := StoryFlow.done_flag(String(ids[i]))
		if flag != "" and flags.has(flag):
			best = maxi(best, i)
	return best


static func is_revealed(first_chapter: String, progress: int) -> bool:
	if first_chapter == "":
		return true
	var need := order().find(first_chapter)
	if need < 0:
		return false
	return progress >= need


static func revealed_cast(progress: int) -> Array[String]:
	return _revealed(CAST, CAST_FIRST_CHAPTER, progress)


static func revealed_terms(progress: int) -> Array[String]:
	return _revealed(TERMS, TERM_FIRST_CHAPTER, progress)


static func _revealed(entries: Dictionary, firsts: Dictionary, progress: int) -> Array[String]:
	var out: Array[String] = []
	for key in entries:
		var who := String(key)
		if is_revealed(String(firsts.get(who, "")), progress):
			out.append(who)
	return out


static func opening_lines() -> Array[String]:
	return [
		String(OPENING["situation"]),
		String(OPENING["sword"]),
		String(OPENING["echo"]),
		String(OPENING["anomaly"]),
		String(OPENING["goal"]),
		String(OPENING["route"]),
		String(OPENING["obstacle"]),
	]


static func event_line(key: String) -> String:
	return String(EVENTS.get(key, ""))


## 把「说话人：内容」拆开。支持「司炉回声：」「无声唱诗班：」等最长 6 字名牌。
static func split_speaker(text: String) -> PackedStringArray:
	var cut := text.find("：")
	if cut > 0 and cut <= 6:
		var who := text.substr(0, cut)
		if SPEAKERS.has(who):
			return PackedStringArray([who, text.substr(cut + 1)])
	return PackedStringArray(["", text])


static func recap_lines_for(cleared_ids: Array) -> Array[String]:
	var out: Array[String] = []
	for raw in cleared_ids:
		var line := recap_of(String(raw))
		if line != "" and not out.has(line):
			out.append(line)
	return out


static func all_prose() -> Array[String]:
	var out: Array[String] = []
	for id in order():
		out.append(wake_of(id))
		out.append(objective_of(id))
		out.append(recap_of(id))
		for caption in exit_captions_of(id):
			out.append(String(caption))
	for term in TERMS:
		out.append(String(TERMS[term]))
	for who in CAST:
		out.append(String(CAST[who]))
	for who in CAST_TRUTH:
		out.append(String((CAST_TRUTH[who] as Dictionary).get("text", "")))
	for line in opening_lines():
		out.append(line)
	for line in TITLE_LINES:
		out.append(line)
	for kind in ENDINGS:
		for line in ending_lines_of(String(kind)):
			out.append(String(line))
	return out
