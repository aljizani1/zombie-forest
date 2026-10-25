# ════════ شخصية ثلاثية الأبعاد (جندي أو زومبي) ════════
# موديلات GLB مع عظام وأنيميشن (Quaternius، CC0): الزومبي = رسمتين بس (جسم + جفون) بدال ~30 قطعة.
# الأنيميشن بـ AnimationTree: انتقال ناعم (0.2 ث) بين الوقوف / المشي / الركض / الضربة / الموت،
# وسرعة الأنيميشن تمشي ويا سرعة الحركة حتى الرجلين ما تزحلق. الانضراب = حركة قصيرة للنص الفوگاني + لمعة بيضة.
# الوجه لـ -Z (قدّام). نفس الواجهة القديمة: build / animate / set_flash / set_gun / muzzle.
class_name Humanoid
extends Node3D

const ZOMBIE := preload("res://assets/characters/zombie.glb")
const SOLDIER := preload("res://assets/characters/soldier.glb")
const Z_SCALE := 1.3 # الموديل الأصلي 1.36م
const S_SCALE := 0.8
# سرعة الرجل بالأنيميشن الأصلي (م/ث بحجم 1): نقسم سرعة الحركة عليها
const Z_WALK := 0.77
const Z_RUN := 2.12
const S_RUN := 2.47
# الأسلحة: موجودة بموديل الجندي (نفس الستايل)، نظهر وحدة بس
const GUNS := {"pistol": "Pistol", "akm": "AK", "pkm": "Sniper_2"}
const STATES_Z := {"idle": "Idle", "walk": "Walk", "run": "Run", "attack": "Punch", "dead": "Death", "fly": "Jump_Idle"}
const STATES_S := {"idle": "Idle", "shoot": "Idle_Shoot", "run": "Run_Gun", "dead": "Death"}
const UPPER := ["Abdomen", "Torso", "Neck", "Head", "Shoulder.L", "UpperArm.L", "LowerArm.L", "Shoulder.R", "UpperArm.R", "LowerArm.R"]

static var _meshes := {}
static var _mats := {}
static var _trees := {}
static var _tints := {}
static var _stripped := {}
static var flash_mat: StandardMaterial3D

var kind := "soldier"
var gun: Node3D
var muzzle: Node3D
var wings: Array[Node3D] = []
var _model: Node3D
var _tree: AnimationTree
var _acc := 0.0 # وقت أنيميشن متجمع (الزومبي يتحدثون كل إطارين)
var _tick := 0
static var _count := 0
var _skins: Array[MeshInstance3D] = [] # الرسمات اللي تلمع
var _guns := {}
var _state := ""
var _t := 0.0
var _flash := false
var _zombie := true
var _size := 1.0


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


# شجرة الأنيميشن (وحدة لكل نوع موديل، مشتركة): انتقال بين الحالات → سرعة → ضربة قصيرة للنص الفوگاني
static func _tree_for(zombie: bool, prefix: String) -> AnimationNodeBlendTree:
	if _trees.has(zombie):
		return _trees[zombie]
	var states := STATES_Z if zombie else STATES_S
	var bt := AnimationNodeBlendTree.new()
	var tr := AnimationNodeTransition.new()
	tr.xfade_time = 0.2
	bt.add_node("state", tr)
	var i := 0
	for s in states:
		tr.add_input(s)
		var an := AnimationNodeAnimation.new()
		an.animation = prefix + states[s]
		bt.add_node("a_" + s, an)
		bt.connect_node("state", i, "a_" + s)
		i += 1
	var ts := AnimationNodeTimeScale.new()
	bt.add_node("speed", ts)
	bt.connect_node("speed", 0, "state")
	var hit := AnimationNodeOneShot.new()
	hit.fadein_time = 0.06
	hit.fadeout_time = 0.18
	hit.filter_enabled = true
	for b in UPPER:
		hit.set_filter_path(NodePath("RootNode/CharacterArmature/Skeleton3D:" + b), true)
	bt.add_node("hit", hit)
	var ha := AnimationNodeAnimation.new()
	ha.animation = prefix + "HitReact"
	bt.add_node("a_hit", ha)
	bt.connect_node("hit", 0, "speed")
	bt.connect_node("hit", 1, "a_hit")
	bt.connect_node("output", 0, "hit")
	_trees[zombie] = bt
	return bt


# look = {shirt, skin, scale, gun}
func build(k: String, look: Dictionary) -> void:
	kind = k
	_zombie = kind != "soldier"
	_model = (ZOMBIE if _zombie else SOLDIER).instantiate()
	_size = float(look.get("scale", 1.0))
	_model.scale = Vector3.ONE * (Z_SCALE if _zombie else S_SCALE)
	_model.rotation.y = PI # الموديل وجهه لـ +Z
	add_child(_model)
	var prefix := "" if _zombie else "CharacterArmature|"
	var ap: AnimationPlayer = _model.find_children("*", "AnimationPlayer", true, false)[0]
	_prepare_anims(ap, prefix)
	# نشيل نقاط العظام الفاضية (تتحدث كل إطار على الفاضي)
	for ba in _model.find_children("*", "BoneAttachment3D", true, false):
		if ba.find_children("*", "MeshInstance3D", true, false).is_empty():
			ba.free()
	var tint: Color = _tint(look) if _zombie else Color.WHITE
	for m: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _zombie else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if _zombie and m.name == "Zombie":
			m.material_override = _tinted(kind, m.mesh.surface_get_material(0), tint)
		if not _zombie and m.get_parent().name == "Index1_R":
			_guns[str(m.name)] = m
			m.visible = false
			continue
		_skins.append(m)
	ap.active = false # الشجرة هي اللي تشغّل
	_tree = AnimationTree.new()
	_model.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(ap)
	_tree.root_node = _tree.get_path_to(_model)
	_tree.tree_root = _tree_for(_zombie, prefix)
	_tree.deterministic = false
	# نحدّثها احنا (بـ animate) حتى نگدر نخفف التحديث للزومبي
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_tree.active = true
	_tick = _count # نوزعهم: نصهم يتحدث بإطار والنص الثاني بالإطار اللي بعده
	_count += 1
	if kind == "flyer":
		for s in [-1, 1]:
			var w := Node3D.new()
			w.position = Vector3(s * 0.15, 0.95, 0.22)
			add_child(w)
			var wm := MeshInstance3D.new()
			wm.mesh = mesh("box", 0.9, 0.03, 0.45)
			wm.material_override = mat(Color("#3e3348"))
			wm.position = Vector3(s * 0.45, 0, 0.1)
			wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			w.add_child(wm)
			wings.append(w)
			_skins.append(wm)
	if not _zombie:
		set_gun(look.get("gun", "pistol"))
	scale = Vector3.ONE * _size
	_go("fly" if kind == "flyer" else "idle")


# مرة وحدة لكل موديل: الحركات المتكررة تلف، ونشيل حركة الأصابع وأهداف الركب (نص العظام، ما تبين من فوگ)
static func _prepare_anims(ap: AnimationPlayer, prefix: String) -> void:
	if _stripped.has(prefix):
		return
	_stripped[prefix] = true
	for a in ["Idle", "Walk", "Run", "Run_Gun", "Idle_Shoot", "Jump_Idle"]:
		if ap.has_animation(prefix + a):
			ap.get_animation(prefix + a).loop_mode = Animation.LOOP_LINEAR
	for name in ap.get_animation_list():
		var anim := ap.get_animation(name)
		for t in range(anim.get_track_count() - 1, -1, -1):
			var bone := str(anim.track_get_path(t).get_concatenated_subnames())
			if bone.begins_with("Pinky") or bone.begins_with("Middle") or bone.begins_with("Index") or bone.begins_with("Thumb") or bone.begins_with("PoleTarget") or bone.begins_with("Tongue"):
				anim.remove_track(t)


# لون خفيف فوگ أطلس الزومبي حسب النوع (من لون القميص)
static func _tint(look: Dictionary) -> Color:
	var c: Color = look.get("shirt", Color.WHITE)
	return Color.WHITE.lerp(c.lightened(0.45), 0.6)


static func _tinted(k: String, base: Material, tint: Color) -> Material:
	if _tints.has(k):
		return _tints[k]
	var m: StandardMaterial3D = base.duplicate()
	m.albedo_color = tint
	_tints[k] = m
	return m


# يرجع جاهز للاستعمال من جديد (الزومبي ينعادون من مجموعة جاهزة بدال ما ينبنون وينمسحون)
func reset() -> void:
	rotation = Vector3.ZERO
	_t = randf() * 10.0
	set_flash(false)
	_state = ""
	_acc = 0.0
	_go("fly" if kind == "flyer" else "idle")
	visible = true


func _notification(what: int) -> void:
	# المخفي ما يحسب أنيميشن
	if what == NOTIFICATION_VISIBILITY_CHANGED and _tree != null:
		_tree.active = visible


func _go(s: String) -> void:
	if s == _state:
		return
	_state = s
	_tree.set("parameters/state/transition_request", s)


# السلاح بإيد الجندي اليمين، ونقطة الفوهة براس السبطانة
func set_gun(id: String) -> void:
	if gun != null:
		gun.visible = false
	gun = _guns.get(GUNS.get(id, "Pistol"), _guns.get("Pistol"))
	gun.visible = true
	if gun.get_node_or_null("Muzzle") == null:
		var mk := Marker3D.new()
		mk.name = "Muzzle"
		mk.position = _barrel_tip(gun.mesh)
		gun.add_child(mk)
	muzzle = gun.get_node("Muzzle")


# وقت التحميل: كل الأسلحة تبين حتى موادها تتجهز (بعدين يرجع بس المختار)
func show_all_guns(on: bool) -> void:
	for id in GUNS:
		var g: Node3D = _guns.get(GUNS[id])
		if g != null:
			g.visible = on or g == gun


# راس السبطانة: أطول محور بالسلاح، الطرف الأبعد عن الإيد (الإيد عند الصفر)، ومعدّل النقاط اللي يمه
static func _barrel_tip(m: Mesh) -> Vector3:
	var ab := m.get_aabb()
	var ax := ab.get_longest_axis_index()
	var lo := ab.position[ax]
	var hi := ab.end[ax]
	var far := hi if absf(hi) > absf(lo) else lo
	var band := (hi - lo) * 0.06
	var sum := Vector3.ZERO
	var n := 0
	for si in m.get_surface_count():
		for v: Vector3 in m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
			if absf(v[ax] - far) < band:
				sum += v
				n += 1
	var tip := sum / maxi(n, 1)
	tip[ax] = far
	return tip


# لمعة بيضة لمن ينضرب (طبقة فوگ المادة، ما نبدل المواد) + حركة انضراب قصيرة
func set_flash(on: bool) -> void:
	if on == _flash:
		return
	_flash = on
	if flash_mat == null:
		flash_mat = StandardMaterial3D.new()
		flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		flash_mat.albedo_color = Color(1, 1, 1, 0.55)
	for m in _skins:
		m.material_overlay = flash_mat if on else null
	if on and _state != "dead" and not _tree.get("parameters/hit/active"):
		_tree.set("parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


# speed = سرعة المشي (م/ث، بالسالب = لورا)، state: walk / attack / fly / dead، atk = تقدّم الضربة 0..1، recoil 0..1
func animate(dt: float, speed: float, state := "walk", _atk := 0.0, recoil := 0.0) -> void:
	_t += dt
	var v := absf(speed)
	var k := 1.0
	var sz := _size * (Z_SCALE if _zombie else S_SCALE)
	if state == "dead":
		_go("dead")
	elif state == "fly":
		_go("fly")
		for i in wings.size():
			wings[i].rotation.z = (1 if i == 0 else -1) * (0.3 + 0.6 * sin(_t * 12))
	elif state == "attack":
		_go("attack")
		k = 0.75 / 0.4 # الضربة تخلص بـ 0.4 ث
	elif not _zombie:
		if v < 0.3:
			_go("shoot" if recoil > 0 else "idle")
		else:
			_go("run")
			k = speed / (S_RUN * sz)
	elif v < 0.15:
		_go("idle")
	elif kind != "runner" and v < 2.2 * sz:
		_go("walk")
		k = v / (Z_WALK * sz)
	else:
		_go("run")
		k = v / (Z_RUN * sz)
	_tree.set("parameters/speed/scale", k)
	# الجندي كل إطار. الزومبي كل إطارين، واللي برّه الشاشة كل 6 إطارات (ما يبين الفرق من فوگ، ونص الحساب)
	_acc += dt
	_tick += 1
	if _zombie:
		var cam := get_viewport().get_camera_3d()
		var every := 2 if cam == null or cam.is_position_in_frustum(global_position + Vector3(0, 1, 0)) else 6
		if _tick % every != 0:
			return
	_tree.advance(_acc)
	_acc = 0.0
