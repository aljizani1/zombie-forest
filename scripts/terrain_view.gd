# ════════ رسم الحفر والطابوق ════════
# فوگ صور الأرض الثابتة: المربعات المحفورة تنرسم كجدار كهف غامق، والطابوق كطابوق (يتشقق لمن ينضرب).
# الخريطة مقسومة قطع، وبس القطعة اللي تغيّرت تنعاد رسمتها.
extends Node2D

const DRAWN := preload("res://scripts/drawn.gd")
const COLS := 48 # أعمدة بكل قطعة

var map: World
var _parts: Array[Node2D] = []


func setup(m: World) -> void:
	map = m
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


func _draw_part(ci: CanvasItem, c0: int) -> void:
	var b := Batch.new(ci)
	var C := World.CELL
	for c in range(c0, mini(c0 + COLS, map.cols)):
		for r in map.rows:
			var i := r * map.cols + c
			var v := map.cells[i]
			var was := map._orig[i]
			var x := c * C
			var y := r * C
			if v == World.EMPTY and was != World.EMPTY:
				# جدار كهف: أغمق كل ما تنزل، ومربعات شوية مختلفة حتى ما يبين مسطّح
				var k := float((c * 7 + r * 13) % 5) / 5.0
				var col := Color("#3a2616").lerp(Color("#24170c"), clampf(float(r) / map.rows + k * 0.25, 0, 1))
				b.draw_rect(Rect2(x, y, C, C), col)
				# ظل من فوگ إذا فوگه تراب
				if map.cell(c, r - 1) == World.DIRT:
					b.draw_rect(Rect2(x, y, C, 5), Color(0, 0, 0, 0.35))
			elif v == World.BRICK:
				var hp: float = map.brick_hp.get(i, World.BRICK_HP) / World.BRICK_HP
				var base := Color("#b5562a").lerp(Color("#5a2a14"), (1 - hp) * 0.6)
				b.draw_rect(Rect2(x, y, C, C), Color("#e0cdb0"))
				# طابوقتين (نص مزاح بالصفوف حتى يشبه الحايط)
				var off := 0.0 if r % 2 == 0 else C / 2
				b.draw_rect(Rect2(x + 1, y + 1, C - 2, C / 2 - 2), base)
				b.draw_rect(Rect2(x + 1, y + C / 2 + 1, C - 2, C / 2 - 2), base.darkened(0.12))
				b.draw_rect(Rect2(x + off - 0.5 if off > 0 else x + C / 2 - 0.5, y + C / 2, 1.2, C / 2), Color("#e0cdb0"))
				b.draw_rect(Rect2(x + 1, y + 1, C - 2, 2), Color(1, 1, 1, 0.18))
				# شقوق حسب الضرر
				if hp < 0.75:
					b.draw_line(Vector2(x + 4, y + 3), Vector2(x + 10, y + 11), Color(0, 0, 0, 0.6), 1.4)
				if hp < 0.4:
					b.draw_line(Vector2(x + 15, y + 5), Vector2(x + 8, y + 17), Color(0, 0, 0, 0.6), 1.4)
	b.flush()
