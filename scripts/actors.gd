# ════════ رسم كل شي يتحرك (كل إطار) ════════
# الشخصيات، الطلق، الرمانات، الانفجارات، الدم، الفلوس اللي تطلع.
extends Node2D

const PW := Game.PW
const PH := Game.PH

var game: Game
var _lo := -INF # حدود الشاشة (مع هامش) بالعالم
var _hi := INF
var font: Font
var g: Painter


func _ready() -> void:
	g = Painter.new(self)


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	g.begin()
	var t := game.time
	# الأشياء البعيدة عن الشاشة ما نرسمها (أغلب الزومبي يطلعون برّه الشاشة)
	var cam := get_viewport().get_camera_2d()
	var vw := get_viewport().get_visible_rect().size.x
	var cx := cam.get_screen_center_position().x if cam != null else vw / 2
	_lo = cx - vw / 2 - 200
	_hi = cx + vw / 2 + 200
	if game.plane != null:
		Rig.draw_plane(g, game.plane.x, game.plane.y, game.plane.dir, t)
	# دم وحروق على الأرض
	for d in game.decals:
		var col := Color(0.08, 0.05, 0.04, minf(0.5, d.life * 0.12)) if d.burn else Color(0.31, 0.03, 0.03, minf(0.55, d.life * 0.2))
		g.fill(Painter.ellipse_pts(Vector2(d.x, d.y), d.r, d.r * 0.22, 0, 16), col)
	# الميتين ورا
	for z in game.zs:
		if z.dead > 0 and _seen(z.x + z.w / 2):
			_draw_zombie(z, t)
	for z in game.zs:
		if z.dead == 0 and _seen(z.x + z.w / 2):
			_draw_zombie(z, t)
	for i in range(game.players.size() - 1, -1, -1):
		var p: Game.Player = game.players[i]
		if _seen(p.x):
			_draw_player(p, t)

	# الطلق
	# الطلق: خط مضوي (هالة عريضة خفيفة + قلب رفيع لامع) يطول حسب السرعة، ورأس يلمع
	for b in game.bullets:
		if not _seen(b.x):
			continue
		var head := Vector2(b.x, b.y)
		var dir := Vector2(b.vx, b.vy) * 0.045
		var tail := head - dir
		var nn := Vector2(-b.vy, b.vx).normalized()
		var glow := nn * 3.5
		g.b.draw_polygon(PackedVector2Array([tail, head + glow, head + dir * 0.06, head - glow]), PackedColorArray([Color(1, 0.6, 0.2, 0), Color(1, 0.75, 0.3, 0.35), Color(1, 0.8, 0.4, 0.35), Color(1, 0.75, 0.3, 0.35)]))
		var core := nn * 1.2
		var mid := head - dir * 0.55
		g.b.draw_polygon(PackedVector2Array([mid + core * 0.3, head + core, head - core, mid - core * 0.3]), PackedColorArray([Color(1, 0.85, 0.5, 0), Color(1, 1, 0.9, 1), Color(1, 1, 0.9, 1), Color(1, 0.85, 0.5, 0)]))
		g.b.draw_circle(head, 2.2, Color(1, 1, 0.92, 0.95))

	# تفاح الساحرة
	for a in game.apples:
		if _seen(a.x):
			_apple(Vector2(a.x, a.y), 8)

	# الرمانات
	for gr in game.grenades:
		Rig.draw_grenade(g, gr.x, gr.y, gr.rot)
		if gr.t < 0.6 and int(gr.t * 16) % 2 == 0:
			g.circle(Vector2(gr.x, gr.y - 10), 2.5, Color(1, 0.24, 0.16, 0.8))

	# الانفجارات
	for b in game.booms:
		var k: float = b.t / 0.7
		var r := 40 + k * 170
		g.glow(Vector2(b.x, b.y - 20), r, Color(1, 0.95, 0.75, 0.95 * (1 - k)), Color(1, 0.45, 0.1, 0), 24)
		g.glow(Vector2(b.x, b.y - 20), r * 0.5, Color(1, 0.98, 0.85, 0.8 * (1 - k)), Color(1, 0.65, 0.2, 0), 18)
		g.line_loop(Painter.ellipse_pts(Vector2(b.x, b.y - 10), 30 + k * 230, 12 + k * 60, 0, 28), Color(1, 1, 1, 0.5 * (1 - k)), 4 * (1 - k) + 1)

	# دم وظروف طلق وغبار ودخان
	for q in game.parts:
		if not _seen(q.x):
			continue
		var col := q.color
		col.a = minf(1.0, q.life / q.max * 2)
		if q.shell:
			g.save()
			g.translate(q.x, q.y)
			g.rotate(q.rot)
			g.fill(Painter.rect_pts(-3, -1.5, 6, 3), col)
			g.restore()
		else:
			if q.smoke:
				col.a = minf(0.45, q.life / q.max * 0.6)
			_dot(Vector2(q.x, q.y), q.size, col)

	# الفلوس اللي تطلع + هيدشوت (نرسم الأشكال أول حتى النص يطلع فوگها)
	g.end()
	for q in game.pops:
		var a := minf(1.0, q.life * 2)
		if q.head:
			_text(q.text, Vector2(q.x, q.y), 22, Color(1, 0.35, 0.23, a), Color(0.24, 0, 0, 0.85 * a))
		else:
			var w := font.get_string_size(q.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			var x: float = q.x - (w + 22) / 2
			_coin(Vector2(x + 9, q.y - 8), 9, a)
			_text(q.text, Vector2(x + 22 + w / 2, q.y), 22, Color(1, 0.82, 0.25, a) if q.get("mine", true) else Color(0.9, 0.9, 0.9, a), Color(0, 0, 0, 0.75 * a))


func _text(s: String, pos: Vector2, size: int, col: Color, outline: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := pos - Vector2(w / 2, 0)
	draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, outline)
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _coin(c: Vector2, r: float, a: float) -> void:
	draw_circle(c, r, Color(0.66, 0.42, 0.03, a))
	draw_circle(c + Vector2(-1, -1), r * 0.8, Color(0.95, 0.71, 0.2, a))
	draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.3, Color(1, 0.95, 0.66, a))


func _shadow(x: float, feet: float, w: float) -> void:
	var ground := game.map.surface_below(x, feet)
	if ground > game.map.height:
		return
	var k := maxf(0.3, 1 - (ground - feet) / 300)
	g.fill(Painter.ellipse_pts(Vector2(x, ground + 2), w * k, 6 * k, 0, 16), Color(0, 0, 0, 0.28 * k))


# السقطة بعد الموت: يدور حول رجليه لورا
func _fall(dead: float) -> void:
	var a := pow(minf(1.0, dead / 0.45), 2) * (PI / 2) * 0.96
	g.translate(0, -sin(a) * 14)
	g.rotate(-a)
	if dead > 1:
		g.alpha = maxf(0, 1 - (dead - 1) / 0.6)


func _bar(cx: float, y: float, w: float, k: float, col: Color) -> void:
	g.fill(Painter.rect_pts(cx - w / 2 - 1.5, y - 1.5, w + 3, 7, 3), Color(0, 0, 0, 0.6))
	g.fill(Painter.rect_pts(cx - w / 2, y, maxf(2, w * clampf(k, 0, 1)), 4, 2), col)


func _draw_player(p: Game.Player, t: float) -> void:
	var cx := p.x + PW / 2
	var feet := p.y + PH
	_shadow(cx, feet, 26)
	if p.hp > 0 and p.inv > 0 and int(t * 18) % 2 == 0:
		return
	g.save()
	g.translate(cx, feet)
	g.scale(p.face, 1)
	var mode := "idle"
	if p.hp <= 0 or p.inv > 0.45:
		mode = "hurt"
	elif p.chute:
		mode = "fall"
	elif not p.on_ground:
		mode = "jump" if p.vy < 0 else "fall"
	elif absf(p.vx) > 25:
		mode = "run"
	if p.hp <= 0:
		_fall(p.dead)
	if p.chute and p.hp > 0:
		Rig.draw_parachute(g, t)
	var pose := Rig.soldier_pose(mode, p.phase, t)
	var aim := 0.0 if p.weapon == "grenade" else Game.aim_of(p)
	var rl := game.reload_progress(p) if p.hp > 0 else 0.0
	Rig.draw_soldier(g, pose, p.weapon if p.hp > 0 else null, {uniform = p.uniform, flash = 0.45 if p.inv > 0.45 else 0.0, recoil = p.recoil, aim = aim, reload = rl})
	g.alpha = 1.0
	g.restore()

	# حلقة تبديل المخزن فوگ الراس
	if rl > 0:
		var rc := Vector2(cx, p.y - (52 if p.bot else 26))
		var ring := PackedVector2Array()
		Painter.arc_pts(ring, rc, 11, 0, TAU, 24)
		g.polyline(ring, Color(0, 0, 0, 0.55), 4)
		ring.clear()
		Painter.arc_pts(ring, rc, 11, -PI / 2, -PI / 2 + rl * TAU, 24)
		g.polyline(ring, Color("#ffd23f"), 4)

	# وميض الطلقة
	if p.flash > 0 and p.hp > 0 and Game.is_gun(p.weapon):
		var m := Rig.muzzle_of(p.weapon, p.recoil, pose, aim)
		var mp := Vector2(cx + p.face * m.x, feet + m.y)
		var d := Vector2(p.face * cos(aim), sin(aim))
		g.glow(mp, 34, Color(1, 0.94, 0.7, 0.95), Color(1, 0.47, 0.08, 0), 16)
		g.fill(PackedVector2Array([mp + Vector2(-d.y, d.x) * 5, mp + d * 26, mp - Vector2(-d.y, d.x) * 5, mp + d * 8]), Color(1, 0.98, 0.86, 0.95))

	# اسم اللاعبين الثانيين (والبوت) وصحتهم فوگ راسهم
	if not p.local:
		var top := p.y - 268 if p.chute else p.y - 22
		g.end()
		_text(p.name, Vector2(cx, top), 15, Color.WHITE, Color(0, 0, 0, 0.7))
		if p.hp > 0:
			_bar(cx, top + 6, 46, p.hp / p.max_hp, Color("#4fc3f7") if p.bot else Color("#7bd64a"))


# ── الزومبي: كل حركة (مشي، وقفة، ضربة، طيران...) تنرسم مرة وحدة وتنحفظ كمثلثات جاهزة،
# وبعدها كل إطار بس ننقلها لمكان الزومبي. هذا يخلي رسم عشرات الزومبي شبه مجاني (سلاسة عالية).
const WALK_F := 32 # عدد إطارات خطوة المشي
const IDLE_F := 12
const ATK_F := 10
const FLY_F := 16
var _zcache := {} # النوع|الحركة|الإطار ← [نقاط، ألوان]
var _rec: Painter


func _zframe(kind: String, mode: String, f: int) -> Array:
	var key := "%s|%s|%d" % [kind, mode, f]
	if _zcache.has(key):
		return _zcache[key]
	if _rec == null:
		_rec = Painter.new(null)
	_rec.begin()
	var monster := kind == "monster"
	match mode:
		"walk":
			var ph := float(f) / WALK_F * TAU
			if monster:
				Rig.draw_monster(_rec, ph, ph * 0.5, 0, true, 0)
			else:
				Rig.draw_zombie(_rec, kind, Rig.zombie_pose("walk", ph, ph * 0.5, 0), 0, ph * 0.5)
		"idle":
			var t := float(f) / IDLE_F * TAU / 1.7
			if monster:
				Rig.draw_monster(_rec, 0, t, 0, false, 0)
			else:
				Rig.draw_zombie(_rec, kind, Rig.zombie_pose("idle", 0, t, 0), 0, t)
		"attack":
			var atk := (f + 0.5) / ATK_F * 0.35
			if monster:
				Rig.draw_monster(_rec, 0, 0, atk, false, 0)
			else:
				Rig.draw_zombie(_rec, kind, Rig.zombie_pose("attack", 0, 0, atk), 0, 0)
		"fly":
			var t := float(f) / FLY_F * TAU / 9.0
			Rig.draw_zombie(_rec, kind, Rig.zombie_pose("fly", 0, t, 0), 0, t)
		_:
			Rig.draw_zombie(_rec, kind, Rig.zombie_pose("air", 0, 0, 0), 0, 0)
	var soup := _rec.b.to_soup()
	_rec.b.parts.clear()
	_zcache[key] = soup
	return soup


func _draw_zombie(z: Game.Zombie, _t: float) -> void:
	if z.kind == "witch":
		_draw_witch(z)
		return
	var scale: float = Config.ZOMBIES[z.kind].scale
	var cx := z.x + z.w / 2
	var feet := z.y + z.h
	if z.dead == 0:
		_shadow(cx, feet, 60.0 if z.kind == "monster" else 26 * scale)
	g.save()
	g.translate(cx, feet)
	g.scale(z.face * scale, scale)
	if z.dead > 0:
		_fall(z.dead)
	var moving := absf(z.vx) > 8
	var mode := "walk" if moving else "idle"
	if z.dead > 0:
		mode = "idle"
	elif z.kind == "flyer":
		mode = "fly"
	elif not z.on_ground and z.kind != "monster":
		mode = "air"
	elif z.atk_t > 0:
		mode = "attack"
	var f := 0
	match mode:
		"walk":
			f = int(posmod(z.phase, TAU) / TAU * WALK_F) % WALK_F
		"idle":
			f = int(posmod(game.time * 1.7 + z.id, TAU) / TAU * IDLE_F) % IDLE_F
		"attack":
			f = clampi(int((0.35 - z.atk_t) / 0.35 * ATK_F), 0, ATK_F - 1)
		"fly":
			f = int(posmod(game.time * 9 + z.id, TAU) / TAU * FLY_F) % FLY_F
	var fr := _zframe(z.kind, mode, f if z.dead == 0 else 0)
	var cols: PackedColorArray = fr[1]
	# لمعة الضربة أو الاختفاء بعد الموت: نغيّر الألوان بس لهذا الزومبي
	var flash := 0.7 if z.hurt > 0 else 0.0
	if flash > 0 or g.alpha < 1:
		cols = cols.duplicate()
		for i in cols.size():
			var c := cols[i].lerp(Color(1, 1, 1, cols[i].a), flash)
			c.a *= g.alpha
			cols[i] = c
	g.b.soup(g.xf * (fr[0] as PackedVector2Array), cols)
	g.alpha = 1.0
	g.restore()
	if z.dead == 0 and z.hp < z.max:
		var w := 96.0 if z.kind == "monster" else (70.0 if z.kind == "brute" else 44.0)
		_bar(cx, z.y - 18, w, z.hp / z.max, Color("#e53935"))


# ── الساحرة: راكبة مكنسة، عباية سودا بغطا راس، شعر أبيض، عيون خضرا تلمع، وتفاحة حمرا بإيدها ──
const W_CLOAK := Color("#1f1a26")
const W_SKIN := Color("#ddd0b8")


func _draw_witch(z: Game.Zombie) -> void:
	var cx := z.x + z.w / 2
	var feet := z.y + z.h
	var t := game.time
	if z.dead == 0:
		_shadow(cx, feet, 46)
	g.save()
	g.translate(cx, feet)
	g.scale(z.face, 1)
	if z.dead > 0:
		_fall(z.dead)
	g.flash = 0.7 if z.hurt > 0 else 0.0
	g.flash_to = Color.WHITE
	g.translate(0, -15 + sin(t * 3.1) * 5)
	g.rotate(clampf(z.vx * z.face / 1500.0, -0.15, 0.15))
	# المكنسة
	var br := PackedVector2Array([Vector2(-58, -14), Vector2(-100, -28 + sin(t * 9) * 3), Vector2(-110, -8), Vector2(-100, 12 + sin(t * 7) * 3), Vector2(-58, -2)])
	g.shade(br, Color("#c9a24a"))
	for i in 5:
		g.line(Vector2(-60, -12 + i * 2.5), Vector2(-104, -26 + i * 9), Color("#8a6a2a"), 1.2)
	g.limb(Vector2(-62, -8), Vector2(60, -14), 7, 6, Color("#7a5230"))
	g.fill(Painter.rect_pts(-62, -15, 8, 13, 2), Color("#4a2e18"))
	# العباية: من الكتف للمكنسة وتطير لورا بحواف ممزقة
	var cloak := PackedVector2Array([Vector2(4, -92), Vector2(18, -60), Vector2(26, -14), Vector2(10, -4)])
	for i in 6:
		var k := i / 5.0
		cloak.append(Vector2(6 - k * 76, -2 + sin(t * 6 + i * 1.3) * 5 + k * 8 + (10.0 if i % 2 == 0 else 0.0)))
	cloak.append(Vector2(-60, -42 + sin(t * 5) * 6))
	cloak.append(Vector2(-36, -80))
	cloak.append(Vector2(-14, -98))
	g.shade(cloak, W_CLOAK)
	# رجل وچزمة گدام تحت العباية
	g.limb(Vector2(12, -16), Vector2(36, -4), 9, 7, Color("#2a2430"))
	g.shade(Painter.ellipse_pts(Vector2(40, -4), 9, 5, -0.3, 10), Color("#3a2a1a"))
	# الإيد الورا ماسكة المكنسة
	g.limb(Vector2(-6, -74), Vector2(20, -22), 8, 7, Painter.light(W_CLOAK, 0.1))
	g.blob(Vector2(22, -18), 5, W_SKIN)
	# غطا الراس
	g.shade(Painter.ellipse_pts(Vector2(4, -112), 26, 30, 0, 16), W_CLOAK)
	# شعر أبيض نازل
	for i in 6:
		var hx := -4 + i * 4.0
		var pts := PackedVector2Array([Vector2(hx, -110)])
		Painter.quad(pts, Vector2(hx - 6 + sin(t * 2 + i) * 3, -92), Vector2(hx - 4 + sin(t * 2.6 + i) * 4, -72 - (i % 3) * 5), 4)
		g.polyline(pts, Color("#ebe5d2"), 2.2)
	# الوجه جانبي: خشم معكوف وحنك طالع
	var face := PackedVector2Array([Vector2(4, -128), Vector2(16, -131), Vector2(23, -124), Vector2(37, -113), Vector2(27, -110), Vector2(24, -104), Vector2(29, -97), Vector2(18, -92), Vector2(8, -96), Vector2(2, -108)])
	g.shade(face, W_SKIN)
	g.circle(Vector2(31, -112), 1.8, Color("#a8a070"))
	# العين: توهج أخضر + حاجب غامق نازل
	g.glow(Vector2(17, -120), 10, Color(0.55, 1, 0.3, 0.55), Color(0.4, 1, 0.2, 0), 14)
	g.fill(Painter.ellipse_pts(Vector2(17, -120), 4.4, 3.3, 0, 10), Color("#f4f1e0"))
	g.circle(Vector2(18.6, -120), 2.1, Color("#7dff3a"))
	g.circle(Vector2(19, -120), 0.9, Color.BLACK)
	g.line(Vector2(10, -127), Vector2(24, -122.5), Color("#1a1414"), 2.8)
	# ضحكة بسن وحدة
	g.polyline(PackedVector2Array([Vector2(13, -103), Vector2(20, -100.5), Vector2(26, -104)]), Color("#5a1010"), 2.2)
	g.fill(Painter.rect_pts(18, -102, 2.4, 3.2), Color("#f0ead0"))
	g.polyline(PackedVector2Array([Vector2(-4, -138), Vector2(10, -141), Vector2(24, -133)]), Painter.light(W_CLOAK, 0.25), 3)
	# الإيد الگدامية: ترتفع وقت الرمي، والتفاحة بيها لحد ما ترميها
	var up := 0.0 if z.atk_t <= 0 else sin((1 - z.atk_t / 0.35) * PI)
	var hand := Vector2(44, -70 - up * 30)
	g.limb(Vector2(8, -86), hand, 9, 7, Painter.light(W_CLOAK, 0.08))
	g.blob(hand + Vector2(3, 0), 5.5, W_SKIN)
	for i in 3:
		g.line(hand + Vector2(4, -2 + i * 2.5), hand + Vector2(11, -4 + i * 3.5), Painter.dark(W_SKIN, 0.15), 1.6)
	if z.atk_t <= 0 and z.dead == 0:
		_apple(hand + Vector2(9, -7), 8)
	g.flash = 0.0
	g.restore()


# تفاحة حمرا لامعة ويا توهج أخضر خفيف (مسمومة)
func _apple(p: Vector2, r: float) -> void:
	g.glow(p, r * 2.2, Color(0.5, 1, 0.3, 0.35), Color(0.4, 1, 0.2, 0), 14)
	g.shade(Painter.ellipse_pts(p, r, r * 0.92, 0, 14), Color("#d32f2f"))
	g.circle(p + Vector2(-r * 0.35, -r * 0.35), r * 0.28, Color(1, 1, 1, 0.55))
	g.line(p + Vector2(0, -r * 0.8), p + Vector2(2, -r * 1.4), Color("#4e342e"), 1.6)
	g.fill(Painter.ellipse_pts(p + Vector2(r * 0.5, -r * 1.2), r * 0.45, r * 0.22, -0.5, 8), Color("#43a047"))


func _seen(x: float) -> bool:
	return x > _lo and x < _hi


# دايرة صغيرة (دم، غبار، دخان) من قالب جاهز: أسرع بهواي من حساب دايرة كل مرة
var _dot_v := PackedVector2Array()
var _dot_c := PackedColorArray()


func _dot(p: Vector2, r: float, col: Color) -> void:
	if _dot_v.is_empty():
		var n := 10
		for i in n:
			var a0 := TAU * i / n
			var a1 := TAU * (i + 1) / n
			_dot_v.append_array([Vector2.ZERO, Vector2(cos(a0), sin(a0)), Vector2(cos(a1), sin(a1))])
		_dot_c.resize(_dot_v.size())
	_dot_c.fill(col)
	g.b.soup(Transform2D(0.0, Vector2(r, r), 0.0, p) * _dot_v, _dot_c)
