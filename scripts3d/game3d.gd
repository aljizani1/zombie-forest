# ════════ اللعبة ثلاثية الأبعاد (من فوگ) ════════
# حركة بكل الاتجاهات، تصويب بكل الاتجاهات، طلق، رمانات، موجات زومبي حسب الصعوبة التكيفية.
# المنطق على مستوى الأرض (Vector2 = x, z) والرسم بالـ 3D. المتر = وحدة.
class_name Game3D
extends Node3D

const H := preload("res://scripts3d/humanoid.gd")
const PX := 1.0 / 60.0 # تحويل السرعات القديمة (بكسل/ث) لمتر/ث
const P_SPEED := 5.2
const P_R := 0.4
const MAX_PARTS := 400
const MAX_BULLETS := 160
const POPS := 12
const NADES := 6
const BOOMS := 4

const LOOKS := {
	"walker": {skin = Color("#93a86e"), shirt = Color("#4f6f99"), pants = Color("#4a4f5c")},
	"runner": {skin = Color("#c9c2b0"), shirt = Color("#2b2b2e"), pants = Color("#3a3f4a")},
	"tough": {skin = Color("#86a08c"), shirt = Color("#7d3434"), pants = Color("#3c4038"), helmet = Color("#56604f"), vest = Color("#3d4636"), eye = Color("#ffd23f")},
	"brute": {skin = Color("#7b9658"), shirt = Color("#5e4680"), pants = Color("#3b322c"), scale = 1.35},
	"monster": {skin = Color("#5f7d33"), shirt = Color("#3f5a24"), pants = Color("#2f4520"), scale = 1.6, eye = Color("#ffe066")},
	"flyer": {skin = Color("#a194ad"), shirt = Color("#3b2f45"), pants = Color("#2d2a33")},
}


class Inp:
	var move_v := Vector2.ZERO # الحركة (x, z)
	var move := 0.0
	var down := false
	var jump := 0.0
	var fire := false
	var aim = null # زاوية التصويب على الأرض (0 = يمين الشاشة، π/2 = لتحت الشاشة)
	var swap := false
	var throw := false
	var reload := false
	var select := ""


class P:
	var id := "me"
	var name := ""
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var aim := -PI / 2
	var hp := 100.0
	var max_hp := 100.0
	var weapon := "pistol"
	var ammo := {}
	var reload := 0.0
	var grenades := 5
	var fire_cd := 0.0
	var g_cd := 0.0
	var recoil := 0.0
	var inv := 0.0
	var dead := 0.0
	var local := true
	var bot := false
	var bricks := 0
	var node: Humanoid


class Z:
	var id := 0
	var kind := "walker"
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var r := 0.45
	var hp := 1.0
	var max := 1.0
	var speed := 1.0
	var atk := 0.0
	var atk_t := 0.0
	var hurt := 0.0
	var dead := 0.0
	var fly := 0.0 # ارتفاع الطاير
	var node: Humanoid


var park: Park
var level := 1.0
var cfg := {}
var time := 0.0
var players: Array = []
var zs: Array = []
var owned: Array = ["pistol"]
var status := "play"
var end_t := 0.0
var total := 0
var spawned := 0
var killed := 0
var spawn_cd := 1.5
var credits := {}
var me_id := "me"
var my_kills := 0
var my_headshots := 0
var took_damage := false
var min_hp := {}
var sounds: Array[String] = []
var shake := 0.0
var _next := 1

# مؤثرات (مصفوفات + MultiMesh)
var _bul := [] # {p: Vector3, v: Vector3, dmg, life, owner}
var _bul_mm: MultiMesh
var _parts := [] # {p, v, life, max, col, s}
var _part_mm: MultiMesh
var _decals := [] # {p, r, life}
var _decal_mm: MultiMesh
var _nades := [] # {p: Vector3, v: Vector3, t, node, owner}
var _booms := [] # {node, t}
var _pops := [] # {node, life}
var _flash: MeshInstance3D
# مجموعات جاهزة: كل شي ينبني وقت التحميل، وباللعب بس نخفي ونظهر (ماكو بناء ولا مسح وسط القتال)
var _zpool := {} # النوع ← [Humanoid مخفي]
var _pop_nodes: Array[Label3D] = []
var _nade_nodes: Array[MeshInstance3D] = []
var _boom_nodes: Array[MeshInstance3D] = []
var _boom_mat: StandardMaterial3D
const FONT := preload("res://fonts/cairo_bold.tres")
var _blob_mm: MultiMesh # ظلال دائرية ناعمة تحت الزومبي (رسمة وحدة)
var _flash_t := 0.0
var _shots := 0 # للقياس بس (أول طلقة)


func _init(p: Park, level_v: float, owned_list: Array, weapon: String, who := {}) -> void:
	park = p
	level = maxf(1.0, level_v)
	cfg = Config.level_cfg(level)
	total = cfg.total
	owned = owned_list
	me_id = who.get("id", "me")
	var m := P.new()
	m.id = me_id
	m.name = who.get("name", "")
	m.pos = Vector2(0, 19)
	m.weapon = weapon if owned.has(weapon) else "pistol"
	for w in Config.WEAPONS:
		m.ammo[w] = Config.WEAPONS[w].mag
	m.grenades = Config.GRENADE.per_stage
	players.append(m)


func _ready() -> void:
	var m: P = players[0]
	m.node = H.new()
	m.node.build("soldier", {shirt = Color("#6b7040"), helmet = Color("#4f5a34"), gun = m.weapon})
	add_child(m.node)
	_bul_mm = _mm(_glow_box(), MAX_BULLETS, true)
	_part_mm = _mm(H.mesh("sphere", 0.5), MAX_PARTS, true)
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.01
	disc.radial_segments = 14
	_decal_mm = _mm(disc, 80, true)
	var blob := PlaneMesh.new()
	blob.size = Vector2(1, 1)
	_blob_mm = _mm(blob, 64, true, _blob_shader())
	_make_pools()
	_flash = MeshInstance3D.new()
	_flash.mesh = H.mesh("sphere", 0.16)
	_flash.material_override = H.mat(Color("#ffe9a0"), 0.2, 6.0)
	_flash.visible = false
	add_child(_flash)


func _make_pools() -> void:
	for kind in cfg.mix:
		if cfg.mix[kind] <= 0:
			continue
		var list: Array = []
		for i in cfg.max_alive + 5:
			list.append(_new_zombie(kind))
		_zpool[kind] = list
	for i in POPS:
		var l := Label3D.new()
		l.font = FONT
		l.font_size = 64
		l.pixel_size = 0.008
		l.outline_modulate = Color(0, 0, 0, 0.85)
		l.outline_size = 14
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.visible = false
		add_child(l)
		_pop_nodes.append(l)
	for i in NADES:
		var node := MeshInstance3D.new()
		node.mesh = H.mesh("sphere", 0.12, 1.2)
		node.material_override = H.mat(Color("#4f5e38"), 0.6)
		node.visible = false
		add_child(node)
		_nade_nodes.append(node)
	# مادة الانفجار وحدة للكل، والتلاشي بـ transparency مال كل كرة
	_boom_mat = StandardMaterial3D.new()
	_boom_mat.albedo_color = Color(1.0, 0.7, 0.25, 0.9)
	_boom_mat.emission_enabled = true
	_boom_mat.emission = Color(1.0, 0.55, 0.15)
	_boom_mat.emission_energy_multiplier = 3.0
	_boom_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_boom_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in BOOMS:
		var ball := MeshInstance3D.new()
		ball.mesh = H.mesh("sphere", 1.0)
		ball.material_override = _boom_mat
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ball.visible = false
		add_child(ball)
		_boom_nodes.append(ball)


func _new_zombie(kind: String) -> Humanoid:
	var n := H.new()
	n.build(kind, LOOKS[kind])
	n.visible = false
	add_child(n)
	return n


func _take_zombie(kind: String) -> Humanoid:
	var list: Array = _zpool.get(kind, [])
	if list.is_empty():
		Perf.ev("pool miss " + kind)
		return _new_zombie(kind)
	return list.pop_back()


func _give_back(z: Z) -> void:
	z.node.visible = false
	if not _zpool.has(z.kind):
		_zpool[z.kind] = []
	_zpool[z.kind].append(z.node)


# أقدم واحد ما مستعمل (أو أقدم واحد بالمرة لو كلهم مستعملين)
func _free_node(nodes: Array, used: Array) -> Node3D:
	for n in nodes:
		if not n.visible:
			return n
	var old: Dictionary = used.pop_front()
	return old.node


func _glow_box() -> Mesh:
	var b := BoxMesh.new()
	b.size = Vector3(0.05, 0.05, 1.0)
	return b


func _blob_shader() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = (1.0 - smoothstep(0.25, 1.0, d)) * COLOR.a;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _mm(mesh: Mesh, n: int, colors: bool, mat_: Material = null) -> MultiMesh:
	var m: Material = mat_
	if m == null:
		var sm := StandardMaterial3D.new()
		sm.vertex_color_use_as_albedo = true
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m = sm
	mesh = mesh.duplicate()
	mesh.surface_set_material(0, m)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = n
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mm


func me() -> P:
	return players[0]


func earned() -> int:
	return int(credits.get(me_id, 0)) + (Config.CLEAR_BONUS * ceili(level) if status == "won" else 0)


func min_hp_avg() -> float:
	if min_hp.is_empty():
		return 1.0
	var s := 0.0
	for k in min_hp:
		s += min_hp[k]
	return s / min_hp.size()


func next_level() -> float:
	return Config.next_level(level, status == "won", min_hp_avg(), time)


func best_gun() -> String:
	for i in range(Config.GUN_ORDER.size() - 1, -1, -1):
		if owned.has(Config.GUN_ORDER[i]):
			return Config.GUN_ORDER[i]
	return "pistol"


static func v3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


# التصويب بالماوس: نقطة الأرض تحت المؤشر
func aim_at_screen(sp: Vector2):
	var cam := park.cam
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	if absf(d.y) < 0.0001:
		return null
	var t := -(o.y - 1.0) / d.y
	var hit := o + d * t
	var dv := Vector2(hit.x, hit.z) - me().pos
	return dv.angle() if dv.length() > 0.3 else null


# ════════ خطوة ════════
func step(inp: Inp, dt: float) -> void:
	time += dt
	if status != "play":
		end_t += dt
	var p := me()
	_update_player(p, inp, dt)
	_spawn(dt)
	_update_zombies(dt)
	_update_bullets(dt)
	_update_nades(dt)
	_update_fx(dt)
	if status == "play":
		min_hp[p.id] = minf(min_hp.get(p.id, 1.0), clampf(p.hp / p.max_hp, 0, 1))
		if p.hp < p.max_hp:
			took_damage = true
		if killed >= total:
			status = "won"
			sounds.append("win")
		elif p.hp <= 0:
			status = "lost"
			sounds.append("lose")
	_camera(dt)


func _update_player(p: P, inp: Inp, dt: float) -> void:
	var alive := p.hp > 0 and status == "play"
	p.fire_cd -= dt
	p.g_cd -= dt
	p.inv -= dt
	p.recoil = maxf(0, p.recoil - dt * 8)
	if alive:
		var mv: Vector2 = inp.move_v.limit_length(1.0)
		p.vel = p.vel.lerp(mv * P_SPEED, minf(1.0, dt * 14))
		if inp.aim != null:
			p.aim = inp.aim
		elif mv.length() > 0.2:
			p.aim = lerp_angle(p.aim, mv.angle(), minf(1.0, dt * 10))
		if inp.swap:
			inp.swap = false
			var list := Config.GUN_ORDER.filter(func(w): return owned.has(w))
			if list.size() > 1:
				p.weapon = list[(list.find(p.weapon) + 1) % list.size()]
				p.reload = 0
				p.fire_cd = 0.2
				p.node.set_gun(p.weapon)
		if inp.throw:
			inp.throw = false
			_throw(p)
		if inp.reload:
			inp.reload = false
			_start_reload(p)
		if p.reload > 0:
			p.reload -= dt
			if p.reload <= 0:
				p.reload = 0
				p.ammo[p.weapon] = Config.WEAPONS[p.weapon].mag
				sounds.append("reload")
		if inp.fire and p.fire_cd <= 0 and p.reload <= 0:
			if p.ammo[p.weapon] > 0:
				_fire(p)
				p.ammo[p.weapon] -= 1
			if p.ammo[p.weapon] <= 0:
				_start_reload(p)
	else:
		p.vel = p.vel.lerp(Vector2.ZERO, minf(1.0, dt * 6))
		if p.hp <= 0:
			p.dead += dt
	p.pos = park.resolve(p.pos + p.vel * dt, P_R)
	# الرسم
	var n := p.node
	n.position = v3(p.pos)
	n.rotation.y = -p.aim - PI / 2
	if p.hp <= 0:
		n.rotation.x = lerpf(n.rotation.x, -1.45, minf(1.0, dt * 6))
		n.animate(dt, 0, "walk")
	else:
		var fwd := Vector2.from_angle(p.aim)
		n.animate(dt, p.vel.length() * (1.0 if p.vel.dot(fwd) >= -0.2 else -1.0), "walk", 0, p.recoil)
		n.set_flash(p.inv > 0.45)
		n.visible = not (p.inv > 0 and int(time * 18) % 2 == 0)


func _start_reload(p: P) -> void:
	if p.reload > 0 or p.ammo[p.weapon] >= Config.WEAPONS[p.weapon].mag:
		return
	p.reload = Config.WEAPONS[p.weapon].reload
	sounds.append("reload")


func reload_progress(p: P) -> float:
	return 1 - p.reload / Config.WEAPONS[p.weapon].reload if p.reload > 0 else 0.0


func _fire(p: P) -> void:
	var w: Dictionary = Config.WEAPONS[p.weapon]
	p.fire_cd = w.rate
	p.recoil = 1
	var a := p.aim + randf_range(-w.spread, w.spread) * 0.004
	var origin: Vector3 = p.node.muzzle.global_position if p.node.muzzle != null else v3(p.pos, 1.3)
	var dir := Vector3(cos(a), 0, sin(a))
	_bul.append({p = origin, v = dir * w.speed * PX, dmg = w.damage, life = 0.9, owner = p.id})
	_flash.position = origin
	_flash.visible = true
	_flash_t = 0.05
	# ظرف الطلقة
	_add_part(origin + Vector3(0, -0.05, 0), Vector3(-dir.z, 0, dir.x) * randf_range(1.5, 2.5) + Vector3(0, 3, 0), 0.7, Color("#d9a441"), 0.04)
	sounds.append(p.weapon)
	if _shots == 0:
		Perf.ev("first shot")
	_shots += 1


func _throw(p: P) -> void:
	if p.grenades <= 0 or p.g_cd > 0:
		return
	p.grenades -= 1
	p.g_cd = Config.GRENADE.cooldown
	var dir := Vector2.from_angle(p.aim)
	var node := _free_node(_nade_nodes, _nades)
	node.visible = true
	node.position = v3(p.pos, 1.3)
	_nades.append({p = v3(p.pos, 1.3), v = v3(dir * 11.0, 6.5) + v3(p.vel * 0.4), t = Config.GRENADE.fuse, node = node, owner = p.id})
	p.recoil = 1
	sounds.append("throw")
	Perf.ev("grenade thrown")


# ════════ الزومبي ════════
func _spawn(dt: float) -> void:
	if status != "play" or spawned >= total:
		return
	var living := zs.filter(func(z): return z.dead == 0).size()
	var prog := float(spawned) / total
	spawn_cd -= dt
	if spawn_cd > 0 or living >= cfg.max_alive + int(prog * 4):
		return
	spawn_cd = randf_range(cfg.every[0], cfg.every[1]) * (1 - 0.35 * prog)
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
	# مكان بعيد عن اللاعب (برّه الشاشة) وداخل الحديقة
	var at := Vector2.ZERO
	for i in 20:
		at = me().pos + Vector2.from_angle(randf() * TAU) * randf_range(16, 24)
		if absf(at.x) < Park.HALF - 2 and absf(at.y) < Park.HALF - 2 and not park.blocked(at, 0.6):
			break
	var c: Dictionary = Config.ZOMBIES[kind]
	var z := Z.new()
	z.id = _next
	_next += 1
	z.kind = kind
	z.pos = at
	z.r = 0.45 * float(LOOKS[kind].get("scale", 1.0))
	z.speed = randf_range(c.speed[0], c.speed[1]) * PX * cfg.speed_mult * (1.6 if kind != "runner" else 1.3)
	z.hp = roundf(c.hp * cfg.hp_mult * 10) / 10
	z.max = z.hp
	z.atk = randf_range(0.3, 0.8)
	z.fly = 2.2 if kind == "flyer" else 0.0
	z.node = _take_zombie(kind)
	z.node.reset()
	z.node.position = v3(z.pos, z.fly)
	zs.append(z)
	spawned += 1
	Perf.ev("spawn " + kind)
	if kind == "monster":
		sounds.append("roar")


func _update_zombies(dt: float) -> void:
	var p := me()
	for z in zs:
		z.hurt -= dt
		z.atk -= dt
		z.atk_t -= dt
		if z.dead > 0:
			z.dead += dt
			var n: Humanoid = z.node
			n.rotation.x = lerpf(n.rotation.x, -1.5, minf(1.0, dt * 7))
			n.position.y = lerpf(n.position.y, -0.2 if z.dead > 1.2 else 0.0, minf(1.0, dt * 4))
			n.animate(dt, 0, "walk")
			n.set_flash(false)
			continue
		var to: Vector2 = p.pos - z.pos
		var dist: float = to.length()
		var want := Vector2.ZERO
		if p.hp > 0 and status == "play":
			want = to / maxf(dist, 0.001) * z.speed
		# نبعد عن بعض شوية (حتى ما يصيرون كتلة وحدة)
		for o in zs:
			if o != z and o.dead == 0:
				var d: Vector2 = z.pos - o.pos
				var l := d.length()
				if l < (z.r + o.r) * 1.1 and l > 0.001:
					want += d / l * z.speed * 0.8
		z.vel = z.vel.lerp(want, minf(1.0, dt * 6))
		var reach: float = z.r + P_R + 0.35
		if dist < reach:
			z.vel *= 0.2
			if z.atk <= 0 and p.hp > 0:
				z.atk = 0.9 if z.kind != "flyer" else 1.4
				z.atk_t = 0.35
				_hurt(p, z)
		if z.fly > 0:
			z.pos += z.vel * dt
			z.pos = z.pos.clamp(Vector2(-Park.HALF, -Park.HALF), Vector2(Park.HALF, Park.HALF))
		else:
			z.pos = park.resolve(z.pos + z.vel * dt, z.r)
		var n: Humanoid = z.node
		n.position = v3(z.pos, z.fly + (sin(time * 3 + z.id) * 0.15 if z.fly > 0 else 0.0))
		if dist > 0.01:
			n.rotation.y = lerp_angle(n.rotation.y, -to.angle() - PI / 2, minf(1.0, dt * 8))
		var state := "fly" if z.fly > 0 else ("attack" if z.atk_t > 0 else "walk")
		n.animate(dt, z.vel.length(), state, 1.0 - z.atk_t / 0.35)
		n.set_flash(z.hurt > 0)
	# الظلال الدائرية (الطاير ظله أصغر وأخف)
	var nb := 0
	for z in zs:
		if nb >= 64:
			break
		var a: float = 0.55 if z.fly == 0 else 0.3
		if z.dead > 0:
			a *= clampf(2.0 - z.dead, 0, 1)
		var r: float = z.r * (2.6 if z.fly == 0 else 1.8)
		_blob_mm.set_instance_transform(nb, Transform3D(Basis.IDENTITY.scaled(Vector3(r, 1, r)), Vector3(z.node.position.x, 0.04, z.node.position.z)))
		_blob_mm.set_instance_color(nb, Color(0, 0, 0, a))
		nb += 1
	_blob_mm.visible_instance_count = nb
	for z in zs:
		if z.dead > 2.0:
			_give_back(z)
	zs = zs.filter(func(z): return z.dead <= 2.0)


func _hurt(p: P, z: Z) -> void:
	if p.inv > 0:
		return
	p.hp = maxf(0, p.hp - Config.ZOMBIES[z.kind].damage)
	p.inv = 0.6
	p.vel += (p.pos - z.pos).normalized() * 7
	shake = maxf(shake, 0.2)
	sounds.append("hurt")
	_splash(v3(p.pos, 1.1), 8, [Color("#b71c1c"), Color("#7f1010")])


func _kill(z: Z, owner: String) -> void:
	z.dead = 0.0001
	killed += 1
	Perf.ev("died " + z.kind)
	var c: int = Config.ZOMBIES[z.kind].coins
	credits[owner] = int(credits.get(owner, 0)) + c
	if owner == me_id:
		my_kills += 1
	_pop(v3(z.pos, 2.2 + z.fly), "+%d" % c, Color("#ffd23f"))
	_splash(v3(z.pos, 1.0 + z.fly), 16, [Color("#7a1212"), Color("#4b1010"), Color("#5d6b2a")])
	if z.fly == 0:
		_decals.append({p = v3(z.pos, 0.03), r = randf_range(0.5, 0.9) * z.r / 0.45, life = 10.0})
	else:
		z.fly = 0.0
	sounds.append("die")


# ════════ الطلق ════════
func _update_bullets(dt: float) -> void:
	for b in _bul:
		var a: Vector3 = b.p
		var nxt: Vector3 = a + b.v * dt
		b.life -= dt
		# أقرب زومبي على طريق الطلقة
		var seg := Vector2(nxt.x - a.x, nxt.z - a.z)
		var a2 := Vector2(a.x, a.z)
		var best: Z = null
		var best_t := 2.0
		for z in zs:
			if z.dead > 0:
				continue
			var t := clampf((z.pos - a2).dot(seg) / maxf(seg.length_squared(), 0.0001), 0, 1)
			if (a2 + seg * t).distance_to(z.pos) < z.r + 0.12 and t < best_t:
				best_t = t
				best = z
		if best != null:
			b.life = 0
			var hit := a.lerp(nxt, best_t)
			var head := randf() < 0.14 # هيدشوت (ضربة حرجة)
			best.hurt = 0.08
			best.hp -= b.dmg * (Config.HEADSHOT if head else 1.0)
			best.vel += seg.normalized() * (0.6 if best.kind == "brute" or best.kind == "monster" else 2.2)
			_splash(Vector3(hit.x, 1.1 + best.fly, hit.z), 12 if head else 6, [Color("#7a1212"), Color("#5d6b2a"), Color("#ffd27a")])
			if head:
				sounds.append("headshot")
				Perf.ev("headshot")
				if b.owner == me_id:
					my_headshots += 1
					_pop(v3(best.pos, 2.6 + best.fly), "هيدشوت!", Color("#ff5a3a"))
			else:
				sounds.append("hit")
			if best.hp <= 0:
				_kill(best, b.owner)
			continue
		# صدم شجرة/سور
		var g := Vector2(nxt.x, nxt.z)
		if park.blocked(g) and not _over_water(g):
			b.life = 0
			_splash(nxt, 4, [Color("#8a6a4a"), Color("#c9b28c")])
			continue
		b.p = nxt
	_bul = _bul.filter(func(b): return b.life > 0)
	_bul_mm.visible_instance_count = mini(_bul.size(), MAX_BULLETS)
	for i in _bul_mm.visible_instance_count:
		var b: Dictionary = _bul[i]
		var dir: Vector3 = (b.v as Vector3).normalized()
		var basis := Basis.looking_at(dir, Vector3.UP).scaled(Vector3(1, 1, 1.4))
		_bul_mm.set_instance_transform(i, Transform3D(basis, b.p - dir * 0.7))
		_bul_mm.set_instance_color(i, Color(1.0, 0.92, 0.6))


func _over_water(g: Vector2) -> bool:
	return g.length() < Park.POND_R


# ════════ الرمانات ════════
func _update_nades(dt: float) -> void:
	for n in _nades:
		n.v.y -= 22.0 * dt
		var np: Vector3 = n.p + n.v * dt
		if np.y < 0.12:
			np.y = 0.12
			n.v.y = -n.v.y * 0.35
			n.v.x *= 0.6
			n.v.z *= 0.6
		var g := Vector2(np.x, np.z)
		if park.blocked(g, 0.1) and not _over_water(g):
			n.v.x = -n.v.x * 0.4
			n.v.z = -n.v.z * 0.4
			np = n.p
		n.p = np
		n.node.position = np
		n.node.rotation.x += dt * 8
		n.t -= dt
		if n.t <= 0:
			_explode(n)
	_nades = _nades.filter(func(n): return n.t > 0)


func _explode(n: Dictionary) -> void:
	n.node.visible = false
	var c: Vector3 = n.p
	var ball := _free_node(_boom_nodes, _booms)
	ball.visible = true
	ball.position = c
	_booms.append({node = ball, t = 0.0})
	shake = maxf(shake, 0.5)
	sounds.append("boom")
	Perf.ev("explosion")
	for i in 26:
		_add_part(c, Vector3(randf_range(-1, 1), randf_range(0.3, 1.2), randf_range(-1, 1)).normalized() * randf_range(4, 10), randf_range(0.3, 0.7), [Color("#ffd25a"), Color("#ff8a2a"), Color("#ff5a1a")][i % 3], randf_range(0.08, 0.16))
	for i in 12:
		_add_part(c + Vector3(randf_range(-0.8, 0.8), 0.3, randf_range(-0.8, 0.8)), Vector3(randf_range(-1, 1), randf_range(1.5, 3), randf_range(-1, 1)), randf_range(0.8, 1.5), Color(0.25, 0.25, 0.25, 0.6), randf_range(0.3, 0.55), true)
	_decals.append({p = Vector3(c.x, 0.025, c.z), r = 1.6, life = 10.0, burn = true})
	var R: float = Config.GRENADE.radius * PX
	var g := Vector2(c.x, c.z)
	for z in zs:
		if z.dead > 0:
			continue
		var d: float = z.pos.distance_to(g)
		if d > R + z.r:
			continue
		z.hp -= Config.GRENADE.damage * (1 - minf(1.0, d / R) * 0.6)
		z.hurt = 0.12
		z.vel += (z.pos - g).normalized() * 6
		if z.hp <= 0:
			_kill(z, n.owner)


# ════════ مؤثرات ════════
func _add_part(p: Vector3, v: Vector3, life: float, col: Color, size: float, smoke := false) -> void:
	if _parts.size() >= MAX_PARTS:
		_parts.pop_front()
	_parts.append({p = p, v = v, life = life, max = life, col = col, s = size, smoke = smoke})


func _splash(p: Vector3, n: int, cols: Array) -> void:
	for i in n:
		_add_part(p, Vector3(randf_range(-1, 1), randf_range(0.2, 1.4), randf_range(-1, 1)) * randf_range(1.5, 4.5), randf_range(0.35, 0.8), cols[i % cols.size()], randf_range(0.04, 0.09))


func _pop(p: Vector3, text: String, col: Color) -> void:
	var l: Label3D = _free_node(_pop_nodes, _pops)
	l.text = text
	l.modulate = col
	l.position = p
	l.visible = true
	Perf.ev("popup " + text)
	_pops.append({node = l, life = 1.1})


func _update_fx(dt: float) -> void:
	# جزيئات
	for q in _parts:
		if q.smoke:
			q.v *= pow(0.5, dt)
			q.s += dt * 0.5
		else:
			q.v.y -= 14.0 * dt
		q.p += q.v * dt
		if q.p.y < 0.03 and not q.smoke:
			q.p.y = 0.03
			q.v *= 0.3
		q.life -= dt
	_parts = _parts.filter(func(q): return q.life > 0)
	_part_mm.visible_instance_count = _parts.size()
	for i in _parts.size():
		var q: Dictionary = _parts[i]
		var col: Color = q.col
		col.a *= minf(1.0, q.life / q.max * 2)
		_part_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * q.s * 2), q.p))
		_part_mm.set_instance_color(i, col)
	# بقع الدم والحروق
	for d in _decals:
		d.life -= dt
	_decals = _decals.filter(func(d): return d.life > 0)
	if _decals.size() > 80:
		_decals = _decals.slice(_decals.size() - 80)
	_decal_mm.visible_instance_count = _decals.size()
	for i in _decals.size():
		var d: Dictionary = _decals[i]
		_decal_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(d.r, 1, d.r * 0.8)), d.p))
		var a := minf(0.6, d.life * 0.15)
		_decal_mm.set_instance_color(i, Color(0.08, 0.05, 0.04, a) if d.get("burn", false) else Color(0.35, 0.03, 0.03, a))
	# انفجارات
	for b in _booms:
		b.t += dt
		var k: float = b.t / 0.5
		b.node.scale = Vector3.ONE * (0.6 + k * 3.2)
		b.node.transparency = k
	for b in _booms:
		if b.t >= 0.5:
			b.node.visible = false
	_booms = _booms.filter(func(b): return b.t < 0.5)
	# الفلوس اللي تطلع
	for q in _pops:
		q.life -= dt
		q.node.position.y += dt * 1.2
		q.node.modulate.a = minf(1.0, q.life * 2)
	for q in _pops:
		if q.life <= 0:
			q.node.visible = false
	_pops = _pops.filter(func(q): return q.life > 0)
	# وميض الطلقة
	_flash_t -= dt
	_flash.visible = _flash_t > 0
	shake = maxf(0, shake - dt)


# الكاميرا تلحق اللاعب من فوگ (مايلة شوية مثل ألعاب التوب داون)
func _camera(dt: float) -> void:
	var p := me()
	var look := v3(p.pos) + v3(Vector2.from_angle(p.aim) * 1.5)
	var want := look + Vector3(0, 12.5, 8.2)
	var cam := park.cam
	cam.position = cam.position.lerp(want, minf(1.0, dt * 6))
	var sh := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * shake * 0.6
	cam.look_at(cam.position - Vector3(0, 12.5, 8.2) + sh)
