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


func _on_ground(gx: float):
	for s in ground:
		if gx >= s.x0 + 50 and gx <= s.x1 - 50:
			return s.y
	return null


# سطح الأرض عند نقطة x (null = حفرة)
func ground_at(x: float):
	var top = null
	for g in ground:
		if x >= g.x0 and x <= g.x1 and (top == null or g.y < top):
			top = g.y
	return top


# أول سطح (أرض أو منصة) تحت النقطة
func surface_below(x: float, y: float) -> float:
	var best := Config.AH + 400
	for g in ground:
		if x >= g.x0 and x <= g.x1 and g.y >= y - 4 and g.y < best:
			best = g.y
	for p in platforms:
		if x >= p.x0 and x <= p.x1 and p.y >= y - 4 and p.y < best:
			best = p.y
	return best
