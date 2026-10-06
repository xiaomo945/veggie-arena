extends RefCounted

# 选角页那一行"这条 build 长什么样"（B3）。
#
# 为什么要有这一行：卡片上只写"本命·手枪"，玩家知道该拿什么，但不知道【拿多少把】
#   分别给多少 —— 而"再买一把同样的"到底值不值，全看这个阶梯的形状。
#   没开局就把阶梯摊开，玩家才会带着"我要堆 6 把"的目标进第一波，
#   而不是进商店再看哪张卡顺眼。
#
# 格式（一行）：本命·手枪 1:+4% 2:+9% 3:+15% 4:+22% 5:+30% 6:+40% ｜ 羁绊·枪械 2:+4% 4:+9% 6:+15%
#   数字是"凑够 N 件时这一档给的总加成"，不是每档增量 —— 与游戏内实际生效值一致。
#
# 单独成文件：CharacterPicker / TitleScreen 都已接近 300 行红线，
#   而且这段只做"把阶梯翻译成一行字"，与卡片绘制、页面布局都没关系。

const SynText := preload("res://ui/Screens/SynText.gd")

static func line(char_entry: Dictionary) -> String:
	var out := ""
	for branch in ["signature", "bond"]:
		var br := char_entry.get(branch, {}) as Dictionary
		if br.is_empty():
			continue
		var tiers = br.get("tiers", [])
		# 属性名只写一次（放在名字后面）：六档都写"暴击+4%"会把一行撑爆屏宽
		var prop := SynText.name_of(
			(tiers as Array)[-1].get("stats", {}) if (tiers as Array).size() > 0 else {})
		var seg := SynText.head_of(branch, br) + (" " + prop if prop != "" else "") + " "
		for i in (tiers as Array).size():
			var t = (tiers as Array)[i]
			if not (t is Dictionary):
				continue
			var td := t as Dictionary
			seg += "%d:%s " % [int(td.get("need", 0)), SynText.value_of(td.get("stats", {}))]
		out += seg.strip_edges() + "  ｜  "
	return out.strip_edges().trim_suffix("｜").strip_edges()
