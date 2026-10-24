# ════════ منطق اللعبة ════════
# الحركة، الطلق، الرمانات، الزومبي (العادي والطاير والوحش)، البوت المساعد، والمراحل. ما بيه أي رسم.
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
	var dead := 0.0
	var safe := Vector2.ZERO # آخر مكان آمن (إذا وگع بحفرة يرجع له)


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
var stage := 0
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
var coins := 0
var status := "play" # play / won / lost
var end_t := 0.0
var owned: Array = ["pistol"]
var sounds: Array[String] = []
var next_id := 1
var helper_at = null # متى ينزل البوت (نسبة القتل)، null = ما ينزل هاي اللعبة
var plane = null # {x, y, dir, drop_x, dropped}


func _init(m: World, stage_i: int, owned_list: Array, weapon: String) -> void:
	map = m
	stage = stage_i
	owned = owned_list
	total = Config.STAGES[stage].total
	var me := _make_player("me", "أنا", Color("#8a7d4f"), weapon if owned.has(weapon) else "pistol")
	me.local = true
	players.append(me)
	helper_at = randf_range(HELPER.at[0], HELPER.at[1]) if randf() < HELPER.chance else null


func me() -> Player:
	return players[0]


func earned() -> int:
	return coins + (Config.CLEAR_BONUS * (stage + 1) if status == "won" else 0)


func _make_player(id: String, name: String, uniform: Color, weapon: String) -> Player:
	var p := Player.new()
	p.id = id
	p.name = name
	p.uniform = uniform
	p.w = PW
	p.h = PH
	p.x = map.start.x - PW / 2
	p.y = minf(map.surface_below(p.x + PW / 2, map.start.y - 200), Config.AH) - PH
	p.hp = Config.PLAYER.hp
	p.max_hp = p.hp
	p.weapon = weapon
	for w in Config.WEAPONS:
		p.ammo[w] = Config.WEAPONS[w].mag
	p.grenades = Config.GRENADE.per_stage
	p.safe = Vector2(p.x, p.y)
	return p


static func local_aim(face: int, aim: float) -> float:
	var a := aim if face > 0 else PI - aim
	a = atan2(sin(a), cos(a))
	return clampf(a, -AIM_LIMIT, AIM_LIMIT)


static func world_aim(face: int, local: float) -> float:
	return local if face > 0 else PI - local


static func aim_of(p: Player) -> float:
	return local_aim(p.face, p.aim)


func reload_progress(p: Player) -> float:
	if p.reload > 0 and p.weapon != "grenade":
		return 1 - p.reload / Config.WEAPONS[p.weapon].reload
	return 0.0


# الحركة + التصادم مع الأرض (حيطان وسطوح) والمنصات
func physics(o: Body, dt: float) -> bool:
	var was_air := not o.on_ground
	o.vy = minf(o.vy + Config.GRAVITY * dt, MAX_FALL)
	o.wall = 0

	# أفقي: الأرض الأعلى منك تصير حايط (إلا إذا صغيرة، تصعدها)
	o.x += o.vx * dt
	for b in map.ground:
		var bottom := o.y + o.h
		if bottom <= b.y + 1 or o.x + o.w <= b.x0 or o.x >= b.x1:
			continue
		if bottom - b.y <= 14 and o.vy >= 0:
			o.y = b.y - o.h
			continue
		if o.x + o.w / 2 < (b.x0 + b.x1) / 2:
			o.x = b.x0 - o.w
			o.wall = 1
		else:
			o.x = b.x1
			o.wall = -1
	o.x = clampf(o.x, 0, map.width - o.w)

	# عمودي
	var prev := o.y + o.h
	o.y += o.vy * dt
	o.on_ground = false
	o.drop = maxf(0, o.drop - dt)
	if o.vy < 0:
		return false
	var bottom := o.y + o.h
	var land := INF
	for b in map.ground:
		if prev <= b.y + 0.5 and bottom >= b.y and o.x + o.w > b.x0 + 2 and o.x < b.x1 - 2:
			land = minf(land, b.y)
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
	if p.weapon == "grenade":
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
	p.g_cd = Config.GRENADE.cooldown
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
	# خلصت الرمانات: يرجع لأقوى سلاح
	if p.grenades <= 0 and p.weapon == "grenade":
		p.weapon = best_gun()


func start_reload(p: Player) -> void:
	if p.weapon == "grenade" or p.reload > 0 or p.ammo[p.weapon] >= Config.WEAPONS[p.weapon].mag:
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
		var wall = map.ground_at(gr.x)
		var prev_top = map.ground_at(px)
		if wall != null and gr.y > wall + 6 and (prev_top == null or prev_top > py):
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
		if inp.down and p.on_ground and map.ground_at(p.x + PW / 2) != p.y + PH:
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
	if p.on_ground and map.ground_at(p.x + PW / 2) == p.y + PH:
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
	if p.on_ground and map.ground_at(p.x + PW / 2) == p.y + PH:
		p.safe = Vector2(p.x, p.y)
	fell_in_pit(p)
	if p.on_ground:
		p.phase += absf(p.vx) * dt * TAU / 150


# ── الزومبي ──
func spawn_zombie() -> void:
	var mix: Dictionary = Config.STAGES[stage].mix
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
	z.speed = randf_range(cfg.speed[0], cfg.speed[1]) * (1 + stage * 0.03)
	z.hp = roundf(cfg.hp * (1 + stage * Config.HP_PER_STAGE) * 10) / 10
	z.max = z.hp
	if kind == "flyer":
		z.on_ground = false
	if kind == "monster":
		sounds.append("roar")
	zs.append(z)


# وين يطلع الزومبي: جنب اللاعب (برّه الشاشة)، والطاير ينزل من السما
func spawn_spot(z: Zombie) -> Dictionary:
	var anchor := me()
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

	# القفز للمنصات
	z.jump_cd -= dt
	if cfg.jumpy > 0 and z.on_ground and z.jump_cd <= 0 and above and absf(dx) < 170:
		z.vy = -Config.PLAYER.jump
		z.air = signf(dx) * maxf(z.speed, 260) * minf(1.0, absf(dx) / 80 + 0.3)
		z.jump_cd = randf_range(1.2, 3) / cfg.jumpy
	# النزول من المنصة إذا اللاعب جوّه
	if below and z.on_ground and map.ground_at(zcx) != zb and absf(pcx - zcx) < 110:
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
	if owner != "bot":
		coins += c
		pops.append({x = z.x + z.w / 2, y = z.y, text = "+%d" % c, life = 1.2, head = false})
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
		else:
			bot_ai(p, dt)
		p.fire_cd -= dt
		p.g_cd -= dt
		p.recoil = maxf(0, p.recoil - dt * 9)
		p.flash -= dt
		p.inv -= dt
		if p.reload > 0:
			p.reload -= dt
			if p.reload <= 0 and p.weapon != "grenade":
				p.reload = 0
				p.ammo[p.weapon] = Config.WEAPONS[p.weapon].mag
				if p.local:
					sounds.append("reload")
		if p.hp > 0 and p.firing and p.fire_cd <= 0 and status == "play" and p.weapon != "grenade" and p.reload <= 0:
			if p.ammo[p.weapon] > 0:
				fire(p)
				p.ammo[p.weapon] -= 1
			if p.ammo[p.weapon] <= 0:
				start_reload(p)
	players = players.filter(func(p): return not (p.bot and p.dead > 3))

	# ── البوت المساعد: طيارة تنزله بنص المرحلة (مو بكل لعبة) ──
	if status == "play" and helper_at != null and float(killed) / total >= helper_at:
		helper_at = null
		launch_helper()
	update_plane(dt)

	# ── ظهور الزومبي (يزيدون كل ما تتقدم بالمرحلة) ──
	if status == "play":
		var st: Dictionary = Config.STAGES[stage]
		var prog := float(spawned) / total
		var living := 0
		for z in zs:
			if z.dead == 0:
				living += 1
		spawn_cd -= dt
		if spawned < total and spawn_cd <= 0 and living < st.max_alive + int(prog * 4):
			spawn_zombie()
			spawned += 1
			spawn_cd = randf_range(st.every[0], st.every[1]) * (1 - 0.35 * prog)

	# ── الزومبي ──
	for z in zs:
		z.hurt -= dt
		z.atk_t -= dt
		z.kb *= pow(0.002, dt)
		if z.dead > 0:
			z.dead += dt
			z.vx = z.kb
			physics(z, dt)
			continue
		var ox := z.x
		if z.kind == "flyer":
			flyer_ai(z, dt)
		else:
			zombie_ai(z, dt)
			physics(z, dt)
			# وگع بحفرة: ينحسب مقتول (بدون فلوس)
			if z.y > Config.AH + 150:
				z.dead = 5
				killed += 1
		if z.on_ground or z.kind == "flyer":
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
			var top = map.ground_at(px)
			if top != null and py > top + 2:
				b.life = 0
				splash(px, top, 3, [Color("#8a6a4a"), Color("#c9b28c")], 0, 2)
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
			if b.owner == "me":
				pops.append({x = hit.x + hit.w / 2, y = hit.y - 18, text = "هيدشوت!", life = 0.9, head = true})
		else:
			sounds.append("hit")
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

	# ── نهاية المرحلة ──
	if status == "play":
		if killed >= total:
			status = "won"
			sounds.append("win")
		elif me().hp <= 0:
			status = "lost"
			sounds.append("lose")
