# ════════ أداة الرسم ════════
# تشبه رسم الـ Canvas بالنسخة القديمة: save/restore/translate/rotate/scale وأشكال بتظليل.
# التظليل يصير بألوان على رؤوس المضلع (الضوء جاي من فوگ يسار)، فالـ GPU يرسمه بسرعة.
class_name Painter
extends RefCounted

const OUTLINE := Color("#1c1612")
const OL := 2.2
const LIGHT_DIR := Vector2(-0.6, -0.8)

var ci: CanvasItem
var xf := Transform2D.IDENTITY
var _stack: Array[Transform2D] = []
var alpha := 1.0
# لمعة الضربة (أبيض للزومبي، أحمر للاعب)
var flash := 0.0
var flash_to := Color.WHITE


func _init(item: CanvasItem) -> void:
	ci = item


func begin() -> void:
	xf = Transform2D.IDENTITY
	_stack.clear()
	alpha = 1.0
	flash = 0.0
	ci.draw_set_transform_matrix(xf)


func save() -> void:
	_stack.append(xf)


func restore() -> void:
	xf = _stack.pop_back()
	ci.draw_set_transform_matrix(xf)


func translate(x: float, y: float) -> void:
	xf = xf * Transform2D(0.0, Vector2(x, y))
	ci.draw_set_transform_matrix(xf)


func rotate(a: float) -> void:
	xf = xf * Transform2D(a, Vector2.ZERO)
	ci.draw_set_transform_matrix(xf)


func scale(sx: float, sy: float) -> void:
	xf = xf * Transform2D.IDENTITY.scaled(Vector2(sx, sy))
	ci.draw_set_transform_matrix(xf)


# ── ألوان ──
func c(col: Color) -> Color:
	var out := col.lerp(flash_to, flash) if flash > 0.0 else col
	out.a *= alpha
	return out


static func light(col: Color, k := 0.28) -> Color:
	return col.lerp(Color.WHITE, k)


static func dark(col: Color, k := 0.35) -> Color:
	return col.lerp(Color.BLACK, k)


# ── منحنيات ──
# نقاط منحنى تربيعي من a إلى b (بدون a)
static func quad(pts: PackedVector2Array, ctrl: Vector2, b: Vector2, n := 6) -> void:
	var a := pts[pts.size() - 1]
	for i in range(1, n + 1):
		var t := float(i) / n
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))


static func arc_pts(pts: PackedVector2Array, center: Vector2, r: float, a0: float, a1: float, n := 8) -> void:
	for i in range(n + 1):
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(center + Vector2(cos(a), sin(a)) * r)


static func ellipse_pts(center: Vector2, rx: float, ry: float, rot := 0.0, n := 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cr := cos(rot)
	var sr := sin(rot)
	for i in n:
		var a := TAU * i / n
		var p := Vector2(cos(a) * rx, sin(a) * ry)
		pts.append(center + Vector2(p.x * cr - p.y * sr, p.x * sr + p.y * cr))
	return pts


static func rect_pts(x: float, y: float, w: float, h: float, r := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if r <= 0.0:
		pts.append_array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)])
		return pts
	r = minf(r, minf(absf(w), absf(h)) / 2)
	arc_pts(pts, Vector2(x + w - r, y + r), r, -PI / 2, 0, 3)
	arc_pts(pts, Vector2(x + w - r, y + h - r), r, 0, PI / 2, 3)
	arc_pts(pts, Vector2(x + r, y + h - r), r, PI / 2, PI, 3)
	arc_pts(pts, Vector2(x + r, y + r), r, PI, PI * 1.5, 3)
	return pts


# ── أشكال ──
# مضلع بتظليل (فاتح من فوگ يسار، غامق من تحت يمين) + خط خارجي
func shade(pts: PackedVector2Array, base: Color, outline := true, k := 0.3) -> void:
	if pts.size() < 3:
		return
	var lo := INF
	var hi := -INF
	for p in pts:
		var d := p.dot(LIGHT_DIR)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	var span := maxf(0.001, hi - lo)
	var cols := PackedColorArray()
	var lt := c(light(base, k))
	var mid := c(base)
	var dk := c(dark(base, k))
	for p in pts:
		var t := (p.dot(LIGHT_DIR) - lo) / span # 1 = جهة الضوء
		cols.append(mid.lerp(lt, (t - 0.5) * 2) if t > 0.5 else dk.lerp(mid, t * 2))
	tris(pts, cols)
	if outline:
		line_loop(pts, OUTLINE, OL)


func fill(pts: PackedVector2Array, col: Color) -> void:
	if pts.size() >= 3:
		var cols := PackedColorArray()
		cols.resize(pts.size())
		cols.fill(c(col))
		tris(pts, cols)


# نقسّم المضلع مثلثات بأنفسنا؛ إذا الشكل متداخل (نادر بالأنيميشن) نرسم الغلاف المحدّب بداله
func tris(pts: PackedVector2Array, cols: PackedColorArray) -> void:
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		var hull := Geometry2D.convex_hull(pts)
		if hull.size() < 4:
			return
		hull.remove_at(hull.size() - 1)
		var hc := PackedColorArray()
		for p in hull:
			hc.append(cols[_nearest(pts, p)])
		pts = hull
		cols = hc
		idx = Geometry2D.triangulate_polygon(pts)
		if idx.is_empty():
			return
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)


static func _nearest(pts: PackedVector2Array, p: Vector2) -> int:
	for i in pts.size():
		if pts[i].is_equal_approx(p):
			return i
	return 0


func line_loop(pts: PackedVector2Array, col: Color, w: float) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, c(col), w, true)


func line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	ci.draw_line(a, b, c(col), w, true)


func polyline(pts: PackedVector2Array, col: Color, w: float) -> void:
	if pts.size() >= 2:
		ci.draw_polyline(pts, c(col), w, true)


func circle(center: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(center, r, c(col))


# دايرة بتظليل
func blob(center: Vector2, r: float, base: Color, outline := true) -> void:
	shade(ellipse_pts(center, r, r, 0.0, 16), base, outline)


# توهج: لون بالنص ويختفي للأطراف
func glow(center: Vector2, r: float, inner: Color, outer: Color, n := 20) -> void:
	var pts := PackedVector2Array([center])
	var cols := PackedColorArray([c(inner)])
	for i in n + 1:
		var a := TAU * i / n
		pts.append(center + Vector2(cos(a), sin(a)) * r)
		cols.append(c(outer))
	# مروحة مثلثات
	for i in n:
		ci.draw_polygon(PackedVector2Array([pts[0], pts[i + 1], pts[i + 2]]), PackedColorArray([cols[0], cols[i + 1], cols[i + 2]]))


# طرف (ذراع/رجل) بشكل كبسولة مظللة
func limb(a: Vector2, b: Vector2, w1: float, w2: float, base: Color) -> void:
	var d := b - a
	var ang := d.angle()
	var pts := PackedVector2Array()
	arc_pts(pts, b, w2 / 2, ang - PI / 2, ang + PI / 2, 5)
	arc_pts(pts, a, w1 / 2, ang + PI / 2, ang + PI * 1.5, 5)
	shade(pts, base)
