extends Node

# 局内 HUD / 摇杆的双布局参数表。竖屏 540x900；横屏 960x540（16:9）。
# 作为 autoload 全局可用（保证被加载）。所有局内控件只读这里，不各自写死两套坐标（docs/07 §5.6）。
# HUD 全量 reflow 属真机迭代项：这里的横屏坐标是第一版可用布局，需真机微调。

func design_size() -> Vector2:
	return Vector2(960.0, 540.0) if Data.is_landscape() else Vector2(540.0, 900.0)

# ---- HudTop：暂停按钮位置（右上角）----
func top_pause_pos() -> Vector2:
	return Vector2(960.0 - 56.0, 16.0) if Data.is_landscape() else Vector2(540.0 - 56.0, 16.0)

# ---- HudBars：顶部血条 / 锅气条 / 总进度条宽度（横屏铺满宽条）----
func bar_x() -> float: return 40.0
func bar_w() -> float: return 920.0 if Data.is_landscape() else 486.0
func wok_x() -> float: return 40.0
func wok_w() -> float: return 920.0 if Data.is_landscape() else 486.0
func run_x() -> float: return 8.0
func run_w() -> float: return 944.0 if Data.is_landscape() else 524.0

# ---- WeaponBar：武器槽，右上锚定 ----
func slot_right() -> float: return 948.0 if Data.is_landscape() else 528.0
func slot_y() -> float: return 30.0

# ---- HudButtons：右下技能簇（圆心 + 扇面半径 + 冲刺位 + 扇面角度）----
func buttons_pivot() -> Vector2:
	return Vector2(820.0, 430.0) if Data.is_landscape() else Vector2(468.0, 762.0)
func buttons_arc_r() -> float: return 130.0 if Data.is_landscape() else 152.0
func buttons_dash_center() -> Vector2:
	return Vector2(690.0, 470.0) if Data.is_landscape() else Vector2(455.0, 500.0)
func buttons_fan() -> Array:
	if Data.is_landscape():
		return [
			{"type": "wok",   "deg": 240.0},
			{"type": "skill", "id": "frost",  "deg": 195.0},
			{"type": "skill", "id": "poison", "deg": 150.0},
		]
	return [
		{"type": "wok",   "deg": 240.0},
		{"type": "skill", "id": "frost",  "deg": 195.0},
		{"type": "skill", "id": "poison", "deg": 150.0},
	]

# ---- HudBanners：横幅宽度（横屏拉满）----
func banner_w() -> float: return 960.0 if Data.is_landscape() else 540.0

# ---- Joystick：左下移动区 + 固定底盘 ----
func joy_fixed_base() -> Vector2:
	return Vector2(118.0, 430.0) if Data.is_landscape() else Vector2(118.0, 786.0)
func joy_move_zone_w() -> float: return 430.0 if Data.is_landscape() else 250.0
func joy_move_zone_y() -> float: return 300.0 if Data.is_landscape() else 400.0
