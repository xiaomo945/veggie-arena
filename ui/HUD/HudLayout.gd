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

# ---- 竖屏安全区：底部按钮上移量（避开全面屏手势条 / Home Indicator）----
# 从 HUD.gd 搬来： HudButtons.relayout 要自己重放这次平移（横竖屏翻转时），
# 而组件不该反向依赖 HUD.gd 的常量。两处各写一份必然漂移。
func bottom_shift() -> float: return 34.0

# ---- HudTop：暂停按钮（右上角）----
# 40px 而不是原来的 48px：右上角要让给暂停，三条进度条的右端必须停在它左边。
# 位置 (492,2) / (908,2) → 占 y 2~42，右下角留给武器槽那一行。
func top_pause_pos() -> Vector2:
	return Vector2(908.0, 2.0) if Data.is_landscape() else Vector2(492.0, 2.0)
func top_pause_size() -> float: return 40.0

# ---- HudTop：「属性」按钮（D3-2，暂停键左侧）----
# 竖屏 (449,2)：暂停键在 (492,2)，进度条右端已缩到 440 给这里腾位，
# 按钮 40px 占 x449~489，与暂停键间隔 3px、不压进度条/武器槽。横屏同构左移。
func top_stats_pos() -> Vector2:
	return Vector2(864.0, 2.0) if Data.is_landscape() else Vector2(449.0, 2.0)

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
# 右端停在 440（竖屏）/ 852（横屏）：给右上角「暂停 + 属性」两个 40px 按钮留位，
# 不压进度条（原 476/892 会顶到属性按钮）。⚠️ 别拉满宽。
func bar_x() -> float: return 36.0
func bar_right() -> float: return 852.0 if Data.is_landscape() else 440.0
func bar_w() -> float: return bar_right() - bar_x()
func wok_x() -> float: return 36.0
func wok_w() -> float: return bar_w()
func run_x() -> float: return 8.0
# 总波次条右端对齐 bar_right（440/852），避免伸到右上角「属性」按钮底下
func run_w() -> float: return 852.0 if Data.is_landscape() else 440.0
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

# ---- HudBanners：五条横幅的 Y ----
# 竖屏 900 高铺得开（锅气 196 / 套装 244 / Boss 300 / 解锁 360 / 强化 560）；
# 横屏 540 高：560 直接出屏（强化反馈永远看不见）——压到 150~420 中上部带。
# 顺序固定 [wok, set, boss, unlock, effect]，HudBanners 按序取。
func banner_ys() -> Array:
	return [150.0, 195.0, 240.0, 285.0, 420.0] if Data.is_landscape() \
		else [196.0, 244.0, 300.0, 360.0, 560.0]

# ---- HudBanners：横幅宽度（横屏拉满）----
func banner_w() -> float: return 960.0 if Data.is_landscape() else 540.0

# ---- HudButtons：右下技能簇（圆心 + 扇面半径 + 冲刺位 + 扇面角度）----
func buttons_pivot() -> Vector2:
	return Vector2(820.0, 430.0) if Data.is_landscape() else Vector2(468.0, 762.0)
# ⚠️ 弧半径是几何约束推出来的，别随手调（test_button_layout.gd 钉死）：
#   攻击键(半50)↔锅气键(半40)斜 45° 相对，轴净距 = r·sin45°，要 ≥ 98（半径和+净距8）
#   → r ≥ 138.6；锅气键屏上底边 = 攻击屏上y + r·sin45° + 40 ≤ 屏高：
#   横屏 396+…≤540 → r ≤ 147.1（取 143，两侧各剩 3~4px）；竖屏 728+…≤900 → r ≤ 186.7（取 152）。
func buttons_arc_r() -> float: return 143.0 if Data.is_landscape() else 152.0
func buttons_dash_center() -> Vector2:
	# 竖屏：冲刺在扇面左上 (455,500)，远离技能环也不进摇杆移动区。
	# 横屏：贴在扇面左侧 (580,385)。⚠️ 不能更靠右：技1（180°）屏上中心
	#    (677,396)，冲刺半 44 + 技能半 38 + 净距 8 = 90 → 冲刺圆心 x ≤ 587，
	#    取 580 留 7px 余量；与锅气键(135°)轴净距 139、与攻击键 240，都富余。
	return Vector2(580.0, 385.0) if Data.is_landscape() else Vector2(455.0, 500.0)
# ⚠️ skill 槽【不写 id】：技能表已角色化，且武器/道具还会【赠送】技能
#    （见 core/SkillSlots.gd）—— 写死 id 就会放出一个招不出来的按钮（真踩过：
#    这里写 poison，而 poison 已被角色专属技能取代 → 按钮点了没反应）。
#    留空 = 由 SkillSystem 槽位广播（Events.skill_slots_changed）决定放几个、什么 id。
# 扇面里【没有快进】：2 倍速按钮没有任何消费者（Events.fast_forward_toggled
#    全仓库零订阅方，Game 从不处理），且和冲刺键位太近被玩家误按
#    （"按了快进角色扁一下"= 实际按到冲刺）—— main 线曾加过又成了死键，别再捡回来。
func buttons_fan() -> Array:
	# 王者荣耀式环绕（玩家原话："123技能分别环绕在攻击按钮的左边，左上，上"）：
	# 攻击键居圆心，技能 1/2/3 在【正左 180° / 左上 225° / 正上 270°】，
	# 锅气大按钮去左下 135°（右侧出屏：540 宽放不下，0°/315° 都会探出屏幕）。
	# 等角距 45° 扇面：治旧版"间隔不一样太难看"——相邻角差恒 45°，
	# 弦长 = 2·r·sin22.5°：竖屏 r=152 → 116px；横屏 r=143 → 109px。
	# 按钮是轴对齐方块，斜向相邻不能只看圆心距，|dx| 或 |dy| 必须 > 两者半径和：
	#   竖屏：wok↔技1 |dy|=107.5>80（40+38）；技1↔技2 |dy|=107.5>76（38+38）；
	#         技2↔技3 |dx|=107.5>76；技3↔攻击 |dy|=152>88（38+50）。全部通过。
	#   横屏：wok↔技1 |dy|=101.1>80；技1↔技2 101.1>76；技2↔技3 |dx|=101.1>76；
	#         技3↔攻击 |dy|=143>88；攻击↔wok（斜 45°）101.1>90（50+40）。同样通过。
	# ⚠️ 竖屏 wok 局部底边 869.5+40=909.5 会出屏：靠 HudLayout.bottom_shift()=34
	#    整体上移兜底（屏上底边 875.5<900）。技1 左缘 278 与摇杆旋钮极值
	#    （基址钳 220 + 半径 70 = 290）有 12px 交叠，但触摸按"先认领"分配，
	#    摇杆只认领移动区内落指，不会双触发。
	return [
		{"type": "wok",   "deg": 135.0},
		{"type": "skill", "deg": 180.0},
		{"type": "skill", "deg": 225.0},
		{"type": "skill", "deg": 270.0},
	]

# ---- Joystick：左下移动区 + 固定底盘 ----
# 底盘中心与右侧攻击键【同一水平线】（玩家原话："左下轮盘调整一下中心跟右边
# 攻击按钮一样的中心点"）：攻击键屏上中心 = buttons_pivot − bottom_shift()
# （竖屏 (468,762−34)=(468,728)；横屏 (820,430−34)=(820,396)）。
# ⚠️ Joystick 是 Main 下的独立 CanvasLayer，不吃 HUD 给 _buttons 的那次平移，
#    所以 bottom_shift 必须在这里自己减掉。
func joy_fixed_base() -> Vector2:
	return Vector2(118.0, 396.0) if Data.is_landscape() else Vector2(118.0, 728.0)
# 竖屏移动区 250：main 线曾收紧到 220 防"一根手指同时被摇杆和技能键认领"——
# 但 ours 口径下最左技能键（技1）左缘 278，与 250 之间已有 28px 净距，
# 且触摸按"先认领"分配（Joystick 只认领移动区内落指），250 是验收值，不动。
func joy_move_zone_w() -> float: return 430.0 if Data.is_landscape() else 250.0
func joy_move_zone_y() -> float: return 300.0 if Data.is_landscape() else 400.0
