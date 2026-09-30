extends SceneTree

# 测试入口：godot --headless --path . --script res://tests/run_tests.gd
# 每个被测模块一个 test_*.gd，失败会明确列出，不会静默跳过

const TCombat := preload("res://tests/test_combat.gd")
const TSpawner := preload("res://tests/test_spawner.gd")
const TEconomy := preload("res://tests/test_economy.gd")
const TInventory := preload("res://tests/test_inventory.gd")
const TBalance := preload("res://tests/test_balance.gd")
const TMovement := preload("res://tests/test_movement.gd")
const TWeapon := preload("res://tests/test_weapon.gd")
const THit := preload("res://tests/test_hit.gd")
const TWok := preload("res://tests/test_wok.gd")
const DataScript := preload("res://autoload/Data.gd")

var passed := 0
var failed := 0
var failures: Array = []

func _initialize() -> void:
	var data = DataScript.new()
	data.load_all()
	print("")
	print("=== veggie-arena 单元测试 ===")
	print("数据表: balance=%d 武器=%d 敌人=%d 强化=%d" % [
		data.balance.size(), data.weapons.size(),
		data.enemies.size(), data.upgrades.size()])

	_run("Combat", TCombat)
	_run("Spawner", TSpawner)
	_run("Economy", TEconomy)
	_run("Inventory", TInventory)
	_run("Balance(配平)", TBalance, data)
	_run("Movement(手感)", TMovement, data)
	_run("Weapon(武器)", TWeapon, data)
	_run("Hit(命中/分离)", THit, data)
	_run("Wok(锅气)", TWok, data)

	# Data 是 Node，不会自动释放，避免退出时的 ObjectDB 泄漏警告
	data.free()

	print("")
	print("通过 %d / 失败 %d" % [passed, failed])
	if failed > 0:
		print("")
		print("失败明细：")
		for f in failures:
			print("  ✗ " + str(f))
		quit(1)
	else:
		print("=== 全部通过 ===")
		quit(0)

func _run(name: String, script, arg = null) -> void:
	var t = script.new()
	print("")
	print("-- " + name + " --")
	var r = t.run(arg) if arg != null else t.run()
	passed += int(r.get("pass", 0))
	failed += int(r.get("fail", 0))
	for f in r.get("failures", []):
		failures.append(name + ": " + str(f))
