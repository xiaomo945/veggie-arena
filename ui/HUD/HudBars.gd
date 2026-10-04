extends Node2D

# HUD 的绘制层：血条 + 武器槽。
# 单独拆出来，是为了让"画什么"和"什么时候更新"分开，改样式不会碰坏逻辑。

var hp_ratio := 1.0
var wave_progress := 0.0
var wok_ratio := 0.0       # 0..1 火候
var wok_tier := 0          # 0 微温 / 1 翻炒 / 2 爆炒
var run_wave := 1          # 当前波次（用于总进度条）
var run_total := 20        # 总波次

const BAR_X := 40.0
const BAR_Y := 8.0
var BAR_W := 486.0
const BAR_H := 14.0

# 武器槽不在这里画了：搬去 ui/HUD/WeaponBar.gd（带行为符文，单独一层）
# 锅气条放在顶部 HUD 区（与血条并排，全宽），手机底部会被浏览器底栏遮挡，不能放下面
const WOK_X := 40.0
const WOK_Y := 24.0
var WOK_W := 486.0
const WOK_H := 16.0

# 总波次进度条（"这局打到第几波了"），贴最顶，全宽细条，避开刘海区
const RUN_X := 8.0
const RUN_Y := 4.0
var RUN_W := 524.0
const RUN_H := 3.0

func _ready() -> void:
	# 横屏（960 宽）把顶部三条进度条铺满宽度；竖屏保持原 540 宽。
	BAR_W = HudLayout.bar_w()
	WOK_W = HudLayout.wok_w()
	RUN_W = HudLayout.run_w()

func _draw() -> void:
	_draw_run_progress()
	_draw_hp_bar()
	_draw_wok()

# 总波次进度：run_wave / run_total，一眼看出距离通关还有多远
func _draw_run_progress() -> void:
	draw_rect(Rect2(RUN_X, RUN_Y, RUN_W, RUN_H), Color(0, 0, 0, 0.5))
	var frac := clampf(float(run_wave) / maxf(1.0, float(run_total)), 0.0, 1.0)
	draw_rect(Rect2(RUN_X, RUN_Y, RUN_W * frac, RUN_H), Color(1.0, 0.72, 0.32, 0.9))

# 圆角块工具：frame 传 null 则为无描边纯色块
func _round(x: float, y: float, w: float, h: float, fill: Color, frame: Color, bw: int, rad: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(rad))
	if frame != null and frame.a > 0.001:
		sb.border_color = frame
		sb.set_border_width_all(bw)
	draw_style_box(sb, Rect2(x, y, w, h))

# 通用条：圆角底槽 + 圆角填充 + 顶部高光，卡通感比纯矩形强很多
func _bar(x: float, y: float, w: float, h: float, frac: float, fill: Color, frame: Color) -> void:
	_round(x, y, w, h, Color(0.04, 0.04, 0.06, 0.62), frame, 2, 7.0)
	var fw := clampf(w * frac, 0.0, w)
	if fw > 5.0:
		_round(x + 2.0, y + 2.0, fw - 4.0, h - 4.0, fill, Color(0, 0, 0, 0.0), 0, 5.0)
		draw_rect(Rect2(x + 4.0, y + 3.0, fw - 8.0, 2.0), fill.lightened(0.45))

func _draw_hp_bar() -> void:
	# 波次进度（细条，叠在血条下方，让玩家知道"还有多久这波结束"）
	draw_rect(Rect2(BAR_X, BAR_Y + BAR_H + 2.0, BAR_W, 3.0), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(BAR_X, BAR_Y + BAR_H + 2.0, BAR_W * clampf(wave_progress, 0.0, 1.0), 3.0),
		Color(0.55, 0.85, 0.55, 0.75))
	# 血量：低于 30% 变红，危险感要一眼看到；危急时整条描红边
	var r := clampf(hp_ratio, 0.0, 1.0)
	var c := Color(0.92, 0.32, 0.30) if r < 0.3 else Color(0.40, 0.82, 0.44)
	var frame := Color(0.95, 0.45, 0.42) if r < 0.3 else Color(0.20, 0.30, 0.16)
	_bar(BAR_X, BAR_Y, BAR_W, BAR_H, r, c, frame)
	# 分段刻度，方便估算还剩多少血
	for i in range(1, 5):
		var x := BAR_X + BAR_W * float(i) / 5.0
		draw_line(Vector2(x, BAR_Y + 2.0), Vector2(x, BAR_Y + BAR_H - 2.0), Color(0, 0, 0, 0.30), 1.0)

func _draw_wok() -> void:
	# 火候填充：档位越高越"炽热"
	var r := clampf(wok_ratio, 0.0, 1.0)
	var c := Color(0.52, 0.52, 0.52)
	if wok_tier >= 2:
		c = Color(1.0, 0.40, 0.24)     # 爆炒：红热
	elif wok_tier >= 1:
		c = Color(1.0, 0.66, 0.26)     # 翻炒：橙
	elif r > 0.01:
		c = Color(0.85, 0.78, 0.58)     # 微温：暖灰
	# 爆炒档描一圈"滋滋"高光，强化"热"的反馈
	if wok_tier >= 2:
		_round(WOK_X - 2.0, WOK_Y - 2.0, WOK_W + 4.0, WOK_H + 4.0, Color(1.0, 0.6, 0.4, 0.0),
			Color(1.0, 0.6, 0.4, 0.55), 2, 9.0)
	_bar(WOK_X, WOK_Y, WOK_W, WOK_H, r, c, Color(0.30, 0.18, 0.10))
	# 档位刻度：翻炒(34%) 与 爆炒(68%) 的分界，玩家一眼知道火候到哪了
	_draw_tick(float(Data.wok_cfg().get("stir_from", 34)) / 100.0, Color(1, 0.8, 0.4, 0.8))
	_draw_tick(float(Data.wok_cfg().get("wokhei_from", 68)) / 100.0, Color(1, 0.45, 0.3, 0.9))
	# 满锅气线（颠勺就绪）
	_draw_tick(1.0, Color(1, 1, 1, 0.9))
	# 百分比文字：直接在条上写，玩家一眼看到火候涨到多少
	var pct := int(round(r * 100.0))
	var txt := I18n.t("hud_wok_heat") % pct
	draw_string(ThemeDB.fallback_font, Vector2(WOK_X + 6.0, WOK_Y + WOK_H - 3.0),
		txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 1.0, 1.0, 0.92))

func _draw_tick(frac: float, c: Color) -> void:
	var x := WOK_X + WOK_W * clampf(frac, 0.0, 1.0)
	draw_line(Vector2(x, WOK_Y - 2.0), Vector2(x, WOK_Y + WOK_H + 2.0), c, 1.5)
