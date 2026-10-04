extends Control

# HUD 横幅区：Boss 波横幅 / 锅气上档弹窗 / 解锁提示。
#
# 三条横幅共用一套"弹出来 → 停留 → 最后 0.6s 渐隐"的生命周期，区别只是
# 触发源不同，所以收在同一个组件里：一个 _tick 管三个计时器。
#
# 职责边界：不订阅 Events（HUD.gd 负责），只提供 pop_* / queue_* / tick。

const FADE := 0.6        # Boss / 锅气横幅渐隐时长（秒）
const UNLOCK_FADE := 0.5 # 解锁提示渐隐稍快一点
const BOSS_HOLD := 2.6   # Boss 横幅停留
const WOK_HOLD := 1.6    # 锅气弹窗停留
const UNLOCK_HOLD := 2.2 # 解锁提示停留
const SET_HOLD := 2.0    # 套装凑齐提示停留

var _banner: Label
var _banner_t := 0.0
var _wok_banner: Label
var _wok_banner_t := 0.0
var _unlock: Label
var _unlock_t := 0.0
var _unlock_queue: Array = []   # 待展示的解锁提示（一次一条，避免刷屏）
var _set: Label                 # 套装凑齐提示（Q1）
var _set_t := 0.0

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	size = HudLayout.design_size()

	# Boss 波居中横幅
	_banner = _mk(Vector2(0, 288), HudLayout.banner_w(), 44.0, 34, Color(0.96, 0.34, 0.46))
	# 锅气档位弹窗（顶部偏下，火候上档时弹出"翻炒!"/"爆炒!"）
	_wok_banner = _mk(Vector2(0, 96), HudLayout.banner_w(), 40.0, 30, Color(1, 1, 1))
	# 解锁横幅
	_unlock = _mk(Vector2(0, 340), HudLayout.banner_w(), 40.0, 24, Color(1.0, 0.84, 0.36))
	# 套装凑齐横幅（放在锅气弹窗下方、Boss 横幅上方，三条互不遮挡）
	_set = _mk(Vector2(0, 150), HudLayout.banner_w(), 36.0, 22, Color(1.0, 0.92, 0.70))

func _mk(pos: Vector2, w: float, h: float, fs: int, c: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.custom_minimum_size = Vector2(w, h)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.text = ""
	add_child(l)
	return l

# ---- 对外接口（由 HUD.gd 调用）----

func pop_boss(text: String) -> void:
	_banner.add_theme_font_size_override("font_size", 34)
	_banner.text = text
	_banner_t = BOSS_HOLD

# 终局 Boss：字号更大、停留更久，配得上"这一局最后一道坎"
func pop_final_boss(text: String) -> void:
	_banner.add_theme_font_size_override("font_size", 44)
	_banner.text = text
	_banner_t = BOSS_HOLD * 1.6

func pop_wok(text: String, c: Color) -> void:
	_wok_banner.text = text
	_wok_banner.add_theme_color_override("font_color", c)
	_wok_banner.modulate.a = 1.0
	_wok_banner_t = WOK_HOLD

# 套装凑齐：件数刚跨过一档时弹一次，让"我凑出了一套"这件事被看见
func pop_set(text: String, c: Color) -> void:
	_set.text = text
	_set.add_theme_color_override("font_color", c)
	_set.modulate.a = 1.0
	_set_t = SET_HOLD

# 解锁提示：一次显示一条，UNLOCK_HOLD 秒后换下一条（多条时排队，不叠在一起）
func queue_unlock(key: String) -> void:
	_unlock_queue.append(key)

func tick(delta: float) -> void:
	if _banner_t > 0.0:
		_banner_t -= delta
		_banner.modulate.a = clampf(_banner_t / FADE, 0.0, 1.0)
		if _banner_t <= 0.0:
			_banner.text = ""
	if _wok_banner_t > 0.0:
		_wok_banner_t -= delta
		_wok_banner.modulate.a = clampf(_wok_banner_t / FADE, 0.0, 1.0)
		if _wok_banner_t <= 0.0:
			_wok_banner.text = ""
	if _set_t > 0.0:
		_set_t -= delta
		_set.modulate.a = clampf(_set_t / FADE, 0.0, 1.0)
		if _set_t <= 0.0:
			_set.text = ""
	if _unlock_t > 0.0:
		_unlock_t -= delta
		_unlock.modulate.a = clampf(_unlock_t / UNLOCK_FADE, 0.0, 1.0)
		if _unlock_t <= 0.0:
			_unlock.text = ""
		return
	if _unlock_queue.is_empty():
		return
	var key := str(_unlock_queue.pop_front())
	var def := Data.weapon(key)
	_unlock.text = I18n.t("hud_unlocked") % I18n.pick(def).to_upper()
	_unlock_t = UNLOCK_HOLD

# 竖屏安全区：横幅整体下移，避开刘海 / 状态栏。
func apply_safe_area(top: float) -> void:
	position += Vector2(0.0, top)
