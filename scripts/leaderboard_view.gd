# ════════ لوحة المتصدرين (بطاقة غامقة + شريط لكل لاعب حسب عدد القتلى) ════════
# كل صف: الترتيب، الاسم (مع ميدالية للأوائل)، شريط أزرق طوله حسب القتلى، ورقم بنهاية الشريط.
# الضغط على صف يفتح ملف اللاعب.
extends Control

signal picked(name: String)

const ROW_H := 62.0
const GAP := 10.0
const TOP := 118.0 # مكان العنوان فوگ
const RANK_W := 54.0
const NAME_W := 230.0

var font: Font
var rows: Array = [] # [{rank, name, kills, best_level}]
var me := "" # اسمي (حتى يتلوّن صفي)
var status := "..."
var _hover := -1


func set_rows(list: Array) -> void:
	rows = list
	status = "" if list.size() else "بعد محد لعب. كن الأول!"
	custom_minimum_size.y = TOP + maxf(1, rows.size()) * (ROW_H + GAP) + 24
	queue_redraw()


func _row_rect(i: int) -> Rect2:
	return Rect2(RANK_W + 22, TOP + i * (ROW_H + GAP), size.x - RANK_W - 44, ROW_H)


func _gui_input(e: InputEvent) -> void:
	var pos := Vector2.INF
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		pos = e.position
	elif e is InputEventScreenTouch and e.pressed:
		pos = e.position
	if pos != Vector2.INF:
		for i in rows.size():
			if _row_rect(i).grow(4).has_point(pos):
				picked.emit(str(rows[i].name))
				accept_event()
				return
	if e is InputEventMouseMotion:
		var h := -1
		for i in rows.size():
			if _row_rect(i).has_point(e.position):
				h = i
		if h != _hover:
			_hover = h
			queue_redraw()


func _box(r: Rect2, bg: Color, radius := 14, border := Color(0, 0, 0, 0), bw := 0, shadow := 0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	if shadow > 0:
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = shadow
		sb.shadow_offset = Vector2(0, 3)
	draw_style_box(sb, r)


func _text(s: String, pos: Vector2, sz: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(font, pos, s, align, width, sz, col)


func _draw() -> void:
	var w := size.x
	# البطاقة: تدرّج كحلي غامق
	var top := Color("#22304d")
	var bot := Color("#121a2b")
	var card := Rect2(0, 0, w, size.y)
	_box(card, bot, 26, Color(1, 1, 1, 0.06), 2, 12)
	draw_polygon(PackedVector2Array([Vector2(14, 14), Vector2(w - 14, 14), Vector2(w - 14, size.y * 0.6), Vector2(14, size.y * 0.6)]),
		PackedColorArray([top, top, Color(top, 0), Color(top, 0)]))

	# العنوان
	_text("المتصدرين", Vector2(0, 58), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w)
	_text("منو أكثر واحد قتل زومبي؟ (الرقم = عدد الزومبي المقتولين)", Vector2(0, 94), 22, Color("#9fb0cc"), HORIZONTAL_ALIGNMENT_CENTER, w)
	if status != "":
		_text(status, Vector2(0, TOP + 40), 24, Color("#c8d3e6"), HORIZONTAL_ALIGNMENT_CENTER, w)
		return

	var most := 1.0
	for r in rows:
		most = maxf(most, float(r.kills))
	var medals := [Color("#f5c542"), Color("#c9ced6"), Color("#cd7f45")]
	for i in rows.size():
		var r: Dictionary = rows[i]
		var rr := _row_rect(i)
		var mine := me != "" and str(r.name).to_lower() == me.to_lower()
		var rank := int(r.rank)
		# رقم الترتيب برّه الصف
		_text(str(rank), Vector2(8, rr.position.y + ROW_H / 2 + 12), 32, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, RANK_W)
		# الصف
		var row_bg := Color("#2a3a5c") if i != _hover else Color("#33466d")
		_box(rr, row_bg, 14, Color("#ffd23f") if mine else Color(1, 1, 1, 0.07), 3 if mine else 1, 6)
		draw_rect(Rect2(rr.position + Vector2(14, 4), Vector2(rr.size.x - 28, 2)), Color(1, 1, 1, 0.06))
		# ميدالية للأوائل، ونقطة للباقين
		var mx := rr.position.x + 30
		var my := rr.position.y + ROW_H / 2
		if rank <= 3:
			draw_circle(Vector2(mx, my), 15, medals[rank - 1].darkened(0.35))
			draw_circle(Vector2(mx, my - 1), 12, medals[rank - 1])
			_text(str(rank), Vector2(mx - 15, my + 8), 18, Color("#2a1e05"), HORIZONTAL_ALIGNMENT_CENTER, 30)
		else:
			draw_circle(Vector2(mx, my), 6, Color("#5b7bb3"))
		# الاسم
		_text(str(r.name), Vector2(mx + 26, my + 10), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, NAME_W - 40)
		# الشريط (يبدي بعد الاسم وطوله حسب القتلى)
		var bx := rr.position.x + NAME_W + 20
		var bmax := rr.end.x - bx - 250 # نخلي مكان للرقم وللصعوبة
		var bw := maxf(36, bmax * float(r.kills) / most)
		var by := my - 11
		var light := Color("#4f9bff")
		var deep := Color("#1747a8")
		draw_polygon(PackedVector2Array([Vector2(bx, by), Vector2(bx + bw, by), Vector2(bx + bw, by + 22), Vector2(bx, by + 22)]),
			PackedColorArray([deep, light, light.darkened(0.25), deep.darkened(0.25)]))
		draw_rect(Rect2(bx, by + 2, bw, 4), Color(1, 1, 1, 0.22))
		# الرقم بنهاية الشريط
		var label := str(int(r.kills))
		var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x + 26
		var badge := Rect2(bx + bw - 8, my - 20, lw, 40)
		_box(badge, Color("#0f1626"), 12, Color(1, 1, 1, 0.08), 1, 4)
		_text(label, Vector2(badge.position.x, my + 8), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, lw)
		# أعلى صعوبة (صغير يمين)
		_text("صعوبة %.1f" % float(r.best_level), Vector2(rr.end.x - 120, my + 7), 17, Color("#9fb0cc"), HORIZONTAL_ALIGNMENT_RIGHT, 108)
