extends RefCounted

# 敌人合批的跟随代理（EnemyDraw.gd 的搭档；独立文件走项目 const+preload 约定）。
#
# 为什么需要它：EnemyShape 的绘制函数内部会 draw_set_transform 做绝对复位
# （显式多边形阴影拒绝跟随 squash 的刻意设计，见 EnemyShape.ground_shadow 注释），
# 所以合批节点不能"设一次每怪变换再复用它们"。
#
# 它复刻 CanvasItem 的变换语义：draw_set_transform 是绝对设置（非叠加），
# 绘制点 = frame × xform × 局部点；把收到的每个 draw_* 转写到真正的绘制节点
# （EnemyDraw 自身，此刻正在执行 _draw）。与原"每只怪自己是 CanvasItem"时
# 引擎的语义逐字一致 —— 这是合批后画面与合批前逐像素相同的关键。
#
# line/arc 线宽不吃画布缩放（引擎行为），原样透传天然一致。
# 只转发本项目 EnemyShape/绘制序列用到的 7 个 draw_*。
# 全局一只，每只怪 begin() 重置帧偏移（稳态零分配）。

var _target: CanvasItem = null
var _frame := Transform2D.IDENTITY
var _xform := Transform2D.IDENTITY

# offset = 该怪相对合批节点的位置（等价于"这只怪自己是 CanvasItem"的节点变换）
func begin(target: CanvasItem, offset: Vector2) -> void:
	_target = target
	_frame = _mk(0.0, offset, Vector2.ONE)
	_xform = Transform2D.IDENTITY
	_apply()

func draw_set_transform(pos: Vector2, rot: float = 0.0, scl: Vector2 = Vector2.ONE) -> void:
	_xform = _mk(rot, pos, scl)
	_apply()

# rot+pos+scale → Transform2D。Godot 4 没有 float,Vector2,Vector2 构造器，
# 用有文档的三 Vector2 形式手搭基向量（避免 API 猜测）。
static func _mk(rot: float, pos: Vector2, scl: Vector2) -> Transform2D:
	var cr := cos(rot)
	var sr := sin(rot)
	return Transform2D(Vector2(cr, sr) * scl.x, Vector2(-sr, cr) * scl.y, pos)

func _apply() -> void:
	var t := _frame * _xform
	_target.draw_set_transform(t.origin, t.get_rotation(), t.get_scale())

func draw_circle(position: Vector2, radius: float, color: Color,
		filled: bool = true, width: float = -1.0, antialiased: bool = false) -> void:
	_target.draw_circle(position, radius, color, filled, width, antialiased)

func draw_line(from: Vector2, to: Vector2, color: Color,
		width: float = -1.0, antialiased: bool = false) -> void:
	_target.draw_line(from, to, color, width, antialiased)

func draw_colored_polygon(points: PackedVector2Array, color: Color,
		uvs: PackedVector2Array = PackedVector2Array(), texture: Texture2D = null) -> void:
	_target.draw_colored_polygon(points, color, uvs, texture)

func draw_rect(rect: Rect2, color: Color,
		filled: bool = true, width: float = -1.0, antialiased: bool = false) -> void:
	_target.draw_rect(rect, color, filled, width, antialiased)

func draw_arc(center: Vector2, radius: float, start: float, end: float,
		point_count: int, color: Color, width: float = -1.0, aa: bool = false) -> void:
	_target.draw_arc(center, radius, start, end, point_count, color, width, aa)

func draw_texture_rect_region(tex: Texture2D, rect: Rect2, region: Rect2,
		color: Color = Color(1, 1, 1), transpose: bool = false,
		antialiased: bool = true) -> void:
	_target.draw_texture_rect_region(tex, rect, region, color, transpose, antialiased)
