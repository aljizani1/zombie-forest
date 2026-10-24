# ════════ رسم الطبيعة (السما، الغيوم، الجبال، الغابة، الأرض، المنصات، الأشجار) ════════
# - السما ثابتة بالشاشة، والغيوم والجبال طبقات Parallax2D تتحرك أبطأ من الكاميرا (عمق).
# - كل شي ثابت ينرسم مرة وحدة على صورة (SubViewport) وبعدها نعرض الصورة بس: رسمها ما يكلف شي.
# - الأرض بقطع (chunk): نخلي بس الصور القريبة من الكاميرا بالذاكرة (التلفون بالمتصفح ذاكرته محدودة).
extends Node2D

const DRAWN := preload("res://scripts/drawn.gd")
const CHUNK := 1024.0
const STRIP := 2048.0
const AH := 720.0
const NEAR := 2 # كم قطعة نخلي يمين ويسار الكاميرا

const LEAF := {
	"oak": [Color("#2f6a2c"), Color("#4a9436"), Color("#6cb845"), Color("#9fd768")],
	"birch": [Color("#5b7a28"), Color("#86a83a"), Color("#aecb4c"), Color("#d6e47c")],
	"pine": [Color("#1f4f33"), Color("#2f6b45"), Color("#3f8a55"), Color("#62a86c")],
}

var map: World
var _sky: Node2D
var _chunks: Array = [] # لكل قطعة: {back, front} (الرسم المسجل)
var _baked := {} # رقم القطعة ← العقد (صور + SubViewport)


static func V(x: float, y: float) -> Vector2:
	return Vector2(x, y)


static func seed_of(a: float, b: float, c := 7.0) -> int:
	return int(a) * 73856093 ^ int(b) * 19349663 ^ int(c) * 83492791


static func rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


# عقدة ترسم نفسها مباشرة (للأشياء الصغيرة)
func _node(parent: Node, fn: Callable) -> Node2D:
	var n: Node2D = DRAWN.new()
	n.fn = func(ci: CanvasItem) -> void:
		var b := Batch.new(ci)
		fn.call(b)
		b.flush()
	parent.add_child(n)
	return n


# نسجل الرسم (بدون ما نرسم) ونحسب حدوده
func _record(fn: Callable) -> Dictionary:
	var b := Batch.new()
	fn.call(b)
	b.flush()
	if b.parts.is_empty():
		return {}
	var r := b.bounds()
	r.end = Vector2(r.end.x, minf(r.end.y, AH + 8)) # تحت الشاشة ما يبين
	return {parts = b.parts, rect = r}


# نرسم المسجل على صورة مرة وحدة، ونرجع [SubViewport, Sprite2D]
func _bake(rec: Dictionary, parent: Node, z: int, rect := Rect2()) -> Array:
	if rec.is_empty():
		return []
	var r: Rect2 = rect if rect.size != Vector2.ZERO else Rect2(rec.rect.position.floor() - V(1, 1), rec.rect.size.ceil() + V(2, 2))
	var vp := SubViewport.new()
	vp.size = Vector2i(maxi(1, ceili(r.size.x)), maxi(1, ceili(r.size.y)))
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var n: Node2D = DRAWN.new()
	n.position = -r.position
	n.fn = func(ci: CanvasItem) -> void: Batch.play(ci, rec.parts)
	vp.add_child(n)
	add_child(vp)
	var spr := Sprite2D.new()
	spr.texture = vp.get_texture()
	spr.centered = false
	spr.position = r.position
	spr.z_index = z
	parent.add_child(spr)
	return [vp, spr]


func setup(m: World) -> void:
	map = m
	# ── السما (ثابتة بالشاشة) ──
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -10
	add_child(sky_layer)
	_sky = _node(sky_layer, _draw_sky)
	get_viewport().size_changed.connect(_sky.queue_redraw)

	# ── الغيوم والجبال والغابة البعيدة ──
	_parallax(0.05, Vector2(-10, 0), _draw_clouds)
	_parallax(0.1, Vector2.ZERO, _draw_far)
	_parallax(0.25, Vector2.ZERO, _draw_mid)
	_parallax(0.5, Vector2.ZERO, _draw_forest)

	# ── ظلمة الحفر ──
	var abyss := _node(self, func(ci) -> void:
		_vgrad(ci, 0, map.width, AH - 90, AH + 2, [Color(0.08, 0.05, 0.04, 0), Color(0.08, 0.05, 0.04, 0.85), Color(0.08, 0.05, 0.04, 0.95)], [0.0, 0.25, 1.0]))
	abyss.z_index = -1

	# ── قطع الأرض (كل شي ينحط بالقطعة اللي بيها نصه) ──
	var n := ceili(map.width / CHUNK)
	var lists := []
	for i in n:
		lists.append({trees = [], ground = [], plats = [], decor = []})
	var ci_of := func(x: float) -> int: return clampi(int(x / CHUNK), 0, n - 1)
	for t in map.trees:
		lists[ci_of.call(t.x)].trees.append(t)
	for b in map.ground:
		lists[ci_of.call((b.x0 + b.x1) / 2)].ground.append(b)
	for p in map.platforms:
		lists[ci_of.call((p.x0 + p.x1) / 2)].plats.append(p)
	for d in map.decor:
		lists[ci_of.call(d.x)].decor.append(d)
	for L in lists:
		# الأشجار ورا، والأرض والمنصات والزينة قدّام
		_chunks.append({
			back = _record(func(ci): for t in L.trees: draw_tree(ci, t.x, t.y + 6, t.kind, t.size, seed_of(t.x, t.y, 17))),
			front = _record(func(ci):
				for b in L.ground: _draw_ground(ci, b)
				for p in L.plats: _draw_platform(ci, p)
				for d in L.decor: draw_decor(ci, d.kind, d.x, d.y, seed_of(d.x, d.y, 5))),
		})


# نخلي بس القطع القريبة من الكاميرا مرسومة
func _process(_dt: float) -> void:
	if _chunks.is_empty():
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var c := int(cam.get_screen_center_position().x / CHUNK)
	for i in _baked.keys():
		if absi(i - c) > NEAR:
			for node in _baked[i]:
				node.queue_free()
			_baked.erase(i)
	for i in range(c - NEAR, c + NEAR + 1):
		if i < 0 or i >= _chunks.size() or _baked.has(i):
			continue
		_baked[i] = _bake(_chunks[i].back, self, -2) + _bake(_chunks[i].front, self, 0)


func _parallax(f: float, auto: Vector2, fn: Callable) -> void:
	var p := Parallax2D.new()
	p.scroll_scale = Vector2(f, 1) # عمودياً تتحرك ويا العالم (لمن الكاميرا تنزل تحت الأرض)
	p.repeat_size = Vector2(STRIP, 0)
	p.repeat_times = 3
	p.autoscroll = auto
	p.z_index = -5
	add_child(p)
	var rec := _record(fn)
	if rec.is_empty():
		return
	# الصورة بعرض الشريط بالضبط حتى تتكرر بدون فراغات
	var top: float = floorf(rec.rect.position.y) - 1
	_bake(rec, p, 0, Rect2(0, top, STRIP, rec.rect.end.y - top + 1))


# ── أدوات رسم ──
# تدرّج عمودي على مستطيل (ألوان على نقاط)
static func _vgrad(ci, x0: float, x1: float, y0: float, y1: float, cols: Array, stops: Array) -> void:
	for i in cols.size() - 1:
		var a := lerpf(y0, y1, stops[i])
		var b := lerpf(y0, y1, stops[i + 1])
		ci.draw_polygon(PackedVector2Array([V(x0, a), V(x1, a), V(x1, b), V(x0, b)]), PackedColorArray([cols[i], cols[i], cols[i + 1], cols[i + 1]]))


# دايرة بتدرّج (نقطة الضوء مزاحة لفوگ يسار)
static func disc(ci, c: Vector2, r: float, inner: Color, outer: Color, n := 14) -> void:
	var f := c + V(-r * 0.35, -r * 0.4)
	var pts := PackedVector2Array([f])
	var cols := PackedColorArray([inner])
	for i in n + 1:
		var a := TAU * i / n
		pts.append(c + V(cos(a), sin(a)) * r)
		cols.append(outer)
	for i in n:
		ci.draw_polygon(PackedVector2Array([pts[0], pts[i + 1], pts[i + 2]]), PackedColorArray([cols[0], cols[i + 1], cols[i + 2]]))


static func ellipse(ci, c: Vector2, rx: float, ry: float, rot: float, col: Color, n := 10) -> void:
	ci.draw_colored_polygon(Painter.ellipse_pts(c, rx, ry, rot, n), col)


# ── السما + الشمس ──
func _draw_sky(ci) -> void:
	var s := get_viewport().get_visible_rect().size
	_vgrad(ci, 0, s.x, 0, s.y, [Color("#3d84c6"), Color("#7dbbe5"), Color("#cbe7f1"), Color("#e8f3e4")], [0.0, 0.5, 0.85, 1.0])
	var sun := V(s.x * 0.8, s.y * 0.1)
	var R := s.y * 0.45
	# حلقات توهج
	var rings := [[0.0, Color(1, 0.99, 0.9, 1)], [0.12, Color(1, 0.96, 0.82, 0.9)], [0.4, Color(1, 0.94, 0.78, 0.25)], [1.0, Color(1, 0.94, 0.78, 0)]]
	var n := 32
	for k in rings.size() - 1:
		var r0: float = rings[k][0] * R
		var r1: float = rings[k + 1][0] * R
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			var p := PackedVector2Array([sun + V(cos(a0), sin(a0)) * r0, sun + V(cos(a1), sin(a1)) * r0, sun + V(cos(a1), sin(a1)) * r1, sun + V(cos(a0), sin(a0)) * r1])
			ci.draw_polygon(p, PackedColorArray([rings[k][1], rings[k][1], rings[k + 1][1], rings[k + 1][1]]))


# ── الغيوم ──
func _draw_clouds(ci) -> void:
	var r := rng(5)
	for i in ceili(STRIP / 260):
		var cx := (i + r.randf() * 0.6) * 260
		var cy := 50 + r.randf() * 150
		var w := 110 + r.randf() * 150
		for k in 11:
			var t := k / 10.0
			var p := V(cx - w / 2 + t * w + (r.randf() - 0.5) * 20, cy - sin(t * PI) * (18 + r.randf() * 22))
			var rad := maxf(6, 18 + r.randf() * 22 * sin(t * PI + 0.3))
			for dx in [0.0, -STRIP, STRIP]:
				if p.x + dx > -60 and p.x + dx < STRIP + 60:
					disc(ci, p + V(dx, 0), rad, Color.WHITE, Color("#d6e3ee"))


# خط قمم يتكرر كل STRIP
static func ridge(base: float, amp: float, s: int, step: float) -> PackedVector2Array:
	var r := rng(s)
	var k := [2 + r.randi() % 2, 5 + r.randi() % 3, 11 + r.randi() % 5]
	var ph := [r.randf() * 9, r.randf() * 9, r.randf() * 9]
	var pts := PackedVector2Array()
	var x := 0.0
	while x <= STRIP + 0.1:
		var t := x / STRIP * TAU
		pts.append(V(x, base - amp * (0.55 * absf(sin(t * k[0] * 0.5 + ph[0])) + 0.3 * absf(sin(t * k[1] * 0.5 + ph[1])) + 0.15 * sin(t * k[2] + ph[2]))))
		x += step
	return pts


# الجبل كشرائط عمودية (حتى التدرّج يكون مضبوط والمضلع ما يتعقد)
static func fill_ridge(ci, pts: PackedVector2Array, top: Color, bottom: Color, y_top: float, y_bot: float, snow := false) -> void:
	var col_at := func(y: float) -> Color: return top.lerp(bottom, clampf((y - y_top) / (y_bot - y_top), 0, 1))
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		ci.draw_polygon(PackedVector2Array([a, b, V(b.x, AH + 300), V(a.x, AH + 300)]),
			PackedColorArray([col_at.call(a.y), col_at.call(b.y), bottom, bottom]))
		if snow:
			# ثلج على القمم العالية
			var sa := clampf(1 - (a.y - 200) / 130, 0, 0.95)
			var sb := clampf(1 - (b.y - 200) / 130, 0, 0.95)
			if sa > 0 or sb > 0:
				var ea := maxf(a.y, 330.0)
				var eb := maxf(b.y, 330.0)
				ci.draw_polygon(PackedVector2Array([a, b, V(b.x, eb), V(a.x, ea)]),
					PackedColorArray([Color(0.98, 0.99, 1, sa), Color(0.98, 0.99, 1, sb), Color(0.98, 0.99, 1, 0), Color(0.98, 0.99, 1, 0)]))


func _draw_far(ci) -> void:
	fill_ridge(ci, ridge(470, 260, 3, 10), Color("#8fa9c2"), Color("#c8d9e4"), 210, 520, true)


func _draw_mid(ci) -> void:
	fill_ridge(ci, ridge(530, 190, 8, 8), Color("#6e9a84"), Color("#a9c8b6"), 340, 560)
	_vgrad(ci, 0, STRIP, 420, AH + 300, [Color(0.88, 0.93, 0.93, 0), Color(0.88, 0.93, 0.93, 0.45), Color(0.88, 0.93, 0.93, 0.45)], [0.0, 0.33, 1.0])


func _draw_forest(ci) -> void:
	var r := rng(11)
	for row in 2:
		var base_y := 575.0 + row * 22
		var cols: Array = [Color("#35664a"), Color("#4c7f57"), Color("#6a9c68")] if row else [Color("#4f7f68"), Color("#62927a"), Color("#86b293")]
		var x := 0.0
		while x < STRIP:
			var h := (70.0 if row else 55.0) + r.randf() * 50
			var cone := r.randf() < 0.5
			var rad := 14 + r.randf() * 10
			for dx in [0.0, -STRIP, STRIP]:
				var xx: float = x + dx
				if xx < -40 or xx > STRIP + 40:
					continue
				if cone:
					ci.draw_polygon(PackedVector2Array([V(xx, base_y - h), V(xx - 15, base_y), V(xx + 15, base_y)]), PackedColorArray([cols[1], cols[2], cols[0]]))
				else:
					ci.draw_rect(Rect2(xx - 2, base_y - h * 0.6, 4, h * 0.6), cols[0])
					disc(ci, V(xx, base_y - h * 0.6), rad, cols[2], cols[0], 12)
			x += 10 + r.randf() * 14
		ci.draw_rect(Rect2(-20, base_y - 2, STRIP + 40, AH + 300), cols[0])


# ── الأشجار والزينة ──
static func leaf_clump(ci, x: float, y: float, r: float, pal: Array, rnd: RandomNumberGenerator) -> void:
	disc(ci, V(x, y), r, pal[3], pal[0], 14)
	var n := roundi(r * 0.4)
	for i in n:
		var a := rnd.randf() * TAU
		var d := sqrt(rnd.randf()) * r * 0.9
		var lx := x + cos(a) * d
		var ly := y + sin(a) * d
		var top := ly < y - r * 0.2 and lx < x + r * 0.2
		var col: Color = pal[3] if top else (pal[1] if rnd.randf() < 0.5 else pal[0])
		col.a = 0.55
		ellipse(ci, V(lx, ly), 2.6, 1.5, rnd.randf() * PI, col, 6)


static func draw_tree(ci, x: float, base: float, kind: String, size: float, s: int) -> void:
	var rnd := rng(s)
	var pal: Array = LEAF[kind]
	if kind == "pine":
		var h := 330 * size
		var w := 44 * size
		ci.draw_polygon(Painter.rect_pts(x - 7 * size, base - 70 * size, 14 * size, 72 * size), PackedColorArray([Color("#7a5034"), Color("#3e2616"), Color("#3e2616"), Color("#7a5034")]))
		for i in 7:
			var k := i / 7.0
			var ty := base - 60 * size - k * (h - 70 * size)
			var tw := w * (2.2 - k * 1.7)
			var pts := PackedVector2Array([V(x, ty - 70 * size)])
			Painter.quad(pts, V(x - tw * 0.4, ty - 20 * size), V(x - tw, ty), 5)
			Painter.quad(pts, V(x, ty - 10 * size), V(x + tw, ty), 5)
			Painter.quad(pts, V(x + tw * 0.4, ty - 20 * size), V(x, ty - 70 * size), 5)
			pts.remove_at(pts.size() - 1)
			var cols := PackedColorArray()
			for p in pts:
				var t := clampf((p.x - (x - tw)) / (2 * tw), 0, 1)
				cols.append(pal[3].lerp(pal[2], t * 2.5) if t < 0.4 else pal[2].lerp(pal[0], (t - 0.4) / 0.6))
			ci.draw_polygon(pts, cols)
		return
	var birch := kind == "birch"
	var th := (200.0 if birch else 170.0) * size
	var tw := (15.0 if birch else 26.0) * size
	var trunk := PackedVector2Array([V(x - tw * 1.1, base + 4)])
	Painter.quad(trunk, V(x - tw * 0.55, base - 10), V(x - tw * 0.5, base - 40), 4)
	trunk.append(V(x - tw * 0.32, base - th))
	trunk.append(V(x + tw * 0.32, base - th))
	trunk.append(V(x + tw * 0.5, base - 40))
	Painter.quad(trunk, V(x + tw * 0.55, base - 10), V(x + tw * 1.1, base + 4), 4)
	var tc := PackedColorArray()
	var c0 := Color("#f5f1e6") if birch else Color("#8f6040")
	var c1 := Color("#9c947f") if birch else Color("#3a2414")
	for p in trunk:
		tc.append(c0.lerp(c1, clampf((p.x - (x - tw)) / (2 * tw), 0, 1)))
	ci.draw_polygon(trunk, tc)
	for i in (14 if birch else 9):
		var yy := base - 20 - rnd.randf() * (th - 30)
		if birch:
			var xx := x - tw * 0.4 + rnd.randf() * tw * 0.4
			ci.draw_line(V(xx, yy), V(xx + tw * 0.35, yy + 1), Color("#2c2a26"), 2.2)
		else:
			var xx := x - tw * 0.35 + rnd.randf() * tw * 0.7
			var pts := PackedVector2Array([V(xx, yy)])
			Painter.quad(pts, V(xx + 2, yy - 15), V(xx, yy - 30), 4)
			ci.draw_polyline(pts, Color(0.12, 0.07, 0.04, 0.5), 1.4)
	for side in [-1.0, 1.0]:
		var pts := PackedVector2Array([V(x, base - th * 0.7)])
		Painter.quad(pts, V(x + side * 30 * size, base - th * 0.85), V(x + side * 50 * size, base - th * 1.02), 6)
		ci.draw_polyline(pts, Color("#cfc8b5") if birch else Color("#5a3a24"), tw * 0.35, true)
	var cy := base - th - 10 * size
	var R := (62.0 if birch else 92.0) * size
	var clumps := []
	for i in (16 if birch else 26):
		var a := rnd.randf() * TAU
		var d := sqrt(rnd.randf())
		clumps.append(Vector3(x + cos(a) * R * d, cy + sin(a) * R * 0.62 * d, (20.0 if birch else 27.0) * size * (0.7 + rnd.randf() * 0.5)))
	clumps.sort_custom(func(a, b): return a.y < b.y)
	for cl in clumps:
		leaf_clump(ci, cl.x, cl.y, cl.z, pal, rnd)


static func draw_decor(ci, kind: String, x: float, y: float, s: int) -> void:
	var r := rng(s)
	match kind:
		"bush":
			var w := 40 + r.randf() * 30
			var base := y + 4
			var n := maxi(3, roundi(w / 14))
			var clumps := []
			for i in n:
				var k := (i + 0.5) / n
				clumps.append(Vector3(x - w / 2 + k * w + (r.randf() - 0.5) * 6, base - 10 - sin(k * PI) * 10 - r.randf() * 5, 11 + r.randf() * 7))
			clumps.sort_custom(func(a, b): return a.y < b.y)
			for cl in clumps:
				leaf_clump(ci, cl.x, cl.y, cl.z, [Color("#2d6a2b"), Color("#4a9938"), Color("#73c049"), Color("#a6dc6c")], r)
		"rock":
			var w := 24 + r.randf() * 16
			var base := y + 3
			var h := w * (0.55 + r.randf() * 0.2)
			var pts := PackedVector2Array([V(x - w / 2, base + 2)])
			Painter.quad(pts, V(x - w / 2, base - h), V(x, base - h), 5)
			Painter.quad(pts, V(x + w / 2, base - h), V(x + w / 2, base + 2), 5)
			var cols := PackedColorArray()
			for p in pts:
				cols.append(Color("#c4cbc6").lerp(Color("#59625e"), clampf((p.x - x + w / 2) / w * 0.6 + (p.y - base + h) / h * 0.4, 0, 1)))
			ci.draw_polygon(pts, cols)
			ellipse(ci, V(x - w * 0.05, base - h * 0.93), w * 0.3, h * 0.14, -0.1, Color(0.38, 0.63, 0.24, 0.75))
		"mushroom":
			var base := y + 2
			ci.draw_rect(Rect2(x - 2, base - 7, 4, 7), Color("#efe4cc"))
			var cap := PackedVector2Array()
			Painter.arc_pts(cap, V(0, 0), 1, PI, TAU, 8)
			for i in cap.size():
				cap[i] = V(x + cap[i].x * 7, base - 8 + cap[i].y * 5)
			ci.draw_colored_polygon(cap, Color("#d8402e"))
			ci.draw_circle(V(x - 3, base - 10), 1.2, Color("#fff4ea"))
			ci.draw_circle(V(x + 2, base - 11), 1.0, Color("#fff4ea"))
		_:
			for i in 3:
				var fx := x - 7 + i * 7
				var base := y + 2
				var h := 8 + r.randf() * 8
				var stem := PackedVector2Array([V(fx, base)])
				Painter.quad(stem, V(fx + 2, base - h / 2), V(fx, base - h), 4)
				ci.draw_polyline(stem, Color("#3f8a2f"), 1.4)
				var col: Color = [Color("#fff6e0"), Color("#ffd7e8"), Color("#ffe36b")][r.randi() % 3]
				for k in 5:
					var a := k / 5.0 * TAU
					ci.draw_circle(V(fx + cos(a) * 2.6, base - h + sin(a) * 2.6), 2, col)
				ci.draw_circle(V(fx, base - h), 1.6, Color("#f2b632"))


# ── التراب والعشب ──
# عشب: شفرات منحنية
static func blades(ci, x0: float, x1: float, y: float, rnd: RandomNumberGenerator, density: float, h_max: float) -> void:
	var cols := [Color("#4e9a30"), Color("#62b03b"), Color("#78c34a"), Color("#91d45e"), Color("#3f8a2a")]
	var x := x0
	while x < x1:
		var h := h_max * (0.4 + rnd.randf() * 0.6)
		var bend := (rnd.randf() - 0.5) * h * 0.8
		ci.draw_polyline(PackedVector2Array([V(x, y + 3), V(x + bend * 0.3, y - h * 0.6), V(x + bend, y - h)]), cols[rnd.randi() % 5], 1.4 + rnd.randf() * 1.2)
		x += density * (0.6 + rnd.randf() * 0.8)


# بقع وحجار بالتراب (بس داخل المضلع: نعطيه دالة تقول الحد السفلي عند x)
static func soil_bits(ci, x0: float, x1: float, top: float, bottom_at: Callable, rnd: RandomNumberGenerator) -> void:
	var area := (x1 - x0) * 160
	for i in int(area / 700):
		var x := x0 + rnd.randf() * (x1 - x0)
		var y: float = top + 18 + rnd.randf() * (float(bottom_at.call(x)) - top - 18)
		var r := 1 + rnd.randf() * 3
		var col := Color(0.12, 0.07, 0.04, 0.45) if rnd.randf() < 0.5 else Color(0.63, 0.47, 0.31, 0.25)
		ellipse(ci, V(x, y), r * 1.4, r, rnd.randf(), col, 6)
	for i in int(area / 4000):
		var x := x0 + rnd.randf() * (x1 - x0)
		var y := top + 26 + rnd.randf() * maxf(0, float(bottom_at.call(x)) - top - 40)
		var w := 7 + rnd.randf() * 12
		var pts := Painter.ellipse_pts(V(x, y), w, w * 0.65, rnd.randf() * 0.5, 10)
		var cols := PackedColorArray()
		for p in pts:
			cols.append(Color("#a58b70").lerp(Color("#4a3826"), clampf(((p - V(x, y)).dot(V(0.6, 0.8)) / w + 1) / 2, 0, 1)))
		ci.draw_polygon(pts, cols)
	# جذور
	for i in int((x1 - x0) / 60):
		var x := x0 + rnd.randf() * (x1 - x0)
		var len := rnd.randf() * 20
		var pts := PackedVector2Array([V(x, top + 14)])
		Painter.quad(pts, V(x + 6, top + 34), V(x + 4, top + 50 + len), 5)
		ci.draw_polyline(pts, Color(0.24, 0.14, 0.07, 0.7), 1.6)


# شريط العشب فوق التراب
static func grass_top(ci, x0: float, x1: float, top: float, rnd: RandomNumberGenerator) -> void:
	var x := x0
	while x < x1:
		var nx := minf(x + 8, x1)
		var ya := top + 12 + sin(x * 0.3) * 2 + rnd.randf() * 5
		var yb := top + 12 + sin(nx * 0.3) * 2 + rnd.randf() * 5
		ci.draw_polygon(PackedVector2Array([V(x, top - 3), V(nx, top - 3), V(nx, top + 4), V(x, top + 4)]), PackedColorArray([Color("#9ad85c"), Color("#9ad85c"), Color("#6db43f"), Color("#6db43f")]))
		ci.draw_polygon(PackedVector2Array([V(x, top + 4), V(nx, top + 4), V(nx, yb), V(x, ya)]), PackedColorArray([Color("#6db43f"), Color("#6db43f"), Color("#3f7f2a"), Color("#3f7f2a")]))
		x = nx


func _draw_ground(ci, b: Dictionary) -> void:
	var r := rng(seed_of(b.x0, b.x1, b.y))
	_vgrad(ci, b.x0, b.x1, b.y, AH + 300, [Color("#74502f"), Color("#56391f"), Color("#2b1b10"), Color("#2b1b10")], [0.0, 0.12, 0.35, 1.0])
	soil_bits(ci, b.x0, b.x1, b.y, func(_x): return AH + 40, r)
	# حواف الجرف
	for e in [[b.x0, 1.0], [b.x1, -1.0]]:
		var ex: float = e[0]
		var dir: float = e[1]
		var cont := false
		for o in map.ground:
			if o != b and o.y <= b.y and ((o.x1 >= ex and o.x0 < ex) if dir > 0 else (o.x0 <= ex and o.x1 > ex)):
				cont = true
		if cont:
			continue
		var x2 := ex + dir * 16
		ci.draw_polygon(PackedVector2Array([V(ex, b.y + 6), V(x2, b.y + 6), V(x2, AH + 300), V(ex, AH + 300)]),
			PackedColorArray([Color(0.1, 0.06, 0.03, 0.65), Color(0.1, 0.06, 0.03, 0), Color(0.1, 0.06, 0.03, 0), Color(0.1, 0.06, 0.03, 0.65)]))
		ci.draw_line(V(ex, b.y + 2), V(ex, AH + 300), Color(0.12, 0.07, 0.04, 0.7), 2)
	grass_top(ci, b.x0, b.x1, b.y, r)
	blades(ci, b.x0, b.x1, b.y, r, 2.6, 16)


func _draw_platform(ci, p: Dictionary) -> void:
	# ظل المنصة على الأرض
	var cx: float = (p.x0 + p.x1) / 2
	var gy = map.ground_at(cx)
	if gy != null and gy > p.y:
		ellipse(ci, V(cx, gy + 4), (p.x1 - p.x0) / 2, 7, 0, Color(0, 0, 0, 0.12), 20)
	var r := rng(seed_of(p.x0, p.x1, p.y + 3))
	var n := maxi(6, roundi((p.x1 - p.x0) / 24))
	var depth := minf(46, 16 + (p.x1 - p.x0) / 10)
	var x0: float = p.x0 - 6
	var x1: float = p.x1 + 6
	var under := PackedFloat32Array()
	for i in n + 1:
		var k := float(i) / n
		under.append(p.y + 24 + sin(k * PI) * depth + ((r.randf() - 0.5) * 14 if i > 0 and i < n else 0.0))
	var bottom_at := func(x: float) -> float:
		var k := clampf((x - x0) / (x1 - x0), 0, 1) * n
		var i := mini(int(k), n - 1)
		return lerpf(under[i], under[i + 1], k - i)
	# التراب كشرائط عمودية (المضلع السفلي مو محدّب)
	for i in n:
		var xa := lerpf(x0, x1, float(i) / n)
		var xb := lerpf(x0, x1, float(i + 1) / n)
		var top_c := Color("#74502f")
		var bot := Color("#3a2414")
		ci.draw_polygon(PackedVector2Array([V(xa, p.y), V(xb, p.y), V(xb, under[i + 1]), V(xa, under[i])]),
			PackedColorArray([top_c, top_c, top_c.lerp(bot, (under[i + 1] - p.y) / 80), top_c.lerp(bot, (under[i] - p.y) / 80)]))
	soil_bits(ci, x0 + 8, x1 - 8, p.y, func(x): return bottom_at.call(x) - 4, r)
	var outline := PackedVector2Array([V(x0, p.y)])
	for i in n + 1:
		outline.append(V(lerpf(x0, x1, float(i) / n), under[i]))
	outline.append(V(x1, p.y))
	ci.draw_polyline(outline, Color(0.12, 0.07, 0.04, 0.6), 2, true)
	# جذور متدلية
	for i in roundi(n * 0.6):
		var k := 1 + r.randi() % (n - 1)
		var x := lerpf(x0, x1, float(k) / n)
		var y := under[k]
		var len := 12 + r.randf() * 30
		var pts := PackedVector2Array([V(x, y - 4)])
		Painter.quad(pts, V(x + (r.randf() - 0.5) * 16, y + len * 0.5), V(x + (r.randf() - 0.5) * 10, y + len), 5)
		ci.draw_polyline(pts, Color("#4a2f1a"), 1.2 + r.randf() * 1.5, true)
	grass_top(ci, x0, x1, p.y, r)
	blades(ci, x0 + 2, x1 - 2, p.y, r, 3, 13)
