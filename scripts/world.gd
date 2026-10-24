# ════════ الخريطة ════════
# خريطة كبيرة وحدة (16 شاشة) تنصنع تلقائياً: أرض بارتفاعات مختلفة وحفر، منصات طايرة، أشجار وزينة.
# نفس طريقة النسخة القديمة، بس بالـ GDScript.
class_name World
extends RefCounted

const SCREEN_W := 1280.0

var width := 0.0
var ground: Array = [] # كل قطعة {x0, x1, y}: أرض صلبة من y لتحت (الفراغ بين قطعتين = حفرة)
var platforms: Array = [] # منصات تنط عليها من تحت
var trees: Array = [] # {x, y, kind, size}
var decor: Array = [] # {x, y, kind}
var start := Vector2.ZERO


func _init(seed_value := 2026) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	width = SCREEN_W * 16
	var sx := width / 2

	# الأرض: قطع بأطوال وارتفاعات مختلفة، وأحياناً حفرة
	var x := 0.0
	var y := 620.0
	while x < width:
		var len := r.randf_range(500, 1500)
		if x < sx + 900 and x + len > sx - 900:
			# منطقة البداية مستوية
			y = 620.0
			len = maxf(len, sx + 900 - x)
		var x1 := minf(width, roundf(x + len))
		ground.append({x0 = roundf(x), x1 = x1, y = y})
		x = x1
		if x >= width:
			break
		if r.randf() < 0.24 and absf(x - sx) > 1200 and x > 700 and x < width - 700:
			x += roundf(r.randf_range(100, 165))
		y = clampf(y + [-80, -60, 0, 0, 0, 60, 80][r.randi() % 7], 500, 620)

	# منصات فوق الأرض (طابق أو طابقين)
	for g in ground:
		var n := int((g.x1 - g.x0) / 520)
		for i in n:
			var w := roundf(r.randf_range(220, 340))
			var px := roundf(g.x0 + 80 + ((g.x1 - g.x0 - 160 - w) * (i + 0.5)) / n + r.randf_range(-60, 60))
			if px < g.x0 + 40 or px + w > g.x1 - 40:
				continue
			var py := roundf(g.y - r.randf_range(180, 200))
			platforms.append({x0 = px, x1 = px + w, y = py})
			var py2 := py - roundf(r.randf_range(170, 190))
			if r.randf() < 0.35 and py2 > 130:
				var w2 := roundf(r.randf_range(200, 280))
				var px2 := roundf(px + (-1 if r.randf() < 0.5 else 1) * r.randf_range(240, 320))
				if px2 > g.x0 and px2 + w2 < g.x1:
					platforms.append({x0 = px2, x1 = px2 + w2, y = py2})

	# أشجار وزينة على الأرض (بعيد عن حواف الحفر)
	var kinds_t := ["oak", "oak", "birch", "pine"]
	var tx := 120.0
	while tx < width:
		var ty = _on_ground(tx)
		if ty != null:
			trees.append({x = roundf(tx), y = ty, kind = kinds_t[r.randi() % 4], size = r.randf_range(0.8, 1.2)})
		tx += r.randf_range(280, 700)
	var kinds_d := ["bush", "bush", "rock", "flower", "mushroom"]
	var dx := 200.0
	while dx < width:
		var dy = _on_ground(dx)
		if dy != null:
			decor.append({x = roundf(dx), y = dy, kind = kinds_d[r.randi() % 5]})
		dx += r.randf_range(180, 420)

	start = Vector2(sx, 620)
	build_cells()


func _on_ground(gx: float):
	for s in ground:
		if gx >= s.x0 + 50 and gx <= s.x1 - 50:
			return s.y
	return null


# ════════ الأرض كمربعات (تنحفر وتنبني) ════════
# الأرض مقسومة مربعات 20×20: فارغ، تراب (ينحفر بالكرك)، طابوق (اللاعب يبنيه والزومبي يكسرونه)، صخر (آخر صفّين، ما ينحفر).
# المنصات الطايرة تبقى مثل ما هي (تنط عليها من تحت وما تنحفر).
signal changed(col: int) # انحفر أو انبنى شي بهذا العمود

const CELL := 20.0
const EMPTY := 0
const DIRT := 1
const BRICK := 2
const ROCK := 3
const BRICK_HP := 40.0
const DEPTH := 150 # كم مربع تحت آخر الشاشة (تحفر لحد هنا، وبعدها صخر)

var cols := 0
var rows := 0
var height := 0.0 # طول العالم كله (فوگ الأرض + تحت الأرض)
var surface_row := 0 # أول صف تحت الشاشة الأصلية (من هنا كلشي تراب حتى بالحفر)
var cells := PackedByteArray()
var _orig := PackedByteArray() # الأرض الأصلية (حتى نرجعها بكل جولة، ورسم الحفر)
var brick_hp := {} # رقم المربع ← الصحة الباقية


func build_cells() -> void:
	cols = ceili(width / CELL)
	surface_row = ceili(Config.AH / CELL)
	rows = surface_row + DEPTH
	height = rows * CELL
	cells.resize(cols * rows)
	cells.fill(EMPTY)
	# تحت الأرض: تراب بكل مكان (حتى تحت الحفر الطبيعية)، وآخر صفّين صخر
	for r in range(surface_row, rows):
		for c in cols:
			cells[r * cols + c] = ROCK if r >= rows - 2 else DIRT
	for g in ground:
		var c0 := int(ceil(g.x0 / CELL - 0.5))
		var c1 := int(floor(g.x1 / CELL - 0.5))
		var r0 := int(g.y / CELL)
		for c in range(maxi(0, c0), mini(cols - 1, c1) + 1):
			for r in range(r0, rows):
				if cells[r * cols + c] == EMPTY:
					cells[r * cols + c] = DIRT
	_orig = cells.duplicate()


# نرجّع الأرض مثل ما كانت (بداية كل جولة)
func reset_cells() -> void:
	if cells != _orig:
		cells = _orig.duplicate()
		brick_hp.clear()
		for c in cols:
			changed.emit(c)


func cell(c: int, r: int) -> int:
	if c < 0 or c >= cols or r < 0 or r >= rows:
		return EMPTY
	return cells[r * cols + c]


func set_cell(c: int, r: int, v: int) -> void:
	if c < 0 or c >= cols or r < 0 or r >= rows:
		return
	var i := r * cols + c
	if cells[i] == v:
		return
	cells[i] = v
	if v == BRICK:
		brick_hp[i] = BRICK_HP
	else:
		brick_hp.erase(i)
	changed.emit(c)


func solid_at(x: float, y: float) -> bool:
	return cell(int(floor(x / CELL)), int(floor(y / CELL))) != EMPTY


# أي مربع صلب داخل المستطيل؟ يرجع رقم المربع (c, r) أو (-1, -1)
func hit_box(x: float, y: float, w: float, h: float) -> Vector2i:
	var c0 := int(floor(x / CELL))
	var c1 := int(floor((x + w - 0.01) / CELL))
	var r0 := maxi(0, int(floor(y / CELL)))
	var r1 := mini(rows - 1, int(floor((y + h - 0.01) / CELL)))
	for c in range(c0, c1 + 1):
		for r in range(r0, r1 + 1):
			if cell(c, r) != EMPTY:
				return Vector2i(c, r)
	return Vector2i(-1, -1)


# سطح الأرض عند نقطة x (أعلى مربع صلب بالعمود، null = حفرة)
func ground_at(x: float):
	var c := int(floor(x / CELL))
	if c < 0 or c >= cols:
		return null
	for r in rows:
		if cells[r * cols + c] != EMPTY:
			return r * CELL
	return null


# أول سطح (أرض أو منصة) تحت النقطة
func surface_below(x: float, y: float) -> float:
	var best := height + 400
	var c := int(floor(x / CELL))
	if c >= 0 and c < cols:
		for r in range(maxi(0, int(ceil((y - 4) / CELL))), rows):
			if cells[r * cols + c] != EMPTY:
				best = r * CELL
				break
	for p in platforms:
		if x >= p.x0 and x <= p.x1 and p.y >= y - 4 and p.y < best:
			best = p.y
	return best
