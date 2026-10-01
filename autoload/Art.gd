extends Node

# 美术资源访问层（autoload）
#
# 职责只有一件：把"名字"翻译成 res://art/ 下的贴图，并把结果缓存起来。
# 缺图时返回 null（不是报错），调用方自己退回手绘外观 ——
# 这样美术永远卡不住开发，反过来也不会因为漏图崩游戏。
#
# 命名 / 目录 / 导入设置见 docs/10_资源接入规范.md

const ART_DIR := "res://art/"
const SPRITE_PREFIX := "sprite_"
const ICON_PREFIX := "icon_"
const EXT := ".png"

# key: 完整路径，value: Texture2D 或 null
# 缓存 null 是有意的：缺图只查一次，之后走字典，不会每帧碰文件系统
var _cache: Dictionary = {}

# ---- 名字归一化：大小写、空格、连字符都不影响命中 ----
static func normalize(name: String) -> String:
	var s := name.strip_edges().to_lower()
	s = s.replace(" ", "_")
	s = s.replace("-", "_")
	while s.find("__") >= 0:
		s = s.replace("__", "_")
	return s

static func sprite_path(name: String) -> String:
	return ART_DIR + SPRITE_PREFIX + normalize(name) + EXT

static func icon_path(name: String) -> String:
	return ART_DIR + ICON_PREFIX + normalize(name) + EXT

func sprite(name: String) -> Texture2D:
	return _cached_load(sprite_path(name))

func icon(name: String) -> Texture2D:
	return _cached_load(icon_path(name))

# 只查不加载（没那张图时避免一次无用的 load）
func has_sprite(name: String) -> bool:
	return FileAccess.file_exists(sprite_path(name))

func has_icon(name: String) -> bool:
	return FileAccess.file_exists(icon_path(name))

# ---- UI 图标：放在 art/ui/ 子目录，与角色/敌人立绘（art/sprite_*）区分开 ----
const UI_DIR := "res://art/ui/"

static func ui_icon_path(name: String) -> String:
	return UI_DIR + ICON_PREFIX + normalize(name) + EXT

func ui_icon(name: String) -> Texture2D:
	return _cached_load(ui_icon_path(name))

func has_ui_icon(name: String) -> bool:
	return FileAccess.file_exists(ui_icon_path(name))

# 换皮 / 热重载贴图时用：清掉缓存，下一次访问重新读磁盘
func clear_cache() -> void:
	_cache.clear()

func cached_count() -> int:
	return _cache.size()

func _cached_load(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path] as Texture2D
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		var res := ResourceLoader.load(path, "Texture2D")
		tex = res as Texture2D
		if tex == null:
			push_warning("Art: 不是贴图或加载失败 " + path)
	_cache[path] = tex
	return tex
