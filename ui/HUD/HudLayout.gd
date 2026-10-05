extends Node

# 局内 HUD / 摇杆的双布局参数表。竖屏 540x900；横屏 960x540（16:9）。
# 作为 autoload 全局可用（保证被加载）。所有局内控件只读这里，不各自写死两套坐标（docs/07 §5.6）。
# HUD 全量 reflow 属真机迭代项：这里的横屏坐标是第一版可用布局，需真机微调。
#
# 【本表是"玩家还看不看得见自己"的第一责任人】
#   顶部 HUD 占多高（hud_block_h），相机就必须在上边让出多少 —— 两件事必须同步。
#   真机踩过：血条/锅气条/经验条/武器槽一路占到 y=112，而玩家走到场地最上沿时
#   角色中心正好在屏幕 y=46，整个萝卜被 HUD 盖死，只剩两片叶子尖露在外面。
#   所以改这张表里任何一个 Y，都要回头核对 hud_block_h 与 tests/test_hud_layout.gd。

func design_size() -> Vector2:
	return Vector2(960.0, 540.0) if Data.is_landscape() else Vector2(540.0, 900.0)

# ---- 安全区避让（刘海 / 状态栏）----
# ⚠️ 原来这个常量在 HUD.gd 里（TOP_SHIFT=34），搬到这里是因为相机要问
#    "顶部到底一共占多高"。两处各写一份必然漂移，守卫钉在 tests/test_hud_layout.gd。
# 横屏刘海在侧边，顶部不用避让，只留 10px 呼吸位。
func safe_top() -> float: return 10.0 if Data.is_landscape() else 34.0

# ---- 顶部 HUD 的局部高度（不含 safe_top）----
# 最后一个控件的底边 = 文字第二行底 77，取 78 留 1px。改任何 Y 都要回来核这个数。
const TOP_CONTENT_H := 78.0
# HUD 底边之下再多留一点，让角色贴着 HUD 站时看着不拥挤。
const TOP_BLOCK_PAD := 6.0
# 顶部 HUD 在屏幕上占的总高 —— 相机上边距就按这个让位。
func hud_block_h() -> float: return safe_top() + TOP_CONTENT_H + TOP_BLOCK_PAD

# ---- HudTop：暂停按钮（右上角）----
# 40px 而不是原来的 48px：右上角要让给暂停，三条进度条的右端必须停在它左边。
# 位置 (492,2) / (908,2) → 占 y 2~42，右下角留给武器槽那一行。
func top_pause_pos() -> Vector2:
	return Vector2(908.0, 2.0) if Data.is_landscape() else Vector2(492.0, 2.0)
func top_pause_size() -> float: return 40.0

# ---- HudBars：顶部三条进度条 ----
# 右端停在 476（竖屏）/ 892（横屏），正好给暂停按钮左边缘留 16px 空当。
# ⚠️ 别把条拉满宽：拉满就会从暂停按钮底下穿过去，看着像按钮压在条上（真踩过）。
func bar_x() -> float: return 36.0
func bar_right() -> float: return 892.0 if Data.is_landscape() else 476.0
func bar_w() -> float: return bar_right() - bar_x()
func wok_x() -> float: return 36.0
func wok_w() -> float: return bar_w()
func run_x() -> float: return 8.0
func run_w() -> float: return 880.0 if Data.is_landscape() else 480.0
# 经验条只画到 230，右边留给"LV n + 经验数字"，再往右是武器槽（竖屏最左 347）。
# ⚠️ 别把这条拉宽：数字是紧跟在条右端画的（见 HudBars._draw），一旦条超过 ~230，
#    数字就推进武器槽行里被图标压住（真踩过：xp_w 竖屏写成 300 时 LV 数字被第 1 格武器吃掉）。
func xp_x() -> float: return 36.0
func xp_w() -> float: return 400.0 if Data.is_landscape() else 194.0

# ---- WeaponBar：武器槽，右上锚定 ----
# ⚠️ 槽位尺寸从 32 缩到 26：顶部每一 px 都会被相机上边距如实让出来（变成场外地面），
#    槽子越大 = 玩家在顶部能活动的屏幕高度越少。缩到 26 仍看得清武器色 + 行为符文。
# ⚠️ slot_y 的坑（更早的一个真实 bug）：槽原本在 y=30，而暂停按钮占 y=16~64，
#    第 4/5 个槽被整块盖住，玩家只看到 3 把武器。现在暂停缩到 40px 且移到 y=2，
#    槽下移到 y=50，两者彻底分开。守卫在 tests/test_hud_layout.gd。
func slot_right() -> float: return 948.0 if Data.is_landscape() else 528.0
func slot_y() -> float: return 50.0
func slot_size() -> float: return 26.0
func slot_gap() -> float: return 5.0

# ---- HudTop：波次 / 金币 / 击杀 / 连击文字行 ----
# 全部挤在 y 56~73 这一行，且右端收在 306 —— 右边 347 起是武器槽，两者同一行不重叠。
func text_row_y() -> float: return 56.0

# ---- HudBanners：横幅宽度（横屏拉满）----
func banner_w() -> float: return 960.0 if Data.is_landscape() else 540.0

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

# ---- Joystick：左下移动区 + 固定底盘 ----
func joy_fixed_base() -> Vector2:
	return Vector2(118.0, 430.0) if Data.is_landscape() else Vector2(118.0, 786.0)
func joy_move_zone_w() -> float: return 430.0 if Data.is_landscape() else 250.0
func joy_move_zone_y() -> float: return 300.0 if Data.is_landscape() else 400.0
