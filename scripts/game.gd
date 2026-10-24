# ════════ منطق اللعبة ════════
# الحركة، الطلق، الرمانات، الزومبي (العادي والطاير والوحش)، البوت المساعد، والمراحل. ما بيه أي رسم.
# باللعب الجماعي: المضيف (authority) هو اللي يحرّك الزومبي ويحسب الضرب والقتل،
# والباقين يحرّكون لاعبهم بس ويستلمون الباقي من المضيف (snapshot).
class_name Game
extends RefCounted

const PW := 44.0
const PH := 128.0
const MAX_FALL := 1400.0
const AIM_LIMIT := 1.3
const HELPER := {chance = 0.2, at = [0.3, 0.6], hp = 120}


class Body:
	var x := 0.0
	var y := 0.0
	var w := 0.0
	var h := 0.0
	var vx := 0.0
	var vy := 0.0
	var on_ground := true
	var drop := 0.0
	var wall := 0 # صدم بحايط (1 يمين، -1 يسار)
	var wall_cell := Vector2i(-1, -1) # المربع اللي صدمه


class Player extends Body:
	var id := ""
	var name := ""
	var uniform := Color("#8a7d4f")
	var local := false
	var bot := false # البوت المساعد
	var chute := false # نازل بالمظلة
	var face := 1
	var hp := 100.0
	var max_hp := 100.0
	var inv := 0.0 # وقت الحماية بعد الضربة
	var kb := 0.0 # دفعة الضربة
	var phase := 0.0
	var fire_cd := 0.0
	var flash := 0.0
	var recoil := 0.0
	var weapon := "pistol"
	var firing := false
	var aim := 0.0 # زاوية التصويب بالعالم
	var ammo := {}
	var reload := 0.0
	var grenades := 0
	var g_cd := 0.0
	var bricks := 0 # كم طابوقة عنده (كل وحدة = مربع 40×40)
	var tool_cd := 0.0 # الانتظار بين ضربة كرك/بناء والثانية
	var g_throws := 0 # عداد الرمانات (حتى الباقين يعرفون إنك رميت)
	var g_seen := 0
	var dead := 0.0
	var safe := Vector2.ZERO # آخر مكان آمن (إذا وگع بحفرة يرجع له)
	var net = null # آخر حالة وصلت من الشبكة {x, y, vx, vy, at}


class Zombie extends Body:
	var id := 0
	var kind := "walker"
	var hp := 1.0
	var max := 1.0
	var speed := 0.0
	var face := 1
	var atk := 0.0
	var atk_t := 0.0 # وقت أنيميشن الضربة
	var jump_cd := 0.0
	var hurt := 0.0
	var dead := 0.0
	var kb := 0.0
	var air := 0.0
	var phase := 0.0
	var aim := 0.0
	var net = null


class Bullet:
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var dmg := 0.0
	var life := 1.2
	var owner := ""


class Grenade:
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var t := 0.0
	var rot := 0.0
	var owner := ""


class Particle:
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var life := 0.0
	var max := 1.0
	var color := Color.WHITE
	var size := 3.0
	var shell := false
	var smoke := false
	var rot := 0.0


# ── المدخلات ──
class Inp:
	var move := 0.0 # من -1 (يسار) إلى 1 (يمين)
	var down := false # نزول من المنصة
	var fire := false
	var jump := 0.0 # >0 يعني انضغط القفز قبل شوية
	var swap := false
	var throw := false # رمي رمانة مباشرة
	var reload := false
	var aim = null # زاوية التصويب، null = قدّام


var map: World
var level := 1.0 # الصعوبة (تتغير بعد كل جولة)
var cfg := {} # إعدادات الجولة حسب الصعوبة
var min_hp := {} # أقل صحة (نسبة) وصلها كل لاعب بهاي الجولة
var my_kills := 0
var my_headshots := 0
var took_damage := false
var time := 0.0
var players: Array[Player] = []
var zs: Array[Zombie] = []
var bullets: Array[Bullet] = []
var grenades: Array[Grenade] = []
var booms: Array = [] # {x, y, t}
var shake := 0.0
var parts: Array[Particle] = []
var pops: Array = [] # {x, y, text, life, head}
var decals: Array = [] # {x, y, r, life, burn}
var total := 0
var spawned := 0
var killed := 0
var spawn_cd := 1.5
var credits := {} # فلوس كل لاعب (حسب الـ id)
var authority := true # المضيف (أو لعب لوحدك)
var networked := false
var me_id := "me"
var kills: Array = [] # قتلات جديدة لازم تنرسل بالسنابشوت الجاي
var edits: Array = [] # تغييرات الأرض الأخيرة [عمود، صف، قيمة، وقت] (تنرسل كم مرة حتى ما تضيع)
const TOOLS := ["shovel", "brick"]
var status := "play" # play / won / lost
var end_t := 0.0
var owned: Array = ["pistol"]
var sounds: Array[String] = []
var next_id := 1
var helper_at = null # متى ينزل البوت (نسبة القتل)، null = ما ينزل هاي اللعبة
var plane = null # {x, y, dir, drop_x, dropped}


# who = {id, name, uniform} للاعب المحلي، net = لعب جماعي، slot = ترتيبه (حتى ما يطلعون فوگ بعض)
func _init(m: World, level_v: float, owned_list: Array, weapon: String, who := {}, is_authority := true, net := false, slot := 0) -> void:
	map = m
	map.reset_cells()
	level = maxf(1.0, level_v)
	cfg = Config.level_cfg(level)
	owned = owned_list
	authority = is_authority
	networked = net
	total = cfg.total
	me_id = who.get("id", "me")
	var mine := _make_player(me_id, who.get("name", "أنا"), who.get("uniform", Color("#8a7d4f")), weapon if owned.has(weapon) else "pistol", slot)
	mine.local = true
	players.append(mine)
	# البوت المساعد بس باللعب لوحدك
	helper_at = randf_range(HELPER.at[0], HELPER.at[1]) if not net and randf() < HELPER.chance else null


func me() -> Player:
	for p in players:
		if p.local:
			return p
	return players[0]


func humans() -> Array:
	return players.filter(func(p): return not p.bot)


func earned() -> int:
	return int(credits.get(me_id, 0)) + (Config.CLEAR_BONUS * ceili(level) if status == "won" else 0)


func _make_player(id: String, name: String, uniform: Color, weapon: String, slot := 0) -> Player:
	var p := Player.new()
	p.id = id
	p.name = name
	p.uniform = uniform
	p.w = PW
	p.h = PH
	p.x = clampf(map.start.x - PW / 2 + (1 if slot % 2 else -1) * ceili(slot / 2.0) * 70, 0, map.width - PW)
	p.y = minf(map.surface_below(p.x + PW / 2, map.start.y - 200), Config.AH) - PH
	p.hp = Config.PLAYER.hp
	p.max_hp = p.hp
	p.weapon = weapon
	for w in Config.WEAPONS:
		p.ammo[w] = Config.WEAPONS[w].mag
	p.grenades = Config.GRENADE.per_stage
	p.safe = Vector2(p.x, p.y)
	return p


static func is_gun(w: String) -> bool:
	return Config.WEAPONS.has(w)


static func local_aim(face: int, aim: float) -> float:
	var a := aim if face > 0 else PI - aim
	a = atan2(sin(a), cos(a))
	return clampf(a, -AIM_LIMIT, AIM_LIMIT)


static func world_aim(face: int, local: float) -> float:
	return local if face > 0 else PI - local


static func aim_of(p: Player) -> float:
	return local_aim(p.face, p.aim)


func reload_progress(p: Player) -> float:
	if p.reload > 0 and is_gun(p.weapon):
		return 1 - p.reload / Config.WEAPONS[p.weapon].reload
	return 0.0


# الحركة + التصادم ويا مربعات الأرض (تراب، طابوق، صخر) والمنصات
const STEP_UP := 22.0 # الدرجة الصغيرة (مربع واحد) يصعدها بدون قفز


func physics(o: Body, dt: float) -> bool:
	var was_air := not o.on_ground
	var C := World.CELL
	o.vy = minf(o.vy + Config.GRAVITY * dt, MAX_FALL)
	o.wall = 0
	o.wall_cell = Vector2i(-1, -1)

	# أفقي: المربع اللي قدّامك يصير حايط (إلا إذا درجة صغيرة، تصعدها)
	var mx := o.vx * dt
	o.x = clampf(o.x + mx, 0, map.width - o.w)
	var hb := map.hit_box(o.x, o.y, o.w, o.h)
	if hb.x >= 0:
		var feet := o.y + o.h
		var up_y := floorf((feet - 0.01) / C) * C - o.h
		if not was_air and o.y - up_y <= STEP_UP and map.hit_box(o.x, up_y, o.w, o.h).x < 0:
			o.y = up_y
		elif mx > 0:
			o.x = floorf((o.x + o.w - 0.01) / C) * C - o.w - 0.01
			o.wall = 1
			o.wall_cell = hb
		elif mx < 0:
			o.x = (floorf(o.x / C) + 1) * C + 0.01
			o.wall = -1
			o.wall_cell = hb
		else:
			# طلع بنص مربع (مثلاً انبنى شي): نطلّعه لفوگ
			o.y = floorf(o.y / C) * C - 0.01
	o.x = clampf(o.x, 0, map.width - o.w)

	# عمودي
	var prev := o.y + o.h
	o.y += o.vy * dt
	o.on_ground = false
	o.drop = maxf(0, o.drop - dt)
	var c0 := int(floor((o.x + 2) / C))
	var c1 := int(floor((o.x + o.w - 2) / C))
	if o.vy < 0:
		# راسه ضرب بالسقف (بالكهوف)
		var r := int(floor(o.y / C))
		for c in range(c0, c1 + 1):
			if map.cell(c, r) != World.EMPTY:
				o.y = (r + 1) * C
				o.vy = 0
				break
		return false
	var bottom := o.y + o.h
	var land := INF
	var r0 := int(floor((prev - 0.5) / C))
	var r1 := int(floor(bottom / C))
	for c in range(c0, c1 + 1):
		for r in range(maxi(0, r0), mini(map.rows - 1, r1) + 1):
			var top := r * C
			if map.cell(c, r) != World.EMPTY and top >= prev - 0.5:
				land = minf(land, top)
				break
	if o.drop <= 0:
		for p in map.platforms:
			if prev <= p.y + 0.5 and bottom >= p.y and o.x + o.w > p.x0 + 8 and o.x < p.x1 - 8:
				land = minf(land, p.y)
	if land < INF:
		o.y = land - o.h
		o.vy = 0
		o.on_ground = true
		return was_air
	return false


# واقف على أرض (مربعات) مو منصة؟
func on_cells(o: Body) -> bool:
	return map.solid_at(o.x + o.w / 2, o.y + o.h + 1)


func splash(x: float, y: float, n: int, colors: Array, dir := 0.0, size := 3.0) -> void:
	for i in n:
		var q := Particle.new()
		q.x = x
		q.y = y
		q.vx = dir * randf_range(60, 260) + randf_range(-90, 90)
		q.vy = randf_range(-420, -60)
		q.life = randf_range(0.35, 0.8)
		q.max = q.life
		q.color = colors[i % colors.size()]
		q.size = randf_range(size * 0.6, size * 1.4)
		parts.append(q)


# فوهة السلاح بالعالم حسب التصويب
func muzzle_point(p: Player, w: String) -> Dictionary:
	var local := aim_of(p)
	var m := Rig.muzzle_of(w, 0, null, local)
	return {x = p.x + PW / 2 + p.face * m.x, y = p.y + PH + m.y, angle = world_aim(p.face, local)}


func fire(p: Player) -> void:
	if not is_gun(p.weapon):
		return
	var w: Dictionary = Config.WEAPONS[p.weapon]
	var m := muzzle_point(p, p.weapon)
	p.fire_cd = w.rate
	p.flash = 0.06
	p.recoil = 1
	var a: float = m.angle + randf_range(-w.spread, w.spread) * 0.004
	var b := Bullet.new()
	b.x = m.x
	b.y = m.y
	b.vx = cos(a) * w.speed
	b.vy = sin(a) * w.speed
	b.dmg = w.damage
	b.owner = p.id
	bullets.append(b)
	# ظرف الطلقة يطير
	var q := Particle.new()
	q.x = p.x + PW / 2 + p.face * 10
	q.y = m.y + 4
	q.vx = -p.face * randf_range(80, 160)
	q.vy = randf_range(-340, -220)
	q.life = 0.9
	q.max = 0.9
	q.color = Color("#d9a441")
	q.size = 3
	q.shell = true
	parts.append(q)
	sounds.append(p.weapon)


# ── الرمانات ──
func throw_grenade(p: Player) -> void:
	if p.grenades <= 0 or p.g_cd > 0:
		return
	p.grenades -= 1
	p.g_throws += 1
	p.g_cd = Config.GRENADE.cooldown
	spawn_grenade(p)
	# خلصت الرمانات: يرجع لأقوى سلاح
	if p.grenades <= 0 and p.weapon == "grenade":
		p.weapon = best_gun()


func spawn_grenade(p: Player) -> void:
	var a := world_aim(p.face, aim_of(p))
	var gr := Grenade.new()
	gr.x = p.x + PW / 2 + p.face * 18
	gr.y = p.y + 30
	gr.vx = cos(a) * Config.GRENADE.throw_x + p.vx * 0.4
	gr.vy = sin(a) * Config.GRENADE.throw_x - Config.GRENADE.throw_y * 0.75
	gr.t = Config.GRENADE.fuse
	gr.owner = p.id
	grenades.append(gr)
	p.recoil = 1
	sounds.append("throw")


func start_reload(p: Player) -> void:
	if not is_gun(p.weapon) or p.reload > 0 or p.ammo[p.weapon] >= Config.WEAPONS[p.weapon].mag:
		return
	p.reload = Config.WEAPONS[p.weapon].reload
	p.firing = false
	if p.local:
		sounds.append("reload")


func best_gun() -> String:
	for i in range(Config.GUN_ORDER.size() - 1, -1, -1):
		if owned.has(Config.GUN_ORDER[i]):
			return Config.GUN_ORDER[i]
	return "pistol"


func explode(gr: Grenade) -> void:
	booms.append({x = gr.x, y = gr.y, t = 0.0})
	shake = maxf(shake, 0.45)
	sounds.append("boom")
	for i in 22:
		var a := randf_range(-PI, 0)
		var sp := randf_range(120, 520)
		var q := Particle.new()
		q.x = gr.x
		q.y = gr.y - 10
		q.vx = cos(a) * sp
		q.vy = sin(a) * sp
		q.life = randf_range(0.3, 0.7)
		q.max = q.life
		q.color = [Color("#ffd25a"), Color("#ff8a2a"), Color("#ff5a1a")][i % 3]
		q.size = randf_range(3, 6)
		parts.append(q)
	for i in 14:
		var q := Particle.new()
		q.x = gr.x + randf_range(-40, 40)
		q.y = gr.y - randf_range(0, 50)
		q.vx = randf_range(-60, 60)
		q.vy = randf_range(-160, -60)
		q.life = randf_range(0.8, 1.6)
		q.max = q.life
		q.color = Color("#4a4a4a")
		q.size = randf_range(10, 20)
		q.smoke = true
		parts.append(q)
	var top := map.surface_below(gr.x, gr.y - 20)
	if top < Config.AH:
		decals.append({x = gr.x, y = top + 3, r = 46.0, life = 8.0, burn = true})
	if not authority:
		return
	# الانفجار يحفر حفرة بالتراب والطابوق
	var C := World.CELL
	for c in range(int((gr.x - 55) / C), int((gr.x + 55) / C) + 1):
		for r in range(int((gr.y - 45) / C), int((gr.y + 55) / C) + 1):
			var v := map.cell(c, r)
			if (v == World.DIRT or v == World.BRICK) and Vector2((c + 0.5) * C - gr.x, (r + 0.5) * C - gr.y).length() < 52:
				edit_cell(c, r, World.EMPTY)
	for z in zs:
		if z.dead > 0:
			continue
		var dx := z.x + z.w / 2 - gr.x
		var dy := z.y + z.h / 2 - gr.y
		var d := sqrt(dx * dx + dy * dy)
		if d > Config.GRENADE.radius + z.w / 2:
			continue
		var dir := 1.0 if dx >= 0 else -1.0
		z.hp -= Config.GRENADE.damage * (1 - minf(1.0, d / Config.GRENADE.radius) * 0.6)
		z.hurt = 0.12
		z.kb = dir * 320
		if z.kind != "flyer" and z.on_ground:
			z.vy = -420
		if z.hp <= 0:
			kill_zombie(z, gr.owner, dir)


func update_grenades(dt: float) -> void:
	for gr in grenades:
		var px := gr.x
		var py := gr.y
		gr.vy = minf(gr.vy + Config.GRAVITY * dt, MAX_FALL)
		gr.x += gr.vx * dt
		gr.y += gr.vy * dt
		gr.rot += gr.vx * dt * 0.03
		# حايط
		if map.solid_at(gr.x, gr.y - 4) and not map.solid_at(px, gr.y - 4):
			gr.x = px
			gr.vx *= -0.45
		# ارتداد على الأرض أو المنصة
		var floor_y := map.surface_below(gr.x, py - 2)
		if gr.vy > 0 and gr.y >= floor_y - 5:
			gr.y = floor_y - 5
			gr.vy *= -0.38
			gr.vx *= 0.62
			if absf(gr.vy) < 60:
				gr.vy = 0
		gr.t -= dt
		if gr.t <= 0:
			explode(gr)
	grenades = grenades.filter(func(gr): return gr.t > 0 and gr.y < Config.AH + 300)
	for b in booms:
		b.t += dt
	booms = booms.filter(func(b): return b.t < 0.7)
	shake = maxf(0, shake - dt)


# ── اللاعبين ──
func slots(p: Player) -> Array:
	var list := []
	for w in Config.GUN_ORDER:
		if owned.has(w):
			list.append(w)
	if p.grenades > 0:
		list.append("grenade")
	list.append("shovel")
	if p.bricks > 0:
		list.append("brick")
	return list


func fell_in_pit(p: Player) -> void:
	if p.y <= Config.AH + 150:
		return
	p.x = p.safe.x
	p.y = p.safe.y - 40
	p.vy = 0
	p.kb = 0
	p.inv = 1


func update_local(p: Player, inp: Inp, dt: float) -> void:
	var alive := p.hp > 0 and status == "play"
	if alive:
		p.vx = inp.move * Config.PLAYER.speed + p.kb
		if inp.aim != null:
			# يصوّب: الوجه يلحق التصويب
			if absf(cos(inp.aim)) > 0.05:
				p.face = 1 if cos(inp.aim) >= 0 else -1
			p.aim = inp.aim
		else:
			if absf(inp.move) > 0.15:
				p.face = 1 if inp.move > 0 else -1
			p.aim = 0.0 if p.face > 0 else PI
		if inp.jump > 0 and p.on_ground:
			p.vy = -Config.PLAYER.jump
			inp.jump = 0
			sounds.append("jump")
		if inp.down and p.on_ground and not on_cells(p):
			p.drop = 0.25
		if inp.swap:
			inp.swap = false
			var list := slots(p)
			if list.size() > 1:
				p.weapon = list[(list.find(p.weapon) + 1) % list.size()]
				p.fire_cd = maxf(p.fire_cd, 0.2)
				p.reload = 0
		if inp.throw:
			inp.throw = false
			throw_grenade(p)
		if inp.reload:
			inp.reload = false
			start_reload(p)
		p.firing = inp.fire
		if p.firing and p.weapon == "grenade":
			throw_grenade(p)
	else:
		p.vx = p.kb
		p.firing = false
	inp.jump = maxf(0, inp.jump - dt)
	p.kb *= pow(0.002, dt)
	if physics(p, dt):
		splash(p.x + PW / 2, p.y + PH - 2, 5, [Color("#a58a66"), Color("#c9b28c")], 0, 2.5)
	if p.on_ground and on_cells(p):
		p.safe = Vector2(p.x, p.y)
	fell_in_pit(p)
	if p.on_ground:
		p.phase += absf(p.vx) * dt * TAU / 150
	if p.hp <= 0:
		p.dead += dt


# ── البوت المساعد (ينزل بالمظلة من طيارة) ──
func launch_helper() -> void:
	var dir := 1 if randf() < 0.5 else -1
	var ax := me().x + PW / 2
	plane = {x = ax - dir * 1100, y = 70.0, dir = dir, drop_x = clampf(ax + randf_range(-120, 120), 80, map.width - 80), dropped = false}
	sounds.append("plane")


func update_plane(dt: float) -> void:
	if plane == null:
		return
	plane.x += plane.dir * 560 * dt
	if not plane.dropped and (plane.x - plane.drop_x) * plane.dir >= 0:
		plane.dropped = true
		var bot := _make_player("bot", "المساعد", Color("#3c4a2c"), "pkm" if best_gun() == "pkm" else "akm")
		bot.bot = true
		bot.chute = true
		bot.x = plane.x - PW / 2
		bot.y = plane.y + 30
		bot.hp = HELPER.hp
		bot.max_hp = HELPER.hp
		bot.on_ground = false
		players = players.filter(func(q): return q.id != "bot")
		players.append(bot)
	if absf(plane.x - plane.drop_x) > 2600:
		plane = null


func bot_ai(p: Player, dt: float) -> void:
	if p.hp <= 0:
		p.dead += dt
		p.firing = false
		p.vx = 0
		physics(p, dt)
		return
	var cx := p.x + PW / 2
	var near := me()
	if p.chute:
		# نازل بالمظلة: بطيء ويتمايل لجهة اللاعب
		p.vx = clampf((near.x + PW / 2 - cx) * 0.5, -70, 70) + sin(time * 1.6) * 30
		p.vy = 95
		p.x += p.vx * dt
		var prev := p.y + PH
		p.y += p.vy * dt
		var floor_y := map.surface_below(p.x + PW / 2, prev - 2)
		if p.y + PH >= floor_y:
			p.y = floor_y - PH
			p.chute = false
			p.on_ground = true
			p.vy = 0
			splash(p.x + PW / 2, floor_y - 2, 6, [Color("#a58a66"), Color("#c9b28c")], 0, 2.5)
		p.firing = false
		return
	# يدوّر على أقرب زومبي، ويبقى قريب من اللاعب
	var target: Zombie = null
	for z in zs:
		if z.dead == 0 and absf(z.x + z.w / 2 - cx) < 1000 and (target == null or absf(z.x - p.x) < absf(target.x - p.x)):
			target = z
	var want := 0.0
	p.firing = false
	if target != null:
		var zx := target.x + target.w / 2
		var dx := zx - cx
		p.face = 1 if dx >= 0 else -1
		var dist := absf(dx)
		if dist > 380:
			want = signf(dx)
		elif dist < 170:
			want = -signf(dx)
		# يصوّب على صدر الزومبي
		p.aim = atan2(target.y + target.h * 0.4 - (p.y + 30), zx - cx)
		if absf(cos(p.aim)) > 0.05:
			p.face = 1 if cos(p.aim) >= 0 else -1
		if dist < 800 and absf(local_aim(p.face, p.aim)) < AIM_LIMIT - 0.05:
			p.firing = true
	elif near.hp > 0 and absf(near.x - p.x) > 160:
		want = signf(near.x - p.x)
		p.face = 1 if want > 0 else -1
		p.aim = 0.0 if p.face > 0 else PI
	p.vx = want * Config.PLAYER.speed * 0.85 + p.kb
	p.kb *= pow(0.002, dt)
	if p.wall != 0 and p.on_ground:
		p.vy = -Config.PLAYER.jump
	if target != null and target.y + target.h < p.y + PH - 80 and p.on_ground and absf(target.x - p.x) < 200 and randf() < dt * 2:
		p.vy = -Config.PLAYER.jump
	physics(p, dt)
	if p.on_ground and on_cells(p):
		p.safe = Vector2(p.x, p.y)
	fell_in_pit(p)
	if p.on_ground:
		p.phase += absf(p.vx) * dt * TAU / 150


# ── الزومبي ──
func spawn_zombie() -> void:
	var mix: Dictionary = cfg.mix
	var sum := 0.0
	for k in mix:
		sum += mix[k]
	var roll := randf() * sum
	var kind: String = mix.keys()[0]
	for k in mix:
		roll -= mix[k]
		if roll <= 0:
			kind = k
			break
	var z := new_zombie(next_id, kind)
	next_id += 1
	var spot := spawn_spot(z)
	z.x = spot.x - z.w / 2
	z.y = spot.y - z.h
	z.face = spot.face
	var cfg: Dictionary = Config.ZOMBIES[kind]
	z.speed = randf_range(cfg.speed[0], cfg.speed[1]) * self.cfg.speed_mult
	z.hp = roundf(cfg.hp * self.cfg.hp_mult * 10) / 10
	z.max = z.hp
	if kind == "flyer":
		z.on_ground = false
	if kind == "monster":
		sounds.append("roar")
	zs.append(z)


# وين يطلع الزومبي: جنب اللاعب (برّه الشاشة)، والطاير ينزل من السما
func spawn_spot(z: Zombie) -> Dictionary:
	var alive := players.filter(func(q): return q.hp > 0 and not q.chute)
	var anchor: Player = alive[randi() % alive.size()] if alive.size() else players[0]
	var ax := anchor.x + PW / 2
	var face_of := func(x: float) -> int: return 1 if x < ax else -1
	if z.kind == "flyer":
		var fx := clampf(ax + (-1 if randf() < 0.5 else 1) * randf_range(250, 650), 60, map.width - 60)
		return {x = fx, y = -120 + z.h, face = face_of.call(fx)}
	for i in 12:
		var side := -1 if randf() < 0.5 else 1
		var x := ax + side * randf_range(760, 1050)
		if x < z.w or x > map.width - z.w:
			x = ax - side * randf_range(760, 1050)
		x = clampf(x, z.w, map.width - z.w)
		var top = map.ground_at(x)
		if top != null:
			return {x = x, y = top, face = face_of.call(x)}
	var edge := map.width - z.w if ax < map.width / 2 else z.w
	var et = map.ground_at(edge)
	return {x = edge, y = et if et != null else minf(map.surface_below(edge, 0), Config.AH), face = face_of.call(edge)}


func new_zombie(id: int, kind: String) -> Zombie:
	var cfg: Dictionary = Config.ZOMBIES[kind]
	var z := Zombie.new()
	z.id = id
	z.kind = kind
	if cfg.has("size"):
		z.w = cfg.size[0]
		z.h = cfg.size[1]
	else:
		z.w = 44 * cfg.scale
		z.h = (100.0 if kind == "flyer" else 122.0) * cfg.scale
	z.on_ground = kind != "flyer"
	z.hp = cfg.hp
	z.max = cfg.hp
	z.speed = cfg.speed[0]
	z.jump_cd = randf_range(1, 2.5)
	z.phase = randf() * 6
	z.aim = randf_range(-14, 14)
	return z


func hurt_player(p: Player, z: Zombie) -> void:
	if p.inv > 0 or p.hp <= 0:
		return
	p.hp = maxf(0, p.hp - Config.ZOMBIES[z.kind].damage)
	p.inv = 0.6
	if p.local or p.bot:
		p.kb = z.face * 300
		if p.on_ground:
			p.vy = -300
	if p.local:
		sounds.append("hurt")
	splash(p.x + PW / 2, p.y + 40, 7, [Color("#b71c1c"), Color("#7f1010")], z.face)


func nearest_target(x: float) -> Player:
	var target: Player = null
	for p in players:
		if p.hp > 0 and not p.chute and (target == null or absf(p.x + PW / 2 - x) < absf(target.x + PW / 2 - x)):
			target = p
	return target


# الزومبي الطاير: يحوم فوگ اللاعب وبعدين ينزل عليه
func flyer_ai(z: Zombie, dt: float) -> void:
	var target := nearest_target(z.x + z.w / 2)
	z.atk -= dt
	if target == null or status != "play":
		z.vx = 0
		z.vy = -40
	else:
		var tx := target.x + PW / 2
		var zx := z.x + z.w / 2
		var diving := z.atk <= 0 and absf(tx - zx) < 140
		var ty := target.y + 20 if diving else target.y - 170 + sin(time * 2 + z.id) * 25
		var dx := tx - zx
		var dy := ty - (z.y + z.h / 2)
		var len := maxf(0.001, sqrt(dx * dx + dy * dy))
		var sp := z.speed * (1.9 if diving else 1.0)
		var k := minf(1.0, dt * 3)
		z.vx += ((dx / len) * sp - z.vx) * k
		z.vy += ((dy / len) * sp - z.vy) * k
		if absf(dx) > 4:
			z.face = 1 if dx > 0 else -1
		var touching := absf(dx) < (PW + z.w) / 2 + 14 and z.y + z.h > target.y + 10 and z.y < target.y + PH
		if touching and z.atk <= 0:
			z.atk = 1.6
			z.atk_t = 0.35
			z.vy = -sp * 1.5
			hurt_player(target, z)
	z.x = clampf(z.x + (z.vx + z.kb) * dt, 0, map.width - z.w)
	z.y = maxf(-300, z.y + z.vy * dt)
	z.on_ground = false


func zombie_ai(z: Zombie, dt: float) -> void:
	var cfg: Dictionary = Config.ZOMBIES[z.kind]
	var zcx := z.x + z.w / 2
	var zb := z.y + z.h
	var target := nearest_target(zcx)
	if target == null or status != "play":
		if z.on_ground:
			z.air = 0
		z.vx = z.air + z.kb
		return
	var pcx := target.x + PW / 2
	var pb := target.y + PH
	var above := pb < zb - 60
	var below := pb > zb + 60

	# إذا اللاعب عالي هواي، يروح لأقرب منصة بالنص
	var tx := pcx + z.aim
	if above and pb < zb - 250:
		var best = null
		for pl in map.platforms:
			if pl.y > pb + 10 and pl.y < zb - 10 and absf(pl.x0 - zcx) < 900 and (best == null or absf(pl.x0 + pl.x1 - 2 * zcx) < absf(best.x0 + best.x1 - 2 * zcx)):
				best = pl
		if best != null:
			tx = clampf(zcx, best.x0 + 40, best.x1 - 40)
	var dx := tx - zcx
	var reach: float = (PW + z.w) / 2 + 26 * cfg.scale
	var touching := absf(pcx - zcx) < reach and pb > z.y + 10 and target.y < zb - 10

	if absf(pcx - zcx) > 4:
		z.face = 1 if pcx > zcx else -1
	if z.on_ground:
		z.air = 0.0 if touching or absf(dx) < 4 else signf(dx) * z.speed
	z.vx = z.air + z.kb

	z.atk -= dt
	if touching and z.atk <= 0:
		z.atk = 0.9
		z.atk_t = 0.35
		hurt_player(target, z)
	# طابوق بطريقه (أو تحت رجليه واللاعب جوّه): يوگف ويضربه لحد ما ينكسر
	var brick := Vector2i(-1, -1)
	if z.wall != 0 and map.cell(z.wall_cell.x, z.wall_cell.y) == World.BRICK:
		brick = z.wall_cell
	elif below and z.on_ground and absf(pcx - zcx) < 80:
		var under := Vector2i(int(floor(zcx / World.CELL)), int(floor((zb + 1) / World.CELL)))
		if map.cell(under.x, under.y) == World.BRICK:
			brick = under
	if brick.x >= 0 and not touching:
		z.air = 0
		z.vx = z.kb
		if z.atk <= 0:
			z.atk = 0.9
			z.atk_t = 0.35
			hit_brick(brick.x, brick.y, Config.ZOMBIES[z.kind].damage * 2)
		return

	# القفز للمنصات
	z.jump_cd -= dt
	if cfg.jumpy > 0 and z.on_ground and z.jump_cd <= 0 and above and absf(dx) < 170:
		z.vy = -Config.PLAYER.jump
		z.air = signf(dx) * maxf(z.speed, 260) * minf(1.0, absf(dx) / 80 + 0.3)
		z.jump_cd = randf_range(1.2, 3) / cfg.jumpy
	# النزول من المنصة إذا اللاعب جوّه
	if below and z.on_ground and not on_cells(z) and absf(pcx - zcx) < 110:
		z.drop = 0.3
	# صدم حايط (أرض أعلى منه): ينط
	if z.wall != 0 and z.on_ground and z.jump_cd < 1:
		z.vy = -Config.PLAYER.jump * (0.85 if z.kind == "brute" or z.kind == "monster" else 1.0)
		z.air = z.wall * maxf(z.speed, 200)
		z.jump_cd = 1.2


func kill_zombie(z: Zombie, owner: String, dir: float) -> void:
	z.dead = 0.0001
	z.vy = -260
	z.kb = dir * 120
	killed += 1
	var c: int = Config.ZOMBIES[z.kind].coins
	credits[owner] = int(credits.get(owner, 0)) + c
	if owner == me_id:
		my_kills += 1
	kills.append([roundi(z.x + z.w / 2), roundi(z.y), c, owner])
	if owner != "bot":
		pops.append({x = z.x + z.w / 2, y = z.y, text = "+%d" % c, life = 1.2, head = false, mine = owner == me_id})
	death_fx(z, dir)


func death_fx(z: Zombie, dir: float) -> void:
	splash(z.x + z.w / 2, z.y + z.h * 0.35, 14, [Color("#7a1212"), Color("#4b1010"), Color("#5d6b2a")], dir, 4)
	var dx := z.x + z.w / 2 + dir * 30
	var top := map.surface_below(dx, z.y + z.h - 20)
	if top < Config.AH and z.kind != "flyer":
		decals.append({x = dx, y = top + 3, r = 18 + randf() * 14, life = 6.0, burn = false})
	sounds.append("die")


# ── خطوة وحدة من اللعبة ──
func step(inp: Inp, dt: float) -> void:
	time += dt
	if status != "play":
		end_t += dt

	for p in players:
		if p.local:
			update_local(p, inp, dt)
		elif p.bot:
			bot_ai(p, dt)
		else:
			update_remote(p, dt)
		p.fire_cd -= dt
		p.g_cd -= dt
		p.recoil = maxf(0, p.recoil - dt * 9)
		p.flash -= dt
		p.inv -= dt
		var own := p.local or p.bot
		p.tool_cd -= dt
		if TOOLS.has(p.weapon):
			if p.hp > 0 and p.firing and p.tool_cd <= 0 and status == "play":
				if own:
					use_tool(p)
				else:
					p.tool_cd = 0.22
					p.recoil = 1
		if own and p.reload > 0:
			p.reload -= dt
			if p.reload <= 0 and is_gun(p.weapon):
				p.reload = 0
				p.ammo[p.weapon] = Config.WEAPONS[p.weapon].mag
				if p.local:
					sounds.append("reload")
		if p.hp > 0 and p.firing and p.fire_cd <= 0 and status == "play" and is_gun(p.weapon) and p.reload <= 0:
			if not own:
				# لاعب ثاني يرمي: نرسم طلقته (والمضيف يحسب ضررها)
				fire(p)
			else:
				if p.ammo[p.weapon] > 0:
					fire(p)
					p.ammo[p.weapon] -= 1
				if p.ammo[p.weapon] <= 0:
					start_reload(p)
	players = players.filter(func(p): return not (p.bot and p.dead > 3))
	# أقل صحة وصلها كل لاعب (للصعوبة الجاية)
	if status == "play":
		for p in players:
			if not p.bot:
				var r := clampf(p.hp / p.max_hp, 0, 1)
				min_hp[p.id] = minf(min_hp.get(p.id, 1.0), r)
				if p.local and r < 1:
					took_damage = true

	# ── البوت المساعد: طيارة تنزله بنص المرحلة (مو بكل لعبة) ──
	if status == "play" and helper_at != null and float(killed) / total >= helper_at:
		helper_at = null
		launch_helper()
	update_plane(dt)

	# ── ظهور الزومبي (يزيدون كل ما تتقدم بالمرحلة، وأكثر إذا أكو لاعبين أكثر) ──
	if authority and status == "play":
		var st: Dictionary = cfg
		var prog := float(spawned) / total
		var living := 0
		for z in zs:
			if z.dead == 0:
				living += 1
		spawn_cd -= dt
		var people := humans().size()
		if spawned < total and spawn_cd <= 0 and living < st.max_alive + int(prog * 4) + (people - 1) * 3:
			spawn_zombie()
			spawned += 1
			spawn_cd = randf_range(st.every[0], st.every[1]) * (1 - 0.35 * prog) / sqrt(people)

	# ── الزومبي ──
	for z in zs:
		z.hurt -= dt
		z.atk_t -= dt
		z.kb *= pow(0.002, dt)
		if z.dead > 0:
			z.dead += dt
			z.vx = z.kb
			if authority or z.net == null:
				physics(z, dt)
			continue
		var ox := z.x
		if not authority:
			# الزومبي يتحرك حسب آخر سنابشوت (مع توقع بسيط حتى تكون الحركة ناعمة)
			if z.net != null:
				var ahead := minf(0.2, time - z.net.at)
				var k := minf(1.0, dt * 10)
				z.x += (z.net.x + z.net.vx * ahead - z.x) * k
				z.y += (z.net.y + z.net.vy * ahead - z.y) * k
				z.vx = z.net.vx
		elif z.kind == "flyer":
			flyer_ai(z, dt)
		else:
			zombie_ai(z, dt)
			physics(z, dt)
			# وگع بحفرة: ينحسب مقتول (بدون فلوس)
			if z.y > Config.AH + 150:
				z.dead = 5
				killed += 1
		if z.on_ground or z.kind == "flyer" or not authority:
			z.phase += absf(z.x - ox) * TAU / 120 + (dt * 9 if z.kind == "flyer" else 0.0)
	zs = zs.filter(func(z): return z.dead < 1.6)

	# ── الطلق ──
	for b in bullets:
		var x0 := b.x
		var y0 := b.y
		b.x += b.vx * dt
		b.y += b.vy * dt
		b.life -= dt
		# أول زومبي على طريق الطلقة (نفحص نقاط على الخط)
		var steps := maxi(1, ceili(Vector2(b.x - x0, b.y - y0).length() / 10))
		var hit: Zombie = null
		var hy := b.y
		for i in range(1, steps + 1):
			var px := x0 + (b.x - x0) * i / steps
			var py := y0 + (b.y - y0) * i / steps
			for z in zs:
				if z.dead == 0 and px >= z.x and px <= z.x + z.w and py >= z.y and py <= z.y + z.h:
					hit = z
					hy = py
					break
			if hit != null:
				break
			# الطلقة ضربت الأرض
			if map.solid_at(px, py):
				b.life = 0
				splash(px, py, 3, [Color("#8a6a4a"), Color("#c9b28c")], 0, 2)
				break
		if hit == null:
			continue
		b.life = 0
		var dir := 1.0 if b.vx >= 0 else -1.0
		hit.hurt = 0.09
		# هيدشوت: الطلقة ضربت الراس
		var head: bool = hy < hit.y + hit.h * Config.ZOMBIES[hit.kind].head
		splash(hit.x + hit.w / 2 - dir * hit.w * 0.3, hy, 12 if head else 5, [Color("#7a1212"), Color("#5d6b2a"), Color("#ffd27a")], dir, 4.0 if head else 3.0)
		if head:
			sounds.append("headshot")
			if b.owner == me_id:
				my_headshots += 1
				pops.append({x = hit.x + hit.w / 2, y = hit.y - 18, text = "هيدشوت!", life = 0.9, head = true, mine = true})
		else:
			sounds.append("hit")
		# الضرر الحقيقي يحسبه المضيف بس
		if authority:
			hit.hp -= b.dmg * (Config.HEADSHOT if head else 1.0)
			hit.kb = dir * (50.0 if hit.kind == "brute" else 140.0)
			if hit.hp <= 0:
				kill_zombie(hit, b.owner, dir)
	bullets = bullets.filter(func(b): return b.life > 0 and b.x > -500 and b.x < map.width + 500 and b.y > -600 and b.y < Config.AH + 100)

	update_grenades(dt)

	# ── بقايا ──
	for q in parts:
		if q.smoke:
			q.vy *= pow(0.4, dt)
			q.size += dt * 14
		else:
			q.vy += Config.GRAVITY * 0.7 * dt
		q.x += q.vx * dt
		q.y += q.vy * dt
		if q.shell:
			q.rot += q.vx * dt * 0.2
		if not q.smoke:
			var floor_y := map.surface_below(q.x, q.y - q.vy * dt - 2)
			if q.y > floor_y + 2:
				q.y = floor_y + 2
				q.vy *= -0.35
				q.vx *= 0.6
		q.life -= dt
	parts = parts.filter(func(q): return q.life > 0)
	if parts.size() > 600:
		parts = parts.slice(parts.size() - 600)
	for q in pops:
		q.y -= 50 * dt
		q.life -= dt
	pops = pops.filter(func(q): return q.life > 0)
	for d in decals:
		d.life -= dt
	decals = decals.filter(func(d): return d.life > 0)

	# ── نهاية المرحلة (المضيف يقرر) ──
	if authority and status == "play":
		if killed >= total:
			status = "won"
			sounds.append("win")
		elif humans().all(func(q): return q.hp <= 0):
			status = "lost"
			sounds.append("lose")


# ════════ اللعب الجماعي: تحويل الحالة لرسايل صغيرة وبالعكس ════════
const KINDS := ["walker", "tough", "brute", "flyer", "runner", "monster"]


# لاعب ثاني: يتحرك بنعومة لآخر مكان وصل (مع توقع بسيط)
func update_remote(p: Player, dt: float) -> void:
	if p.hp <= 0:
		p.dead += dt
	if p.net == null:
		return
	var n: Dictionary = p.net
	var ahead := minf(0.15, time - n.at)
	var tx: float = n.x + n.vx * ahead
	var ty: float = n.y + (0.0 if p.on_ground else n.vy * ahead)
	var k := minf(1.0, dt * 14)
	if absf(tx - p.x) > 250:
		p.x = tx
	else:
		p.x += (tx - p.x) * k
	p.y += (ty - p.y) * k
	p.vx = n.vx
	p.vy = n.vy
	if p.on_ground:
		p.phase += absf(p.vx) * dt * TAU / 150


func add_player(who: Dictionary, weapon: String) -> Player:
	for q in players:
		if q.id == who.id:
			return q
	var p := _make_player(who.id, who.name, who.uniform, weapon, players.size())
	players.append(p)
	return p


func remove_player(id: String) -> void:
	players = players.filter(func(p): return p.local or p.bot or p.id != id)


# حالة لاعبي (كل لاعب يرسل حالته)
func player_msg() -> Dictionary:
	var p := me()
	return {id = p.id, x = roundi(p.x), y = roundi(p.y), vx = roundi(p.vx), vy = roundi(p.vy), f = p.face, g = p.on_ground,
		w = p.weapon, fi = p.firing, gn = p.g_throws, a = snappedf(p.aim, 0.01), rl = snappedf(reload_progress(p), 0.05), te = recent_edits()}


func apply_player_msg(m: Dictionary, who: Dictionary) -> void:
	if m.get("id") == me_id:
		return
	var p := add_player(who, str(m.w))
	p.name = who.name
	p.uniform = who.uniform
	if p.net == null:
		p.x = m.x
		p.y = m.y
		p.g_seen = int(m.get("gn", 0))
	p.net = {x = float(m.x), y = float(m.y), vx = float(m.vx), vy = float(m.vy), at = time}
	p.face = int(m.f)
	p.on_ground = bool(m.g)
	p.weapon = str(m.w)
	p.firing = bool(m.fi)
	p.aim = float(m.get("a", 0.0 if p.face > 0 else PI))
	# نخلي التعبئة تبين على اللاعب الثاني
	var rl := float(m.get("rl", 0))
	p.reload = (1 - rl) * Config.WEAPONS[p.weapon].reload if rl > 0 and is_gun(p.weapon) else 0.0
	# رمى رمانات جديدة
	var gn := int(m.get("gn", 0))
	for i in mini(3, gn - p.g_seen):
		spawn_grenade(p)
	p.g_seen = maxi(p.g_seen, gn)
	apply_edits(m.get("te"))


# سنابشوت المضيف: الزومبي + صحة اللاعبين + الفلوس + القتلات الجديدة
func snapshot() -> Dictionary:
	var z := []
	for q in zs:
		var flags := (1 if q.atk_t > 0 else 0) | (2 if q.dead > 0 else 0) | (4 if q.hurt > 0 else 0) | (8 if q.on_ground else 0)
		z.append_array([q.id, KINDS.find(q.kind), roundi(q.x), roundi(q.y), q.face, maxf(0, snappedf(q.hp, 0.1)), flags, q.max])
	var hp := {}
	for p in humans():
		hp[p.id] = roundi(p.hp)
	var ev := kills
	kills = []
	return {st = ["play", "won", "lost"].find(status), k = killed, n = spawned, z = z, hp = hp, c = credits.duplicate(), ev = ev, te = recent_edits()}


func apply_snapshot(s: Dictionary) -> void:
	var seen := {}
	var arr: Array = s.get("z", [])
	var i := 0
	while i + 7 < arr.size():
		var id := int(arr[i])
		var kind: String = KINDS[clampi(int(arr[i + 1]), 0, KINDS.size() - 1)]
		var x := float(arr[i + 2])
		var y := float(arr[i + 3])
		var face := int(arr[i + 4])
		var hp := float(arr[i + 5])
		var flags := int(arr[i + 6])
		var mx := float(arr[i + 7])
		i += 8
		seen[id] = true
		var z: Zombie = null
		for q in zs:
			if q.id == id:
				z = q
				break
		if z == null:
			z = new_zombie(id, kind)
			z.x = x
			z.y = y
			if kind == "monster":
				sounds.append("roar")
			zs.append(z)
		z.max = mx if mx > 0 else z.max
		var prev = z.net if z.net != null else {x = x, y = y}
		z.net = {x = x, y = y, vx = (x - prev.x) * 8, vy = (y - prev.y) * 8 if kind == "flyer" else 0.0, at = time}
		z.face = face
		z.hp = hp
		z.on_ground = (flags & 8) > 0
		if flags & 1 and z.atk_t <= 0:
			z.atk_t = 0.35
		if flags & 4:
			z.hurt = 0.09
		if flags & 2 and z.dead == 0:
			z.dead = 0.0001
			z.vy = -260
			z.net = null
	# الزومبي اللي اختفى من السنابشوت
	zs = zs.filter(func(q): return q.dead > 0 or seen.has(q.id))

	apply_edits(s.get("te"))
	killed = int(s.get("k", killed))
	spawned = int(s.get("n", spawned))
	credits = s.get("c", credits)
	var hps: Dictionary = s.get("hp", {})
	for p in players:
		if not hps.has(p.id) or p.bot:
			continue
		var hp := float(hps[p.id])
		if p.local and hp < p.hp:
			# انضربت: نرجع لورا شوية
			var near: Zombie = null
			for q in zs:
				if q.dead == 0 and (near == null or absf(q.x - p.x) < absf(near.x - p.x)):
					near = q
			p.kb = (-1.0 if near != null and near.x > p.x else 1.0) * 300
			if p.on_ground:
				p.vy = -300
			p.inv = 0.6
			sounds.append("hurt")
			splash(p.x + PW / 2, p.y + 40, 7, [Color("#b71c1c"), Color("#7f1010")], 0)
		elif not p.local and hp < p.hp:
			p.inv = 0.6
		p.hp = hp
	for e in s.get("ev", []):
		var owner := str(e[3])
		if owner == me_id:
			my_kills += 1
		if owner != "bot":
			pops.append({x = float(e[0]), y = float(e[1]), text = "+%d" % int(e[2]), life = 1.2, head = false, mine = owner == me_id})
		for q in zs:
			if q.dead > 0 and absf(q.x + q.w / 2 - float(e[0])) < 30:
				death_fx(q, -q.face)
				break
	var st: String = ["play", "won", "lost"][clampi(int(s.get("st", 0)), 0, 2)]
	if st != status:
		status = st
		if st != "play":
			sounds.append("win" if st == "won" else "lose")


# معدّل أقل صحة لكل اللاعبين (للصعوبة الجاية)
func min_hp_avg() -> float:
	if min_hp.is_empty():
		return 1.0
	var sum := 0.0
	for k in min_hp:
		sum += min_hp[k]
	return sum / min_hp.size()


# الصعوبة الجاية بعد ما تخلص الجولة
func next_level() -> float:
	return Config.next_level(level, status == "won", min_hp_avg(), time)


# ════════ الحفر والبناء ════════
# الأداة تشتغل على مربع 40×40 قدّام اللاعب (حسب اتجاه التصويب)
func tool_target(p: Player) -> Vector2i:
	var center := Vector2(p.x + PW / 2, p.y + 64)
	var t := center + Vector2(cos(p.aim), sin(p.aim)) * 70
	return Vector2i(int(floor(t.x / World.CELL - 0.5)), int(floor(t.y / World.CELL - 0.5)))


func use_tool(p: Player) -> void:
	var t := tool_target(p)
	var C := World.CELL
	if p.weapon == "shovel":
		# الكرك يحفر 60×60 (أعرض من اللاعب حتى يكدر ينزل بالحفرة أو يمشي بالنفق)
		var dug := 0
		for dc in range(-1, 2):
			for dr in range(-1, 2):
				var v := map.cell(t.x + 1 + dc, t.y + 1 + dr)
				if v == World.DIRT or v == World.BRICK:
					edit_cell(t.x + 1 + dc, t.y + 1 + dr, World.EMPTY)
					dug += 1
		p.tool_cd = 0.22
		p.recoil = 1
		if dug > 0:
			splash((t.x + 1) * C, (t.y + 1) * C, 8, [Color("#6b4a2b"), Color("#8a6a4a"), Color("#4a3220")], 0, 3)
			sounds.append("dig")
	elif p.weapon == "brick" and p.bricks > 0:
		# لازم المكان فارغ وما بيه أحد
		var r := Rect2(t.x * C, t.y * C, C * 2, C * 2)
		for dc in 2:
			for dr in 2:
				if map.cell(t.x + dc, t.y + dr) != World.EMPTY:
					return
		for q in players:
			if q.hp > 0 and r.intersects(Rect2(q.x, q.y, q.w, q.h)):
				return
		for z in zs:
			if z.dead == 0 and r.intersects(Rect2(z.x, z.y, z.w, z.h)):
				return
		for dc in 2:
			for dr in 2:
				edit_cell(t.x + dc, t.y + dr, World.BRICK)
		p.bricks -= 1
		p.tool_cd = 0.25
		p.recoil = 1
		sounds.append("build")
		if p.bricks <= 0:
			p.weapon = best_gun()


# نغيّر مربع ونسجله حتى ينرسل للباقين
func edit_cell(c: int, r: int, v: int) -> void:
	if map.cell(c, r) == World.ROCK:
		return
	map.set_cell(c, r, v)
	edits.append([c, r, v, time])


# الزومبي يضرب طابوقة
func hit_brick(c: int, r: int, dmg: float) -> void:
	var i := r * map.cols + c
	var hp: float = map.brick_hp.get(i, World.BRICK_HP) - dmg
	if hp <= 0:
		edit_cell(c, r, World.EMPTY)
		splash((c + 0.5) * World.CELL, (r + 0.5) * World.CELL, 10, [Color("#a0522d"), Color("#6e3b1f"), Color("#c9b28c")], 0, 3)
		sounds.append("break")
	else:
		map.brick_hp[i] = hp
		map.changed.emit(c)
		sounds.append("hit")


# التغييرات الأخيرة (آخر ثانية ونص) حتى تنرسل كم مرة وما تضيع
func recent_edits() -> Array:
	edits = edits.filter(func(e): return time - e[3] < 1.5)
	return edits.map(func(e): return [e[0], e[1], e[2]])


func apply_edits(list) -> void:
	if not (list is Array):
		return
	for e in list:
		if e is Array and e.size() >= 3:
			var c := int(e[0])
			var r := int(e[1])
			var v := int(e[2])
			if map.cell(c, r) != v and map.cell(c, r) != World.ROCK:
				map.set_cell(c, r, v)
				# المضيف يوصّل تغييرات اللاعبين للكل
				if authority:
					edits.append([c, r, v, time])
