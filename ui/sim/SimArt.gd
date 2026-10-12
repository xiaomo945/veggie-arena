extends RefCounted

# 模拟收尾的美术装载报告（从 ui/Screens/Main.gd 拆出来：Main 卡在 300 行架构红线上，
# 而这段纯诊断代码挪走不影响任何玩法逻辑）。
#
# 逐个敌人点名：任何一种缺图，这里会显示"手绘"，一眼看出漏了哪张。

static func enemy_report(keys: Array) -> String:
	var parts := []
	for k in keys:
		var ok := Art.sprite("enemy_" + str(k)) != null
		parts.append("%s=%s" % [str(k), "贴图" if ok else "手绘"])
	return " ".join(parts)
