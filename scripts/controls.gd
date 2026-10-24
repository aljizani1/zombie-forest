# ════════ أزرار اللمس ════════
# جويستيكين منفصلين:
#   - اليسار للحركة (يمين/يسار، ولفوگ = قفز، ولتحت = نزول من المنصة)
#   - اليمين للتصويب والرمي: تأشّر بيه على العدو، السلاح يتوجه لهناك ويرمي
# + زر القفز وزر تبديل السلاح وزر الرمانة.
extends Control

# x و y = نسبة من عرض/طول الشاشة لمركز الزر، size = القطر
const LAYOUT := {
	"stick": {x = 0.13, y = 0.74, size = 150.0},
	"fire": {x = 0.86, y = 0.72, size = 150.0},
	"jump": {x = 0.68, y = 0.85, size = 72.0},
	"swap": {x = 0.93, y = 0.4, size = 60.0},
	"nade": {x = 0.84, y = 0.4, size = 60.0},
	"shovel": {x = 0.75, y = 0.4, size = 60.0},
	"brick": {x = 0.66, y = 0.4, size = 60.0},
}

var inp # مدخلات اللعبة
var hide_ids: Array = ["jump", "shovel", "brick"] # أزرار مو مستعملة بالنسخة الثلاثية الأبعاد
var opacity := 0.85
var _fingers := {} # رقم الإصبع ← الزر
var _knob := {"stick": Vector2.ZERO, "fire": Vector2.ZERO}
var _pressed := {}
var _jumped := false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE


func _center(id: String) -> Vector2:
	var s := size
	return Vector2(LAYOUT[id].x * s.x, LAYOUT[id].y * s.y)


func _radius(id: String) -> float:
	# الحجم يصغر شوية بالشاشات القصيرة
	return minf(LAYOUT[id].size, LAYOUT[id].size * size.y / 720.0 * 1.15) / 2


func _hit(pos: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id in LAYOUT:
		if hide_ids.has(id):
			continue
		var d := pos.distance_to(_center(id))
		var r := _radius(id) * (1.6 if id == "stick" or id == "fire" else 1.3)
		if d < r and d < best_d:
			best = id
			best_d = d
	return best


func _input(e: InputEvent) -> void:
	if not visible or inp == null:
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			var id := _hit(e.position)
			if id == "":
				return
			_fingers[e.index] = id
			_press(id, e.position)
		elif _fingers.has(e.index):
			_release(_fingers[e.index])
			_fingers.erase(e.index)
		get_viewport().set_input_as_handled()
	elif e is InputEventScreenDrag and _fingers.has(e.index):
		var id: String = _fingers[e.index]
		if id == "stick" or id == "fire":
			_move_stick(id, e.position)
		get_viewport().set_input_as_handled()


func _press(id: String, pos: Vector2) -> void:
	_pressed[id] = true
	match id:
		"stick", "fire":
			_move_stick(id, pos)
		"jump":
			inp.jump = 0.15
		"swap":
			inp.swap = true
		"nade":
			inp.throw = true
		"shovel", "brick":
			# نفس الزر مرة ثانية يرجّعك للسلاح
			inp.select = id
	queue_redraw()


func _release(id: String) -> void:
	_pressed.erase(id)
	if id == "stick":
		_knob.stick = Vector2.ZERO
		_jumped = false
		inp.move = 0
		inp.move_v = Vector2.ZERO
		inp.down = false
	elif id == "fire":
		_knob.fire = Vector2.ZERO
		inp.fire = false
		inp.aim = null
	queue_redraw()


func _move_stick(id: String, pos: Vector2) -> void:
	var travel := _radius(id) * 0.64
	var d := (pos - _center(id)).limit_length(travel)
	_knob[id] = d
	var n := d / travel
	if id == "stick":
		var mag := 0.0 if absf(n.x) < 0.18 else minf(1.0, (absf(n.x) - 0.18) / 0.55)
		# لفوگ = قفز (مرة وحدة كل ما ترفعه)
		var up := n.y < -0.65
		if up and not _jumped:
			inp.jump = 0.15
		_jumped = up
		inp.move = signf(n.x) * mag
		inp.down = n.y > 0.7
		# حركة بكل الاتجاهات (نتجاهل الهزّة الصغيرة بالنص)
		inp.move_v = n if n.length() > 0.15 else Vector2.ZERO
	else:
		# التصويب: الاتجاه = وين تأشّر، ويرمي إذا سحبت شوية
		if n.length() > 0.3:
			inp.aim = d.angle()
			inp.fire = true
		else:
			inp.fire = false
	queue_redraw()


func _draw() -> void:
	var a := opacity
	for id in LAYOUT:
		if hide_ids.has(id):
			continue
		var c := _center(id)
		var r := _radius(id)
		if id == "stick" or id == "fire":
			var red: bool = id == "fire"
			draw_circle(c, r, Color(0.5, 0.1, 0.1, 0.3 * a) if red else Color(0, 0, 0, 0.3 * a))
			draw_arc(c, r - 2, 0, TAU, 40, Color(1, 0.7, 0.7, 0.7 * a) if red else Color(1, 1, 1, 0.45 * a), 4, true)
			var k: Vector2 = c + _knob[id]
			draw_circle(k, r * 0.42, Color(0.86, 0.15, 0.15, 0.8 * a) if red else Color(1, 1, 1, 0.45 * a))
			draw_arc(k, r * 0.42, 0, TAU, 28, Color(1, 1, 1, 0.9 * a), 4, true)
			if red:
				var cr := r * 0.2
				draw_arc(k, cr, 0, TAU, 20, Color(1, 1, 1, a), 2.4, true)
				for v in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
					draw_line(k + v * cr * 0.6, k + v * cr * 1.5, Color(1, 1, 1, a), 2.4, true)
		else:
			var down: bool = _pressed.has(id)
			var rr := r * (0.9 if down else 1.0)
			var bg := Color(0.86, 0.15, 0.15, 0.8 * a) if id == "jump" else (Color(0.3, 0.4, 0.2, 0.8 * a) if id == "nade" else (Color(0.45, 0.3, 0.15, 0.85 * a) if id == "shovel" or id == "brick" else Color(0.15, 0.15, 0.16, 0.75 * a)))
			draw_circle(c + Vector2(0, 4), rr, Color(0, 0, 0, 0.35 * a))
			draw_circle(c, rr, bg)
			draw_arc(c, rr - 2, 0, TAU, 32, Color(1, 1, 1, 0.85 * a), 4, true)
			var w := Color(1, 1, 1, a)
			var s := rr * 0.45
			match id:
				"jump":
					for dy in [-0.35, 0.35]:
						draw_polyline(PackedVector2Array([c + Vector2(-s, s * (dy + 0.4)), c + Vector2(0, s * (dy - 0.4)), c + Vector2(s, s * (dy + 0.4))]), w, 3, true)
				"swap":
					draw_polyline(PackedVector2Array([c + Vector2(-s, -s * 0.4), c + Vector2(s, -s * 0.4), c + Vector2(s * 0.5, -s * 0.9)]), w, 3, true)
					draw_polyline(PackedVector2Array([c + Vector2(s, s * 0.4), c + Vector2(-s, s * 0.4), c + Vector2(-s * 0.5, s * 0.9)]), w, 3, true)
				"nade":
					draw_circle(c + Vector2(0, s * 0.15), s * 0.6, w)
					draw_rect(Rect2(c + Vector2(-s * 0.25, -s * 0.75), Vector2(s * 0.5, s * 0.35)), w)
				"shovel":
					# كرك: يد مايلة وراس
					draw_line(c + Vector2(-s * 0.8, s * 0.8), c + Vector2(s * 0.4, -s * 0.4), w, 4, true)
					draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.1, -s * 0.7), c + Vector2(s * 0.9, -s * 0.2), c + Vector2(s * 0.7, s * 0.1), c + Vector2(-s * 0.1, -s * 0.4)]), w)
				"brick":
					draw_rect(Rect2(c + Vector2(-s * 0.8, -s * 0.5), Vector2(s * 1.6, s)), Color("#c0602f", a))
					draw_rect(Rect2(c + Vector2(-s * 0.8, -s * 0.5), Vector2(s * 1.6, s)), w, false, 2)
					draw_line(c + Vector2(-s * 0.8, 0), c + Vector2(s * 0.8, 0), w, 2)
					draw_line(c + Vector2(0, -s * 0.5), c + Vector2(0, 0), w, 2)
