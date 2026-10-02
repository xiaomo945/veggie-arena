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

# ---- 程序化补妆：把大图在运行时缩好 + 生成 mipmap，专治"nearest 过滤下把
# 512 大图缩到 20px 采样成小黄点"的问题。缩图 + mipmap 一次性做完后缓存。 ----
var _coin_tex: Texture2D = null

# 统一的卡通金币（萝卜印金饼）。项目里其实有一张 512px 的漂亮金币
# （sprite_pickup_gold），但世界拾取物只画 13~21px，nearest 直接采样成"黄点"。
# 这里把原图缩到 64px 并生成 mipmap，所有要画金币的地方（地面拾取物 / HUD /
# 商店 / 结算页）都走这一个入口，保证全游戏金币长得一样、且小尺寸依然清晰。
func coin_icon() -> Texture2D:
	if _coin_tex != null:
		return _coin_tex
	var src := sprite("pickup_gold")
	if src != null:
		var img := src.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			img.resize(64, 64, Image.INTERPOLATE_LANCZOS)
			img.generate_mipmaps()
			_coin_tex = ImageTexture.create_from_image(img)
	if _coin_tex == null:
		_coin_tex = ui_icon("coin")   # 旧 48px 图兜底，再没有就返回 null
	return _coin_tex

# 卡通加压按钮：圆角 + 深描边 + 底部投影 + 按压态。结算页等弹层共用一套按钮语言。
static func style_button(b: Button, bg: Color, fg: Color, border: Color) -> void:
	var n := StyleBoxFlat.new()
	n.bg_color = bg
	n.set_corner_radius_all(18)
	n.border_color = border
	n.set_border_width_all(3)
	n.shadow_color = Color(0, 0, 0, 0.4)
	n.shadow_size = 5
	n.shadow_offset = Vector2(0, 3)
	b.add_theme_stylebox_override("normal", n)
	var hov := n.duplicate() as StyleBoxFlat
	hov.bg_color = bg.lightened(0.10)
	b.add_theme_stylebox_override("hover", hov)
	var pre := n.duplicate() as StyleBoxFlat
	pre.bg_color = bg.darkened(0.18)
	pre.shadow_size = 0
	b.add_theme_stylebox_override("pressed", pre)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_hover_color", fg)

# 换皮 / 热重载贴图时用：清掉缓存，下一次访问重新读磁盘
func clear_cache() -> void:
	_cache.clear()
	_coin_tex = null

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
