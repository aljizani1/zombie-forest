# ════════ مواد المؤثرات (شيدرات بدون صور) ════════
# كلها تنرسم بـ MultiMesh (رسمة وحدة لكل نوع): بقع دم، جزيئات ودخان، انفجارات، خطوط الطلق، وفلاش الفوهة.
extends RefCounted

const NOISE := """
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
"""

# مربع يواجه الكاميرا ويحافظ على الحجم (يشتغل ويا MultiMesh)
const BILLBOARD := """
void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(INV_VIEW_MATRIX[0].xyz * s, 0.0), vec4(INV_VIEW_MATRIX[1].xyz * s, 0.0), vec4(INV_VIEW_MATRIX[2].xyz * s, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	prog = COLOR.a;
}
"""

# بقعة دم بشكل عشوائي (حواف متعرجة + قطرات حواليها). البذرة من INSTANCE_CUSTOM.x
const SPLAT := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;
varying float seed;
""" + NOISE + """
void vertex() { seed = INSTANCE_CUSTOM.x * 50.0; }
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	vec2 dir = vec2(cos(a), sin(a));
	float edge = 0.42 + 0.28 * noise(dir * 1.6 + seed) + 0.14 * noise(dir * 4.0 + seed * 1.7);
	float body = 1.0 - smoothstep(edge - 0.05, edge, r);
	vec2 g = p * 5.0 + seed;
	vec2 cell = floor(g);
	vec2 off = vec2(hash(cell + 1.3), hash(cell + 2.1)) - 0.5;
	float drop = step(0.8, hash(cell)) * step(edge, r) * (1.0 - smoothstep(0.1, 0.16, length(fract(g) - 0.5 - off * 0.5)));
	float m = max(body, drop) * (1.0 - smoothstep(0.85, 1.0, r));
	float shade = 0.7 + 0.3 * noise(p * 5.0 + seed);
	ALBEDO = COLOR.rgb * shade;
	ALPHA = m * COLOR.a;
}
"""

# جزيء ناعم (قطرة / دخان)
const PUFF := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;
varying float prog;
""" + BILLBOARD + """
void fragment() {
	float r = length(UV * 2.0 - 1.0);
	ALBEDO = COLOR.rgb;
	ALPHA = prog * (1.0 - smoothstep(0.45, 1.0, r));
}
"""

# انفجار: كرة نار تكبر وتبرد وتصير دخان (اللون alpha = تقدّم الانفجار 0..1)
const BOOM := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;
varying float prog;
""" + NOISE + BILLBOARD + """
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float n = noise(p * 3.0 + prog * 2.5) * 0.6 + noise(p * 7.0 - prog * 4.0) * 0.4;
	float radius = 0.3 + 0.6 * sqrt(prog);
	float fire = 1.0 - smoothstep(radius - 0.25, radius, r + (n - 0.5) * 0.5);
	float heat = 1.0 - prog;
	vec3 col = mix(vec3(1.0, 0.45, 0.1), vec3(1.0, 0.92, 0.6), clamp(heat * 1.3 - r, 0.0, 1.0));
	col = mix(col, vec3(0.16, 0.14, 0.13), smoothstep(0.3, 0.8, prog));
	ALBEDO = col * (1.0 + 1.5 * heat * heat);
	ALPHA = fire * (1.0 - smoothstep(0.55, 1.0, prog)) * (0.75 + 0.25 * n);
}
"""

# خط طلقة مضيء (رأسه قوي وذيله يتلاشى)
const TRACER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
varying float k;
void vertex() { k = 0.5 - VERTEX.z; }
void fragment() {
	ALBEDO = COLOR.rgb * 1.6;
	ALPHA = k * k * COLOR.a;
}
"""

# فلاش الفوهة: نجمة (3 أشكال) تدور عشوائياً
const FLASH := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform float variant = 0.0;
uniform float spin = 0.0;
varying float prog;
""" + BILLBOARD + """
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p = mat2(vec2(cos(spin), sin(spin)), vec2(-sin(spin), cos(spin))) * p;
	float r = length(p);
	float a = atan(p.y, p.x);
	float rays = pow(abs(cos(a * (2.0 + variant))), 6.0 + variant * 3.0);
	float star = 1.0 - smoothstep(0.0, 1.0, r / (0.3 + 0.7 * rays));
	float core = 1.0 - smoothstep(0.0, 0.42, r);
	ALBEDO = mix(vec3(1.0, 0.5, 0.12), vec3(1.0, 0.95, 0.75), core) * 1.5;
	ALPHA = clamp(star + core, 0.0, 1.0);
}
"""

static var _cache := {}


static func mat(code: String) -> ShaderMaterial:
	if _cache.has(code):
		return _cache[code]
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	_cache[code] = m
	return m
