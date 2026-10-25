# ════════ العالم ثلاثي الأبعاد (حديقة من فوگ) ════════
# كل شي ينبني بالكود: أرض عشب، ممرات حجر، بحيرة وجسر، أشجار، شجيرات، مصاطب، طاولات، أعمدة إنارة، سور.
# الأشياء المتكررة (أشجار، شجيرات، حجار، ورد) تنرسم بـ MultiMesh (رسمة وحدة لكل نوع = أداء عالي بالتلفون).
# العوائق (للتصادم) دواير وسطوح بسيطة على مستوى الأرض.
class_name Park
extends Node3D

const HALF := 40.0 # نص طول الحديقة (السور على ±40م)
const POND_R := 9.0
const RING_IN := 13.0 # الممر الدائري حول البحيرة
const RING_OUT := 15.5

var obstacles: Array = [] # {p: Vector2, r: float} دواير
var boxes: Array = [] # Rect2 بالـ XZ (سور، مصاطب...)
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var rng := RandomNumberGenerator.new()
var _mats := {}


func _ready() -> void:
	rng.seed = 2026
	_light()
	_ground()
	_paths()
	_pond()
	_walls()
	_props()
	_trees()
	_merge_static()
	cam = Camera3D.new()
	cam.fov = 42
	cam.far = 200
	add_child(cam)
	cam.position = Vector3(0, 21, 13)
	cam.look_at(Vector3.ZERO)
	cam.current = true


# ── مواد ──
func mat(col: Color, rough := 0.9, emit := 0.0) -> StandardMaterial3D:
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


func _shader(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


const NOISE := """
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
"""


# ── الضوء والجو ──
func _light() -> void:
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -35, 0)
	sun.light_energy = 1.0
	sun.light_color = Color("#fff3df")
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45
	sun.shadow_blur = 1.5
	add_child(sun)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#9cc9e8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b9cfe0")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color("#c9dcea")
	env.fog_density = 0.0015
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


# 0 منخفضة، 1 متوسطة، 2 عالية
func apply_quality(q: int) -> void:
	get_viewport().scaling_3d_scale = [0.7, 0.85, 1.0][q]
	sun.shadow_enabled = q > 0
	sun.directional_shadow_max_distance = 32.0 if q == 1 else 45.0
	RenderingServer.directional_shadow_atlas_set_size(1024 if q < 2 else 4096, true)
	env.fog_enabled = q > 0


# ── الأرض: عشب بألوان متغيرة ──
func _ground() -> void:
	var m := _shader("""
shader_type spatial;
varying vec3 wp;
""" + NOISE + """
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float n = noise(wp.xz * 0.12) * 0.6 + noise(wp.xz * 0.7) * 0.4;
	vec3 a = vec3(0.24, 0.48, 0.16);
	vec3 b = vec3(0.42, 0.62, 0.22);
	vec3 col = mix(a, b, n);
	col *= 0.93 + 0.14 * noise(wp.xz * 2.5);
	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = 0.95;
}
""")
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(HALF * 2 + 30, HALF * 2 + 30)
	g.mesh = pm
	g.material_override = m
	add_child(g)


# ── ممرات حجر (دائري حول البحيرة + أربع ممرات للأبواب) ──
func _stone_mat() -> ShaderMaterial:
	return _shader("""
shader_type spatial;
render_mode cull_disabled;
varying vec3 wp;
""" + NOISE + """
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = (abs(NORMAL.y) > 0.5 ? wp.xz : (abs(NORMAL.x) > 0.5 ? wp.zy : wp.xy)) * 1.6;
	vec2 cell = floor(p + vec2(0.0, mod(floor(p.x), 2.0) * 0.5));
	vec2 f = fract(p + vec2(0.0, mod(floor(p.x), 2.0) * 0.5));
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
	float tone = 0.78 + 0.22 * hash(cell);
	vec3 stone = vec3(0.74, 0.71, 0.66) * tone + 0.06 * noise(wp.xz * 6.0);
	vec3 col = mix(vec3(0.28, 0.27, 0.25), stone, smoothstep(0.03, 0.09, edge));
	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = 0.85;
}
""")


func _paths() -> void:
	var m := _stone_mat()
	# الدائري
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 72
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p := [Vector3(cos(a0) * RING_IN, 0, sin(a0) * RING_IN), Vector3(cos(a0) * RING_OUT, 0, sin(a0) * RING_OUT),
			Vector3(cos(a1) * RING_OUT, 0, sin(a1) * RING_OUT), Vector3(cos(a1) * RING_IN, 0, sin(a1) * RING_IN)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.add_vertex(p[k])
	var ring := MeshInstance3D.new()
	ring.mesh = st.commit()
	ring.material_override = m
	ring.position.y = 0.02
	add_child(ring)
	# ممرات للأبواب
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		var len := HALF - RING_OUT + 2
		pm.size = Vector2(3.2, len) if d.x == 0 else Vector2(len, 3.2)
		mi.mesh = pm
		mi.material_override = m
		var c: Vector2 = d * (RING_OUT + len / 2 - 1)
		mi.position = Vector3(c.x, 0.021, c.y)
		add_child(mi)
	# ساحات رمل (مثل ساحة الألعاب)
	var sand := mat(Color("#d9c08a"), 1.0)
	for c in [Vector2(-24, -24), Vector2(25, -22), Vector2(-23, 25)]:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 6.5
		cm.bottom_radius = 6.5
		cm.height = 0.04
		cm.radial_segments = 32
		mi.mesh = cm
		mi.material_override = sand
		mi.position = Vector3(c.x, 0.0, c.y)
		add_child(mi)


# ── البحيرة + الجسر ──
func _pond() -> void:
	var water := _shader("""
shader_type spatial;
render_mode specular_schlick_ggx;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float w = sin(wp.x * 1.3 + TIME * 1.4) * 0.5 + sin(wp.z * 1.7 - TIME * 1.1) * 0.5;
	float r = length(wp.xz) / 9.0;
	vec3 deep = vec3(0.05, 0.25, 0.45);
	vec3 shallow = vec3(0.2, 0.6, 0.75);
	ALBEDO = pow(mix(deep, shallow, smoothstep(0.55, 1.0, r)) + w * 0.03, vec3(2.2));
	NORMAL = normalize(NORMAL + vec3(cos(wp.x * 1.3 + TIME * 1.4), 0.0, cos(wp.z * 1.7 - TIME * 1.1)) * 0.08);
	ROUGHNESS = 0.08;
	METALLIC = 0.1;
}
""")
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = POND_R
	cm.bottom_radius = POND_R
	cm.height = 0.05
	cm.radial_segments = 48
	mi.mesh = cm
	mi.material_override = water
	mi.position.y = 0.01
	add_child(mi)
	# حجار الحافة
	var rocks := []
	for i in 60:
		var a := TAU * i / 60 + rng.randf() * 0.05
		var rr := POND_R + rng.randf_range(-0.2, 0.4)
		rocks.append([Vector3(cos(a) * rr, 0.1, sin(a) * rr), rng.randf_range(0.35, 0.6), Color("#8e928f").lerp(Color("#b9b3a5"), rng.randf())])
	_multi(_rock_mesh(), rocks)
	# الجسر (خشب) يمر من الشمال للجنوب
	var wood := mat(Color("#a8743f"), 0.8)
	for i in 14:
		var z := -POND_R - 0.6 + i * ((POND_R * 2 + 1.2) / 13.0)
		_box(Vector3(0, 0.25, z), Vector3(2.6, 0.12, 0.62), wood)
	for s in [-1, 1]:
		_box(Vector3(s * 1.35, 0.6, 0), Vector3(0.12, 0.12, POND_R * 2 + 1.4), mat(Color("#7a5230"), 0.8))
	# البحيرة عائق (إلا الجسر)
	for i in 24:
		var a := TAU * i / 24
		var c := Vector2(cos(a), sin(a)) * (POND_R - 1.6)
		if absf(c.x) > 2.2:
			obstacles.append({p = c, r = 2.6})
	obstacles.append({p = Vector2(-5.5, 0), r = 3.6})
	obstacles.append({p = Vector2(5.5, 0), r = 3.6})


# ── السور (حجر) + سياج شجيرات ──
func _walls() -> void:
	var stone := _stone_mat()
	for side in 4:
		var horiz := side < 2
		var s := -1.0 if side % 2 == 0 else 1.0
		# فتحة للباب بالنص
		for half in [-1, 1]:
			var len := HALF - 2.5
			var c := Vector2((half * (2.5 + len / 2)), s * HALF) if horiz else Vector2(s * HALF, half * (2.5 + len / 2))
			var size := Vector3(len, 2.2, 0.8) if horiz else Vector3(0.8, 2.2, len)
			var w := _box(Vector3(c.x, 1.1, c.y), size, null)
			w.material_override = stone
			boxes.append(Rect2(c.x - size.x / 2, c.y - size.z / 2, size.x, size.z))
	# الأبواب مسدودة بسياج حديد (الزومبي يطلعون من فوگها)
	var hedge := []
	for i in 160:
		var t := rng.randf_range(-HALF + 2, HALF - 2)
		var side := i % 4
		var p := Vector2(t, -HALF + 1.4) if side == 0 else (Vector2(t, HALF - 1.4) if side == 1 else (Vector2(-HALF + 1.4, t) if side == 2 else Vector2(HALF - 1.4, t)))
		if absf(t) < 3:
			continue
		hedge.append([Vector3(p.x, 0.45, p.y), rng.randf_range(0.7, 1.0), Color("#2f6a2c").lerp(Color("#4a9436"), rng.randf())])
	_multi(_blob_mesh(), hedge)


# ── مصاطب، طاولات، أعمدة إنارة، حجار، ورد ──
func _props() -> void:
	var wood := mat(Color("#b07b45"), 0.8)
	var dark := mat(Color("#3b3b3f"), 0.6)
	# مصاطب حول الممر الدائري (وجهها للبحيرة)
	for i in 8:
		var a := TAU * i / 8 + PI / 8
		var p := Vector2(cos(a), sin(a)) * (RING_OUT + 1.3)
		var b := Node3D.new()
		b.position = Vector3(p.x, 0, p.y)
		b.rotation.y = -a + PI / 2
		add_child(b)
		_box(Vector3(0, 0.45, 0), Vector3(1.8, 0.08, 0.5), wood, b)
		_box(Vector3(0, 0.75, 0.22), Vector3(1.8, 0.4, 0.06), wood, b)
		for s in [-0.75, 0.75]:
			_box(Vector3(s, 0.22, 0), Vector3(0.08, 0.45, 0.5), dark, b)
		obstacles.append({p = p, r = 0.8})
	# طاولات بالساحات الرملية
	for c in [Vector2(-24, -24), Vector2(-20, -27), Vector2(-23, 25)]:
		var t := Node3D.new()
		t.position = Vector3(c.x, 0, c.y)
		t.rotation.y = rng.randf() * PI
		add_child(t)
		_box(Vector3(0, 0.75, 0), Vector3(1.9, 0.08, 0.9), wood, t)
		for s in [-0.6, 0.6]:
			_box(Vector3(0, 0.42, s), Vector3(1.9, 0.06, 0.32), wood, t)
			_box(Vector3(s * 1.2, 0.37, 0), Vector3(0.08, 0.75, 0.8), wood, t)
		obstacles.append({p = c, r = 1.2})
	# ألعاب أطفال (زحليكة + مرجيحة)
	var slide := Node3D.new()
	slide.position = Vector3(25, 0, -22)
	add_child(slide)
	_box(Vector3(0, 1.0, 0), Vector3(1.2, 0.1, 1.2), mat(Color("#4aa3d8"), 0.5), slide)
	_box(Vector3(0, 2.0, 0), Vector3(1.4, 0.5, 1.4), mat(Color("#e8e2d0"), 0.7), slide)
	for s in [Vector2(-0.6, -0.6), Vector2(0.6, -0.6), Vector2(-0.6, 0.6), Vector2(0.6, 0.6)]:
		_box(Vector3(s.x, 0.9, s.y), Vector3(0.12, 1.8, 0.12), wood, slide)
	var sl := _box(Vector3(0, 0.55, 1.9), Vector3(0.9, 0.08, 2.4), mat(Color("#2f6fb3"), 0.4), slide)
	sl.rotation.x = 0.45
	obstacles.append({p = Vector2(25, -22), r = 1.4})
	# أعمدة إنارة
	for i in 4:
		var a := TAU * i / 4 + PI / 4
		var p := Vector2(cos(a), sin(a)) * (RING_IN - 0.6)
		_cyl(Vector3(p.x, 1.6, p.y), 0.07, 3.2, dark)
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		lamp.mesh = sm
		lamp.material_override = mat(Color("#fff2c4"), 0.3, 1.5)
		lamp.position = Vector3(p.x, 3.3, p.y)
		add_child(lamp)
		obstacles.append({p = p, r = 0.25})
	# حجار وورد وشجيرات متفرقة
	var rocks := []
	var bushes := []
	var flowers := []
	for i in 70:
		var p := _free_spot(2.0)
		if i < 18:
			rocks.append([Vector3(p.x, 0.15, p.y), rng.randf_range(0.4, 0.9), Color("#8d918e").lerp(Color("#b5ae9e"), rng.randf())])
			obstacles.append({p = p, r = 0.5})
		elif i < 45:
			bushes.append([Vector3(p.x, 0.4, p.y), rng.randf_range(0.7, 1.2), Color("#2d6a2b").lerp(Color("#5aa83f"), rng.randf())])
			obstacles.append({p = p, r = 0.6})
		else:
			for k in 6:
				var q := p + Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2))
				flowers.append([Vector3(q.x, 0.18, q.y), rng.randf_range(0.12, 0.18), [Color("#ff6b8a"), Color("#ffd23f"), Color("#ffffff"), Color("#c084fc")][rng.randi() % 4]])
	_multi(_rock_mesh(), rocks)
	_multi(_blob_mesh(), bushes)
	_multi(_blob_mesh(), flowers)


# ── الأشجار: جذع + 3 كتل أوراق ──
func _trees() -> void:
	var trunks := []
	var leaves := []
	var spots := []
	# صف أشجار جنب السور + أشجار متفرقة
	for i in 26:
		var t := -HALF + 5 + i * ((HALF * 2 - 10) / 25.0)
		spots.append(Vector2(t, -HALF + 3.2))
		spots.append(Vector2(t, HALF - 3.2))
	for i in 18:
		spots.append(_free_spot(3.0))
	for p in spots:
		if absf(p.x) < 4 or absf(p.y) < 4:
			continue
		var s := rng.randf_range(0.85, 1.25)
		trunks.append([Vector3(p.x, 1.2 * s, p.y), s, Color("#6b4428")])
		var base := Color("#2f6a2c").lerp(Color("#5d9e3a"), rng.randf())
		for k in 3:
			var o := Vector3(rng.randf_range(-0.6, 0.6), 2.9 * s + k * 0.55 * s, rng.randf_range(-0.6, 0.6))
			leaves.append([Vector3(p.x, 0, p.y) + o, s * (1.5 - k * 0.25), base.lightened(k * 0.08)])
		obstacles.append({p = p, r = 0.45 * s})
	var tm := CylinderMesh.new()
	tm.top_radius = 0.16
	tm.bottom_radius = 0.26
	tm.height = 2.4
	tm.radial_segments = 8
	_multi(tm, trunks)
	_multi(_blob_mesh(1.2), leaves)


# مكان فاضي (مو على البحيرة ولا الممر ولا قريب من شي)
func _free_spot(margin: float) -> Vector2:
	for i in 60:
		var p := Vector2(rng.randf_range(-HALF + 4, HALF - 4), rng.randf_range(-HALF + 4, HALF - 4))
		var d := p.length()
		if d < RING_OUT + 2.5:
			continue
		if absf(p.x) < 2.6 or absf(p.y) < 2.6:
			continue
		var ok := true
		for o in obstacles:
			if p.distance_to(o.p) < o.r + margin:
				ok = false
				break
		if ok:
			return p
	return Vector2(HALF - 6, HALF - 6)


# ── أدوات بناء ──
func _box(pos: Vector3, size: Vector3, m: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	if m != null:
		mi.material_override = m
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	return mi


func _cyl(pos: Vector3, r: float, h: float, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 8
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	add_child(mi)


# كتلة مدورة شوية مضلعة (للأوراق والشجيرات والورد)
func _blob_mesh(r := 0.6) -> Mesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 1.7
	sm.radial_segments = 9
	sm.rings = 5
	return sm


func _rock_mesh() -> Mesh:
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 0.6
	sm.radial_segments = 7
	sm.rings = 4
	return sm


# MultiMesh: list = [[الموقع، الحجم، اللون]]
func _multi(mesh: Mesh, list: Array) -> void:
	if list.is_empty():
		return
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	mesh.surface_set_material(0, m)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		var e: Array = list[i]
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * float(e[1]))
		mm.set_instance_transform(i, Transform3D(b, e[0]))
		mm.set_instance_color(i, (e[2] as Color).srgb_to_linear()) # ألوان النسخ لازم تتحول لخطية
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	add_child(mi)


# كل القطع الثابتة (مصاطب، طاولات، جسر، أعمدة، سور...) تندمج برسمة وحدة لكل مادة:
# بدال ~110 رسمة (وضعفها للظلال) تصير ~10
func _merge_static() -> void:
	var groups := {} # المادة ← [MeshInstance3D]
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if not (mi.material_override is StandardMaterial3D) or mi.mesh.get_surface_count() != 1:
			continue
		var key: Material = mi.material_override
		if not groups.has(key):
			groups[key] = []
		groups[key].append(mi)
	for m: Material in groups:
		var list: Array = groups[m]
		if list.size() < 2:
			continue
		var st := SurfaceTool.new()
		for mi: MeshInstance3D in list:
			st.append_from(mi.mesh, 0, global_transform.affine_inverse() * mi.global_transform)
		var merged := MeshInstance3D.new()
		merged.mesh = st.commit()
		merged.material_override = m
		add_child(merged)
		for mi: MeshInstance3D in list:
			mi.free()
	# مجموعات فاضية (المصاطب والطاولات كانت Node3D فيها قطع)
	for c in get_children():
		if c.get_class() == "Node3D" and c.get_child_count() == 0:
			c.free()


# ── التصادم: نطلّع الدايرة (موقع + نص قطر) من العوائق والسور ──
func resolve(p: Vector2, r: float) -> Vector2:
	for o in obstacles:
		var d: Vector2 = p - o.p
		var min_d: float = o.r + r
		var l := d.length()
		if l < min_d and l > 0.0001:
			p = o.p + d / l * min_d
	for b in boxes:
		var q := Vector2(clampf(p.x, b.position.x, b.end.x), clampf(p.y, b.position.y, b.end.y))
		var d := p - q
		var l := d.length()
		if l < r:
			p = q + (d / l * r if l > 0.0001 else Vector2(0, r))
	var lim := HALF - 0.6 - r
	return Vector2(clampf(p.x, -lim, lim), clampf(p.y, -lim, lim))


func blocked(p: Vector2, r := 0.0) -> bool:
	for o in obstacles:
		if p.distance_to(o.p) < o.r + r:
			return true
	return absf(p.x) > HALF - 1 or absf(p.y) > HALF - 1
