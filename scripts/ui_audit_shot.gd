extends SceneTree

# 全界面 UI 遮挡排查（Task #284）：把玩家能看到的每一个界面都真渲染截图，
# 逐张目检"文字被压 / 元素被切 / 已购状态看不出"这类 headless 单测抓不到的问题。
#
# 出图清单（全部存 /tmp）：
#   aud_title / aud_char_detail / aud_weapon_picker / aud_weapon_detail
#   aud_shop / aud_shop_bought（真实购买后的 150px 小卡）/ aud_hud / aud_pause
#   aud_wave_result / aud_death / aud_victory / aud_stats / aud_unlock_tree_fresh
#
#   xvfb-run -a -s "-screen 0 540x900x24" /opt/godot/Godot_v4.3-stable_linux.x86_64 \
#       --path /workspace/veggie-arena --script res://scripts/ui_audit_shot.gd
#
# 与 ui_shot.gd / shop_shot.gd 同样的坑：--script 模式不注册 autoload，
# 必须手动 new 出来挂到 root 下（名字要对，否则各界面里编译期标识符全报错）。

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
var _main: Node


func _initialize() -> void:
	for k in AUTOLOADS:
		var n: Node = load(AUTOLOADS[k]).new()
		n.name = k
		root.add_child(n)
	_events = root.get_node("Events")
	_gs = root.get_node("GameState")

	# ---- 1) 标题页 + 选角（真实 Main 场景，开局就是它）----
	_main = load("res://ui/Screens/Main.tscn").instantiate()
	root.add_child(_main)
	for _f in 20:
		await process_frame
	_save("aud_title")

	# ---- 2) 角色详情页（CharDetail 基类是 CanvasLayer，as Control 会静默失败）----
	var detail: CanvasLayer = null
	for c in root.find_children("*", "CanvasLayer", true, false):
		if c.get_script() == load("res://ui/Screens/CharDetail.gd"):
			detail = c as CanvasLayer
	var first_key := str(root.get_node("SaveMgr").character_order()[0])
	if detail != null:
		detail.call("show_for", first_key)
		for _f in 8:
			await process_frame
		_save("aud_char_detail")
		detail.call("hide_page")
	else:
		print("!! 没找到 CharDetail")

	# ---- 3) 解锁树（新档锁定状态 —— 新玩家第一眼看到的画面）----
	var tree: Control = null
	var tree_layer: CanvasLayer = null
	for layer in root.find_children("*", "CanvasLayer", true, false):
		for c in layer.get_children():
			if c.get_script() == load("res://ui/Screens/UnlockTree.gd"):
				tree = c as Control
				tree_layer = layer as CanvasLayer
	if tree != null:
		var real: Dictionary = root.get_node("SaveMgr").data
		root.get_node("SaveMgr").data = load("res://core/Save.gd").defaults()
		tree.call("show_page")
		tree_layer.visible = true
		for _f in 8:
			await process_frame
		_save("aud_unlock_tree_fresh")
		root.get_node("SaveMgr").data = real
		tree.call("hide_page")
		for _f in 2:
			await process_frame
	else:
		print("!! 没找到 UnlockTree")

	_main.queue_free()
	await process_frame

	# ---- 4) 选武器页 + 武器详情页 ----
	var canvas := CanvasLayer.new()
	canvas.layer = 50
	root.add_child(canvas)
	var picker: Control = load("res://ui/Screens/WeaponPicker.gd").new()
	canvas.add_child(picker)
	picker.call("show_page")
	for _f in 10:
		await process_frame
	_save("aud_weapon_picker")

	var wdetail: Control = picker.get_child(picker.get_child_count() - 1) as Control
	wdetail.call("show_for", "bow")
	for _f in 12:
		await process_frame
	_save("aud_weapon_detail")

	# 4b) 羁绊数值镜头：当前角色（turnip，bond=kitchen）拿厨具 spatula →
	#     SET BONUS 节应显示 2/4/6 件的实际加成（P2-2 修复的验证点）
	wdetail.call("show_for", "spatula")
	for _f in 12:
		await process_frame
	_save("aud_weapon_detail_bond")
	# 4c) 中文 locale 复检：档位行措辞（"N 件："）与全角冒号都在中文下走一遍
	root.get_node("I18n").set_locale("zh")
	for _f in 4:
		await process_frame
	_save("aud_weapon_detail_bond_zh")
	root.get_node("I18n").set_locale("en")

	canvas.queue_free()
	await process_frame

	# ---- 5) 商店（真实 3 列网格 → 150px 小卡）+ 真实购买一张后的小卡 ----
	var shop: Node = load("res://ui/Shop/Shop.tscn").instantiate()
	root.add_child(shop)
	for _f in 6:
		await process_frame
	_setup_run(3, 9000, [{"key": "pistol", "lv": 3}, {"key": "smg", "lv": 2}])
	_events.shop_opened.emit()
	for _f in 10:
		await process_frame
	_save("aud_shop")
	_report_shop("aud_shop")
	# 真实购买第 0 张卡：截 150px 小卡的已售形态（宽卡那版 sold 视觉在 3 列网格下
	# 是死代码，只有这里能验到真机上玩家看到的画面）
	shop.call("_buy", 0)
	for _f in 10:
		await process_frame
	_save("aud_shop_bought")
	_report_shop("aud_shop_bought")

	shop.queue_free()
	await process_frame

	# ---- 6) HUD（开跑状态：血条/波次/金币/武器槽/技能钮全亮）----
	var hud: Node = load("res://ui/HUD/HUD.tscn").instantiate()
	root.add_child(hud)
	hud.add_to_group("hud")
	_setup_run(5, 640, [
		{"key": "pistol", "lv": 4}, {"key": "smg", "lv": 3},
		{"key": "bow", "lv": 2}, {"key": "cleaver", "lv": 1},
	])
	_events.run_started.emit()
	_events.player_hp_changed.emit(68, 100)
	_events.gold_changed.emit(640)
	_events.wave_started.emit(5)
	_events.xp_changed.emit(4, 120, 200, 0.6)
	_events.wok_charges_changed.emit(2)
	_events.shield_changed.emit(3)
	_events.dash_state_changed.emit(0.7, true)
	for _f in 12:
		await process_frame
	_save("aud_hud")

	# ---- 7) 暂停菜单（HUD 之上；必须先实例化 PauseScreen 再发信号）----
	var pause: Node = load("res://ui/Screens/PauseScreen.tscn").instantiate()
	root.add_child(pause)
	for _f in 4:
		await process_frame
	_events.run_paused.emit(true)
	for _f in 8:
		await process_frame
	_save("aud_pause")
	_events.run_paused.emit(false)
	pause.queue_free()
	await process_frame

	# ---- 8) 波次结算页 ----
	var wr: Node = load("res://ui/Screens/WaveResultScreen.gd").new()
	root.add_child(wr)
	for _f in 4:
		await process_frame
	_events.wave_result_ready.emit(5)
	for _f in 8:
		await process_frame
	_save("aud_wave_result")
	wr.queue_free()
	await process_frame

	# ---- 9) 死亡页 ----
	var ds: Node = load("res://ui/Screens/DeathScreen.tscn").instantiate()
	root.add_child(ds)
	for _f in 4:
		await process_frame
	_events.player_died.emit()
	for _f in 10:
		await process_frame
	_save("aud_death")
	ds.queue_free()
	await process_frame

	# ---- 10) 胜利页 ----
	var vs: Node = load("res://ui/Screens/VictoryScreen.tscn").instantiate()
	root.add_child(vs)
	for _f in 4:
		await process_frame
	_events.run_won.emit()
	for _f in 10:
		await process_frame
	_save("aud_victory")
	vs.queue_free()
	await process_frame

	hud.queue_free()
	await process_frame

	# ---- 11) 属性页 ----
	var stats: Node = load("res://ui/Screens/StatsScreen.gd").new()
	root.add_child(stats)
	for _f in 4:
		await process_frame
	stats.call("show_menu")
	for _f in 10:
		await process_frame
	_save("aud_stats")
	stats.queue_free()

	print("AUDIT SHOT done -> " + OUT)
	quit(0)


func _setup_run(wave: int, gold: int, weapons: Array) -> void:
	_gs.wave = wave
	_gs.gold = gold
	_gs.weapons = weapons.duplicate(true)
	_gs.upgrades = {}
	_gs.running = true


# 把货架上每张卡的几何（宽/高/位置）抖出来 —— 截图看不出"是不是真的走了小卡路径"
func _report_shop(tag: String) -> void:
	var shop: Node = null
	for c in root.get_children():
		if c.get_script() == load("res://ui/Shop/Shop.gd"):
			shop = c
	if shop == null:
		return
	var shown := 0
	var geos := []
	for c in shop.find_children("*", "Control", true, false):
		if c.get_script() != load("res://ui/Shop/ShopCard.gd"):
			continue
		if not c.visible:
			continue
		shown += 1
		geos.append("%.0fx%.0f@%.0f,%.0f" % [c.size.x, c.size.y, c.position.x, c.position.y])
	print("[%s] 可见卡片 %d 张，几何：%s" % [tag, shown, " | ".join(geos)])


func _save(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, name])
	print("shot " + name)
