# ════════ الأصوات ════════
# كل الأصوات تنصنع بالكود (بدون ملفات): طلقات، ضربات، هيدشوت، زومبي، انفجار، تعبئة...
# لكل صوت كم نسخة مختلفة، وكل مرة يشتغل بنبرة وقوة عشوائية شوية، حتى ما يصير مكرر وممل.
extends Node

const RATE := 22050

var _bank := {} # اسم الصوت ← [نسخ]
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last := {} # آخر وقت اشتغل بيه كل صوت (حتى ما تتكدس نفس الأصوات بنفس اللحظة)
var enabled := true

# الصوت ← [عدد النسخ، القوة بالديسيبل، أقل وقت بين مرتين]
const SOUNDS := {
	"pistol": [3, -6.0, 0.04], "akm": [3, -8.0, 0.03], "pkm": [3, -8.0, 0.03],
	"hit": [3, -10.0, 0.03], "headshot": [2, -6.0, 0.05], "die": [4, -7.0, 0.08],
	"hurt": [3, -5.0, 0.15], "jump": [2, -14.0, 0.1], "throw": [2, -10.0, 0.1],
	"boom": [2, -2.0, 0.08], "reload": [2, -9.0, 0.2], "roar": [2, -3.0, 0.5],
	"plane": [1, -10.0, 1.0], "win": [1, -6.0, 1.0], "lose": [1, -6.0, 1.0],
}


func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


# نصنع الأصوات شوية شوية (صوت واحد كل إطار) حتى ما يصير تقطيع وقت اللعب
func _process(_dt: float) -> void:
	for name in SOUNDS:
		if not _bank.has(name):
			_fill(name)
			return
	set_process(false)


func _fill(name: String) -> void:
	_bank[name] = []
	for v in SOUNDS[name][0]:
		_bank[name].append(_make(name, v))


func play(name: String) -> void:
	if not enabled or not SOUNDS.has(name):
		return
	var cfg: Array = SOUNDS[name]
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(name, -1.0)) < cfg[2]:
		return
	_last[name] = now
	if not _bank.has(name):
		_fill(name)
	var list: Array = _bank[name]
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = list[randi() % list.size()]
	p.pitch_scale = randf_range(0.9, 1.1)
	p.volume_db = cfg[1] + randf_range(-1.5, 1.0)
	p.play()


# ── صناعة الأصوات ──
func _make(name: String, variant: int) -> AudioStreamWAV:
	var r := RandomNumberGenerator.new()
	r.seed = hash(name) + variant * 7919
	var j := func(a: float, b: float) -> float: return r.randf_range(a, b) # اختلاف بسيط بين النسخ
	var s: PackedFloat32Array
	match name:
		"pistol":
			s = _gun(r, 0.2, j.call(0.55, 0.7), j.call(110, 140), 26)
		"akm":
			s = _gun(r, 0.17, j.call(0.7, 0.85), j.call(85, 105), 30)
		"pkm":
			s = _gun(r, 0.22, j.call(0.6, 0.75), j.call(65, 80), 22)
		"hit":
			s = _noise(r, 0.09, j.call(0.12, 0.22), 40)
			_mix(s, _tone(j.call(90, 130), 0.09, 35, 0.5), 0)
		"headshot":
			s = _noise(r, 0.08, 0.3, 45)
			_mix(s, _tone(j.call(1500, 1900), 0.18, 18, 0.35), 0)
			_mix(s, _tone(j.call(2400, 2800), 0.12, 25, 0.2), 0)
		"die":
			s = _groan(r, j.call(0.45, 0.7), j.call(130, 170), j.call(60, 80))
		"hurt":
			s = _groan(r, 0.22, j.call(200, 240), j.call(130, 160), 0.15)
		"jump":
			s = _sweep_noise(r, 0.16, 0.08, 0.35)
		"throw":
			s = _sweep_noise(r, 0.22, 0.15, 0.5)
		"boom":
			s = _noise(r, 1.3, j.call(0.05, 0.08), 3.5)
			_mix(s, _tone(j.call(45, 55), 1.0, 4, 1.0), 0)
			_mix(s, _noise(r, 0.12, 0.6, 30), 0)
		"reload":
			s = PackedFloat32Array()
			s.resize(int(RATE * 0.45))
			_mix(s, _noise(r, 0.03, 0.9, 120), 0)
			_mix(s, _noise(r, 0.04, 0.7, 90), int(RATE * j.call(0.22, 0.3)))
			_mix(s, _tone(j.call(900, 1200), 0.03, 80, 0.3), int(RATE * 0.36))
		"roar":
			s = _groan(r, j.call(1.0, 1.3), j.call(95, 110), j.call(45, 55), 0.5)
		"plane":
			s = _tone(70, 2.5, 0.6, 0.5)
			_mix(s, _noise(r, 2.5, 0.05, 0.6), 0)
		"win":
			s = _melody([523.0, 659.0, 784.0, 1047.0], 0.12)
		"lose":
			s = _melody([392.0, 330.0, 262.0, 196.0], 0.16)
	return _wav(s)


# طلقة: انفجار ضوضاء حاد + ضربة واطية
func _gun(r: RandomNumberGenerator, dur: float, bright: float, thump: float, decay: float) -> PackedFloat32Array:
	var s := _noise(r, dur, bright, decay)
	_mix(s, _tone(thump, dur, decay * 0.7, 0.9), 0)
	_mix(s, _noise(r, 0.012, 1.0, 200), 0) # طقة البداية
	return s


# ضوضاء بفلتر (bright: 0 مكتومة .. 1 حادة) وتخفت بسرعة decay
func _noise(r: RandomNumberGenerator, dur: float, bright: float, decay: float) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	for i in n:
		y += (r.randf_range(-1, 1) - y) * bright
		s[i] = y * exp(-decay * i / RATE)
	return s


func _tone(freq: float, dur: float, decay: float, amp: float) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * freq * (1.0 - 0.3 * t / dur) / RATE # النبرة تنزل شوية
		s[i] = sin(ph) * amp * exp(-decay * t)
	return s


# صوت زومبي/أنين: موجة خشنة تنزل نبرتها مع رجفة
func _groan(r: RandomNumberGenerator, dur: float, f0: float, f1: float, rough := 0.35) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	var y := 0.0
	var vib := r.randf_range(5, 9)
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, t) * (1 + 0.06 * sin(TAU * vib * i / RATE))
		ph += f / RATE
		var saw := fmod(ph, 1.0) * 2 - 1
		y += (saw + r.randf_range(-rough, rough) - y) * 0.25
		var env := minf(1.0, t * 12) * (1 - t) * (1 - t)
		s[i] = y * env * 0.8
	return s


# هوا (قفز/رمي): ضوضاء تصعد وتنزل
func _sweep_noise(r: RandomNumberGenerator, dur: float, b0: float, b1: float) -> PackedFloat32Array:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / n
		y += (r.randf_range(-1, 1) - y) * lerpf(b0, b1, t)
		s[i] = y * sin(PI * t) * 0.6
	return s


func _melody(notes: Array, step: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(RATE * (step * notes.size() + 0.3)))
	for k in notes.size():
		var tone := _tone(notes[k], step + 0.25, 6, 0.4)
		_mix(s, tone, int(RATE * step * k))
	return s


func _mix(dst: PackedFloat32Array, src: PackedFloat32Array, at: int) -> void:
	for i in mini(src.size(), dst.size() - at):
		dst[at + i] += src[i]


func _wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var peak := 0.001
	for v in s:
		peak = maxf(peak, absf(v))
	var g := 0.9 / peak
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i] * g, -1, 1) * 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w
