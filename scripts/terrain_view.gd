# ════════ رسم تحت الأرض + الحفر والطابوق ════════
# - خلفية التراب تحت الأرض (تدرّج يغمق كل ما تنزل + حجار) تنرسم مرة وحدة وما تتغير.
# - فوگها طبقة صغيرة: المربعات المحفورة (جدار كهف غامق) والطابوق (يتشقق لمن ينضرب).
#   هاي مقسومة قطع ضيقة، وبس القطعة اللي تغيّرت تنعاد رسمتها (حتى الحفر ما يسبب تقطيع).
extends Node2D

const DRAWN := preload("res://scripts/drawn.gd")
const BG_COLS := 64 # أعمدة بكل قطعة خلفية
const COLS := 12 # أعمدة بكل قطعة حفر/طابوق

var map: World
var _parts: Array[Node2D] = []


func setup(m: World) -> void:
	map = m
	for i in ceili(float(map.cols) / BG_COLS):
		var n: Node2D = DRAWN.new()
		var c0 := i * BG_COLS
		n.fn = func(ci: CanvasItem) -> void: _draw_bg(ci, c0)
		add_child(n)
	for i in ceili(float(map.cols) / COLS):
		var n: Node2D = DRAWN.new()
		var c0 := i * COLS
		n.fn = func(ci: CanvasItem) -> void: _draw_part(ci, c0)
		add_child(n)
		_parts.append(n)
	map.changed.connect(func(c: int):
		var i := c / COLS
		if i >= 0 and i < _parts.size():
			_parts[i].queue_redraw())


# التراب تحت الأرض: يغمق كل ما تنزل، وحجار متفرّقة، وآخر شي صخر
func _draw_bg(ci: CanvasItem, c0: int) -> void:
	var b := Batch.new(ci)
	var C := World.CELL
	var x0 := c0 * C
	var x1 := minf(map.cols, c0 + BG_COLS) * C
	var y0 := map.surface_row * C
	var y1 := (map.rows - 2) * C
	var stops := [[y0, Color("#56391f")], [y0 + 400, Color("#4a3019")], [y0 + 1400, Color("#3a2614")], [y1, Color("#2a1b10")]]
	for i in stops.size() - 1:
		var a: Array = stops[i]
		var z: Array = stops[i + 1]
		b.draw_polygon(PackedVector2Array([Vector2(x0, a[0]), Vector2(x1, a[0]), Vector2(x1, z[0]), Vector2(x0, z[0])]),
			PackedColorArray([a[1], a[1], z[1], z[1]]))
	b.draw_rect(Rect2(x0, y1, x1 - x0, C * 2), Color("#3c3c40"))
	var r := RandomNumberGenerator.new()
	r.seed = c0 * 7919 + 17
	for i in int((x1 - x0) * (y1 - y0) / 2600):
		var x := r.randf_range(x0, x1)
		var y := r.randf_range(y0 + 10, y1 - 10)
		var w := r.randf_range(3, 11)
		var col := Color("#7a5a3a") if r.randf() < 0.5 else Color("#2a1a0e")
		col.a = 0.55
		b.draw_colored_polygon(Painter.ellipse_pts(Vector2(x, y), w, w * 0.65, r.randf(), 6), col)
	b.flush()


func _draw_part(ci: CanvasItem, c0: int) -> void:
	var b := Batch.new(ci)
	var C := World.CELL
	var cave_top := Color("#3a2616")
	var cave_deep := Color("#170e07")
	for c in range(c0, mini(c0 + COLS, map.cols)):
		var x := c * C
		var r := 0
		while r < map.rows:
			var i := r * map.cols + c
			var v := map.cells[i]
			if v == World.EMPTY and map._orig[i] != World.EMPTY:
				# نجمع المربعات المحفورة اللي ورا بعض بالعمود بمستطيل واحد
				var r1 := r
				while r1 + 1 < map.rows and map.cells[(r1 + 1) * map.cols + c] == World.EMPTY and map._orig[(r1 + 1) * map.cols + c] != World.EMPTY:
					r1 += 1
				var ka := clampf(float(r) / map.rows * 1.6, 0, 1)
				var kb := clampf(float(r1 + 1) / map.rows * 1.6, 0, 1)
				var ca := cave_top.lerp(cave_deep, ka)
				var cb := cave_top.lerp(cave_deep, kb)
				b.draw_polygon(PackedVector2Array([Vector2(x, r * C), Vector2(x + C, r * C), Vector2(x + C, (r1 + 1) * C), Vector2(x, (r1 + 1) * C)]),
					PackedColorArray([ca, ca, cb, cb]))
				# ظل من فوگ إذا فوگه تراب
				if map.cell(c, r - 1) == World.DIRT:
					b.draw_rect(Rect2(x, r * C, C, 5), Color(0, 0, 0, 0.35))
				r = r1 + 1
				continue
			if v == World.BRICK:
				_brick(b, c, r, i)
			r += 1
	b.flush()


func _brick(b: Batch, c: int, r: int, i: int) -> void:
	var C := World.CELL
	var x := c * C
	var y := r * C
	var hp: float = map.brick_hp.get(i, World.BRICK_HP) / World.BRICK_HP
	var base := Color("#b5562a").lerp(Color("#5a2a14"), (1 - hp) * 0.6)
	b.draw_rect(Rect2(x, y, C, C), Color("#e0cdb0"))
	b.draw_rect(Rect2(x + 1, y + 1, C - 2, C / 2 - 2), base)
	b.draw_rect(Rect2(x + 1, y + C / 2 + 1, C - 2, C / 2 - 2), base.darkened(0.12))
	b.draw_rect(Rect2(x + (C / 2 if r % 2 == 0 else 2) - 0.5, y + C / 2, 1.2, C / 2), Color("#e0cdb0"))
	b.draw_rect(Rect2(x + 1, y + 1, C - 2, 2), Color(1, 1, 1, 0.18))
	# شقوق حسب الضرر
	if hp < 0.75:
		b.draw_line(Vector2(x + 4, y + 3), Vector2(x + 10, y + 11), Color(0, 0, 0, 0.6), 1.4)
	if hp < 0.4:
		b.draw_line(Vector2(x + 15, y + 5), Vector2(x + 8, y + 17), Color(0, 0, 0, 0.6), 1.4)
