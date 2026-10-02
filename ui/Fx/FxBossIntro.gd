extends Control

# Boss 登场演出（屏幕空间）：全屏压暗 + 地面震裂 + 名字横幅扫过。
# 订阅 Events.boss_wave / final_boss_wave，自己播自己，FxLayer 只负责 add_child。
#
# 时序（总 1.9s，全用缓动，无硬切）：
#   0.00-0.30  压暗淡入（到 0.62），地面裂纹从屏幕中心裂开
#   0.18-0.62  裂纹长到最长 + 轻震屏
#   0.28-1.20  横幅从右扫入 → 停在中央 → 向左扫出
#   1.20-1.90  压暗淡出，交还战场
#
# 为什么画在屏幕空间：Boss 在玩家视野外一圈刷出（470px），世界空间的"裂纹"
# 根本看不见 —— 登场演出本质是给"玩家"看的，不是给"那个点"看的。

const LIFE := 1.9
const DARK := 0.62
const DARK_IN := 0.30
const DARK_OUT_FROM := 1.20

const Crack := preload("res://art/BossCrack.gd")
const Shake := preload("res://entities/effects/Shake.gd")

var t := -1.0
var _final := false
var _wave := 0
var _shaken := false

func _ready() -> void:
	anchor_left = -1.0
	anchor_top = -1.0
	anchor_right = 2.0
	anchor_bottom = 2.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	name = "BossIntro"
	Events.boss_wave.connect(func(w: int) -> void: play(w, false))
	Events.final_boss_wave.connect(func(w: int) -> void: play(w, true))

func play(wave: int, final: bool) -> void:
	_wave = wave
	_final = final
	_shaken = false
	t = 0.0
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	if t < 0.0:
		set_process(false)
		return
	t += delta
	# 地裂到位的瞬间震一下屏（比"喊一嗓子"更直觉的"大地裂开"）
	if not _shaken and t >= 0.26:
		_shaken = true
		Shake.kick(8.0, 0.34)
	if t >= LIFE:
		t = -1.0
		set_process(false)
	queue_redraw()

func _draw() -> void:
	if t < 0.0:
		return
	var view := get_viewport_rect().size
	if view.x <= 0.0:
		view = Vector2(540.0, 900.0)
	var c := view + view * 0.5   # anchor -1..2 时视口中心的局部坐标
	_darken(view)
	Crack.paint(self, c, _crack_k())
	_banner(view, c)

# ---- 压暗：快速淡入，末段缓慢淡出（Boss 走进场时画面已恢复）----
func _darken(view: Vector2) -> void:
	var a := 0.0
	if t < DARK_IN:
		a = t / DARK_IN
	elif t < DARK_OUT_FROM:
		a = 1.0
	else:
		a = 1.0 - (t - DARK_OUT_FROM) / (LIFE - DARK_OUT_FROM)
	a *= DARK
	if a <= 0.003:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.02, 0.05, a))
	# 压暗时给一层从边缘往里的红黑晕（终局更红），比纯黑更"凶"
	var edge := Color(0.55, 0.10, 0.12, a * (0.42 if _final else 0.17))
	Crack.vignette(self, view, edge)

# ---- 名字横幅：色带 + 大字 + 上下描边，从右扫入停中再扫出 ----
func _banner(view: Vector2, c: Vector2) -> void:
	var k0 := 0.28
	var k1 := 1.22
	if t < k0 or t > k1:
		return
	var h := view.y * (0.10 if _final else 0.082)
	var x := 0.0
	if t < 0.62:
		var u := (t - k0) / (0.62 - k0)
		x = (1.0 - _ease_out(u)) * (view.x * 2.2)
	elif t < 0.92:
		x = 0.0
	else:
		var u2 := (t - 0.92) / (k1 - 0.92)
		x = -_ease_in(u2) * (view.x * 2.2)
	# 带宽 = 3 倍屏宽（本控件 anchor -1..2，视口只是中间那 1/3）
	var bw := view.x * 3.0
	var band := Rect2(c.x - bw * 0.5 + x, c.y - h * 0.5, bw, h)
	var col := Color(0.72, 0.10, 0.16) if _final else Color(0.62, 0.14, 0.20)
	draw_rect(band.grow(5.0), Color(0.05, 0.03, 0.05, 0.92))
	draw_rect(band, col)
	draw_rect(Rect2(band.position, Vector2(band.size.x, h * 0.14)),
		Color(1.0, 0.85, 0.35, 0.9))
	draw_rect(Rect2(Vector2(band.position.x, band.end.y - h * 0.10),
		Vector2(band.size.x, h * 0.10)), Color(0.0, 0.0, 0.0, 0.35))
	var txt := ("FINAL WAVE %d" if _final else "BOSS WAVE %d") % _wave
	_center_text(txt, c.x + x, band.get_center().y, h * 0.52)

func _center_text(txt: String, cx: float, cy: float, px: float) -> void:
	var f := get_theme_default_font()
	if f == null:
		return
	var sz := int(px)
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var pos := Vector2(cx - w * 0.5, cy + px * 0.36)
	draw_string_outline(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 6,
		Color(0.05, 0.03, 0.05, 0.9))
	draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz,
		Color(1.0, 0.88, 0.42))

static func _ease_out(u: float) -> float:
	return 1.0 - pow(1.0 - clampf(u, 0.0, 1.0), 3.0)

static func _ease_in(u: float) -> float:
	return pow(clampf(u, 0.0, 1.0), 2.4)

# 裂纹生长曲线：0.10 起裂，0.62 长满，1.30 后开始隐去
func _crack_k() -> float:
	if t < 0.10:
		return 0.0
	if t < 0.62:
		return _ease_out((t - 0.10) / 0.52)
	if t < 1.30:
		return 1.0
	return 1.0 - (t - 1.30) / (LIFE - 1.30)
