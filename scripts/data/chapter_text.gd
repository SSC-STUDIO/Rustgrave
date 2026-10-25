class_name ChapterText
extends RefCounted
## Rustgrave 战役的**唯一剧情文本源**（contract §1.2；v3「看得懂」重写版）。
##
## 关卡 layout、开场、第一章事件字幕、章间分镜、暂停菜单「故事」页都从这里取字；改故事只改
## 这个文件 + docs/story.md（tests/chapter_text_test.gd 会逐字比对 docs 的「文本锚点」）。
##
## Canon（v3，一句话：锈墓靠烧死人的魂点了二百年的灯；最后一个守炉人伊尔把自己和最后的
## 火种封进你的剑，请你把它还给炉心，放所有被烧的魂走——代价是你也会被烧尽）：
##   · 炉约：二百年前全城立的誓。人死后名字刻在剑上、剑投进炉里烧，换灯不灭；名字烧了，
##     魂就困在铁里回不来。立誓、烧名字的那批人叫守炉人。
##   · 一百年前炉心熄灭。守炉人把最后一口火封进一枚小核——火种（熔了钟楼的钟舌铸的），
##     放上炉座当灯芯，又烧了一百年，灯一年比一年暗。
##   · 如今火种快灭。最后一个守炉人伊尔不愿再烧：她把自己的魂封进火种、从炉座取下、嵌进
##     你背上的剑，托你带它回炉心。伊尔的动作都在「封进火种之前」；你听到的是火种里的回声。
##   · 你是余烬骑士：守炉人造来替死者扛剑进炉的人偶，没用上就锈了；伊尔从渣里把你捡回来。
##   · 第一章：火种快灭，先放上炉座续一口火才撑得到炉心；刽子手守着炉座（誓约不许任何人碰）。
##   · 钥匙：炉心门认火种不认人，所以只能由你带去。梦魇是不肯进炉的战马，守着炉心门。
##   · 终点：还火（放魂走、你也散成铁）／守炉（留下做新的守炉人，火不灭名字不走）。第一章
##     可以提前熄火：你没问到，魂永远没有出路。
##   · 称呼只用「你 / 余烬骑士」「伊尔」「守炉人」「锈墓（城）」；不出现设计术语（测试会拦）。
##
## 这个脚本必须是叶子节点：只要常量、没有 preload、不引用场景，避免 HUD 的
## PauseMenu → MapScreen → ChapterTitles → ChapterText 预加载链把关卡场景拖回加载图。
##
## 章号与 id 分离：存档/旗标永远用 id（level03_done），显示章号只在这里（14 章重编）。
## 长度纪律：醒来句 ≤30 字；目标 ≤16 字；碑文 ≤2 行 × 22 字；出口字幕 1–2 句、每句 ≤30 字；
## 前情 ≤40 字。台词用「说话人：内容」写，Caption / 分镜会把说话人单独画成名牌。

## 四段。act id 供 StoryFlow / 文档 / 测试分组，name 只显示。
const ACTS: Array[Dictionary] = [
	{"id": &"awake", "name": "醒"},
	{"id": &"debt", "name": "账"},
	{"id": &"cast", "name": "铸"},
	{"id": &"forge", "name": "炉"},
]

## 能出现在「说话人：」前缀位置的名字。Caption 与分镜按这张表认人。
const SPEAKERS: Array[String] = [
	"伊尔", "余烬骑士", "刽子手", "灰卫", "梦魇", "守渠人", "铸钟人", "哈伦", "薇尔",
]

const CHAPTERS := {
	"level01": {
		"number": "壹",
		"name": "腐液回廊",
		"act": &"awake",
		"objective": "把火种放上炉座续火",
		"wake": "伊尔：火种快灭了。先去炉座续一口火。",
		"exit_label": "",
		"exit_captions": ["火种续上了火。收回剑里，带它下去。", "脚下的石板松开了，下面有钟声。"],
		"steles": [
			{"node": "SteleForge", "title": "炉约纪事 · 熔熄",
					"text": "一百年前炉心熄了。守炉人把最后一口火封进火种，放上炉座当灯芯。"},
			{"node": "SteleCoolant", "title": "工坊遗训 · 腐液",
					"text": "腐液是淬剑用的冷却液。吸进去伤肺，也会把记忆淬进铁里。"},
			{"node": "SteleExecutioner", "title": "刽子手的誓言",
					"text": "炉座只许守炉人点火。谁碰炉座，谁先被我斩。"},
		],
		"boss_intro": "守 座 的 人",
		"recap": "火种快灭，你在炉座续了一口火，带它下城。",
	},
	"level02": {
		"number": "贰",
		"name": "沉钟地窟",
		"act": &"awake",
		"objective": "停下回声，从钟门出去",
		"wake": "这钟声在数死人。它是回声，不是真钟。",
		"exit_label": "钟门",
		"exit_captions": ["回声停了。真钟还在钟楼响。", "钟门后面是运渣渠。"],
		"steles": [
			{"node": "SteleShaft", "title": "沉钟纪事 · 回声",
					"text": "这里的钟声是回声。真钟在钟楼，一直没停过。"},
			{"node": "SteleGallery", "title": "沉钟纪事 · 数",
					"text": "回声在数被烧掉的名字。每数一个，铁里就多一个魂。"},
		],
		"boss_intro": "钟 的 回 声",
		"recap": "你停住钟的回声，从钟门走向运渣渠。",
	},
	"level02b": {
		"number": "叁",
		"name": "运渣水渠",
		"act": &"awake",
		"objective": "开闸，让渣退下去",
		"wake": "守渠人把渠尽头的闸锁死了。渣不退，就没有路。",
		"exit_label": "渠闸门",
		"exit_captions": ["闸开了。渣退下去，露出通往上城的斜坡。", "去炉心的路只剩圣殿的暗门。先上去。"],
		"steles": [
			{"node": "SteleSluice", "title": "水渠纪事 · 渠",
					"text": "渣里捞得出剑。每把剑上都刻着一个名字。"},
			{"node": "SteleCapstan", "title": "水渠纪事 · 闸",
					"text": "守渠人：闸一开，渣就退，埋在渣里的名字就见光了。"},
		],
		"boss_intro": "守 渠 人",
		"recap": "守渠人倒下，你开了闸，沿着斜坡往上走。",
	},
	"level03": {
		"number": "肆",
		"name": "锈城街巷",
		"act": &"debt",
		"objective": "穿过死城，去圣殿",
		"wake": "窗里亮的不是灯，是锈苔。人都走光了。",
		"exit_label": "圣殿门",
		"exit_captions": ["圣殿的门开着。里面有一盏灯还亮。", "伊尔：炉约的账本在灯下。去看。"],
		"steles": [
			{"node": "SteleWindow", "title": "锈城纪事 · 窗",
					"text": "炉心熄的那夜，人们自己关上门，往地下走了。"},
			{"node": "SteleStair", "title": "锈城纪事 · 阶",
					"text": "没人赶他们。台阶朝下，他们就一级一级走下去。"},
			{"node": "SteleTower", "title": "锈城纪事 · 塔",
					"text": "圣殿的灯另有火源，是守炉人留给自己的。炉座那盏已经暗了。"},
		],
		"boss_intro": "",
		"recap": "你穿过空城，来到圣殿门前。",
	},
	"level04": {
		"number": "伍",
		"name": "圣殿中庭",
		"act": &"debt",
		"objective": "在灯下读炉约的账本",
		"wake": "伊尔：账本就在灯下。你读，我听。",
		"exit_label": "地窖暗门",
		"exit_captions": ["账本的最后一页被人撕走了。", "暗门通向地窖。"],
		"steles": [
			{"node": "SteleCompact", "title": "圣殿铭 · 炉约",
					"text": "炉约二百年：前一百年烧剑烧名字，后一百年烧火种撑灯。"},
			{"node": "StelePrice", "title": "炉约 · 灯",
					"text": "灯亮着。签过名的人早成了灰，名字还刻在石头上。"},
			{"node": "SteleVault", "title": "炉约 · 账",
					"text": "末页是伊尔撕走的。她不想让守炉人看见上面写的字。"},
		],
		"boss_intro": "",
		"recap": "账本说：前一百年烧剑，后一百年烧火种撑灯。",
	},
	"level04b": {
		"number": "陆",
		"name": "圣殿地窖",
		"act": &"debt",
		"objective": "下地窖，找账本末页",
		"wake": "无声的唱诗班还在唱。她们的魂困在火里。",
		"exit_label": "工坊暗门",
		"exit_captions": ["末页是伊尔写的：把火还给炉，让名字走。", "暗门后是工坊。"],
		"steles": [
			{"node": "SteleLedger", "title": "地窖纪事 · 末页",
					"text": "末页是伊尔封进火种前写的：把火还给炉，让名字走。"},
			{"node": "SteleChoir", "title": "地窖纪事 · 唱诗",
					"text": "唱诗班的名字还困在火里。火一还，她们就能走了。"},
			{"node": "SteleYir", "title": "地窖纪事 · 伊尔",
					"text": "伊尔把自己封进火种前，捡回了你，把火种嵌进你的剑。"},
		],
		"boss_intro": "无 声 唱 诗 班",
		"recap": "末页写着：把火还给炉，让名字走。",
	},
	"level05": {
		"number": "柒",
		"name": "齿轮工坊",
		"act": &"debt",
		"objective": "接上锈核，从运渣道出去",
		"wake": "剑上要嵌锈核，那是死人的手艺。",
		"exit_label": "运渣道",
		"exit_captions": ["运渣道通向雨里的墓园。", "墓园里埋着两个还叫得出名字的人。"],
		"steles": [
			{"node": "SteleQuench", "title": "工坊遗训 · 切",
					"text": "剑上的槽是工坊切的。剑在这里接上第一枚锈核。"},
			{"node": "SteleNook", "title": "工坊遗训 · 吊",
					"text": "吊索断了能接。人不是吊索，断了就接不回。"},
			{"node": "SteleChain", "title": "工坊遗训 · 链",
					"text": "每一节吊链上都刻过名字。名字离开了人，留在铁上。"},
		],
		"boss_intro": "",
		"recap": "剑接上第一枚锈核，你回到地面。",
	},
	"level06": {
		"number": "捌",
		"name": "墓园夜雨",
		"act": &"cast",
		"objective": "查清哈伦的剑为何成了门闩",
		"wake": "两个锻工：哈伦坟里没剑，薇尔的剑走了。",
		"exit_label": "钟楼门",
		"exit_captions": ["钟楼的门闩，就是哈伦的剑。", "真钟还在响，上去看看。"],
		"steles": [
			{"node": "SteleHallen", "title": "墓志 · 哈伦",
					"text": "锻工哈伦，下葬时没有剑。守炉人拆了他的剑，做了钟楼的门闩。"},
			{"node": "SteleVeil", "title": "墓志 · 薇尔",
					"text": "锻工薇尔，剑自己走了，她留下守墓。三把剑都去了炉心。"},
			{"node": "SteleTree", "title": "墓志 · 战马",
					"text": "炉心里有匹不肯进炉的战马。守炉人舍不得杀它，它就守在门口。"},
		],
		"boss_intro": "",
		"recap": "守炉人拆了哈伦的剑做钟楼门闩。你往钟楼去。",
	},
	"level07": {
		"number": "玖",
		"name": "钟楼",
		"act": &"cast",
		"objective": "上钟楼，找熔钟舌的地方",
		"wake": "钟还在响，钟舌却不见了。",
		"exit_label": "渣井门",
		"exit_captions": ["井道通到铸钟厅。", "钟舌就是在那里熔掉的。"],
		"steles": [
			{"node": "SteleChain", "title": "守钟人 · 链",
					"text": "这口钟没有钟舌，却一直在响：是炉心的回声在顶它。"},
			{"node": "SteleBell", "title": "守钟人 · 舌",
					"text": "钟舌被熔成了火种，里面封着伊尔。你背上的声音就是她。"},
			{"node": "SteleNook", "title": "守钟人 · 马",
					"text": "夜里常有马蹄声往炉心去。那是不肯进炉的战马。"},
		],
		"boss_intro": "",
		"recap": "守炉人熔了钟舌铸成火种。你背上的声音是伊尔。",
	},
	"level07b": {
		"number": "拾",
		"name": "铸钟厅",
		"act": &"cast",
		"objective": "进铸钟厅，查火种怎么开门",
		"wake": "这座厅的主人是铸钟人，钟是他浇的。",
		"exit_label": "井道门",
		"exit_captions": ["井道通到渣底。", "渣的另一头是城墙。"],
		"steles": [
			{"node": "SteleMold", "title": "铸钟纪事 · 模",
					"text": "钟模里浇过名字。活人站上模台，钟才有声音。"},
			{"node": "SteleFounder", "title": "铸钟纪事 · 工",
					"text": "铸钟人把自己浇进了钟。他说：总得有人替钟说话。"},
			{"node": "SteleKey", "title": "铸钟纪事 · 钥",
					"text": "炉心门认火种，不认人。火种就是钥匙，所以要由你带去。"},
		],
		"boss_intro": "铸 钟 人",
		"recap": "铸钟人倒下。火种就是钥匙，门认火种不认人。",
	},
	"level08": {
		"number": "拾壹",
		"name": "熔渣深渊",
		"act": &"cast",
		"objective": "从渣渊爬去城墙",
		"wake": "你在这里被浇铸。铁成了，你先锈了。",
		"exit_label": "城墙梯",
		"exit_captions": ["梯子往上通向城墙。", "城墙挡的是炉风，不是人。"],
		"steles": [
			{"node": "SteleSlag", "title": "熔渣纪事 · 渣",
					"text": "你在这里被浇铸，没能成形。铁成了，你先锈了。"},
			{"node": "SteleQuench", "title": "熔渣纪事 · 拼",
					"text": "伊尔把自己封进火种之前，从渣面捡起你，把火种嵌进你的剑。"},
			{"node": "SteleVent", "title": "熔渣纪事 · 气",
					"text": "渣下的风是炉心漏出来的。炉约末条：还火的人，自己也要进炉。"},
		],
		"boss_intro": "",
		"recap": "你走过自己锈掉的地方，往城墙去。",
	},
	"level09": {
		"number": "拾贰",
		"name": "锈城城墙",
		"act": &"forge",
		"objective": "翻过城墙，走向风口",
		"wake": "墙上的灰是灰卫，人死了还站着守墙。",
		"exit_label": "城墙外",
		"exit_captions": ["翻过城墙，风小了些。前面是风口。", "钥匙在你背上。风口后面通向炉心门。"],
		"steles": [
			{"node": "SteleWall", "title": "城墙铭 · 挡",
					"text": "城墙不挡人，挡炉风。墙下的灰，曾是守墙的人。"},
			{"node": "SteleWind", "title": "城墙铭 · 风",
					"text": "风里有铁锈和烧焦的油味。墙下的灰，从前会走路。"},
			{"node": "SteleEyrie", "title": "城墙铭 · 鹰",
					"text": "哨位空着。风替守墙人看路，把他们的眼睛磨成了灰。"},
		],
		"boss_intro": "",
		"recap": "你翻过城墙，朝风口走去。",
	},
	"level09b": {
		"number": "拾叁",
		"name": "炉风崖道",
		"act": &"forge",
		"objective": "穿过风口，到炉心门前",
		"wake": "风口后面就是炉心。最后一个灰卫拦着路。",
		"exit_label": "炉心门",
		"exit_captions": ["灰卫让开了。他说：替我看看那团火。", "炉心门就在下面，那匹战马在等你。"],
		"steles": [
			{"node": "SteleAsh", "title": "崖道纪事 · 灰",
					"text": "灰卫守的是门，不是城。他们早就想让人去问一句。"},
			{"node": "SteleHerald", "title": "崖道纪事 · 先驱",
					"text": "最后一个灰卫披着灰。他说：你过去，替我看看这火该不该还。"},
			{"node": "SteleGate", "title": "崖道纪事 · 门",
					"text": "门下面没有守卫，只有风。"},
		],
		"boss_intro": "最 后 一 个 灰 卫",
		"recap": "灰卫让开了路。炉心门在崖道尽头。",
	},
	"level10": {
		"number": "拾肆",
		"name": "炉心深处",
		"act": &"forge",
		"objective": "打败梦魇，在炉心门前做选择",
		"wake": "梦魇是不肯进炉的战马。它守着最后的选择。",
		"exit_label": "炉心门",
		"exit_captions": [],
		"steles": [
			{"node": "SteleNightmare", "title": "炉心铭 · 梦魇",
					"text": "梦魇就是那匹不肯进炉的战马。它守着门，不让没想清楚的人进去。"},
			{"node": "SteleCompact", "title": "炉心铭 · 炉约",
					"text": "炉约最后一条：把火还给炉，把锈还给铁，让城睡下。"},
			{"node": "SteleVigil", "title": "炉心铭 · 守",
					"text": "还火：剑进炉，名字归火，你散成铁。守炉：留剑，名字仍困着，你永守炉边。"},
		],
		"boss_intro": "梦 魇",
		"recap": "梦魇倒下，炉心门开了。你要在门前做选择。",
	},
}

## 术语表（6 条）：第一次出现的专名必须在这里有白话解释；docs/story.md 同步。
## 「锈墓」是地名，不算术语；人物见 CAST。
const TERMS := {
	"炉约": "二百年前全城立的誓：死人的名字刻上剑、投进炉里烧，换灯不灭。",
	"炉心": "城下那座烧铁的大炉膛。一百年前熄了，只剩热和灰。",
	"火种": "炉心熄灭时封住最后一口火的小核。伊尔的魂封在里面，它也是炉心门的钥匙。",
	"守炉人": "立下炉约、负责烧名字的那批人。伊尔是最后一个。",
	"锈核": "从死人剑上取下的手艺。嵌进你的剑，就能借他用一次。",
	"余烬巢": "还剩一口余火的巢。点亮它，你死了能在这里醒来。",
}

## 人物（8 条，一人一句）：盲测复述人物关系用；docs/story.md §3 同步。
const CAST := {
	"余烬骑士": "你。守炉人造的人偶，本该替死者扛剑进炉；没用上就锈了。",
	"伊尔": "最后一个守炉人。她把自己封进火种，托你带她去炉心。",
	"刽子手": "守着炉座的人。他发过誓：谁碰炉座，谁先被斩。",
	"守炉人": "立誓烧名字换灯的那批人。他们熔了钟舌铸成火种。",
	"灰卫": "守城墙和炉心门的卫兵。死后化成灰，仍站在原地守着。",
	"哈伦": "锻工。他的剑被拆去做钟楼门闩，所以他空手入土。",
	"薇尔": "锻工。她的剑自己走了，她留在墓园守着。",
	"梦魇": "那匹不肯进炉的战马。它守着炉心门，不让没想清楚的人进去。",
}

## 人物第一次该出现在故事页的章节。空串 = 序章 / 开场就在，没有任何进度也显示。
## 依据 docs/story.md：刽子手在第一章开场，哈伦与薇尔在墓园（level06），
## 灰卫在城墙（level09），梦魇这个名字要到炉心（level10）才说破。
const CAST_FIRST_CHAPTER := {
	"余烬骑士": "",
	"伊尔": "",
	"刽子手": "level01",
	"守炉人": "",
	"灰卫": "level09",
	"哈伦": "level06",
	"薇尔": "level06",
	"梦魇": "level10",
}

## 名词第一次该出现在故事页的章节。炉约 / 炉心 / 火种 / 守炉人在序章就解释过。
## 余烬巢在第一章的巢旁；锈核要到齿轮工坊（level05）才写进章节文本，开场名词页不列。
const TERM_FIRST_CHAPTER := {
	"炉约": "",
	"炉心": "",
	"火种": "",
	"守炉人": "",
	"锈核": "level05",
	"余烬巢": "level01",
}

## 三枚锈核第一次嵌进剑里时各说一句（之后不再重复）。docs/story.md §8 同步。
const CORE_VOICE := {
	&"heat_forge": "窑匠：把火留在刃上。门会自己让开。",
	&"hookshot_tether": "系索匠：你很重。让世界过来。",
	&"ember_step": "余烬核：灰还能再跳一次。别问它从谁身上来。",
}
## 第一次捡到锈核时把「锈核」就地解释（第一次捡核就要懂）。StoryStage 会接「按 X 或 Y 嵌进剑里。」。
const FIRST_CORE_LINE := "这是锈核——死人留下的手艺，能借来用一次。"

## 关内开场（新游戏只播一次，可跳过）。世界观由开场前的序章分镜讲完（storyboards.gd），
## 这里只负责「醒来、认出声音、知道去哪、看见要打谁」。每句 ≤22 字（含说话人前缀）。
const OPENING := {
	"situation": "伊尔：醒醒，余烬骑士。火种快灭了。",
	"sword": "伊尔：我就封在你背上这把剑里。",
	"echo": "伊尔：你听见的，是我封进火种之前说的话。",
	"anomaly": "钟声又响了。底下有人在数名字。",
	"goal": "伊尔：把火种送回炉心，城底的大炉。",
	"route": "伊尔：炉座是石台。先去续一口火。",
	"obstacle": "刽子手守着炉座，谁碰谁死。",
}

## 标题画面底部墓志的轮换句（第一句是 TitleScreen.EPITAPH，这里是后面几句）。每句 ≤18 字，
## 都是一句陈述，不是台词。
const TITLE_LINES: Array[String] = [
	"灯亮了二百年，烧的是死人的名字。",
	"有人把自己封进了一把剑里。",
	"这火，该还回去了。",
]

## 两个正篇结局 + 第一章提前熄火。三个结局都说清：名字的下场、你的下场、城的下场。
const ENDINGS := {
	"give": {
		"summary": "还火：门开了，你把剑推进炉心。被困的名字都走了，伊尔走在最后。火种连着你的命，你也散成铁屑，城终于睡下。",
		"lines": ["门开了。你把剑推进炉心，火种烧成一团白光。",
				"被困了二百年的名字，一个接一个走了出来。",
				"伊尔走在最后，回头对你笑了一下。",
				"伊尔：谢谢你，送我到这儿。",
				"火种连着你的命。你散成铁屑，落进炉里。城终于睡下。 —— 锈墓・完 ——"],
	},
	"keep": {
		"summary": "守炉：门开了，你没有松手，留下做新的守炉人。火没熄，名字没走，城一直半醒，伊尔的声音还留在剑里。",
		"lines": ["门开了。你没有松手，把剑立在炉边，自己留下守着。",
				"火没有熄，名字也没有走。城一直半醒。",
				"伊尔：你不该留下的……可是，谢谢你没走。",
				"没有人来换你。你成了新的守炉人，一年一年守下去。",
				"炉火还亮着，和从前一样。 —— 锈墓・完 ——"],
	},
	"snuff": {
		"summary": "熄火：你在炉座前熄灭了火种。名字没有路走，你散成铁，城还睡着，炉门里只剩一点红。",
		"lines": ["你在炉座前熄灭了火种。光一点点退了。",
				"伊尔的声音停了。她没来得及说完。",
				"被困的名字没有路可走，也没有人再替它们问一句。",
				"你散成了铁。城还睡着，炉门里只剩一点红。 —— 锈墓・完 ——"],
	},
}

## 第一章事件字幕（Level01StoryBeats 取用）。
const EVENTS := {
	"boss_gate": "刽子手守着炉座。碰炉座的人，他一个也不放过。",
	"boss_slain": "炉座空了，没人再拦你。火种在等你放上去。",
	"toxin": "腐液是淬剑用的冷却液。吸进去伤肺，也会把记忆淬进铁里。",
	"parry": "挡住了，还把他们的火打了回去。",
}


static func has(id: String) -> bool:
	return CHAPTERS.has(id)


## 战役顺序，与 GameContext.LEVEL_ORDER 一致（测试逐项比对）。
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
	var entry := CHAPTERS.get(id, {}) as Dictionary
	var act_id := entry.get("act", &"") as StringName
	for act in ACTS:
		if StringName(act["id"]) == act_id:
			return (act as Dictionary).duplicate(true)
	return {}


static func number_of(id: String) -> String:
	return String(CHAPTERS.get(id, {}).get("number", ""))


static func name_of(id: String) -> String:
	return String(CHAPTERS.get(id, {}).get("name", ""))


## "锈墓・<number> — <name>"。ChapterLevel.chapter_card() 依赖这个分隔符。
static func title_of(id: String) -> String:
	if not CHAPTERS.has(id):
		return ""
	return "锈墓・%s — %s" % [number_of(id), name_of(id)]


## "锈墓・<number>"（章节卡的副标题）。
static func subtitle_of(id: String) -> String:
	if not CHAPTERS.has(id):
		return ""
	return "锈墓・%s" % number_of(id)


static func wake_of(id: String) -> String:
	return String(CHAPTERS.get(id, {}).get("wake", ""))


static func objective_of(id: String) -> String:
	return String(CHAPTERS.get(id, {}).get("objective", ""))


static func exit_label_of(id: String) -> String:
	return String(CHAPTERS.get(id, {}).get("exit_label", ""))


static func exit_captions_of(id: String) -> PackedStringArray:
	return PackedStringArray(CHAPTERS.get(id, {}).get("exit_captions", []))


static func steles_of(id: String) -> Array:
	return (CHAPTERS.get(id, {}).get("steles", []) as Array).duplicate(true)


## 按节点名取碑文（layout 的 stele() 位置常量留在 layout 里，文本从注册表取）。
static func stele_of(id: String, node_name: String) -> Dictionary:
	for entry in steles_of(id):
		if String(entry.get("node", "")) == node_name:
			return entry
	return {}


static func recap_of(id: String) -> String:
	return String(CHAPTERS.get(id, {}).get("recap", ""))


static func boss_intro_of(id: String) -> String:
	return String(CHAPTERS.get(id, {}).get("boss_intro", ""))


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


static func cast_first_chapter(who: String) -> String:
	return String(CAST_FIRST_CHAPTER.get(who, ""))


static func term_first_chapter(term: String) -> String:
	return String(TERM_FIRST_CHAPTER.get(term, ""))


## 当前章节与已通关旗标里，走到的最远下标（都没有 = -1）。
## flags 要有 has()（Array / PackedStringArray）。
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


## first_chapter 为空 = 一开始就出场。progress < 0 时只放行这类条目。
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


## 关内开场字幕，按顺序。
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


## 把「说话人：内容」拆开。返回 [说话人, 内容]；没有（或不认识）说话人时第一项为空串。
## 只认 SPEAKERS 里的名字，「炉约二百年：…」「还火：…」这类不会被误拆。
static func split_speaker(text: String) -> PackedStringArray:
	var cut := text.find("：")
	if cut > 0 and cut <= 4:
		var who := text.substr(0, cut)
		if SPEAKERS.has(who):
			return PackedStringArray([who, text.substr(cut + 1)])
	return PackedStringArray(["", text])


## 已通关章节的 recap（暂停菜单「前情提要」用最近两条）。done_flags 由
## StoryFlow 给（旗标口径跟着存档走），这里只负责挑文本。
static func recap_lines_for(cleared_ids: Array) -> Array[String]:
	var out: Array[String] = []
	for raw in cleared_ids:
		var line := recap_of(String(raw))
		if line != "" and not out.has(line):
			out.append(line)
	return out


## 给 docs 同步测试用：把所有会被玩家读到的长文本收在一起。
static func all_prose() -> Array[String]:
	var out: Array[String] = []
	for id in order():
		out.append(wake_of(id))
		out.append(objective_of(id))
		out.append(recap_of(id))
		for caption in exit_captions_of(id):
			out.append(String(caption))
		for stele in steles_of(id):
			out.append(String(stele.get("title", "")))
			out.append(String(stele.get("text", "")))
	for term in TERMS:
		out.append(String(TERMS[term]))
	for who in CAST:
		out.append(String(CAST[who]))
	for line in opening_lines():
		out.append(line)
	for line in TITLE_LINES:
		out.append(line)
	for kind in ENDINGS:
		for line in ending_lines_of(String(kind)):
			out.append(String(line))
	return out
