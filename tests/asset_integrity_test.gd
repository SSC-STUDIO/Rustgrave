extends TestCase
## 资产完整性：SFX 库的每个音频文件存在；CharFrames 用到的每个角色动作
## 目录存在且至少切出 1 帧 png。素材丢失/改名/误删会在这里最先变红。

## 代码里实际引用的 角色 → 动作 清单
## （player.gd / spitter / scrapper / gear_shield / projectile / fx.gd）。
const CHAR_ACTIONS := {
	"player_ember_knight": ["idle", "run", "jump", "fall", "dash", "hurt",
		"death", "turn", "attack1", "attack2", "attack_combo"],
	"spitter_hell_beast": ["idle", "attack", "death", "projectile"],
	"scrapper_hell_hound": ["idle", "walk", "run", "jump"],
	"gear_shield_executioner": ["idle", "idle2", "summon", "death", "attack", "skill"],
	"fx_enemy_death": ["death"],
}


func test_every_sfx_library_entry_resolves_to_a_file() -> void:
	ok(not Sfx.LIBRARY.is_empty(), "sfx library should not be empty")
	for key in Sfx.LIBRARY:
		var path: String = Sfx.LIBRARY[key]
		ok(ResourceLoader.exists(path), "missing sfx %s -> %s" % [key, path])
	ok(not Sfx.AMBIENCE.is_empty(), "weather ambience library should not be empty")
	for key in Sfx.AMBIENCE:
		var path: String = Sfx.AMBIENCE[key]
		ok(ResourceLoader.exists(path), "missing ambience %s -> %s" % [key, path])


func test_every_char_frames_action_has_at_least_one_frame() -> void:
	for char_name in CHAR_ACTIONS:
		for action in CHAR_ACTIONS[char_name]:
			var frames := CharFrames.anim(char_name, action)
			ok(frames.size() >= 1, "no frames for %s/%s" % [char_name, action])
