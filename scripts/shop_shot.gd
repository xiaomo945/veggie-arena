extends SceneTree

# 商店目检：真渲染抓"补给站"两张图 —— 中期普通店 / 后期大商店。
# 目的只有一个：肉眼确认【货架刷满 6 张、3 列 × 2 行一个空位都没有】。
# 这个 bug（第 3 波起只出 4 张 + 2 个空白卡位）是玩家肉眼发现的，headless 单测
# 只能验"offer_count == 6"，验不了"卡真的画在格子里"，所以必须出图看。
#
#   xvfb-run -a -s "-screen 0 540x900x24" /opt/godot/Godot_v4.3-stable_linux.x86_64 \
#       --path /workspace/veggie-arena --script res://scripts/shop_shot.gd
#
# 与 ui_shot.gd 同样的坑：--script 模式不注册 autoload（autoload 名是编译期标识符，
# 直接写 Events 会 "Identifier not found"），必须手动 new 出来挂到 root 再按节点取。

const AUTOLOADS := {
	"Art": "res://autoload/Art.gd",
	"Data": "res://autoload/Data.gd",
	"Events": "res://autoload/Events.gd",
	"GameState": "res://autoload/GameState.gd",
	"Settings": "res://autoload/Settings.gd",
	"Steam": "res://autoload/Steam.gd",
	"SaveMgr": "res://autoload/SaveMgr.gd",
	"Sfx": "res://autoload/Sfx.gd",
	"Bgm": "res://autoload/Bgm.gd",
	"Gamepad": "res://autoload/Gamepad.gd",
	"I18n": "res://autoload/I18n.gd",
	"HudLayout": "res://ui/HUD/HudLayout.gd",
	"ScreenMode": "res://ui/Screens/ScreenMode.gd",
	"Perf": "res://autoload/Perf.gd",
}

const OUT := "/tmp"

var _events: Node
var _gs: Node
var _shop: Node


func _initialize() -> void:
	for k in AUTOLOADS:
		var n: Node = load(AUTOLOADS[k]).new()
		n.name = k
		root.add_child(n)
	_events = root.get_node("Events")
	_gs = root.get_node("GameState")

	_shop = load("res://ui/Shop/Shop.tscn").instantiate()
	root.add_child(_shop)
	for _f in 6:
		await process_frame

	# ---- 1) 第 3 波普通店（玩家反馈出现空白卡位的就是这一段）----
	_setup_run(3, 260, [{"key": "pistol", "lv": 3}, {"key": "smg", "lv": 2}])
	_events.shop_opened.emit()
	for _f in 8:
		await process_frame
	_report("第 3 波")
	_save("shop_w3")

	# ---- 2) 第 15 波大商店（全场打折 + 高级武器，最容易出高阶卡）----
	_setup_run(15, 5200, [
		{"key": "pistol", "lv": 8}, {"key": "smg", "lv": 7}, {"key": "bow", "lv": 6},
	])
	_events.shop_opened.emit()
	for _f in 8:
		await process_frame
	_report("第 15 波")
	_save("shop_w15")

	# ---- 3) 直接构造一张"已购买"的卡目检（不受随机货源影响）----
	var canvas := CanvasLayer.new()
	canvas.layer = 40   # 盖过商店（layer 30），目检卡才不会被货架挡住
	root.add_child(canvas)
	var card = load("res://ui/Shop/ShopCard.gd").new()
	card.set_size(Vector2(480, 130))
	card.set_position(Vector2(30, 330))
	canvas.add_child(card)
	card.setup({"kind": "upgrade", "name": "番茄急救", "tip": "立刻回一口血", "cost": 12,
		"affordable": true, "sold": true, "disabled": false, "icon": null,
		"base_cost": 12, "inflated": false, "infl_pct": 0,
		"accent": Color(0.35, 0.66, 1.0), "rarity": 2, "tag": "UPG"})
	for _f in 8:
		await process_frame
	_save("shop_bought")
	print("[已购] 目检卡已出图")

	print("SHOP SHOT done -> " + OUT)
	quit(0)


func _setup_run(wave: int, gold: int, weapons: Array) -> void:
	_gs.wave = wave
	_gs.gold = gold
	_gs.weapons = weapons.duplicate(true)
	_gs.upgrades = {}
	_gs.running = false


# 把"货架上真画了几张卡、每张卡叫什么"抖出来 —— 截图看不清的地方靠这个兜底。
func _report(tag: String) -> void:
	var shown := 0
	var names := []
	for c in _shop.find_children("*", "Control", true, false):
		if c.get_script() != load("res://ui/Shop/ShopCard.gd"):
			continue
		if not c.visible:
			continue
		shown += 1
		var t := ""
		for cc in c.get_children():
			if cc is Label and t == "" and cc.text != "":
				t = cc.text
		if t != "":
			names.append(t)
	print("[%s] 可见卡片 %d 张：%s" % [tag, shown, ", ".join(names)])


func _save(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
	print("shot " + name)
