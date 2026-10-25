# ════════ الشاشة الرئيسية ════════
# الدخول بالاسم (ورمز اختياري)، القائمة، المتجر، المتصدرين، الملف الشخصي، الإعدادات، لوحة الأدمن،
# LAN (سيرفرات + لوبي)، اللعب، الكاميرا، الكيبورد والماوس، ونهاية الجولة.
# الحفظ المحلي: user://save.cfg (الفلوس، الأسلحة، التوكن، الصوت). الإحصائيات بـ Supabase.
extends Node2D

const SAVE_PATH := "user://save.cfg"
const BRICK_PRICE := 40 # سعر 10 طابوقات
# رقم النسخة (GitHub يكتبه بكل بناء)
var VERSION := FileAccess.get_file_as_string("res://version.txt").strip_edges()

# الإنجازات: المعرّف ← [الاسم، الوصف]
const ACHIEVEMENTS := {
	"first_blood": ["أول دم", "أول زومبي تقتله"],
	"k100": ["صياد", "تقتل 100 زومبي"],
	"k1000": ["جزار الزومبي", "تقتل 1000 زومبي"],
	"k5000": ["أسطورة", "تقتل 5000 زومبي"],
	"hs100": ["قناص", "100 هيدشوت"],
	"flawless": ["بدون خدش", "تفوز بجولة بدون ما تنضرب"],
	"survivor": ["على الحافة", "تفوز وصحتك أقل من 15%"],
	"fast": ["صاروخ", "تخلص جولة بنص الوقت المتوقع"],
	"lvl5": ["محترف", "توصل صعوبة 5"],
	"lvl10": ["وحش", "توصل صعوبة 10"],
	"lvl20": ["ما ينوقف", "توصل صعوبة 20"],
	"lan": ["فريق", "تلعب جولة LAN ويا أصدقائك"],
	"r50": ["مدمن", "تلعب 50 جولة"],
}

var park: Park # الحديقة الثلاثية الأبعاد (تنبني مرة وحدة)
var game: Game3D
var inp := Game3D.Inp.new()
var font: Font

var _orbit := 0.0 # دوران الكاميرا ورا القوائم
var hud: Control
var touch: Control
var ui: Control # الشاشات (قوائم، نهاية الجولة، زر الخروج)

# الحفظ المحلي
var coins := 0
var owned: Array = ["pistol"]
var weapon := "pistol"
var bricks := 10 # طابوق للبناء
var level := 1.0 # صعوبتي
var token := ""
var player_name := ""
var sound_on := true
var coins_moved := false # فلوس الجهاز انتقلت للحساب

# الحساب
var online := false # داخل بحساب (لو لا = بدون نت)
var has_pin := false
var is_admin := false
var stats := {} # آخر ملف شخصي وصل من السيرفر

# LAN
var supa: Supa
var session: Session
var _screen := "menu"
var _send_st := 0.0
var _send_snap := 0.0
var _rooms_box: VBoxContainer
var _lan_status: Label

var _use_touch := false
var _mouse_aim := false
var _ended := false
var _touch_t := 0.0
var _shot := ""
var _shot_t := 0.0
var _bench := {} # --bench: قياس أداء ثابت (20 زومبي)


func _ready() -> void:
	# خط Cairo العربي داخل اللعبة (المتصفح ما يعطي خطوط الجهاز)، وهو الخط الافتراضي بالمشروع كله
	font = load("res://fonts/cairo_bold.tres")
	_load()
	Sfx.enabled = sound_on
	supa = Supa.new()
	add_child(supa)

	park = Park.new()
	add_child(park)
	Perf.park = park
	Perf.apply_quality()
	Perf.quality_changed.connect(_save)

	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	hud = preload("res://scripts/hud.gd").new()
	hud.font = font
	layer.add_child(hud)
	touch = preload("res://scripts/controls.gd").new()
	touch.inp = inp
	layer.add_child(touch)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui)

	_use_touch = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.get_cmdline_user_args().has("--touch")

	# للفحص: يلعب لوحده شوية ويحفظ صورة الشاشة ويطلع (بدون حساب)
	var args := OS.get_cmdline_user_args()
	if args.has("--bench"):
		_bench = {t = 0.0, frames = [], shot = "user://bench.png"}
		var i := args.find("--bench")
		if args.size() > i + 1 and not args[i + 1].begins_with("--"):
			_bench.shot = args[i + 1]
		level = float(args[args.find("--level") + 1]) if args.has("--level") else 15.0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Perf.quality = args[args.find("--quality") + 1] if args.has("--quality") else "high"
		Perf.apply_quality()
		_start()
		return
	if args.has("--shot"):
		_shot = args[args.find("--shot") + 1] if args.size() > args.find("--shot") + 1 else "user://shot.png"
		if args.has("--level"):
			level = float(args[args.find("--level") + 1])
		if args.has("--lan-host") or args.has("--lan-join"):
			_auto_lan(args.has("--lan-host"))
			return
		if args.has("--menu") or args.has("--boot") or args.has("--board"):
			if args.has("--boot"):
				_boot()
			elif args.has("--board"):
				_show_leaderboard()
			else:
				_show_menu()
			await get_tree().create_timer(3.0).timeout
			print("menu fps=", Engine.get_frames_per_second())
			get_viewport().get_texture().get_image().save_png(_shot)
			get_tree().quit()
			return
		_start()
		return
	_boot()


# ── الحفظ المحلي ──
func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	coins = cf.get_value("save", "coins", 0)
	owned = cf.get_value("save", "owned", ["pistol"])
	weapon = cf.get_value("save", "weapon", "pistol")
	bricks = cf.get_value("save", "bricks", 10)
	level = cf.get_value("save", "level", 1.0)
	token = cf.get_value("save", "token", "")
	player_name = cf.get_value("save", "name", "")
	sound_on = cf.get_value("save", "sound", true)
	coins_moved = cf.get_value("save", "coins_moved", false)
	Perf.quality = cf.get_value("save", "quality", "auto")
	Perf.auto_level = cf.get_value("save", "auto_level", 2)


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("save", "coins", coins)
	cf.set_value("save", "owned", owned)
	cf.set_value("save", "weapon", weapon)
	cf.set_value("save", "bricks", bricks)
	cf.set_value("save", "level", level)
	cf.set_value("save", "token", token)
	cf.set_value("save", "name", player_name)
	cf.set_value("save", "sound", sound_on)
	cf.set_value("save", "coins_moved", coins_moved)
	cf.set_value("save", "quality", Perf.quality)
	cf.set_value("save", "auto_level", Perf.auto_level)
	cf.save(SAVE_PATH)


# ════════ واجهة (أدوات) ════════
func _clear_ui() -> void:
	for c in ui.get_children():
		c.queue_free()


func _style(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(14)
	sb.border_color = Color(1, 1, 1, 0.8)
	sb.set_border_width_all(3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	return sb


func _button(text: String, cb: Callable, parent: Control, primary := false, col := Color(0, 0, 0, 0)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 60)
	b.add_theme_font_size_override("font_size", 24)
	var bg := col if col.a > 0 else (Color("#c62828") if primary else Color(0.15, 0.15, 0.17, 0.9))
	for st in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(st, _style(bg))
	b.add_theme_stylebox_override("pressed", _style(bg.darkened(0.25)))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


# wrap = عرض النص اللي ينكسر لسطور (0 = سطر واحد)
func _label(text: String, sz: int, parent: Control, col := Color.WHITE, wrap := 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if wrap > 0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = wrap
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 8)
	parent.add_child(l)
	return l


func _row(parent: Control, sep := 12) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_theme_constant_override("separation", sep)
	parent.add_child(r)
	return r


func _edit(text: String, parent: Control, width := 280.0, secret := false) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.secret = secret
	e.custom_minimum_size = Vector2(width, 54)
	e.add_theme_font_size_override("font_size", 24)
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	if secret:
		e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
		e.max_length = 8
	parent.add_child(e)
	return e


func _panel_box() -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	return box


# قائمة تنسحب لفوگ وتحت (للمتصدرين والأدمن)
func _scroll(parent: Control, height := 330.0, width := 760.0) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(width, height)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	sc.add_child(v)
	return v


func _stop_game() -> void:
	if game != null:
		game.queue_free()
	game = null
	hud.game = null
	hud.visible = false
	touch.visible = false
	_clear_ui()


# "قبل 5 دقايق" من تاريخ السيرفر
static func ago(iso: String) -> String:
	if iso.length() < 19:
		return "-"
	var t := Time.get_unix_time_from_datetime_string(iso.substr(0, 19))
	var d := int(Time.get_unix_time_from_system() - t)
	if d < 120:
		return "هسه"
	if d < 3600:
		return "قبل %d دقيقة" % (d / 60)
	if d < 86400:
		return "قبل %d ساعة" % (d / 3600)
	return "قبل %d يوم" % (d / 86400)


static func duration(sec: int) -> String:
	if sec < 3600:
		return "%d دقيقة" % (sec / 60)
	return "%d ساعة و %d دقيقة" % [sec / 3600, (sec % 3600) / 60]


# ════════ الدخول ════════
func _boot() -> void:
	if token == "":
		_show_login()
		return
	_show_wait("دا أدخل...")
	var r = await supa.call_fn("player_resume", {p_token = token})
	if r is Dictionary and r.get("ok", false):
		_signed_in(r)
	elif r == null:
		_show_login("ما گدرت أتصل بالسيرفر، تأكد من النت", player_name)
	else:
		token = ""
		_save()
		_show_login("سجّل دخولك مرة ثانية", player_name)


func _show_wait(text: String) -> void:
	_stop_game()
	var box := _panel_box()
	_label(text, 30, box)


func _show_login(msg := "", name := "", need_pin := false) -> void:
	_screen = "login"
	_stop_game()
	var box := _panel_box()
	_label("زومبي الغابة", 60, box, Color("#ffd23f"))
	_label("اكتب اسمك وادخل", 26, box)
	var name_edit := _edit(name if name != "" else player_name, box, 320)
	name_edit.max_length = 16
	name_edit.placeholder_text = "اسمك"
	var pin_edit: LineEdit = null
	if need_pin:
		_label("هذا الاسم محمي برمز، اكتب الرمز:", 22, box, Color("#ffd23f"))
		pin_edit = _edit("", box, 200, true)
	var status := _label(msg, 22, box, Color("#ff8a80"), 600)
	var go := func() -> void:
		var n := name_edit.text.strip_edges()
		if n.length() < 2:
			status.text = "الاسم لازم حرفين أو أكثر"
			return
		status.add_theme_color_override("font_color", Color.WHITE)
		status.text = "دا أدخل..."
		var r = await supa.call_fn("player_login", {p_name = n, p_pin = pin_edit.text if pin_edit != null else ""})
		if r == null:
			_show_login("ما گدرت أتصل بالسيرفر، تأكد من النت", n, need_pin)
		elif r.get("ok", false):
			_signed_in(r)
		else:
			match str(r.get("error", "")):
				"pin":
					_show_login("", n, true)
				"bad_pin":
					_show_login("الرمز غلط", n, true)
				"locked":
					_show_login("انقفل الحساب 10 دقايق بسبب محاولات غلط", n, true)
				_:
					_show_login("الاسم مو صالح", n, need_pin)
	name_edit.text_submitted.connect(func(_t): go.call())
	_button("دخول", go, box, true)
	_button("العب بدون حساب", func():
		online = false
		_show_menu(), box)


func _signed_in(r: Dictionary) -> void:
	online = true
	token = str(r.token)
	player_name = str(r.name)
	has_pin = bool(r.get("has_pin", false))
	is_admin = bool(r.get("admin", false))
	level = maxf(1.0, float(r.get("level", level)))
	var server := int(r.get("coins", 0))
	if coins > 0 and not coins_moved:
		var m = await supa.call_fn("player_add_coins", {p_token = token, p_amount = coins, p_from_device = true})
		server = int(m.coins) if m is Dictionary and m.get("ok", false) else server
	coins_moved = true
	coins = server
	_save()
	_show_menu()
	_refresh_stats()


func _refresh_stats() -> void:
	if not online:
		return
	var p = await supa.call_fn("player_profile", {p_name = player_name})
	if p is Dictionary:
		stats = p


# ════════ القائمة ════════
func _show_menu() -> void:
	_screen = "menu"
	_stop_game()
	var box := _panel_box()
	_label("زومبي الغابة", 56, box, Color("#ffd23f"))
	_label(("أهلاً %s" % player_name if online else "بدون حساب (الإحصائيات ما تنحفظ)") + "   -   الفلوس: %d   -   صعوبتك: %.1f" % [coins, level], 22, box, Color("#ffe9a8"))

	var r1 := _row(box)
	_button("ابدأ", _start, r1, true)
	_button("LAN (نفس الواي فاي)", func(): _show_notice("الـ LAN راح يرجع بالتحديث الجاي للنسخة الثلاثية الأبعاد"), r1, false, Color("#2f6fb3"))
	_button("المتجر", _show_shop, r1, false, Color("#b8860b"))
	var r2 := _row(box)
	_button("المتصدرين", _show_leaderboard, r2, false, Color("#7a5a1e"))
	if online:
		_button("ملفي", func(): _show_profile(player_name), r2, false, Color("#3d6b35"))
	_button("الإعدادات", _show_settings, r2)
	if is_admin:
		_button("لوحة الأدمن", _show_admin, r2, false, Color("#5b2a86"))
	_label("النسخة: " + VERSION, 18, box, Color(1, 1, 1, 0.55))



# ════════ المتجر (الأسلحة، الطابوق، التبرع) ════════
func _show_shop() -> void:
	_screen = "shop"
	_stop_game()
	var box := _panel_box()
	_label("المتجر", 48, box, Color("#ffd23f"))
	_label("فلوسك: %d" % coins, 26, box, Color("#ffe9a8"))
	_label("الأسلحة:", 24, box)
	var guns := _row(box)
	for w in Config.GUN_ORDER:
		var cfg: Dictionary = Config.WEAPONS[w]
		var text: String
		if not owned.has(w):
			text = "%s (%d)" % [cfg.name, cfg.price]
		elif weapon == w:
			text = "%s (مختار)" % cfg.name
		else:
			text = cfg.name
		var b := _button(text, func(): _shop(w), guns, weapon == w)
		b.custom_minimum_size = Vector2(210, 56)
		b.disabled = not owned.has(w) and coins < cfg.price
	if online:
		var g := _button("تبرع لصديق", _show_gift, box, false, Color("#1f7a5c"))
		g.custom_minimum_size = Vector2(420, 56)
	_button("رجوع", _show_menu, box)


func _shop(w: String) -> void:
	if not owned.has(w):
		var price: int = Config.WEAPONS[w].price
		if not await _spend(price):
			return
		owned.append(w)
	weapon = w
	_save()
	_show_shop()


# نصرف من الفلوس (بالحساب إذا داخل، لو لا من الجهاز)
func _spend(amount: int) -> bool:
	if coins < amount:
		return false
	if not online:
		coins -= amount
		return true
	var r = await supa.call_fn("player_spend", {p_token = token, p_amount = amount})
	if r is Dictionary and r.get("ok", false):
		coins = int(r.coins)
		return true
	return false


# ════════ الإعدادات (الرمز، الصوت، الخروج) ════════
func _show_settings(msg := "") -> void:
	_screen = "settings"
	_stop_game()
	var box := _panel_box()
	_label("الإعدادات", 44, box, Color("#ffd23f"))
	var snd := _button("الصوت: " + ("شغّال" if sound_on else "مطفي"), func():
		sound_on = not sound_on
		Sfx.enabled = sound_on
		_save()
		_show_settings(), box)
	snd.custom_minimum_size = Vector2(320, 56)
	var q := _button("الجودة: " + Perf.quality_name(), func():
		Perf.cycle_quality()
		_save()
		_show_settings(), box)
	q.custom_minimum_size = Vector2(320, 56)
	if online:
		_label("حسابك: %s   -   %s" % [player_name, "محمي برمز" if has_pin else "بدون رمز (أي واحد يكدر يدخل باسمك)"], 22, box, Color("#7bd64a") if has_pin else Color("#ff8a80"))
		var r := _row(box)
		_label("رمز جديد (4 إلى 8 أرقام):", 22, r)
		var pin := _edit("", r, 200, true)
		var status := _label(msg, 22, box, Color("#ffd23f"))
		var r2 := _row(box)
		_button("حفظ الرمز", func():
			if not pin.text.is_valid_int() or pin.text.length() < 4:
				status.text = "الرمز لازم 4 إلى 8 أرقام"
				return
			_set_pin(pin.text), r2, true)
		if has_pin:
			_button("شيل الرمز", func(): _set_pin(""), r2)
		_button("تسجيل خروج", func():
			token = ""
			online = false
			is_admin = false
			_save()
			_show_login(), box)
	else:
		_button("تسجيل دخول", func(): _show_login(), box, true)
	_button("رجوع", _show_menu, box)


func _set_pin(pin: String) -> void:
	var r = await supa.call_fn("player_set_pin", {p_token = token, p_pin = pin})
	if r is Dictionary and r.get("ok", false):
		token = str(r.token)
		has_pin = pin != ""
		_save()
		# الأدمن يحتاج رمز، فنعيد الدخول حتى نعرف
		var me = await supa.call_fn("player_resume", {p_token = token})
		if me is Dictionary and me.get("ok", false):
			is_admin = bool(me.get("admin", false))
		_show_settings("انحفظ الرمز. لا تنساه!" if pin != "" else "انشال الرمز")
	else:
		_show_settings("ما انحفظ، تأكد من النت")


# ════════ المتصدرين ════════
func _show_leaderboard() -> void:
	_screen = "leaderboard"
	_stop_game()
	var box := _panel_box()
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(880, 560)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	var board: Control = preload("res://scripts/leaderboard_view.gd").new()
	board.font = font
	board.me = player_name if online else ""
	board.custom_minimum_size = Vector2(864, 260)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.picked.connect(func(n: String): _show_profile(n))
	sc.add_child(board)
	_button("رجوع", _show_menu, box)
	var rows = await supa.call_fn("leaderboard", {p_limit = 50})
	if _screen != "leaderboard" or not is_instance_valid(board):
		return
	if not (rows is Array):
		board.status = "ما گدرت أجيب القائمة، تأكد من النت"
		board.queue_redraw()
		return
	# للفحص بس: بيانات تجريبية حتى نشوف الشكل
	if _shot != "" and (rows.is_empty() or OS.get_cmdline_user_args().has("--fake")):
		rows = []
		for i in 8:
			rows.append({rank = i + 1, name = ["Aljizani", "حسين", "علي", "مصطفى", "زهراء", "Ahmed", "سجاد", "مريم"][i], kills = [1920, 1480, 1430, 1180, 780, 760, 530, 470][i], best_level = 12.4 - i})
	board.set_rows(rows)


# ════════ الملف الشخصي ════════
func _show_profile(name: String) -> void:
	_screen = "profile"
	_stop_game()
	var box := _panel_box()
	_label(name, 44, box, Color("#ffd23f"))
	var info := _label("...", 22, box, Color.WHITE, 900)
	var ach := _scroll(box, 200, 700)
	_button("رجوع", _show_menu, box)
	var p = await supa.call_fn("player_profile", {p_name = name})
	if _screen != "profile" or not is_instance_valid(info):
		return
	if not (p is Dictionary):
		info.text = "ما گدرت أجيب الملف، تأكد من النت"
		return
	if name.to_lower() == player_name.to_lower():
		stats = p
	info.text = "الترتيب: #%d   -   زومبي: %d   -   هيدشوت: %d\nجولات: %d (فاز %d، جماعية %d)   -   الصعوبة: %.1f (أعلى %.1f)\nوقت اللعب: %s   -   آخر ظهور: %s   -   سجّل %s" % [
		int(p.rank), int(p.kills), int(p.headshots), int(p.rounds), int(p.wins), int(p.online_rounds), float(p.level), float(p.best_level),
		duration(int(p.play_seconds)), ago(str(p.last_seen)), ago(str(p.created_at))]
	var got: Array = p.get("achievements", [])
	_label("الإنجازات (%d/%d)" % [got.size(), ACHIEVEMENTS.size()], 24, ach, Color("#ffd23f"))
	for id in ACHIEVEMENTS:
		var a: Array = ACHIEVEMENTS[id]
		var have := got.has(id)
		_label(("[مفتوح] " if have else "[مقفول] ") + a[0] + " - " + a[1], 20, ach, Color("#7bd64a") if have else Color(1, 1, 1, 0.5))


# ════════ لوحة الأدمن (بس لك) ════════
func _show_admin() -> void:
	_screen = "admin"
	_stop_game()
	var box := _panel_box()
	_label("لوحة الأدمن", 40, box, Color("#c9a3ff"))
	var info := _label("...", 22, box, Color.WHITE, 900)
	var list := _scroll(box, 300, 900)
	var r := _row(box)
	_button("تحديث", _show_admin, r)
	_button("رجوع", _show_menu, r)
	var d = await supa.call_fn("admin_overview", {p_token = token})
	if _screen != "admin" or not is_instance_valid(info):
		return
	if not (d is Dictionary) or not d.get("ok", false):
		info.text = "ما عندك صلاحية (لازم حساب الأدمن يكون عليه رمز)"
		return
	info.text = "اللاعبين: %d   -   أونلاين هسه: %d   -   نشطين اليوم: %d\nجولات اليوم: %d (منها جماعية %d)   -   سيرفرات شغّالة هسه: %d" % [
		int(d.players_total), int(d.online_now), int(d.active_today), int(d.rounds_today), int(d.online_rounds_today), int(d.rooms_now)]
	for room in d.get("rooms", []):
		_label("سيرفر: %s (%d لاعبين) %s %s" % [room.name, int(room.players), "LAN" if room.lan else "أونلاين", "يلعبون" if room.status == "playing" else "باللوبي"], 20, list, Color("#4fc3f7"))
	if not d.get("gifts", []).is_empty():
		_label("آخر التبرعات:", 22, list, Color("#7bd64a"))
		for g in d.get("gifts", []):
			_label("%s ← %s : %d فلوس (%s)" % [g.to_name, g.from_name, int(g.amount), ago(str(g.at))], 20, list)
	_label("آخر اللاعبين:", 22, list, Color("#ffd23f"))
	for p in d.get("players", []):
		var t := "%s   |   %d زومبي   |   %d فلوس   |   %d جولة   |   صعوبة %.1f   |   لعب %s   |   %s   |   آخر ظهور %s" % [
			p.name, int(p.kills), int(p.get("coins", 0)), int(p.rounds), float(p.level), duration(int(p.play_seconds)), "برمز" if p.has_pin else "بدون رمز", ago(str(p.last_seen))]
		var b := _button(t, func(): _show_profile(str(p.name)), list)
		b.custom_minimum_size = Vector2(880, 46)
		b.add_theme_font_size_override("font_size", 18)


# ════════ اللعب ════════
func _start() -> void:
	_begin(Game3D.new(park, level, owned, weapon, {id = "me", name = player_name if player_name != "" else "أنا"}))


func _begin(g: Game3D) -> void:
	_screen = "game"
	_clear_ui()
	inp = Game3D.Inp.new()
	touch.inp = inp
	if game != null:
		game.queue_free() # الجولة اللي قبلها (من زر الجولة الجاية)
	game = g
	park.add_child(game)
	# زر الخروج (فوگ يسار تحت معلومات السلاح)
	var quit := _button("خروج", _quit_game, ui)
	quit.custom_minimum_size = Vector2(110, 44)
	quit.add_theme_font_size_override("font_size", 20)
	quit.position = Vector2(14, 112)
	hud.game = game
	hud.visible = true
	touch.visible = _use_touch
	_ended = false
	touch.hide_ids = ["jump", "shovel", "brick"]


func _view_w() -> float:
	return get_viewport().get_visible_rect().size.x


func _quit_game() -> void:
	if game != null:
		_save()
	if session != null:
		_leave_session()
		_show_lan()
	else:
		_show_menu()


func _show_end() -> void:
	_ended = true
	touch.visible = false
	var won := game.status == "won"
	var earned := game.earned()
	coins += earned
	var net := session != null
	var nxt := game.next_level()
	var new_ach := _achievements(won)
	# صعوبتي الشخصية تتغير بس باللعب لوحدي
	if not net:
		level = nxt
	_save()
	if online:
		_add_coins(earned)
		supa.call_fn("player_report", {p_token = token, p_kills = game.my_kills, p_headshots = game.my_headshots, p_seconds = int(game.time),
			p_level = game.level, p_next_level = level, p_won = won, p_online = net, p_achievements = new_ach})
		stats.kills = int(stats.get("kills", 0)) + game.my_kills
		stats.headshots = int(stats.get("headshots", 0)) + game.my_headshots
		stats.rounds = int(stats.get("rounds", 0)) + 1
		stats.achievements = (stats.get("achievements", []) as Array) + new_ach

	var box := _panel_box()
	_label("فزت بالجولة!" if won else "خسرت", 56, box, Color("#7bd64a") if won else Color("#e53935"))
	_label("+%d فلوس   -   قتلت %d زومبي (%d هيدشوت)   -   الوقت %d ثانية" % [earned, game.my_kills, game.my_headshots, int(game.time)], 24, box, Color("#ffd23f"))
	var diff := nxt - game.level
	_label("الصعوبة الجاية: %.1f  (%s%.1f)   -   أقل صحة: %d%%" % [nxt, "+" if diff >= 0 else "", diff, roundi(game.min_hp_avg() * 100)], 22, box)
	for id in new_ach:
		_label("إنجاز جديد: %s - %s" % ACHIEVEMENTS[id], 22, box, Color("#7bd64a"))
	if net:
		# LAN: المضيف يقرر شنو بعدها
		if session.is_host:
			_button("الجولة الجاية", func(): session.start(nxt), box, true)
			_button("اللوبي", func(): session.back_to_lobby(), box)
		else:
			_label("انتظار المضيف...", 24, box)
			_button("طلوع", _quit_game, box)
		return
	_button("الجولة الجاية", _start, box, true)
	_button("القائمة", _show_menu, box)


# إنجازات جديدة من هاي الجولة
func _achievements(won: bool) -> Array:
	if not online:
		return []
	var have: Array = stats.get("achievements", [])
	var kills := int(stats.get("kills", 0)) + game.my_kills
	var hs := int(stats.get("headshots", 0)) + game.my_headshots
	var rounds := int(stats.get("rounds", 0)) + 1
	var me := game.me()
	var check := {
		"first_blood": kills >= 1, "k100": kills >= 100, "k1000": kills >= 1000, "k5000": kills >= 5000, "hs100": hs >= 100,
		"flawless": won and not game.took_damage, "survivor": won and me.hp > 0 and me.hp / me.max_hp < 0.15,
		"fast": won and game.time < Config.expected_time(game.level) * 0.5,
		"lvl5": game.level >= 5, "lvl10": game.level >= 10, "lvl20": game.level >= 20,
		"lan": session != null, "r50": rounds >= 50,
	}
	var out := []
	for id in check:
		if check[id] and not have.has(id):
			out.append(id)
	return out


# ── كل إطار ──
func _process(delta: float) -> void:
	# نخبر السيرفر إنك موجود كل دقيقة (لآخر ظهور)
	if online:
		_touch_t += delta
		if _touch_t > 60:
			_touch_t = 0
			supa.call_fn("player_touch", {p_token = token})
	if game == null:
		_orbit += delta * 0.06
		var c := Vector3(cos(_orbit) * 24, 19, sin(_orbit) * 24)
		park.cam.position = c
		park.cam.look_at(Vector3.ZERO)
		return
	var dt := minf(delta, 1.0 / 30)
	if _shot != "" and session != null:
		inp.move = 0.4 if fmod(game.time, 4.0) < 2.0 else -0.4
		inp.fire = true
		inp.aim = 0.0 if inp.move > 0 else PI
	elif not _bench.is_empty():
		_bench_play(delta)
	elif _shot != "":
		_auto_play(delta)
	elif not _use_touch:
		_keyboard()
	if game == null:
		return
	game.step(inp, dt)
	for s in game.sounds:
		Sfx.play(s)
	game.sounds.clear()
	if session != null:
		_net_tick(delta)
	if game == null:
		return
	if game.status != "play" and game.end_t > 1.2 and not _ended:
		_show_end()



func _keyboard() -> void:
	var k := func(a: Key, b := KEY_NONE) -> bool: return Input.is_physical_key_pressed(a) or (b != KEY_NONE and Input.is_physical_key_pressed(b))
	inp.move = (1.0 if k.call(KEY_D, KEY_RIGHT) else 0.0) - (1.0 if k.call(KEY_A, KEY_LEFT) else 0.0)
	inp.move_v = Vector2(inp.move, (1.0 if k.call(KEY_S, KEY_DOWN) else 0.0) - (1.0 if k.call(KEY_W, KEY_UP) else 0.0)).normalized()
	inp.down = k.call(KEY_S, KEY_DOWN)
	var mouse_fire := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	inp.fire = mouse_fire or k.call(KEY_J)
	if _mouse_aim:
		inp.aim = game.aim_at_screen(get_viewport().get_mouse_position())
	else:
		inp.aim = null


func _unhandled_input(e: InputEvent) -> void:
	if game == null or _use_touch:
		return
	if e is InputEventMouseMotion or e is InputEventMouseButton:
		_mouse_aim = true
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_Q:
				inp.swap = true
			KEY_G:
				inp.throw = true
			KEY_R:
				inp.reload = true

			KEY_ESCAPE:
				_quit_game()
			KEY_SPACE:
				inp.throw = true


# ════════ LAN ════════
func _show_lan(msg := "") -> void:
	_screen = "lan"
	_stop_game()
	if player_name == "":
		player_name = "لاعب %d" % (randi() % 900 + 100)
	var box := _panel_box()
	_label("LAN - العب ويا اللي على نفس الواي فاي", 34, box, Color("#ffd23f"))
	_label("اسمك باللعب: " + player_name, 22, box)
	_lan_status = _label(msg, 22, box, Color("#ff8a80") if msg != "" else Color.WHITE)
	var btns := _row(box)
	_button("إنشاء سيرفر", _create_room, btns, true)
	_button("رجوع", _show_menu, btns)
	_label("السيرفرات بشبكتك:", 24, box)
	_rooms_box = VBoxContainer.new()
	_rooms_box.add_theme_constant_override("separation", 8)
	box.add_child(_rooms_box)
	_label("...", 22, _rooms_box)
	_refresh_rooms()


# قائمة السيرفرات تتحدث كل 3 ثواني وانت بهاي الشاشة
func _refresh_rooms() -> void:
	while _screen == "lan":
		var box := _rooms_box
		var rows = await supa.call_fn("list_rooms", {p_lan = true})
		if _screen != "lan" or box != _rooms_box or not is_instance_valid(box):
			return
		for c in box.get_children():
			c.queue_free()
		if not (rows is Array):
			_label("ما گدرت أجيب السيرفرات، تأكد من النت", 22, box, Color("#ff8a80"))
		elif rows.is_empty():
			_label("ماكو سيرفرات بشبكتك هسه. سوّي واحد أو انتظر صاحبك يسوي", 22, box, Color(1, 1, 1, 0.7))
		else:
			for r in rows:
				var info := "%s   (%d/%d)   %s" % [r.name, int(r.players), Session.MAX_PLAYERS, "يلعبون (صعوبة %d)" % int(r.stage) if r.status == "playing" else "باللوبي"]
				var b := _button(info, func(): _join_room(str(r.code)), box)
				b.custom_minimum_size = Vector2(560, 54)
				b.add_theme_font_size_override("font_size", 22)
		await get_tree().create_timer(3.0).timeout


func _new_session() -> Session:
	var s := Session.new()
	add_child(s)
	return s


func _create_room() -> void:
	if session != null:
		return
	if is_instance_valid(_lan_status):
		_lan_status.text = "دا أسوي السيرفر..."
	var s := _new_session()
	session = s
	s.level = level
	var err := await s.create(supa, player_name)
	if err != "":
		session = null
		_show_lan(err)
		return
	_wire_session()
	_show_lobby()


func _join_room(code: String) -> void:
	if session != null:
		return
	if is_instance_valid(_lan_status):
		_lan_status.text = "دا أدخل..."
	var s := _new_session()
	session = s
	var err := await s.join(supa, code, player_name)
	if err != "":
		session = null
		_show_lan(err)
		return
	_wire_session()
	if session.playing:
		_start_net(session.level)
	else:
		_show_lobby()


func _wire_session() -> void:
	var s := session
	s.roster_changed.connect(func():
		if _screen == "lobby":
			_show_lobby())
	s.started.connect(func(lv: float): _start_net(lv))
	s.to_lobby.connect(func(_lv: float): _show_lobby())
	s.state_msg.connect(func(m: Dictionary):
		if game != null and m.has("id"):
			game.apply_player_msg(m, s.who(str(m.id))))
	s.snap_msg.connect(func(snap: Dictionary):
		if game != null and not s.is_host:
			game.apply_snapshot(snap))
	s.closed.connect(func(why: String):
		session = null
		_show_lan(why))


func _leave_session() -> void:
	if session != null:
		session.leave()
		session = null


func _show_lobby() -> void:
	if session == null:
		return
	_screen = "lobby"
	_stop_game()
	var box := _panel_box()
	_label(session.room_name, 36, box, Color("#ffd23f"))
	_label("اللاعبين (%d/%d):" % [session.members.size(), Session.MAX_PLAYERS], 24, box)
	for m in session.members:
		var tag := " (المضيف)" if m.host else ""
		var me_tag := " - انت" if m.id == session.me.id else ""
		_label(m.name + tag + me_tag, 26, box, session.uniform_of(m.id).lightened(0.35))
	_label("الصعوبة: %.1f (تتغير تلقائياً حسب لعبكم)" % session.level, 22, box)
	if session.is_host:
		_button("ابدأ", func(): session.start(session.level), box, true)
	else:
		_label("انتظار المضيف يبدي...", 24, box, Color(1, 1, 1, 0.8))
	_button("طلوع", func():
		_leave_session()
		_show_lan(), box)


func _start_net(lv: float) -> void:
	if session == null:
		return
	var who := session.who(session.me.id)
	_show_notice("الـ LAN راح يرجع بالتحديث الجاي")


# نرسل حالتنا (والمضيف يرسل السنابشوت) كم مرة بالثانية
func _net_tick(delta: float) -> void:
	var r := session.rates()
	_send_st += delta
	if _send_st >= 1.0 / r[0]:
		_send_st = 0
		session.send_state(game.player_msg())
	if session.is_host:
		_send_snap += delta
		if _send_snap >= 1.0 / r[1]:
			_send_snap = 0
			session.send_snap(game.snapshot())
	# اللي طلعوا من السيرفر
	for p in game.players:
		if not p.local and not p.bot and session.index_of(p.id) < 0:
			game.remove_player(p.id)


# ════════ للفحص ════════
func _auto_play(delta: float) -> void:
	_shot_t += delta
	# يدور ويرمي على أقرب زومبي
	inp.move_v = Vector2.from_angle(_shot_t * 0.8) * 0.8
	var near = null
	for z in game.zs:
		if z.dead == 0 and (near == null or z.pos.distance_to(game.me().pos) < near.pos.distance_to(game.me().pos)):
			near = z
	inp.fire = near != null
	inp.aim = (near.pos - game.me().pos).angle() if near != null else null
	if _shot_t > 10.0:
		print("fps=", Engine.get_frames_per_second(), " zombies=", game.zs.size(), " kills=", game.my_kills, " hp=", game.me().hp)
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()


# بنچ: 14 ثانية بدون رمي (الزومبي يتجمعون لـ ~20) وبعدها 20 ثانية رمي + رمانات. اللاعب ما يموت.
func _bench_play(delta: float) -> void:
	var b := _bench
	if not game.loaded:
		return
	if b.t == 0.0:
		Perf.spikes.clear() # اللي صار وقت التحميل ما ينحسب
	b.t += delta
	var me := game.me()
	me.hp = me.max_hp
	inp.move_v = Vector2.from_angle(b.t * 0.5) * 0.5
	var near = null
	var alive := 0
	for z in game.zs:
		if z.dead == 0:
			alive += 1
			if near == null or z.pos.distance_to(me.pos) < near.pos.distance_to(me.pos):
				near = z
	var firing: bool = b.t > 14.0
	inp.fire = firing and near != null
	inp.aim = (near.pos - me.pos).angle() if near != null else null
	if firing and fmod(b.t, 2.5) < delta:
		inp.throw = true
	if b.t > 1.0:
		b.frames.append([delta * 1000.0, Perf.draw_calls(), alive, Perf.nodes(), firing])
	if b.t > 13.0 and not b.has("pic"):
		b.pic = get_viewport().get_texture().get_image() # تنحفظ بالآخر (الحفظ نفسه يعمل spike)
	if b.t > 20.0 and not b.has("pic2"):
		b.pic2 = get_viewport().get_texture().get_image() # وسط القتال
	if b.t < 34.0:
		return
	b.pic.save_png(b.shot)
	b.pic2.save_png(b.shot.replace(".png", "_fight.png"))
	var n := 0
	var ms := 0.0
	var dc := 0.0
	var dc_max := 0
	var over25 := 0
	var over33 := 0
	var worst := 0.0
	for f in b.frames:
		worst = maxf(worst, f[0])
		over25 += 1 if f[0] > 25 else 0
		over33 += 1 if f[0] > 33 else 0
		if f[2] >= 18:
			n += 1
			ms += f[0]
			dc += f[1]
			dc_max = maxi(dc_max, f[1])
	var peak := 0
	for f in b.frames:
		peak = maxi(peak, f[2])
	print("BENCH %s level=%.0f peak_alive=%d frames=%d" % [RenderingServer.get_current_rendering_method(), level, peak, b.frames.size()])
	if n > 0:
		print("BENCH with>=18 zombies: avg %.2f ms (%.0f fps)  draw calls avg %.0f max %d  nodes %d" % [ms / n, 1000.0 / (ms / n), dc / n, dc_max, Perf.nodes()])
	print("BENCH worst frame %.1f ms  frames>25ms: %d  frames>33ms: %d" % [worst, over25, over33])
	var sp: Array = Perf.spikes.duplicate()
	sp.sort_custom(func(x, y): return x[0] > y[0])
	for i in mini(8, sp.size()):
		print("BENCH spike %.1f ms | %s" % sp[i])
	get_tree().quit()


# جهازين يلعبون LAN لوحدهم ويحفظون صورة
func _auto_lan(host: bool) -> void:
	player_name = "مضيف" if host else "ضيف"
	if host:
		await _create_room()
		while session != null and session.members.size() < 2:
			await get_tree().process_frame
		await get_tree().create_timer(1.0).timeout
		session.start(level)
	else:
		var rows = []
		while not (rows is Array) or rows.is_empty():
			rows = await supa.call_fn("list_rooms", {p_lan = true})
			await get_tree().create_timer(1.0).timeout
		await _join_room(str(rows[0].code))
		while game == null:
			await get_tree().process_frame
	await get_tree().create_timer(10.0).timeout
	print("lan ", "host" if host else "client", ": players=", game.players.size(), " zombies=", game.zs.size(), " killed=", game.killed, " direct=", session.direct(), " my_kills=", game.my_kills)
	get_viewport().get_texture().get_image().save_png(_shot)
	_leave_session()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()


func _add_coins(amount: int) -> void:
	var r = await supa.call_fn("player_add_coins", {p_token = token, p_amount = amount})
	if r is Dictionary and r.get("ok", false):
		coins = int(r.coins)
		_save()


# ════════ التبرع ════════
# قائمة اللاعبين المسجلين، تختار واحد، وتختار كم تنطيه
func _show_gift(msg := "", query := "") -> void:
	_screen = "gift"
	_stop_game()
	var box := _panel_box()
	_label("تبرع لصديق", 40, box, Color("#7bd64a"))
	_label("فلوسك: %d   -   اختار اللاعب اللي تريد تنطيه" % coins, 22, box, Color("#ffd23f"))
	if msg != "":
		_label(msg, 22, box, Color("#7bd64a") if msg.begins_with("وصلت") else Color("#ff8a80"), 800)
	var r := _row(box)
	var search := _edit(query, r, 300)
	search.placeholder_text = "دوّر على اسم"
	_button("دوّر", func(): _show_gift("", search.text.strip_edges()), r)
	search.text_submitted.connect(func(t: String): _show_gift("", t.strip_edges()))
	var list := _scroll(box, 300, 760)
	_label("...", 22, list)
	_button("رجوع", _show_shop, box)
	var rows = await supa.call_fn("list_players", {p_query = query})
	if _screen != "gift" or not is_instance_valid(list):
		return
	for c in list.get_children():
		c.queue_free()
	if not (rows is Array):
		_label("ما گدرت أجيب الأسماء، تأكد من النت", 22, list, Color("#ff8a80"))
		return
	var shown := 0
	for p in rows:
		if str(p.name).to_lower() == player_name.to_lower():
			continue
		shown += 1
		var b := _button("%s     (%d زومبي، آخر ظهور %s)" % [p.name, int(p.kills), ago(str(p.last_seen))], func(): _show_gift_amount(str(p.name)), list)
		b.custom_minimum_size = Vector2(740, 50)
		b.add_theme_font_size_override("font_size", 21)
	if shown == 0:
		_label("ماكو لاعبين بهذا الاسم", 22, list)


func _show_gift_amount(to: String, msg := "") -> void:
	_screen = "gift_amount"
	_stop_game()
	var box := _panel_box()
	_label("تبرع لـ " + to, 40, box, Color("#7bd64a"))
	_label("فلوسك: %d" % coins, 24, box, Color("#ffd23f"))
	var status := _label(msg, 22, box, Color("#ff8a80"), 700)
	var r := _row(box)
	for amount in [50, 100, 500, 1000]:
		var b := _button(str(amount), func(): _gift(to, amount), r, false, Color("#1f7a5c"))
		b.custom_minimum_size = Vector2(130, 56)
		b.disabled = coins < amount
	var r2 := _row(box)
	_label("أو اكتب المبلغ:", 22, r2)
	var amt := _edit("", r2, 160)
	amt.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_button("أرسل", func():
		if not amt.text.is_valid_int() or int(amt.text) <= 0:
			status.text = "اكتب رقم صحيح"
			return
		_gift(to, int(amt.text)), r2, true)
	_button("رجوع", func(): _show_gift(), box)


func _gift(to: String, amount: int) -> void:
	if amount > coins:
		_show_gift_amount(to, "ما عندك هلكد فلوس")
		return
	var r = await supa.call_fn("player_gift", {p_token = token, p_to = to, p_amount = amount})
	if r is Dictionary and r.get("ok", false):
		coins = int(r.coins)
		_save()
		_show_gift("وصلت %d فلوس لـ %s" % [amount, to])
	else:
		var err := str(r.get("error", "")) if r is Dictionary else ""
		_show_gift_amount(to, {"coins": "ما عندك هلكد فلوس", "no_player": "اللاعب مو موجود", "self": "ما تكدر تتبرع لنفسك"}.get(err, "ما وصلت، تأكد من النت"))


func _show_notice(text: String) -> void:
	_screen = "notice"
	_stop_game()
	var box := _panel_box()
	_label(text, 30, box, Color("#ffd23f"), 800)
	_button("رجوع", _show_menu, box)
