extends RefCounted

# 按钮键位角标（2026-10-20）：开局引导层删除后，键盘映射直接画在 HUD 按钮上
# （玩家原话"把按键映射放在按钮上就看明白了"）。口径与 autoload/Keyboard.gd 一致：
# J/K/L = 技能槽 1/2/3，U = 攻击，空格 = 冲刺；锅气键无键盘映射（不画角标）。
# 独立成文件：SkillButton.gd 顶 300 行红线（arch_guard R1 硬失败）。

# 按钮类型 → 键位字母。skill 按槽位下标取 J/K/L（HudButtons._rebuild_skills 写入）。
static func label(btn_type: String, slot_index: int) -> String:
	match btn_type:
		"dash":
			return "SP"
		"attack":
			return "U"
		"skill":
			if slot_index >= 0 and slot_index < 3:
				return "JKL"[slot_index]
	return ""

# 在按钮右上角画深底圆角键帽。target = SkillButton（CanvasItem），size = 按钮尺寸。
static func draw(target: CanvasItem, lbl: String, size: Vector2) -> void:
	if lbl.is_empty():
		return
	var fs := ThemeDB.fallback_font
	if fs == null:
		return
	var tw: float = fs.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var bw: float = maxf(22.0, tw + 8.0)
	var r := Rect2(size.x - bw - 6.0, 4.0, bw, 16.0)
	target.draw_rect(r, Color(0.05, 0.06, 0.10, 0.72))
	target.draw_rect(r, Color(1.0, 1.0, 1.0, 0.35), false, 1.0)
	# 字母基线 = 框底上抬 4px（16px 框里 13px 字，垂直居中）
	target.draw_string(fs, Vector2(r.position.x + (bw - tw) * 0.5, r.position.y + 13.0),
		lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 1.0, 1.0, 0.92))
