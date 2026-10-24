# ════════ معلومات اللعب فوگ الشاشة ════════
# الصحة، الصعوبة والزومبي المقتولين، الفلوس، السلاح والطلقات والرمانات + حمرة لمن تنضرب.
extends Control

var game: Game3D
var font: Font
var _sb: StyleBoxFlat


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(_dt: float) -> void:
	queue_redraw()


func _panel(r: Rect2) -> void:
	if _sb == null:
		_sb = StyleBoxFlat.new()
		_sb.bg_color = Color(0.05, 0.07, 0.12, 0.6)
		_sb.set_corner_radius_all(12)
		_sb.border_color = Color(1, 1, 1, 0.08)
		_sb.set_border_width_all(1)
	draw_style_box(_sb, r)


func _text(s: String, pos: Vector2, sz: int, col := Color.WHITE) -> void:
	draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, 0.6))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _draw() -> void:
	if game == null:
		return
	var s := size
	var p := game.me()
	if p.inv > 0.35 or p.hp <= 0:
		_edges(s, Color(0.78, 0, 0, 0.35))

	# الصحة
	_panel(Rect2(14, 12, 250, 44))
	draw_rect(Rect2(26, 26, 160, 16), Color(0.2, 0.05, 0.05, 0.8))
	var k := clampf(p.hp / p.max_hp, 0, 1)
	draw_rect(Rect2(26, 26, 160 * k, 16), Color("#7bd64a") if k > 0.35 else Color("#e53935"))
	_text("%d" % ceili(p.hp), Vector2(196, 41), 20)

	# الصعوبة والقتل
	var mid := s.x / 2
	_panel(Rect2(mid - 150, 12, 300, 44))
	var t := "الصعوبة %.1f   -   %d / %d" % [game.level, game.killed, game.total]
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	_text(t, Vector2(mid - w / 2, 41), 20)

	# الفلوس
	_panel(Rect2(s.x - 164, 12, 150, 44))
	draw_circle(Vector2(s.x - 140, 34), 11, Color("#a86b08"))
	draw_circle(Vector2(s.x - 141, 33), 9, Color("#f2b632"))
	_text("%d" % game.earned(), Vector2(s.x - 122, 42), 22, Color("#ffd23f"))

	# السلاح والطلقات والرمانات
	_panel(Rect2(14, 64, 280, 40))
	var wname: String = Config.WEAPONS[p.weapon].name
	var ammo := "تعبئة..." if p.reload > 0 else "%d / %d" % [p.ammo[p.weapon], Config.WEAPONS[p.weapon].mag]
	_text(wname, Vector2(26, 92), 19)
	_text(ammo, Vector2(110, 92), 19, Color("#ffd23f") if p.reload > 0 else Color.WHITE)
	_text("رمانة %d" % p.grenades, Vector2(200, 92), 19)


func _edges(s: Vector2, col: Color) -> void:
	var clear := Color(col.r, col.g, col.b, 0)
	var e := minf(s.x, s.y) * 0.28
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x - e, e), Vector2(e, e)]), PackedColorArray([col, col, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(0, s.y), Vector2(e, s.y - e), Vector2(s.x - e, s.y - e), Vector2(s.x, s.y)]), PackedColorArray([col, clear, clear, col]))
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(e, e), Vector2(e, s.y - e), Vector2(0, s.y)]), PackedColorArray([col, clear, clear, col]))
	draw_polygon(PackedVector2Array([Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(s.x - e, s.y - e), Vector2(s.x - e, e)]), PackedColorArray([col, col, clear, clear]))
