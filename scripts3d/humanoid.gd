# ════════ شخصية ثلاثية الأبعاد (جندي أو زومبي) ════════
# جسم من قطع (ورك، جذع، راس، ذراع، ساعد، فخذ، ساق، رجل) مربوطة بمفاصل، والأنيميشن بالكود:
# الجندي: ركض + يمسك السلاح لقدّام + ارتداد الطلقة. الزومبي: مشية عرجة، إيدين لقدّام، ضربة، وطيران للطاير.
# الوجه لـ -Z (قدّام). التدوير الموجب حول X يحرّك الطرف لقدّام.
class_name Humanoid
extends Node3D

const SKIN := Color("#e9b98f")

static var _meshes := {}
static var _mats := {}
static var flash_mat: StandardMaterial3D

var kind := "soldier"
var hips: Node3D
var spine: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var gun: Node3D
var muzzle: Node3D
var wings: Array[Node3D] = []
var _parts: Array = [] # [MeshInstance3D، مادته]
var _phase := 0.0
var _t := 0.0
var _flash := false
var _shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_ON # الزومبي بدون ظل حقيقي (ظل دائري تحتهم من اللعبة)


static func mesh(kind_: String, a: float, b := 0.0, c := 0.0) -> Mesh:
	var key := "%s|%.3f|%.3f|%.3f" % [kind_, a, b, c]
	if _meshes.has(key):
		return _meshes[key]
	var m: Mesh
	match kind_:
		"capsule":
			var cm := CapsuleMesh.new()
			cm.radius = a
			cm.height = maxf(b, a * 2.01)
			cm.radial_segments = 10
			cm.rings = 3
			m = cm
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = a
			sm.height = a * 2 * (b if b > 0 else 1.0)
			sm.radial_segments = 12
			sm.rings = 6
			m = sm
		"cone":
			var co := CylinderMesh.new()
			co.top_radius = 0.0
			co.bottom_radius = a
			co.height = b
			co.radial_segments = 8
			m = co
		_:
			var bm := BoxMesh.new()
			bm.size = Vector3(a, b, c)
			m = bm
	_meshes[key] = m
	return m


static func mat(col: Color, rough := 0.8, emit := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [col.to_html(), rough, emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if emit > 0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	_mats[key] = m
	return m


func _part(parent: Node3D, m: Mesh, col: Color, pos := Vector3.ZERO, rot := Vector3.ZERO, rough := 0.8) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	var mt := mat(col, rough)
	mi.material_override = mt
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = _shadow
	parent.add_child(mi)
	_parts.append([mi, mt])
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


# look = {shirt, pants, skin, helmet, eye, gun}
func build(k: String, look: Dictionary) -> void:
	kind = k
	var shirt: Color = look.get("shirt", Color("#6b7040"))
	var pants: Color = look.get("pants", shirt.darkened(0.25))
	var skin: Color = look.get("skin", SKIN)
	var boots := Color("#2b2520")
	var zombie := kind != "soldier"
	if zombie:
		_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wide := 1.3 if kind == "brute" or kind == "monster" else 1.0

	hips = _pivot(self, Vector3(0, 0.92, 0))
	spine = _pivot(hips, Vector3.ZERO)
	# الجذع
	_part(spine, mesh("capsule", 0.2 * wide, 0.62), shirt, Vector3(0, 0.3, 0))
	_part(spine, mesh("box", 0.36 * wide, 0.1, 0.24), pants.darkened(0.2), Vector3(0, 0.02, 0))
	if not zombie:
		# صدرية + جيوب
		_part(spine, mesh("box", 0.38, 0.32, 0.27), shirt.darkened(0.3), Vector3(0, 0.33, 0))
		_part(spine, mesh("box", 0.1, 0.1, 0.05), shirt.darkened(0.45), Vector3(-0.09, 0.3, -0.14))
		_part(spine, mesh("box", 0.1, 0.1, 0.05), shirt.darkened(0.45), Vector3(0.09, 0.3, -0.14))
	elif look.has("vest"):
		_part(spine, mesh("box", 0.38, 0.3, 0.27), look.vest, Vector3(0, 0.33, 0))
	# الراس
	head = _pivot(spine, Vector3(0, 0.68, 0))
	_part(head, mesh("sphere", 0.14 * (1.1 if kind == "brute" else 1.0), 1.1), skin, Vector3(0, 0.1, 0))
	if zombie:
		var eye: Color = look.get("eye", Color("#ff3a2a"))
		for s in [-0.05, 0.05]:
			var e := MeshInstance3D.new()
			e.mesh = mesh("sphere", 0.025)
			e.material_override = mat(eye, 0.3, 3.0)
			e.position = Vector3(s, 0.13, -0.125)
			e.cast_shadow = _shadow
			head.add_child(e)
		_part(head, mesh("box", 0.12, 0.04, 0.03), Color("#2b0d0d"), Vector3(0, 0.03, -0.13))
	else:
		# نظارة خضرا
		var g := MeshInstance3D.new()
		g.mesh = mesh("box", 0.2, 0.05, 0.04)
		g.material_override = mat(Color("#5cc23f"), 0.2, 1.2)
		g.position = Vector3(0, 0.13, -0.13)
		head.add_child(g)
	if look.has("helmet"):
		_part(head, mesh("sphere", 0.165, 0.7), look.helmet, Vector3(0, 0.17, 0.01))
	if kind == "monster":
		for s in [-1, 1]:
			_part(head, mesh("cone", 0.05, 0.25), Color("#b8b6a6"), Vector3(s * 0.1, 0.3, 0), Vector3(0, 0, -s * 0.5))

	# الذراعين
	var arm_w := 0.065 * wide
	arm_l = _pivot(spine, Vector3(-0.27 * wide, 0.56, 0))
	arm_r = _pivot(spine, Vector3(0.27 * wide, 0.56, 0))
	for a in [arm_l, arm_r]:
		_part(a, mesh("capsule", arm_w, 0.34), shirt.darkened(0.1), Vector3(0, -0.15, 0))
		var el := _pivot(a, Vector3(0, -0.3, 0))
		_part(el, mesh("capsule", arm_w * 0.9, 0.3), skin if zombie else shirt.darkened(0.1), Vector3(0, -0.13, 0))
		_part(el, mesh("sphere", arm_w * 1.2), skin if zombie else Color("#3a3328"), Vector3(0, -0.29, 0))
		if a == arm_l:
			elbow_l = el
		else:
			elbow_r = el
	# الرجلين
	leg_l = _pivot(hips, Vector3(-0.11 * wide, 0, 0))
	leg_r = _pivot(hips, Vector3(0.11 * wide, 0, 0))
	for l in [leg_l, leg_r]:
		_part(l, mesh("capsule", 0.085 * wide, 0.48), pants, Vector3(0, -0.22, 0))
		var kn := _pivot(l, Vector3(0, -0.45, 0))
		_part(kn, mesh("capsule", 0.075 * wide, 0.46), pants.darkened(0.1), Vector3(0, -0.21, 0))
		_part(kn, mesh("box", 0.13 * wide, 0.08, 0.26), boots, Vector3(0, -0.43, -0.05))
		if l == leg_l:
			knee_l = kn
		else:
			knee_r = kn
	# أجنحة الطاير
	if kind == "flyer":
		for s in [-1, 1]:
			var w := _pivot(spine, Vector3(s * 0.12, 0.5, 0.12))
			_part(w, mesh("box", 0.9, 0.03, 0.45), Color("#3e3348"), Vector3(s * 0.45, 0, 0.1))
			wings.append(w)
	if not zombie:
		set_gun(look.get("gun", "pistol"))
	scale = Vector3.ONE * float(look.get("scale", 1.0))


# السلاح بين الإيدين قدّام الصدر
func set_gun(id: String) -> void:
	if gun != null:
		gun.queue_free()
		_parts = _parts.filter(func(p): return is_instance_valid(p[0]) and not gun.is_ancestor_of(p[0]))
	gun = _pivot(spine, Vector3(0.1, 0.42, -0.3))
	var metal := Color("#2e3036")
	var wood := Color("#8a4f22")
	var length := 0.3
	match id:
		"pistol":
			_part(gun, mesh("box", 0.06, 0.08, 0.26), metal, Vector3(0, 0, -0.08), Vector3.ZERO, 0.4)
			_part(gun, mesh("box", 0.05, 0.12, 0.06), metal, Vector3(0, -0.07, 0.02))
			length = 0.24
		"akm":
			_part(gun, mesh("box", 0.07, 0.09, 0.62), metal, Vector3(0, 0, -0.18), Vector3.ZERO, 0.4)
			_part(gun, mesh("box", 0.06, 0.08, 0.28), wood, Vector3(0, -0.02, 0.22))
			_part(gun, mesh("box", 0.05, 0.18, 0.07), Color("#2c2a27"), Vector3(0, -0.12, -0.14), Vector3(-0.3, 0, 0))
			length = 0.5
		"pkm":
			_part(gun, mesh("box", 0.08, 0.1, 0.86), metal, Vector3(0, 0, -0.26), Vector3.ZERO, 0.4)
			_part(gun, mesh("box", 0.12, 0.14, 0.16), Color("#4f5a34"), Vector3(0, -0.1, -0.08))
			_part(gun, mesh("box", 0.06, 0.08, 0.26), Color("#2b2826"), Vector3(0, -0.02, 0.26))
			length = 0.72
		_:
			_part(gun, mesh("box", 0.06, 0.08, 0.26), metal, Vector3(0, 0, -0.08))
	muzzle = _pivot(gun, Vector3(0, 0, -length))


# يرجع جاهز للاستعمال من جديد (الزومبي ينعادون من مجموعة جاهزة بدال ما ينبنون وينمسحون)
func reset() -> void:
	rotation = Vector3.ZERO
	_phase = 0.0
	_t = randf() * 10.0
	set_flash(false)
	visible = true


# لمعة بيضة لمن ينضرب
func set_flash(on: bool) -> void:
	if on == _flash:
		return
	_flash = on
	if flash_mat == null:
		flash_mat = mat(Color(1, 1, 1), 0.5, 1.5)
	for p in _parts:
		if is_instance_valid(p[0]):
			p[0].material_override = flash_mat if on else p[1]


# speed = سرعة المشي (م/ث)، state: walk / attack / fly / dead، atk = تقدّم الضربة 0..1، recoil 0..1
func animate(dt: float, speed: float, state := "walk", atk := 0.0, recoil := 0.0) -> void:
	_t += dt
	var zombie := kind != "soldier"
	var stride := 6.5 if not zombie else 4.5
	_phase += speed * dt * stride / (1.0 + (0.3 if zombie else 0.0))
	var amp := clampf(speed / (4.5 if not zombie else 2.0), 0, 1)
	var s := sin(_phase)
	var c := cos(_phase)
	if state == "fly":
		# طاير: رجلين متدلية وأجنحة ترفرف
		leg_l.rotation.x = 0.3 + 0.1 * sin(_t * 3)
		leg_r.rotation.x = 0.2 + 0.1 * sin(_t * 3 + 1)
		knee_l.rotation.x = -0.6
		knee_r.rotation.x = -0.7
		for i in wings.size():
			wings[i].rotation.z = (1 if i == 0 else -1) * (0.3 + 0.6 * sin(_t * 12))
		hips.position.y = 0.92
	else:
		# رجلين: فخذ يتمرجح، والركبة تنثني وقت الرجل ورا
		var leg_amp := (0.75 if not zombie else 0.5) * amp
		leg_l.rotation.x = s * leg_amp
		leg_r.rotation.x = -s * leg_amp
		knee_l.rotation.x = -maxf(0.0, -s) * 1.1 * amp - 0.05
		knee_r.rotation.x = -maxf(0.0, s) * 1.1 * amp - 0.05
		hips.position.y = 0.92 - absf(c) * 0.04 * amp + (0.01 * sin(_t * 2.2) if amp < 0.1 else 0.0)
	if zombie:
		# منحني لقدّام، الراس مايل، والإيدين ممدودة
		var sway := sin(_t * 1.7)
		spine.rotation.x = 0.32 + 0.05 * sin(_phase * 2)
		spine.rotation.z = 0.06 * sway + 0.08 * s * amp
		head.rotation = Vector3(0.25 + 0.08 * sin(_phase + 0.5), 0.15 * sway, 0.12 * sway)
		var reach := 1.45
		if state == "attack":
			var k := clampf(atk, 0, 1)
			var sw := k / 0.4 if k < 0.4 else 1.0 - (k - 0.4) / 0.6
			reach = 1.3 + sw * 1.3
			spine.rotation.x = 0.32 + (1 - sw) * 0.2
		arm_l.rotation = Vector3(reach - spine.rotation.x + 0.1 * sin(_phase + 1.2), 0, 0.12)
		arm_r.rotation = Vector3(reach - spine.rotation.x + 0.1 * sin(_phase), 0, -0.12)
		elbow_l.rotation.x = 0.25
		elbow_r.rotation.x = 0.18
	else:
		# جندي: الجذع ثابت شوية، الإيدين ماسكة السلاح لقدّام، والسلاح يرتد لمن يرمي
		spine.rotation.x = 0.06 * amp - recoil * 0.06
		spine.rotation.z = 0.0
		head.rotation = Vector3(-0.05, 0, 0)
		arm_r.rotation = Vector3(1.25 - recoil * 0.2, 0.2, -0.05)
		arm_l.rotation = Vector3(1.45 - recoil * 0.2, -0.55, 0.1)
		elbow_r.rotation.x = 0.45
		elbow_l.rotation.x = 0.15
		if gun != null:
			gun.position.z = -0.3 + recoil * 0.07
			gun.rotation.x = recoil * 0.12
