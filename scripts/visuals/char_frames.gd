class_name CharFrames
## assets/characters/ 切帧序列的加载器（进程内缓存）。
## 目录约定：assets/characters/<角色>/<动作>/<动作>_<i>.png，i 从 0 连续递增。
## headless 下 ResourceLoader 照常工作；缺目录/缺帧返回空数组，调用方自行回退。

const BASE := "res://assets/characters/"

static var _cache: Dictionary = {}


static func anim(char_name: String, action: String) -> Array[Texture2D]:
	var key := char_name + "/" + action
	if _cache.has(key):
		return _cache[key]
	var frames: Array[Texture2D] = []
	var i := 0
	while true:
		var path := "%s%s/%s_%d.png" % [BASE, key, action, i]
		if not ResourceLoader.exists(path):
			break
		var tex := DensityTextures.load_texture(path)
		if tex == null:
			break
		frames.append(tex)
		i += 1
	_cache[key] = frames
	return frames


static func available(char_name: String, action: String = "idle") -> bool:
	return not anim(char_name, action).is_empty()
