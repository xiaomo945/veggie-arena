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
# 最后一个控件的底边 = 羁绊条底（局部 y 80 + 高 16 = 96）。
# ⚠️ 羁绊条（HudSynergy）是这一带最新的控件，改它的 Y 必须回来核这个数，
#    否则相机按旧高度让位，玩家贴场地最上沿时会被羁绊条压住（同类 bug 真踩过）。
const TOP_CONTENT_H := 96.0
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

# ---- HudSynergy：羁绊进度条（顶部 HUD 之下那条）----
# 屏幕绝对坐标（与 FpsMeter 同款：直接挂 HUD CanvasLayer，不经 HudTop 的平移）。
# 局部 y=80：上面三条进度条 + 武器槽 + 文字行占到 76，再往下 4px 就是它的地盘。
func synergy_pos() -> Vector2:
	return Vector2(8.0, safe_top() + 80.0)
func synergy_h() -> float: return 16.0
func synergy_w() -> float: return 480.0 if Data.is_landscape() else 400.0

# ---- FPS 计数器（默认隐藏）----
# ⚠️ 屏幕绝对坐标：FpsMeter 直接挂在 HUD CanvasLayer 下，不经 HudTop 的 safe_top 偏移
#    （第一版写 (8,80) 时正好压进 "WAVE 1/12" 那行文字 —— 截图目检抓出来的）。
#    现在羁绊条又占了一条：竖屏顶部块 = 34 + 96 = 130，放 134；横屏 = 10 + 96 = 106，放 112。
#    都贴着相机让位线下沿，不压任何 HUD 控件，只占玩家不会久留的屏幕边缘。
func fps_pos() -> Vector2:
	return Vector2(8.0, 112.0) if Data.is_landscape() else Vector2(8.0, 134.0)

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

# ---- HudButtons：右下技能簇（攻击键圆心 + 环绕技能弧 + 冲刺位）----
# 布局原型：王者荣耀 —— 攻击键在右下，三个技能键等角距环绕它的左 / 左上 / 上方。
# 键盘 J/K/L 与这三个环绕键一一对应（顺序见 addon_slots，按下标取）。
#
# 【圆心为什么要镜像摇杆】玩家要求"左下轮盘和右边攻击键同一个中心点"：
# 摇杆底盘 joy_fixed_base() 在左下，攻击键圆心取它的水平镜像（d.x - base.x），
# 两只大拇指到屏幕边缘的距离就完全一致。竖屏还要回补底部安全区：HUD 按钮整体
# 上移 safe_bottom()（HUD.gd 里统一平移），所以攻击键的布局坐标要 +safe_bottom()，
# 平移后才正好落在摇杆底盘的同一水平线上。
func safe_bottom() -> float: return 34.0
func attack_button_center() -> Vector2:
	var d := design_size()
	var base := joy_fixed_base()
	return Vector2(d.x - base.x, base.y + safe_bottom())

# 环绕技能键：攻击键圆心 + 角度 × 弧半径。角度用屏幕坐标系（y 向下）：
# 180°=左、225°=左上、270°=上，相邻两个正好 45° 等角距 —— 旧版 150/195/240
# 一个 45° 一个 90°，弧长忽宽忽窄，就是"技能按钮间隔不一样、太难看"的由来。
# 【顺序即键盘映射】下标 0/1/2 = J/K/L = 技能 1/2/3。
# ⚠️ skill 槽【不写 id】：技能表已角色化（十个角色十个专属技能），写死 id
#    就会放出一个技能表里已经没有的招（真踩过：这里写 poison，而 poison 已被
#    角色专属技能取代 → 按钮点了没反应）。留空 = SkillButton 自己按当前角色取。
func addon_slots() -> Array:
	return [
		{"type": "skill", "deg": 180.0},
		{"type": "wok",   "deg": 225.0},
		{"type": "ff",    "deg": 270.0},
	]
func addon_arc_r() -> float: return 160.0 if Data.is_landscape() else 152.0

# 冲刺键在扇面外（上方），不压技能环、也不进左下摇杆的移动区。
func buttons_dash_center() -> Vector2:
	return Vector2(900.0, 200.0) if Data.is_landscape() else Vector2(455.0, 500.0)

# ---- Joystick：左下移动区 + 固定底盘 ----
func joy_fixed_base() -> Vector2:
	return Vector2(118.0, 430.0) if Data.is_landscape() else Vector2(118.0, 786.0)
# ⚠️ 竖屏 220 而不是原来的 250：移动区是"x<=W 且 y>=Y"的整块矩形（见 Joystick._in_zone），
#    而最左那个技能键的左缘在 x=228。盖住按钮 = 一根手指同时被摇杆和技能键认领
#    （Joystick 只看在不在矩形里、SkillButton 只看在不在自己矩形里，两边都会触发）。
#    220 给按钮留 8px 缓冲，拇指落到按钮上就只算技能，不会再带着角色一起走。
func joy_move_zone_w() -> float: return 430.0 if Data.is_landscape() else 220.0
func joy_move_zone_y() -> float: return 300.0 if Data.is_landscape() else 400.0
