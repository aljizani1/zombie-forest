# ════════ رسم كل شي يتحرك (كل إطار) ════════
# الشخصيات، الطلق، الرمانات، الانفجارات، الدم، الفلوس اللي تطلع.
extends Node2D

const PW := Game.PW
const PH := Game.PH

var game: Game
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
	if game.plane != null:
		Rig.draw_plane(g, game.plane.x, game.plane.y, game.plane.dir, t)
	# دم وحروق على الأرض
	for d in game.decals:
		var col := Color(0.08, 0.05, 0.04, minf(0.5, d.life * 0.12)) if d.burn else Color(0.31, 0.03, 0.03, minf(0.55, d.life * 0.2))
		g.fill(Painter.ellipse_pts(Vector2(d.x, d.y), d.r, d.r * 0.22, 0, 16), col)
	# الميتين ورا
	for z in game.zs:
		if z.dead > 0:
			_draw_zombie(z, t)
	for z in game.zs:
		if z.dead == 0:
			_draw_zombie(z, t)
	for i in range(game.players.size() - 1, -1, -1):
		_draw_player(game.players[i], t)

	# الطلق
	for b in game.bullets:
		var tail := Vector2(b.x - b.vx * 0.03, b.y - b.vy * 0.03)
		var n := Vector2(-b.vy, b.vx).normalized() * 1.5
		var head := Vector2(b.x, b.y)
		g.b.draw_polygon(PackedVector2Array([tail + n, head + n, head - n, tail - n]), PackedColorArray([Color(1, 0.78, 0.31, 0), Color(1, 0.96, 0.78, 1), Color(1, 0.96, 0.78, 1), Color(1, 0.78, 0.31, 0)]))

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
			g.circle(Vector2(q.x, q.y), q.size, col)

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
			_text(q.text, Vector2(x + 22 + w / 2, q.y), 22, Color(1, 0.82, 0.25, a), Color(0, 0, 0, 0.75 * a))


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
	if ground > Config.AH:
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
	if p.flash > 0 and p.hp > 0 and p.weapon != "grenade":
		var m := Rig.muzzle_of(p.weapon, p.recoil, pose, aim)
		var mp := Vector2(cx + p.face * m.x, feet + m.y)
		var d := Vector2(p.face * cos(aim), sin(aim))
		g.glow(mp, 34, Color(1, 0.94, 0.7, 0.95), Color(1, 0.47, 0.08, 0), 16)
		g.fill(PackedVector2Array([mp + Vector2(-d.y, d.x) * 5, mp + d * 26, mp - Vector2(-d.y, d.x) * 5, mp + d * 8]), Color(1, 0.98, 0.86, 0.95))

	if p.bot:
		var top := p.y - 268 if p.chute else p.y - 22
		g.end()
		_text(p.name, Vector2(cx, top), 15, Color.WHITE, Color(0, 0, 0, 0.7))
		if p.hp > 0:
			_bar(cx, top + 6, 46, p.hp / p.max_hp, Color("#4fc3f7"))


func _draw_zombie(z: Game.Zombie, t: float) -> void:
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
	var flash := 0.7 if z.hurt > 0 else 0.0
	if z.kind == "monster":
		Rig.draw_monster(g, z.phase, t + z.id, 0.35 - z.atk_t if z.atk_t > 0 else 0.0, moving and z.dead == 0, flash)
	else:
		var mode := "walk" if moving else "idle"
		if z.dead > 0:
			mode = "idle"
		elif z.kind == "flyer":
			mode = "fly"
		elif not z.on_ground:
			mode = "air"
		elif z.atk_t > 0:
			mode = "attack"
		Rig.draw_zombie(g, z.kind, Rig.zombie_pose(mode, z.phase, t + z.id, 0.35 - z.atk_t), flash, t + z.id)
	g.alpha = 1.0
	g.restore()
	if z.dead == 0 and z.hp < z.max:
		var w := 96.0 if z.kind == "monster" else (70.0 if z.kind == "brute" else 44.0)
		_bar(cx, z.y - 18, w, z.hp / z.max, Color("#e53935"))
