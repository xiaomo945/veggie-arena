extends RefCounted

# 美术资源齐全性守卫。
#
# 起因（真实事故）：data/weapons.json 有 32 把武器，但 art/ 下只有 12 张图标 ——
# 商店卡直接画空底座、武器栏格子缺形状，玩家看到的是"坏了"，
# 而所有逻辑测试全绿（缺图不报错，Art.icon 返回 null 就静默降级）。
#
# 这类 bug 只能靠"数据表 ↔ 资源文件"对照来抓，所以需要这个守卫：
# 数据表里每出现一个新 key，这里就会失败，逼 landing 前补图。
#
# 顺带守住升级道具：道具目前用宝石兜底（有意为之），但 Map key 变了同样要被发现。

const Art := preload("res://autoload/Art.gd")
const ItemIcons := preload("res://core/ItemIcons.gd")

var _p := 0
var _f := 0
var _failures: Array = []
var _weapon_keys: Array = []

func run(weapons: Dictionary = {}) -> Dictionary:
	_p = 0; _f = 0; _failures = []
	_weapon_keys = weapons.keys()
	_check_weapons()
	_check_sizes()
	_check_items()
	return {"pass": _p, "fail": _f, "failures": _failures}

# 每把武器都必须有一张 art/icon_weapon_<key>.png
func _check_weapons() -> void:
	chk(_weapon_keys.size() > 0, "武器表非空（拿到 %d 把）" % _weapon_keys.size())
	var miss: Array = []
	for k in _weapon_keys:
		var p := "res://art/icon_weapon_%s.png" % Art.normalize(str(k))
		if not ResourceLoader.exists(p):
			miss.append(str(k))
	chk(miss.is_empty(), "武器表 %d 把全部有图标（缺：%s）"
		% [_weapon_keys.size(), ", ".join(miss) if miss.size() > 0 else "无"])

# 图标是 256×256 的：画进 60px 底座才有足够采样，太大会拖慢加载。
# ⚠️ 走 ResourceLoader 而不是 Image.load —— 后者在导出包里读不了 png，
#    用它会造出"本地测试全绿、打包后加载失败"的假通过。
func _check_sizes() -> void:
	var checked := 0
	var bad: Array = []
	for k in _weapon_keys:
		var p := "res://art/icon_weapon_%s.png" % Art.normalize(k)
		var tex := ResourceLoader.load(p, "Texture2D") as Texture2D
		if tex == null:
			bad.append(k + "(加载不了/未导入)")
			continue
		var s := tex.get_size()
		checked += 1
		if int(s.x) < 128 or int(s.y) < 128:
			bad.append("%s(%dx%d)" % [k, int(s.x), int(s.y)])
	chk(checked >= 32, "武器图标全部能被 Godot 加载（实测 %d 张，武器表 %d 把）"
		% [checked, _weapon_keys.size()])
	chk(bad.is_empty(), "所有武器图标 ≥128px（异常：%s）" % (", ".join(bad) if bad.size() > 0 else "无"))

# 道具侧：upgrades.json 每条都必须能映射到一张存在的图标。
# 映射在 core/ItemIcons.gd（18 类覆盖 136 条，wok 类复用 icon_wok.png）；
# 谁往 upgrades.json 加新 stat 而忘了配图标，这里直接红 —— 不许静默退回宝石。
func _check_items() -> void:
	var src := FileAccess.get_file_as_string("res://data/upgrades.json")
	var ups: Dictionary = JSON.parse_string(src) if src != "" else {}
	chk(ups.size() > 100, "道具表非空（拿到 %d 条）" % ups.size())
	var no_map: Array = []
	var miss_file: Array = []
	for k in ups:
		var ik := ItemIcons.key_for_def(ups[k] as Dictionary)
		if ik == "":
			no_map.append(str(k))
		elif not ResourceLoader.exists("res://art/icon_%s.png" % ik):
			miss_file.append("%s(%s)" % [k, ik])
	chk(no_map.is_empty(), "每条道具都有图标映射（未映射：%s）"
		% (", ".join(no_map) if no_map.size() > 0 else "无"))
	chk(miss_file.is_empty(), "道具图标文件齐全（缺：%s）"
		% (", ".join(miss_file) if miss_file.size() > 0 else "无"))
	chk(ItemIcons.POOLS.size() <= 20,
		"图标分类数 %d ≤ 20（分类是手造资产，膨胀失控就该警惕）" % ItemIcons.POOLS.size())
	var tex := ResourceLoader.load("res://art/icon_item_hp.png", "Texture2D") as Texture2D
	chk(tex != null and int(tex.get_size().x) >= 128, "道具图标能被 Godot 加载且 ≥128px")

func chk(cond: bool, msg: String) -> void:
	if cond:
		_p += 1
	else:
		_f += 1
		_failures.append(msg)
	print(("  ✓ " if cond else "  ✗ ") + msg)
