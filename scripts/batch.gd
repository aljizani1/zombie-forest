# ════════ تجميع الرسم ════════
# بدال ما كل شكل صغير ياخذ مكان لحاله بذاكرة كرت الشاشة (التلفون بالمتصفح ما يتحمل عشرات الآلاف)،
# نجمع كل المثلثات بمصفوفة وحدة ونرسمها مرة وحدة. نفس أسماء دوال الرسم مال Godot حتى الكود يبقى نفسه.
class_name Batch
extends RefCounted

var target: CanvasItem # null = نسجّل بس (parts) بدون رسم
var parts: Array = [] # [verts, cols, idx] لكل دفعة مسجلة
var verts := PackedVector2Array()
var cols := PackedColorArray()
var idx := PackedInt32Array()


func _init(ci: CanvasItem = null) -> void:
	target = ci


func _add(pts: PackedVector2Array, colors: PackedColorArray, tris: PackedInt32Array) -> void:
	# الدفعة كبرت هواي: نرسمها ونبدي وحدة جديدة (حتى أرقام النقاط تبقى صغيرة)
	if verts.size() > 50000:
		flush()
	var base := verts.size()
	verts.append_array(pts)
	cols.append_array(colors)
	for i in tris:
		idx.append(base + i)


func draw_polygon(pts: PackedVector2Array, colors: PackedColorArray) -> void:
	if pts.size() < 3:
		return
	if pts.size() == 3:
		_add(pts, colors, PackedInt32Array([0, 1, 2]))
		return
	if pts.size() == 4:
		_add(pts, colors, PackedInt32Array([0, 1, 2, 0, 2, 3]))
		return
	var t := Geometry2D.triangulate_polygon(pts)
	if t.is_empty():
		# شكل متداخل: نرسم الغلاف المحدّب
		var hull := Geometry2D.convex_hull(pts)
		if hull.size() < 4:
			return
		hull.remove_at(hull.size() - 1)
		var hc := PackedColorArray()
		hc.resize(hull.size())
		hc.fill(colors[0])
		pts = hull
		colors = hc
		t = Geometry2D.triangulate_polygon(pts)
	_add(pts, colors, t)


func draw_colored_polygon(pts: PackedVector2Array, col: Color) -> void:
	var c := PackedColorArray()
	c.resize(pts.size())
	c.fill(col)
	draw_polygon(pts, c)


func draw_rect(r: Rect2, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), col)


func draw_line(a: Vector2, b: Vector2, col: Color, w := 1.0, _aa := false) -> void:
	var d := b - a
	if d.length_squared() < 0.0001:
		return
	var n := Vector2(-d.y, d.x).normalized() * (w / 2)
	draw_colored_polygon(PackedVector2Array([a + n, b + n, b - n, a - n]), col)


# خط متعدد النقاط كشريط واحد (أسرع بهواي من خط لكل قطعة)
func draw_polyline(pts: PackedVector2Array, col: Color, w := 1.0, _aa := false) -> void:
	var n := pts.size()
	if n < 2:
		return
	if verts.size() > 50000:
		flush()
	var base := verts.size()
	var h := w / 2
	for i in n:
		var d := pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		var nn := Vector2(-d.y, d.x).normalized() * h
		verts.append(pts[i] + nn)
		verts.append(pts[i] - nn)
	var cc := PackedColorArray()
	cc.resize(n * 2)
	cc.fill(col)
	cols.append_array(cc)
	for i in n - 1:
		var a := base + i * 2
		idx.append(a)
		idx.append(a + 1)
		idx.append(a + 2)
		idx.append(a + 1)
		idx.append(a + 3)
		idx.append(a + 2)


func draw_circle(c: Vector2, r: float, col: Color) -> void:
	var n := clampi(int(r * 0.8), 8, 24)
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	var cc := PackedColorArray()
	cc.resize(n)
	cc.fill(col)
	var t := PackedInt32Array()
	for i in range(1, n - 1):
		t.append_array([0, i, i + 1])
	_add(pts, cc, t)


# نرسم كل اللي تجمّع على العقدة (مرة وحدة)
func flush() -> void:
	if idx.size():
		if target == null:
			parts.append([verts.duplicate(), cols.duplicate(), idx.duplicate()])
		else:
			RenderingServer.canvas_item_add_triangle_array(target.get_canvas_item(), idx, verts, cols)
	verts.clear()
	cols.clear()
	idx.clear()


# حدود كل اللي تسجّل
func bounds() -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for part in parts:
		for v in part[0]:
			lo = lo.min(v)
			hi = hi.max(v)
	return Rect2(lo, hi - lo)


# نرسم الدفعات المسجلة على عقدة
static func play(ci: CanvasItem, recorded: Array) -> void:
	for part in recorded:
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), part[2], part[0], part[1])
