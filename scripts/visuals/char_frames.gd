class_name CharFrames
## assets/characters/ 切帧序列的加载器（进程内缓存）。
## 目录约定：assets/characters/<角色>/<动作>/<动作>_<i>.png，i 从 0 连续递增。
## headless 下 ResourceLoader 照常工作；缺目录/缺帧返回空数组，调用方自行回退。

const BASE := "res://assets/characters/"

static var _cache: Dictionary = {}
const MAX_CACHE_BYTES := 96 * 1024 * 1024
static var _cache_bytes := 0
static var _cache_cost: Dictionary = {}


static func anim(char_name: String, action: String) -> Array[Texture2D]:
	var key := char_name + "/" + action
	if _cache.has(key):
		var hit: Array[Texture2D] = _cache[key]
		_cache.erase(key)
		_cache[key] = hit
		return hit
	var frames: Array[Texture2D] = []
	var i := 0
	while true:
		var path := "%s%s/%s_%d.png" % [BASE, key, action, i]
		if not ResourceLoader.exists(path):
			break
		var tex := ArtTexture.load_texture(path)
		if tex == null:
			break
		frames.append(tex)
		i += 1
	var cost := 0
	for texture in frames:
		cost += int(texture.get_meta("physical_bytes", texture.get_width() * texture.get_height() * 4))
	while not _cache.is_empty() and _cache_bytes + cost > MAX_CACHE_BYTES:
		var oldest: String = _cache.keys()[0]
		_cache_bytes -= int(_cache_cost[oldest])
		_cache_cost.erase(oldest)
		_cache.erase(oldest)
	if cost <= MAX_CACHE_BYTES:
		_cache[key] = frames
		_cache_cost[key] = cost
		_cache_bytes += cost
	return frames


static func available(char_name: String, action: String = "idle") -> bool:
	return not anim(char_name, action).is_empty()
