# ════════ رسم الشخصيات (هيكل عظمي + أنيميشن) ════════
# كل شخصية = عظام (فخذ، ساق، ذراع، جذع، راس) تتحرك بزوايا، ونرسم فوقها أشكال مظللة.
# الرسم يكون والشخصية واجهة لليمين، ونقطة الأصل (0,0) = بين الرجلين على الأرض.
class_name Rig
extends RefCounted

const SIZE := {thigh = 30.0, shin = 29.0, foot = 7.0, torso = 40.0, head = 14.0, upper = 25.0, fore = 23.0}
const STAND := 30.0 + 29.0 + 7.0

static func V(x: float, y: float) -> Vector2:
	return Vector2(x, y)


static func add(a: Vector2, ang: float, len: float) -> Vector2:
	return a + Vector2(sin(ang), cos(ang)) * len


# ذراع بطريقة IK: نعطيه الكتف ووين لازم توصل الإيد، وهو يحسب الكوع
static func ik(s: Vector2, t: Vector2, a: float, b: float) -> Vector2:
	var d := clampf(s.distance_to(t), absf(a - b) + 0.01, a + b - 0.01)
	var base := (t - s).angle()
	var off := acos(clampf((a * a + d * d - b * b) / (2 * a * d), -1, 1))
	var e1 := s + Vector2(cos(base + off), sin(base + off)) * a
	var e2 := s + Vector2(cos(base - off), sin(base - off)) * a
	return e1 if e1.y > e2.y else e2 # الكوع يكون لتحت


# ── الوضعيات ──
# pose = {torso, head, legs: [[thigh, knee], [thigh, knee]] (ورا، قدّام), arms: [4], air, bob}
static func leg_reach(l: Array) -> float:
	return SIZE.thigh * cos(l[0]) + SIZE.shin * cos(l[0] - l[1]) + SIZE.foot


static func hip_of(p: Dictionary) -> Vector2:
	var h: float = STAND - 4 if p.air else maxf(leg_reach(p.legs[0]), leg_reach(p.legs[1]))
	return Vector2(0, -h + p.bob)


static func soldier_pose(mode: String, phase: float, t: float) -> Dictionary:
	var arms := [0.0, 0.0, 0.0, 0.0]
	match mode:
		"run":
			var s := sin(phase)
			var knee := func(q: float) -> float: return 0.15 + 1.15 * pow(maxf(0.0, cos(q)), 2)
			return {torso = 0.13, head = -0.08, legs = [[-0.55 * s, knee.call(phase + PI)], [0.55 * s, knee.call(phase)]], arms = arms, air = false, bob = -2.5 * absf(cos(phase))}
		"jump":
			return {torso = 0.08, head = -0.05, legs = [[0.15, 0.9], [0.95, 1.5]], arms = arms, air = true, bob = 0.0}
		"fall":
			return {torso = 0.02, head = 0.0, legs = [[-0.3, 0.35], [0.4, 0.55]], arms = arms, air = true, bob = 0.0}
		"hurt":
			return {torso = -0.22, head = -0.25, legs = [[-0.2, 0.3], [0.25, 0.2]], arms = arms, air = false, bob = 0.0}
	# وقفة + تنفّس
	var br := sin(t * 2.4)
	return {torso = 0.03 + br * 0.012, head = br * 0.02, legs = [[-0.12, 0.12], [0.14, 0.1]], arms = arms, air = false, bob = br * 0.8}


# وضعية الزومبي (مشية عرجة، ايدين لقدّام)
static func zombie_pose(mode: String, phase: float, t: float, atk: float) -> Dictionary:
	var s := sin(phase)
	var sway := sin(t * 1.7)
	if mode == "fly":
		# الطاير: مايل لقدّام، ايديه ممدودة لتحت، ورجليه متدلية
		return {torso = 0.55, head = 0.12, legs = [[-0.2 + 0.12 * sin(t * 3), 0.55], [0.18 + 0.12 * sin(t * 3 + 1), 0.75]],
			arms = [1.05 + 0.12 * sin(t * 4), 0.25, 1.2 + 0.12 * sin(t * 4 + 1), 0.2], air = true, bob = 0.0}
	if mode == "air":
		return {torso = 0.25, head = 0.2, legs = [[-0.2, 0.6], [0.6, 1.0]], arms = [2.1, 0.3, 2.3, 0.2], air = true, bob = 0.0}
	var arms := [1.35 + 0.1 * sin(phase + 1.2) + sway * 0.03, 0.25, 1.42 + 0.1 * sin(phase) + sway * 0.04, 0.18]
	var torso := 0.36 + 0.05 * sin(phase * 2)
	if mode == "attack":
		# يرفع ايديه ويضرب لتحت
		var k := minf(1.0, atk / 0.35)
		var sw := k / 0.4 if k < 0.4 else 1 - (k - 0.4) / 0.6
		arms = [1.2 + sw * 1.1, 0.4 - sw * 0.3, 1.25 + sw * 1.2, 0.3 - sw * 0.2]
		torso = 0.4 + (1 - sw) * 0.15
	var walking := mode == "walk"
	var legs: Array
	if walking:
		legs = [[-0.32 * s, 0.2 + 0.5 * pow(maxf(0.0, cos(phase + PI)), 2)], [0.48 * s, 0.15 + pow(maxf(0.0, cos(phase)), 2)]]
	else:
		legs = [[-0.15, 0.2], [0.18, 0.15]]
	return {torso = torso, head = 0.28 + (0.1 * sin(phase + 0.5) if walking else sway * 0.06), legs = legs, arms = arms, air = false,
		bob = -3 * absf(cos(phase)) if walking else sway}


# ── أجزاء مشتركة ──
static func ear(g: Painter, x: float, y: float, skin: Color) -> void:
	g.fill(Painter.ellipse_pts(V(x, y), 3, 4.2, 0.15, 12), Painter.dark(skin, 0.06))
	g.line_loop(Painter.ellipse_pts(V(x, y), 3, 4.2, 0.15, 12), Painter.dark(skin, 0.45), 1.2)


static func draw_leg(g: Painter, hip: Vector2, l: Array, pants: Color, boot: Color, back: bool, pads: bool) -> void:
	var k := add(hip, l[0], SIZE.thigh)
	var shin_ang: float = l[0] - l[1]
	var a := add(k, shin_ang, SIZE.shin)
	var pc := Painter.dark(pants, 0.12) if back else pants
	g.limb(hip, k, 15, 13, pc)
	g.limb(k, a, 13, 11, pc)
	if pads:
		g.save()
		g.translate(k.x, k.y)
		g.rotate(-shin_ang)
		g.shade(Painter.rect_pts(-6, -3, 12, 10, 3), Painter.dark(Color("#4a4434"), 0.2) if back else Color("#4a4434"))
		g.restore()
	# الجزمة
	g.save()
	g.translate(a.x, a.y)
	g.rotate(-shin_ang * 0.55)
	var pts := PackedVector2Array([V(-7, -7), V(6, -7)])
	Painter.quad(pts, V(15, -4), V(15, 2), 4)
	pts.append(V(15, 6))
	pts.append(V(-8, 6))
	Painter.quad(pts, V(-9, -1), V(-7, -7), 4)
	pts.remove_at(pts.size() - 1)
	g.shade(pts, Painter.dark(boot, 0.15) if back else boot)
	g.fill(Painter.rect_pts(-8, 3.5, 23, 2.5), Color("#15100c"))
	g.restore()


# ── الأسلحة ──
# نقطة (0,0) = مقبض السلاح، والسبطانة لليمين
const GUN := {
	"pistol": {grip = Vector2(24, 5), front = Vector2(3, 3), muzzle = Vector2(21, -8.5)},
	"akm": {grip = Vector2(10, 15), front = Vector2(33, -4), muzzle = Vector2(65, -6.5)},
	"pkm": {grip = Vector2(8, 16), front = Vector2(36, -3), muzzle = Vector2(86, -7)},
}


static func draw_grenade(g: Painter, x: float, y: float, rot := 0.0) -> void:
	g.save()
	g.translate(x, y)
	g.rotate(rot)
	g.shade(Painter.ellipse_pts(Vector2.ZERO, 5.5, 7, 0, 14), Color("#4f5e38"))
	g.line(V(-5, -1), V(5, -1), Color(0, 0, 0, 0.35), 1)
	g.line(V(-5, 3), V(5, 3), Color(0, 0, 0, 0.35), 1)
	g.fill(Painter.rect_pts(-2.5, -10, 5, 3.5), Color("#6b6b6b"))
	var lever := PackedVector2Array([V(2, -9)])
	Painter.quad(lever, V(7, -8), V(6, -1), 4)
	g.polyline(lever, Color("#9a9a9a"), 1.4)
	g.line_loop(Painter.ellipse_pts(V(-4, -10), 2, 2, 0, 8), Color("#9a9a9a"), 1.4)
	g.restore()


static func _poly(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p)
	return out


static func draw_gun(g: Painter, id: String) -> void:
	var metal := Color("#3a3d44")
	var wood := Color("#8a4f22")
	if id == "pkm":
		# رشاش PKC: أخمص هيكلي، صندوق طلق، سبطانة طويلة، مقبض حمل
		var st := _poly([V(-36, -5), V(-4, -10), V(-2, -1), V(-30, 8)])
		Painter.quad(st, V(-39, 3), V(-36, -5), 3)
		st.remove_at(st.size() - 1)
		g.shade(st, Color("#2b2826"))
		g.fill(Painter.ellipse_pts(V(-20, -1), 8, 3, -0.25, 12), Color(0, 0, 0, 0.55))
		g.shade(Painter.rect_pts(8, -2, 18, 17, 2), Color("#4f5a34"))
		var belt := PackedVector2Array([V(10, -3)])
		Painter.quad(belt, V(16, -9), V(22, -4), 5)
		g.polyline(belt, Color("#d9a441"), 2.2)
		g.shade(_poly([V(2, -2), V(9, -2), V(7, 14), V(0, 12)]), Color("#2b2826"))
		g.shade(Painter.rect_pts(-4, -12, 36, 11, 2), metal)
		var handle := PackedVector2Array([V(34, -12)])
		Painter.quad(handle, V(42, -22), V(50, -12), 6)
		g.polyline(handle, Painter.OUTLINE, 2.4)
		g.shade(Painter.rect_pts(32, -12, 30, 4, 1.5), Color("#2c2e33"))
		g.shade(Painter.rect_pts(32, -9, 50, 4.5), Color("#26282d"))
		g.line(V(64, -5), V(46, -2), Color("#1d1f23"), 2)
		g.line(V(64, -5), V(48, 1), Color("#1d1f23"), 2)
		g.shade(Painter.rect_pts(80, -10.5, 7, 7), Color("#1d1f23"))
		g.shade(Painter.rect_pts(74, -15, 2.5, 6), Color("#1d1f23"))
		g.fill(Painter.rect_pts(-2, -11, 32, 2), Color(1, 1, 1, 0.15))
		return
	if id == "pistol":
		g.shade(_poly([V(-2, -4), V(6, -4), V(4, 10), V(-5, 9)]), Color("#2a2a2e"))
		var guard := PackedVector2Array()
		Painter.arc_pts(guard, V(7, -1), 4, 0, PI, 6)
		g.polyline(guard, Painter.OUTLINE, 1.6)
		g.shade(Painter.rect_pts(-4, -13, 26, 8, 2), metal)
		g.fill(Painter.rect_pts(-2, -12, 22, 2), Color(1, 1, 1, 0.18))
		for i in 4:
			g.fill(Painter.rect_pts(-2 + i * 2.2, -11, 1, 5), Color("#1f2024"))
		return
	# AKM: الأخمص الخشب
	var stock := _poly([V(-30, -4), V(-3, -9), V(-1, -1), V(-27, 7)])
	Painter.quad(stock, V(-32, 2), V(-30, -4), 3)
	stock.remove_at(stock.size() - 1)
	g.shade(stock, wood)
	# المخزن المعكوف
	var mag := _poly([V(14, -2), V(22, -2)])
	Painter.quad(mag, V(24, 8), V(29, 16), 4)
	mag.append(V(20, 19))
	Painter.quad(mag, V(15, 9), V(14, -2), 4)
	mag.remove_at(mag.size() - 1)
	g.shade(mag, Color("#2c2a27"))
	g.shade(_poly([V(5, -2), V(12, -2), V(10, 14), V(3, 12)]), Color("#3b2516"))
	g.shade(Painter.rect_pts(-4, -11, 32, 10, 2), metal)
	g.shade(Painter.rect_pts(28, -14, 22, 3.5, 1.5), metal)
	g.shade(Painter.rect_pts(28, -10.5, 21, 9, 3), wood)
	g.shade(Painter.rect_pts(49, -8.5, 13, 4), Color("#26282d"))
	g.shade(Painter.rect_pts(61, -9.5, 5, 6), Color("#1d1f23"))
	g.shade(Painter.rect_pts(56, -14, 2.5, 5.5), Color("#1d1f23"))
	g.fill(Painter.rect_pts(-2, -10, 28, 2), Color(1, 1, 1, 0.15))


# ── الجندي ──
# look = {uniform, flash, recoil, aim (0 = قدّام), reload (تقدّم تبديل المخزن 0..1)}
static func draw_soldier(g: Painter, pose: Dictionary, slot, look: Dictionary) -> void:
	var weapon = slot if slot != null and slot != "grenade" else null
	g.flash = look.flash
	g.flash_to = Color("#ff3030")
	var U: Color = look.uniform
	var pants := Painter.dark(U, 0.12)
	var boot := Color("#3d2b1d")
	var skin := Color("#f0c19a")
	var glove := Color("#3a3328")

	var hip := hip_of(pose)
	var up := Vector2(sin(pose.torso), -cos(pose.torso))
	var sh := hip + up * SIZE.torso
	var neck := hip + up * (SIZE.torso + 4)

	# مكان السلاح والإيدين
	var gi = GUN[weapon] if weapon != null else null
	var rec: float = look.recoil
	# وقت تبديل المخزن: السلاح ينزل شوية لتحت، والإيد الثانية تسحب المخزن وترجعه
	var rl: float = look.reload
	var aim: float = 0.55 if rl > 0 else look.aim
	var gun_ang := aim - rec * 0.08
	var gp := Vector2.ZERO
	if gi != null:
		gp = sh + Vector2(gi.grip.x - rec * 6, gi.grip.y - rec * 1.5).rotated(aim)
	var to_world := func(q: Vector2) -> Vector2: return gp + q.rotated(gun_ang)

	var back_sh := sh + V(-3, 3)
	var front_sh := sh + V(2, 4)
	var grenade: bool = slot == "grenade"
	var pull := sin(rl * PI) if rl > 0 else 0.0
	var back_hand: Vector2
	var mag_at := Vector2.ZERO
	if gi != null:
		mag_at = to_world.call(V(1, 10) if weapon == "pistol" else V(18, 12 + pull * 26))
		back_hand = mag_at + V(-pull * 6, 0) if rl > 0 else to_world.call(gi.front)
	elif grenade:
		back_hand = sh + V(16, 18)
	else:
		back_hand = back_sh + V(4, 46)
	# الرمانة: الإيد ورا الكتف، ووقت الرمي تنمد لقدّام
	var front_hand: Vector2
	if gi != null:
		front_hand = to_world.call(Vector2.ZERO)
	elif grenade:
		front_hand = sh + (V(26, -6) if rec > 0.25 else V(-10, -8))
	else:
		front_hand = front_sh + V(6, 46)

	# الذراع البعيدة (ورا الجسم)
	var be := ik(back_sh, back_hand, SIZE.upper, SIZE.fore)
	g.limb(back_sh, be, 12, 11, Painter.dark(U, 0.25))
	g.limb(be, back_hand, 11, 9, Painter.dark(U, 0.2))
	# المخزن بإيده وهو يبدّل
	if rl > 0 and pull > 0.15 and gi != null:
		g.save()
		g.translate(back_hand.x, back_hand.y + 4)
		g.rotate(gun_ang + 0.3)
		g.shade(Painter.rect_pts(-4, -2, 8, 14 if weapon == "pkm" else 16, 2), Color("#4f5a34") if weapon == "pkm" else Color("#2c2a27"))
		g.restore()
	g.blob(back_hand, 5, Painter.dark(glove, 0.2))

	draw_leg(g, hip, pose.legs[0], pants, boot, true, true)

	# الجذع
	g.save()
	g.translate(hip.x, hip.y)
	g.rotate(pose.torso)
	var body := _poly([V(-12, 2), V(11, 2)])
	Painter.quad(body, V(16, -18), V(13, -38))
	Painter.quad(body, V(0, -46), V(-13, -40))
	Painter.quad(body, V(-17, -20), V(-12, 2))
	body.remove_at(body.size() - 1)
	g.shade(body, U)
	# الصدرية
	var vest := _poly([V(-12, -6), V(13, -6), V(14, -33)])
	Painter.quad(vest, V(0, -38), V(-13, -34))
	g.shade(vest, Painter.dark(U, 0.3))
	for p in [V(2, -20), V(-7, -20)]:
		g.shade(Painter.rect_pts(p.x, p.y, 9, 11, 2), Painter.dark(U, 0.18))
	g.shade(Painter.rect_pts(-12.5, -6, 25, 6), Color("#2e251a"))
	g.fill(Painter.rect_pts(4, -5, 5, 4), Color("#d9a441"))
	g.restore()

	draw_leg(g, hip, pose.legs[1], pants, boot, false, true)

	# الراس
	g.save()
	g.translate(neck.x, neck.y)
	g.rotate(pose.torso * 0.5 + pose.head + aim * 0.35)
	g.limb(V(0, 2), V(1, -6), 9, 9, skin)
	var face := _poly([V(-11, -14)])
	Painter.quad(face, V(-12, -2), V(-4, 1))
	Painter.quad(face, V(6, 3), V(11, -3))
	Painter.quad(face, V(15, -7), V(13.5, -10))
	face.append(V(15.5, -14))
	Painter.quad(face, V(14, -27), V(1, -28))
	Painter.quad(face, V(-12, -27), V(-11, -14))
	face.remove_at(face.size() - 1)
	g.shade(face, skin)
	g.fill(Painter.ellipse_pts(V(-6, -14), 4, 6, 0.2, 12), Color("#4a2f1c"))
	ear(g, -2.5, -12, skin)
	g.line(V(7, -3.5), V(11, -4.5), Color("#8a4b3a"), 1.6)
	# النظارة الخضرا
	g.fill(Painter.rect_pts(-12, -19, 18, 4), Color("#262626"))
	for l in [[14.5, -16.5, 3.2], [8.0, -16.5, 4.6]]:
		g.circle(V(l[0], l[1]), l[2] + 1.8, Color("#2a2a2a"))
		g.circle(V(l[0], l[1]), l[2], Color("#5cc23f"))
		g.circle(V(l[0] - l[2] * 0.35, l[1] - l[2] * 0.35), l[2] * 0.4, Color("#e4ffc9"))
	# الخوذة
	var helm := _poly([V(-15, -15)])
	Painter.quad(helm, V(-16, -34), V(1, -35))
	Painter.quad(helm, V(17, -34), V(17, -21))
	helm.append(V(21, -19))
	Painter.quad(helm, V(21, -16.5), V(17, -16.5), 3)
	helm.append(V(-13, -16))
	g.shade(helm, Color("#5b5444"))
	g.line(V(-13, -19), V(16, -19), Color("#3a3429"), 2.5)
	g.fill(Painter.ellipse_pts(V(-3, -29), 7, 2.5, -0.2, 12), Color(1, 1, 1, 0.16))
	g.restore()

	# السلاح
	if gi != null:
		g.save()
		g.translate(gp.x, gp.y)
		g.rotate(gun_ang)
		draw_gun(g, weapon)
		g.restore()

	# الذراع القريبة
	var fe := ik(front_sh, front_hand, SIZE.upper, SIZE.fore)
	g.limb(front_sh, fe, 13, 11.5, U)
	g.limb(fe, front_hand, 11.5, 9.5, U)
	if grenade and rec <= 0.25:
		draw_grenade(g, front_hand.x + 2, front_hand.y - 5)
	g.blob(front_hand, 5.5, glove)
	g.flash = 0.0


# وين تطلع الطلقة (بالنسبة لرجلين اللاعب)
static func muzzle_of(weapon: String, recoil := 0.0, pose = null, aim := 0.0) -> Vector2:
	if pose == null:
		pose = soldier_pose("idle", 0, 0)
	var hip := hip_of(pose)
	var sh := hip + Vector2(sin(pose.torso), -cos(pose.torso)) * SIZE.torso
	var gi: Dictionary = GUN[weapon]
	var p := sh + Vector2(gi.grip.x - recoil * 6, gi.grip.y).rotated(aim)
	return p + (gi.muzzle as Vector2).rotated(aim)


# المظلة فوگ البوت
static func draw_parachute(g: Painter, t: float) -> void:
	g.save()
	g.rotate(sin(t * 1.6) * 0.06)
	var cy := -250.0
	var w := 92.0
	for k in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		g.line(V(k * w, cy + 8), V(k * 8, -112), Color(0.16, 0.12, 0.08, 0.8), 1.3)
	var panels := 6
	for i in panels:
		var pts := PackedVector2Array([V(0, cy + 10)])
		Painter.arc_pts(pts, Vector2.ZERO, 1, PI + float(i) / panels * PI, PI + float(i + 1) / panels * PI, 4)
		for j in range(1, pts.size()):
			pts[j] = V(pts[j].x * w, cy + 10 + pts[j].y * 62)
		g.fill(pts, Color("#e8e0c8") if i % 2 else Color("#6b7a3c"))
	var rim := PackedVector2Array()
	Painter.arc_pts(rim, Vector2.ZERO, 1, PI, TAU, 16)
	for j in rim.size():
		rim[j] = V(rim[j].x * w, cy + 10 + rim[j].y * 62)
	g.polyline(rim, Painter.OUTLINE, 2)
	g.restore()


# الطيارة اللي تنزّل البوت
static func draw_plane(g: Painter, x: float, y: float, dir: int, t: float) -> void:
	g.save()
	g.translate(x, y)
	g.scale(dir, 1)
	g.fill(_poly([V(-10, -4), V(40, -4), V(18, -46), V(-2, -46)]), Color("#4f5843"))
	var body := _poly([V(-150, -6)])
	Painter.quad(body, V(-120, -24), V(-40, -22))
	body.append(V(90, -20))
	Painter.quad(body, V(130, -16), V(140, 0))
	Painter.quad(body, V(130, 16), V(90, 18))
	body.append(V(-60, 18))
	Painter.quad(body, V(-130, 14), V(-150, -6))
	body.remove_at(body.size() - 1)
	g.shade(body, Color("#6b7558"))
	g.shade(_poly([V(-120, -14), V(-150, -60), V(-128, -60), V(-90, -18)]), Color("#5b654b"))
	for i in 5:
		g.fill(Painter.rect_pts(-40 + i * 22, -12, 12, 8, 3), Color("#bfe3f2"))
	g.shade(_poly([V(-14, 4), V(40, 4), V(16, 58), V(-6, 58)]), Color("#7a8566"))
	g.shade(Painter.rect_pts(14, 14, 40, 14, 6), Color("#3f4635"))
	g.fill(Painter.ellipse_pts(V(56, 21), 3 + absf(sin(t * 40)) * 2, 22, 0, 12), Color(0.12, 0.12, 0.12, 0.55))
	g.circle(V(-80, 2), 8, Color("#e8e0c8"))
	g.restore()


# ── الزومبي ──
const ZLOOK := {
	"flyer": {skin = Color("#a194ad"), shirt = Color("#3b2f45"), pants = Color("#2d2a33"), eye = Color("#ff3a2a")},
	"runner": {skin = Color("#c9c2b0"), shirt = Color("#2b2b2e"), pants = Color("#3a3f4a"), eye = Color("#ff2a2a")},
	"walker": {skin = Color("#93a86e"), shirt = Color("#4f6f99"), pants = Color("#4a4f5c"), eye = Color("#ff3a2a")},
	"tough": {skin = Color("#86a08c"), shirt = Color("#7d3434"), pants = Color("#3c4038"), eye = Color("#ffd23f"), helmet = Color("#56604f"), vest = Color("#3d4636")},
	"brute": {skin = Color("#7b9658"), shirt = Color("#5e4680"), pants = Color("#3b322c"), eye = Color("#ff3a2a")},
}


static func draw_zombie(g: Painter, kind: String, pose: Dictionary, flash: float, t: float) -> void:
	g.flash = flash
	g.flash_to = Color.WHITE
	var L: Dictionary = ZLOOK[kind]
	var big := kind == "brute"
	var arm_w := 1.45 if big else 1.0
	var hip := hip_of(pose)
	var up := Vector2(sin(pose.torso), -cos(pose.torso))
	var sh := hip + up * SIZE.torso
	var neck := hip + up * (SIZE.torso + 3)

	var arm := func(shoulder: float, elbow: float, back: bool) -> void:
		var s0 := sh + (V(-3, 3) if back else V(2, 5))
		var e := add(s0, shoulder, SIZE.upper)
		var h := add(e, shoulder + elbow, SIZE.fore)
		var sk: Color = Painter.dark(L.skin, 0.25) if back else L.skin
		g.limb(s0, e, 12 * arm_w, 10.5 * arm_w, Painter.dark(L.shirt, 0.25) if back else L.shirt)
		g.limb(e, h, 10 * arm_w, 8.5 * arm_w, sk)
		g.blob(h, 4.8 * arm_w, sk)

	# أجنحة الطاير (ترفرف)
	var wing := func(front: bool) -> void:
		var flap := sin(t * 9 + (0.0 if front else 0.4)) * 0.55
		g.save()
		g.translate(sh.x - 6, sh.y + 6)
		g.rotate(-0.6 + flap + (0.35 if front else -0.25))
		var span := 78.0 if front else 66.0
		var pts := PackedVector2Array([Vector2.ZERO])
		Painter.quad(pts, V(-span * 0.3, -span * 0.75), V(-span, -span * 0.55))
		Painter.quad(pts, V(-span * 0.8, -span * 0.25), V(-span * 0.85, -span * 0.05))
		Painter.quad(pts, V(-span * 0.6, -span * 0.1), V(-span * 0.55, span * 0.12))
		Painter.quad(pts, V(-span * 0.35, 0), V(-span * 0.25, span * 0.22))
		Painter.quad(pts, V(-span * 0.12, span * 0.08), V(0, 6))
		g.shade(pts, Color("#4a3c55") if front else Color("#30283a"))
		for k in [0.55, 0.85]:
			g.line(Vector2.ZERO, V(-span * k, -span * (0.05 if k > 0.7 else 0.1) * 2), Color("#1c1622"), 1.6)
		g.restore()

	if kind == "flyer":
		wing.call(false)
	arm.call(pose.arms[0], pose.arms[1], true)
	draw_leg(g, hip, pose.legs[0], L.pants, Color("#2b2520"), true, false)

	# الجذع + قميص ممزّق
	g.save()
	g.translate(hip.x, hip.y)
	g.rotate(pose.torso)
	var wide := 1.35 if big else 1.0
	var body := PackedVector2Array()
	for i in 7:
		body.append(V((-12 + i * 4) * wide, 0 if i % 2 else 5))
	Painter.quad(body, V(16 * wide, -18), V(13 * wide, -38))
	Painter.quad(body, V(0, -45), V(-13 * wide, -40))
	Painter.quad(body, V(-17 * wide, -20), V(-12 * wide, 4))
	body.remove_at(body.size() - 1)
	g.shade(body, L.shirt)
	g.fill(Painter.ellipse_pts(V(5 * wide, -22), 5, 7, 0.4, 12), Color(0.37, 0.08, 0.08, 0.75))
	g.fill(Painter.ellipse_pts(V(-4 * wide, -10), 3, 4, 0, 10), Color(0.37, 0.08, 0.08, 0.75))
	if L.has("vest"):
		var vest := _poly([V(-12, -8), V(13, -8), V(14, -34)])
		Painter.quad(vest, V(0, -39), V(-13, -35))
		g.shade(vest, L.vest)
	g.restore()

	draw_leg(g, hip, pose.legs[1], L.pants, Color("#2b2520"), false, false)

	# الراس
	g.save()
	g.translate(neck.x, neck.y)
	g.rotate(pose.torso * 0.6 + pose.head)
	if big:
		g.scale(1.1, 1.1)
	g.limb(V(0, 3), V(1, -5), 10, 9, Painter.dark(L.skin, 0.1))
	var face := _poly([V(-11, -13)])
	Painter.quad(face, V(-12, -1), V(-3, 2))
	Painter.quad(face, V(7, 4), V(12, -2))
	face.append(V(14.5, -11))
	Painter.quad(face, V(14, -27), V(1, -28))
	Painter.quad(face, V(-12, -27), V(-11, -13))
	face.remove_at(face.size() - 1)
	g.shade(face, L.skin)
	g.fill(Painter.ellipse_pts(V(-4, -20), 4, 3, 0.3, 10), Painter.dark(L.skin, 0.25))
	g.fill(Painter.ellipse_pts(V(3, -6), 2.5, 2, 0, 8), Painter.dark(L.skin, 0.25))
	ear(g, -2.5, -12, L.skin)
	# تجويف العين + عين تلمع
	g.fill(Painter.ellipse_pts(V(9, -15), 4.5, 3.8, 0, 12), Color("#2a1f1a"))
	var eye: Color = L.eye
	g.glow(V(9.5, -15), 5, Color(1, 1, 1, 0.75 + 0.25 * sin(t * 6)), Color(eye.r, eye.g, eye.b, 0), 10)
	g.circle(V(9.5, -15), 2, eye)
	# الحلگ المفتوح والسنون
	var mouth := _poly([V(5, -5)])
	Painter.quad(mouth, V(10, -8), V(13, -6), 4)
	mouth.append(V(12, 0))
	Painter.quad(mouth, V(8, 1), V(5, -5), 4)
	mouth.remove_at(mouth.size() - 1)
	g.fill(mouth, Color("#2b0d0d"))
	g.fill(Painter.rect_pts(7, -6.5, 1.6, 2), Color("#e8e0c8"))
	g.fill(Painter.rect_pts(9.5, -7, 1.6, 2.2), Color("#e8e0c8"))
	g.fill(Painter.rect_pts(11.5, -6.5, 1.4, 1.8), Color("#e8e0c8"))
	if L.has("helmet"):
		var helm := _poly([V(-14, -15)])
		Painter.quad(helm, V(-15, -34), V(1, -34))
		Painter.quad(helm, V(16, -33), V(16, -18))
		helm.append(V(-13, -16))
		g.shade(helm, L.helmet)
		g.fill(Painter.ellipse_pts(V(-3, -28), 7, 2.5, -0.2, 12), Color(1, 1, 1, 0.14))
	else:
		# شعر متفرّق
		for i in 5:
			var x := -8.0 + i * 3.5
			var hair := PackedVector2Array([V(x, -26 + absi(i - 2))])
			Painter.quad(hair, V(x - 2, -31), V(x - 4 + i, -30), 4)
			g.polyline(hair, Color("#2f2a20"), 1.6)
	g.restore()

	arm.call(pose.arms[2], pose.arms[3], false)
	if kind == "flyer":
		wing.call(true)
	g.flash = 0.0


# ── الوحش: كتلة شعر خضرا محنية، قرون، عيون تلمع، حلگ بأنياب، ايدين طويلة بمخالب ──
const FUR := [Color("#26381a"), Color("#3f5a24"), Color("#5f7d33"), Color("#86a248"), Color("#b7cc7a")]


static func claws(g: Painter, x: float, y: float, ang: float, n: int, len: float) -> void:
	g.save()
	g.translate(x, y)
	g.rotate(ang)
	for i in n:
		var off := (i - (n - 1) / 2.0) * 6
		var pts := PackedVector2Array([V(off - 2.5, 0)])
		Painter.quad(pts, V(off + len * 0.4, len * 0.5), V(off + len * 0.15, len), 4)
		Painter.quad(pts, V(off + len * 0.2, len * 0.45), V(off + 2.5, 0), 4)
		pts.remove_at(pts.size() - 1)
		g.shade(pts, Color("#dedac8"))
	g.restore()


static func strands(g: Painter, a: Vector2, b: Vector2, n: int, t: float, seed_v: float) -> void:
	for i in n:
		var k := (i + 0.5) / n
		var x := a.x + (b.x - a.x) * k + sin(seed_v + i * 7.1) * 8
		var y := a.y + (b.y - a.y) * k + cos(seed_v + i * 3.7) * 6
		var len := 8.0 + fmod(absf(seed_v * 13 + i * 29), 9)
		var pts := PackedVector2Array([V(x, y)])
		Painter.quad(pts, V(x + sin(t * 2 + i) * 2, y + len * 0.6), V(x - 2 + sin(t * 2.4 + i) * 3, y + len), 3)
		g.polyline(pts, FUR[3 + (i % 2)], 1.5)


static func draw_monster(g: Painter, phase: float, t: float, atk: float, moving: bool, flash: float) -> void:
	g.flash = flash
	g.flash_to = Color.WHITE
	var sw := sin(phase) if moving else sin(t * 1.4) * 0.12
	var bob := -absf(cos(phase)) * 5 if moving else sin(t * 2) * 1.5

	var leg := func(hx: float, back: bool) -> void:
		var a := (-1.0 if back else 1.0) * sw * 0.5
		var hip := V(hx, -54 + bob)
		var knee := add(hip, a + 0.25, 28)
		var foot := add(knee, a - 0.35, 28)
		foot.y = minf(foot.y, -4)
		var col: Color = Painter.dark(FUR[2], 0.25) if back else FUR[2]
		g.limb(hip, knee, 34, 28, col)
		g.limb(knee, foot, 28, 22, col)
		claws(g, foot.x + 8, foot.y + 2, -1.35, 3, 16)
		strands(g, hip, knee, 6, t, hx)

	var arm := func(sx: float, sy: float, back: bool) -> void:
		var ang := 0.3 + (1.0 if back else -1.0) * sw * 0.35
		var fore := 0.3
		if not back and atk > 0:
			# يرفع ايده ويضرب لتحت بمخالبه
			var k := minf(1.0, atk / 0.35)
			var s := k / 0.4 if k < 0.4 else 1 - (k - 0.4) / 0.6
			ang = 0.3 + s * 2.1
			fore = 0.3 - s * 0.4
		var sh := V(sx, sy + bob)
		var el := add(sh, ang, 52)
		var hand := add(el, ang + fore, 52)
		var col: Color = Painter.dark(FUR[2], 0.28) if back else FUR[2]
		g.limb(sh, el, 34, 28, col)
		g.limb(el, hand, 28, 24, col)
		strands(g, sh, el, 7, t, sx + 3)
		strands(g, el, hand, 6, t, sx + 9)
		claws(g, hand.x, hand.y, -(ang + fore) + 0.2, 4, 22)

	arm.call(-30, -104, true)
	leg.call(-24, true)

	# الجسم المحني
	var cy := -100 + bob
	g.shade(Painter.ellipse_pts(V(-4, cy), 66, 58, -0.15, 28), FUR[2], true, 0.45)
	for i in 46:
		var a := -PI + (i / 46.0) * PI * 1.9 - 0.3
		var r := 60.0 + (i * 37) % 9
		var x := -4 + cos(a) * r
		var y := cy + sin(a) * r * 0.9
		var len := 10.0 + (i * 17) % 10
		var out := atan2(y - cy, x + 4)
		var pts := PackedVector2Array([V(x, y)])
		Painter.quad(pts, V(x + cos(out) * len * 0.6 + sin(t * 2 + i) * 2, y + sin(out) * len * 0.6 + 3), V(x + cos(out) * len, y + sin(out) * len + 6), 3)
		g.polyline(pts, FUR[4 if i % 3 == 0 else 3], 1.8)
	for i in 28:
		var x := -50.0 + (i * 41) % 95
		var y := cy - 40 + (i * 23) % 80
		var pts := PackedVector2Array([V(x, y)])
		Painter.quad(pts, V(x + 3, y + 7), V(x + 1, y + 13), 3)
		var col: Color = FUR[4] if i % 2 else FUR[1]
		col.a = 0.6
		g.polyline(pts, col, 1.4)

	leg.call(20, false)

	# القرون
	for h in [[6.0, -146.0, -1.0], [40.0, -142.0, 1.0]]:
		var hx: float = h[0]
		var hy: float = h[1] + bob
		var dir: float = h[2]
		var pts := PackedVector2Array([V(hx - 6, hy + 8)])
		Painter.quad(pts, V(hx + dir * 4, hy - 20), V(hx + dir * 16, hy - 26), 5)
		Painter.quad(pts, V(hx + dir * 6, hy - 10), V(hx + 6, hy + 8), 5)
		pts.remove_at(pts.size() - 1)
		g.shade(pts, Color("#8a8878"))

	# الوجه: تجويف غامق، عيون تلمع، حلگ بأنياب
	var fx := 30.0
	var fy := -104 + bob
	g.glow(V(fx, fy), 30, Color("#1a2410"), Color(0.1, 0.14, 0.06, 0), 18)
	var gl := 0.8 + 0.2 * sin(t * 5)
	for ex in [fx - 9, fx + 9]:
		g.glow(V(ex, fy - 9), 6, Color(1, 1, 1, gl), Color(1, 0.88, 0.4, 0), 10)
		g.circle(V(ex, fy - 9), 2.4, Color("#ffe066"))
	var open := 6.0 if atk > 0 else 2 + sin(t * 3) * 1.5
	g.fill(Painter.ellipse_pts(V(fx + 2, fy + 12), 17, 10 + open, 0, 18), Color("#2b0d0a"))
	for i in 6:
		var x := fx - 12 + i * 5
		g.fill(_poly([V(x, fy + 3), V(x + 2.5, fy + 12 + (i % 2) * 3), V(x + 5, fy + 3)]), Color("#efe8d0"))
		g.fill(_poly([V(x, fy + 21 + open), V(x + 2.5, fy + 13 + open - (i % 2) * 2), V(x + 5, fy + 21 + open)]), Color("#efe8d0"))
	strands(g, V(fx - 20, fy - 22), V(fx + 20, fy - 22), 8, t, 5)

	arm.call(16, -84, false)
	g.flash = 0.0
