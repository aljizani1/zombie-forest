# ════════ قياس الأداء (للتطوير) ════════
# F3 أو لمسة بثلاث أصابع = يطلع/يختفي: FPS، وقت الإطار، draw calls، عدد الأشياء والنودات.
# أي إطار أطول من 25ms ينطبع باللوگ ويا الأحداث اللي صارت بيه (زومبي طلع، مات، أول طلقة، انفجار...).
# اللعبة تسجّل الأحداث بـ Perf.ev("...").
extends CanvasLayer

const SPIKE_MS := 25.0

var events: PackedStringArray = [] # أحداث الإطار الحالي
var _prev := "-" # أحداث الإطار اللي قبله (الكارت يتأخر إطار أحياناً)
var spikes: Array = [] # [ms، الأحداث] (للبنچ)
var log_spikes := true
var _label: Label
var _acc := 0.0
var _frames := 0
var _ms_max := 0.0
var _touches := {}

# ════════ الجودة ════════
# auto (الافتراضي) يبدي بـ "عالية" ويقيس أول 5 ثواني من اللعب: إذا المعدل أقل من 50 FPS ينزل درجة (ويحفظها).
# منخفضة: دقة 70%، بدون ظلال، بدون ضباب، جزيئات أقل. متوسطة: دقة 85%، ظلال بخريطة صغيرة. عالية: كلشي.
signal quality_changed
const Q_NAMES := ["منخفضة", "متوسطة", "عالية"]
var quality := "auto" # auto / low / medium / high
var auto_level := 2 # الدرجة اللي وصلها التلقائي
var park: Park
var _q_acc := 0.0
var _q_frames := 0


func level() -> int:
	match quality:
		"low":
			return 0
		"medium":
			return 1
		"high":
			return 2
	return auto_level


func quality_name() -> String:
	return ("تلقائي (%s)" % Q_NAMES[auto_level]) if quality == "auto" else Q_NAMES[level()]


func cycle_quality() -> void:
	quality = {"auto": "low", "low": "medium", "medium": "high", "high": "auto"}[quality]
	apply_quality()


func max_parts() -> int:
	return 150 if level() == 0 else 400


func apply_quality() -> void:
	if park != null:
		park.apply_quality(level())


# اللعبة تناديها كل إطار بأول 5 ثواني من الجولة
func auto_sample(dt: float) -> void:
	if quality != "auto":
		return
	_q_acc += dt
	_q_frames += 1
	if _q_acc < 5.0:
		return
	var fps := _q_frames / _q_acc
	_q_acc = 0
	_q_frames = 0
	if fps < 50 and auto_level > 0:
		auto_level -= 1
		print("[quality] %.0f fps -> %s" % [fps, Q_NAMES[auto_level]])
		apply_quality()
		quality_changed.emit()


func auto_reset() -> void:
	_q_acc = 0
	_q_frames = 0


func _ready() -> void:
	layer = 100
	# يشتغل قبل كل شي بالإطار: delta هنا = طول الإطار اللي فات، والأحداث = اللي صارت بيه
	process_priority = -1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.position = Vector2(10, 150)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color("#9cff6a"))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	add_child(_label)


func ev(what: String) -> void:
	events.append(what)


func _process(delta: float) -> void:
	var ms := delta * 1000.0
	if ms > SPIKE_MS and Engine.get_process_frames() > 30:
		var what := (", ".join(events) if not events.is_empty() else "-") + "  (before: " + _prev + ")"
		spikes.append([ms, what])
		if log_spikes:
			print("[spike] %.1f ms  dc=%d  nodes=%d  | %s" % [ms, draw_calls(), nodes(), what])
	_prev = ", ".join(events) if not events.is_empty() else "-"
	events.clear()
	_acc += delta
	_frames += 1
	_ms_max = maxf(_ms_max, ms)
	if _acc >= 0.5 and _label.visible:
		_label.text = "FPS %d   (%.1f ms avg, %.1f max)\ndraw calls %d   objects %d   prims %dk\nnodes %d   %s" % [
			Engine.get_frames_per_second(), _acc / _frames * 1000.0, _ms_max, draw_calls(),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
			nodes(), RenderingServer.get_current_rendering_method()]
	if _acc >= 0.5:
		_acc = 0
		_frames = 0
		_ms_max = 0


static func draw_calls() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))


static func nodes() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_F3:
		_label.visible = not _label.visible
	elif e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = true
			if _touches.size() == 3:
				_label.visible = not _label.visible
		else:
			_touches.erase(e.index)
