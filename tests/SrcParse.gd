class_name SrcParse
extends RefCounted

# 源码解析小工具：给"读生产代码源码做断言"的单测用。
#
# 为什么需要它：--script 单测模式不注册 autoload，任何用到 Data / Events /
# GameState / HudLayout 标识符的文件都 preload 不了（Compile Error）；
# HudBars / WeaponBar 这类 Node2D 的 _draw() 坐标又全是字面量，也没法实例化。
# 所以只能 FileAccess.get_file_as_string 读源码，用正则/字符串切出坐标再断言。
# test_bgm.gd / test_gamepad.gd / test_hud_layout.gd 都走这条路。
#
# 全部方法 static，测试里直接 SrcParse.ret(...) 调，不用先 new()。
#
# ⚠️ 这里踩过的两个坑，改动前先读：
#
# 1) 别在测试里抄一份产品常量。
#    抄了就会漂：test_hud_layout 曾写 XP_Y=47 而产品是 45、XP_W=194 而产品被
#    _ready() 覆盖成 300 —— 测试全绿，实际 LV 数字被武器图标吃掉。
#    一律现解析，别抄。
#
# 2) 取数字必须先剥掉 "Vector2(" 这种类型包装。
#    top_pause_pos() 返回 Vector2(492.0, 2.0)，从头逐字符扫会先撞上类型名里的
#    2 就停下，得出 x=2。而且 2 恰好也不与武器槽相交，整条断言照样绿 ——
#    假通过最难发现，所以 _to_float 统一处理，写新解析器别绕过它。

# 取 "return <数字>" 的值。
static func ret(src: String, func_sig: String) -> float:
	return num(line_of(src, func_sig), "return ")

# 取 "X if Data.is_landscape() else Y" 里的 Y（竖屏分支，与本项目写法一致）。
# 写法比想象中更笨（找 else 之后第一个数字），但产品代码格式统一；
# 真解析不动了该改产品代码，而不是把测试写成正则地狱。
static func ternary_p(src: String, func_sig: String) -> float:
	var line := line_of(src, func_sig)
	var els := line.find(" else ")
	if els < 0:
		return to_float(line)
	return to_float(line.substr(els + 6))

# 同上但取 X（横屏分支）—— ternary_p 的镜像，两个都要有时成对使用。
static func ternary_l(src: String, func_sig: String) -> float:
	var line := line_of(src, func_sig)
	var mid := line.find(" if ")
	if mid < 0:
		return to_float(line)
	return to_float(line.substr(0, mid))

# 取 "const X := <数字>" 的值。
static func const_val(src: String, name: String) -> float:
	return num(line_of(src, "const " + name), ":=")

# 取 "var X := <数字>" 的值（成员声明的默认值）。
static func var_val(src: String, name: String) -> float:
	return num(line_of(src, "var " + name), ":=")

# 取一段文本里的第一个数字。先剥掉 Vector2( / Vector2i( 类型包装（见文件头坑 2）。
static func to_float(s: String) -> float:
	var t := s.replace("Vector2i(", "(").replace("Vector2(", "(")
	var out := ""
	for i in t.length():
		var ch := t[i]
		if (ch >= "0" and ch <= "9") or ch == ".":
			out += ch
		elif out != "":
			break
	return float(out) if out != "" else -1.0

# 求值 "BAR_Y + BAR_H + 2.0" 这种算式（只支持 +，够覆盖绘制坐标）。
# 算式里的标识符回源码查它自己的 const/var 值 —— 不能把 "BAR_Y" 当数字读，
# 读成 -1 会算出 y=0，让"本波细条在血条下方"这类断言反向失败（真踩过）。
static func expr(src: String, e: String) -> float:
	if src.find(e) < 0:
		return -1.0
	var sum := 0.0
	for part in e.split("+"):
		var token := part.strip_edges()
		if token == "":
			continue
		sum += declared(src, token) if is_ident(token) else to_float(token)
	return sum

# 某个标识符在源码里声明的数值（先找 const 再找 var）。
static func declared(src: String, name: String) -> float:
	var c := const_val(src, name)
	return c if c >= 0.0 else var_val(src, name)

static func is_ident(token: String) -> bool:
	if token.is_empty():
		return false
	var c := token[0]
	return (c < "0" or c > "9") and c != "."

# 取某行里 key 之后的数字。
static func num(line: String, key: String) -> float:
	var i := line.find(key)
	if i < 0:
		return -1.0
	return to_float(line.substr(i + key.length()))

# 返回"签名行 + 紧随其后的第一条代码行"（跳过空行与注释）。
# ⚠️ 必须跨行：产品代码里既有单行写法 `func f() -> float: return 1.0`，
# 也有多行写法。只取签名行会从类型名 "Vector2" 里抠出数字当坐标（真踩过）。
static func line_of(src: String, func_sig: String) -> String:
	var idx := src.find(func_sig)
	if idx < 0:
		return ""
	var end := src.find("\n", idx)
	if end < 0:
		return src.substr(idx)
	return src.substr(idx, end - idx) + next_code_line(src, end)

static func next_code_line(src: String, from: int) -> String:
	var pos := from + 1
	while pos < src.length():
		var e := src.find("\n", pos)
		if e < 0:
			e = src.length()
		var line := src.substr(pos, e - pos).strip_edges()
		if line != "" and not line.begins_with("#"):
			return line
		pos = e + 1
	return ""

# 读文件源码；读不到返回空串（调用方要检查长度，否则路径写错会导致假通过）。
static func read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

# 某个函数从签名到下一个顶层 func 之间的源码。
static func func_body(src: String, func_sig: String) -> String:
	var idx := src.find(func_sig)
	if idx < 0:
		return ""
	var next_top := src.find("\nfunc ", idx + func_sig.length())
	if next_top < 0:
		return src.substr(idx)
	return src.substr(idx, next_top - idx)
