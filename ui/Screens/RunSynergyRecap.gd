extends RefCounted

# 结算页的羁绊复盘（B4）：这一局我堆到哪了、从羁绊里拿到了什么。
#
# 为什么要有这一行：一局打完，玩家看到的是"第几波/击杀/金币"这些结果数字。
#   但真正决定下一局怎么玩的是过程 —— "我本命只堆到 3/6，所以后面打不动"。
#   没有复盘，玩家只会把失败归因为"运气不好"，下一次还是随手买；
#   有了这一行，他会带着"下局我要堆满手枪"的目标重开 —— 这就是研究 build 的正反馈。
#
# 格式：本命·手枪 3/6 暴击 +15%　羁绊·枪械 4/6 攻速 +18%
#   数字与局内实际生效值同源（Synergy.progress），不会出现"面板写 +15% 实际 +12%"这种事。
#
# 单独成文件：死亡页 / 胜利页共用，且两页都已接近 300 行红线。

const Synergy := preload("res://core/Synergy.gd")
const SynText := preload("res://ui/Screens/SynText.gd")

static func text() -> String:
	var ce := Data.character(GameState.character)
	var pr := Synergy.progress(GameState.weapons, ce, Data.weapons)
	var out := ""
	for branch in ["signature", "variety", "bond"]:
		if not pr.has(branch):
			continue
		var d := pr[branch] as Dictionary
		var seg := "%s %d/%d" % [SynText.head_of(branch, ce.get(branch, {}) as Dictionary),
			int(d.get("count", 0)), int(d.get("max_need", 0))]
		var gain := SynText.pair_of(d.get("stats_now", {}))
		if gain != "":
			seg += "  " + gain
		out += seg + "　"
	return out.strip_edges()
