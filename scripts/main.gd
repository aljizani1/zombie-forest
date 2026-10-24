# ════════ الشاشة الرئيسية ════════
# القائمة (اختيار المرحلة + المتجر)، اللعب، الكاميرا، الكيبورد والماوس، ونهاية المرحلة.
# الحفظ: user://save.cfg (أعلى مرحلة مفتوحة، الفلوس، الأسلحة).
extends Node2D

const SAVE_PATH := "user://save.cfg"

var world := World.new()
var game: Game
var inp := Game.Inp.new()
var font: Font

var scenery: Node2D
var actors: Node2D
var cam: Camera2D
var hud: Control
var touch: Control
var ui: Control # القائمة أو شاشة النهاية

# الحفظ
var unlocked := 0
var coins := 0
var owned: Array = ["pistol"]
var weapon := "pistol"
var stage := 0

var _use_touch := false
var _mouse_aim := false
var _ended := false


func _ready() -> void:
	# خط Cairo العربي داخل اللعبة (المتصفح ما يعطي خطوط الجهاز)، وهو الخط الافتراضي بالمشروع كله
	font = load("res://fonts/cairo_bold.tres")
	print("text server: ", TextServerManager.get_primary_interface().get_name(), " | font ok: ", font != null, " | has alif: ", font.has_char(0x0627) if font else false)
	_load()

	scenery = preload("res://scripts/scenery.gd").new()
	add_child(scenery)
	scenery.setup(world)
	actors = preload("res://scripts/actors.gd").new()
	actors.font = font
	add_child(actors)

	cam = Camera2D.new()
	cam.limit_left = 0
	cam.limit_right = int(world.width)
	cam.limit_top = 0
	cam.limit_bottom = int(Config.AH)
	cam.anchor_mode = Camera2D.ANCHOR_MODE_FIXED_TOP_LEFT
	add_child(cam)
	cam.position = Vector2(world.start.x - 640, 0)

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

	_use_touch = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	_show_menu()
	# للفحص: يلعب لوحده شوية ويحفظ صورة الشاشة ويطلع
	var args := OS.get_cmdline_user_args()
	if args.has("--shot"):
		_shot = args[args.find("--shot") + 1] if args.size() > args.find("--shot") + 1 else "user://shot.png"
		if args.has("--stage"):
			stage = int(args[args.find("--stage") + 1])
		if args.has("--menu"):
			await get_tree().create_timer(1.5).timeout
			get_viewport().get_texture().get_image().save_png(_shot)
			get_tree().quit()
			return
		_start()


var _shot := ""
var _shot_t := 0.0


func _auto_play(delta: float) -> void:
	_shot_t += delta
	inp.move = 0.4 if fmod(_shot_t, 4.0) < 2.0 else -0.4
	inp.fire = true
	inp.aim = 0.0 if inp.move > 0 else PI
	if fmod(_shot_t, 1.5) < delta:
		inp.jump = 0.15
	if _shot_t > 8.0:
		print("HUD size=", hud.size, " pos=", hud.position, " vp=", get_viewport().get_visible_rect().size, " touch=", touch.size)
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()


# ── الحفظ ──
func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	unlocked = cf.get_value("save", "unlocked", 0)
	coins = cf.get_value("save", "coins", 0)
	owned = cf.get_value("save", "owned", ["pistol"])
	weapon = cf.get_value("save", "weapon", "pistol")
	stage = mini(unlocked, Config.STAGES.size() - 1)


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("save", "unlocked", unlocked)
	cf.set_value("save", "coins", coins)
	cf.set_value("save", "owned", owned)
	cf.set_value("save", "weapon", weapon)
	cf.save(SAVE_PATH)


# ── واجهة ──
func _clear_ui() -> void:
	for c in ui.get_children():
		c.queue_free()


func _button(text: String, cb: Callable, parent: Control, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 64)
	b.add_theme_font_size_override("font_size", 26)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#c62828") if primary else Color(0.15, 0.15, 0.17, 0.9)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(1, 1, 1, 0.8)
	sb.set_border_width_all(3)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _label(text: String, sz: int, parent: Control, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 8)
	parent.add_child(l)
	return l


func _panel_box() -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	return box


func _show_menu() -> void:
	game = null
	actors.game = null
	hud.game = null
	hud.visible = false
	touch.visible = false
	_clear_ui()
	var box := _panel_box()
	_label("زومبي الغابة", 64, box, Color("#ffd23f"))
	_label("الفلوس: %d" % coins, 26, box, Color("#ffd23f"))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var prev := _button("<", func(): _pick_stage(-1), row)
	prev.custom_minimum_size = Vector2(70, 64)
	var sl := _label("المرحلة %d" % (stage + 1), 32, row)
	sl.custom_minimum_size = Vector2(200, 0)
	var nxt := _button(">", func(): _pick_stage(1), row)
	nxt.custom_minimum_size = Vector2(70, 64)
	_button("ابدأ", _start, box, true)

	# المتجر
	var shop := HBoxContainer.new()
	shop.alignment = BoxContainer.ALIGNMENT_CENTER
	shop.add_theme_constant_override("separation", 12)
	box.add_child(shop)
	for w in Config.GUN_ORDER:
		var cfg: Dictionary = Config.WEAPONS[w]
		var text: String
		if not owned.has(w):
			text = "%s (%d)" % [cfg.name, cfg.price]
		elif weapon == w:
			text = "%s (مختار)" % cfg.name
		else:
			text = cfg.name
		var b := _button(text, func(): _shop(w), shop, weapon == w)
		b.custom_minimum_size = Vector2(200, 60)
		b.disabled = not owned.has(w) and coins < cfg.price


func _pick_stage(d: int) -> void:
	stage = clampi(stage + d, 0, mini(unlocked, Config.STAGES.size() - 1))
	_show_menu()


func _shop(w: String) -> void:
	if not owned.has(w):
		var price: int = Config.WEAPONS[w].price
		if coins < price:
			return
		coins -= price
		owned.append(w)
	weapon = w
	_save()
	_show_menu()


func _start() -> void:
	_clear_ui()
	inp = Game.Inp.new()
	touch.inp = inp
	game = Game.new(world, stage, owned, weapon)
	actors.game = game
	hud.game = game
	hud.visible = true
	touch.visible = _use_touch
	_ended = false
	cam.position.x = clampf(game.me().x + Game.PW / 2 - _view_w() / 2, 0, world.width - _view_w())


func _view_w() -> float:
	return get_viewport().get_visible_rect().size.x


func _show_end() -> void:
	_ended = true
	touch.visible = false
	var won := game.status == "won"
	var earned := game.earned()
	coins += earned
	if won:
		unlocked = maxi(unlocked, mini(stage + 1, Config.STAGES.size() - 1))
	_save()
	var box := _panel_box()
	_label("فزت!" if won else "خسرت", 60, box, Color("#7bd64a") if won else Color("#e53935"))
	_label("+%d فلوس" % earned, 30, box, Color("#ffd23f"))
	if won and stage < Config.STAGES.size() - 1:
		_button("المرحلة الجاية", func():
			stage += 1
			_start(), box, true)
	_button("إعادة", _start, box, not won)
	_button("القائمة", _show_menu, box)


# ── كل إطار ──
func _process(delta: float) -> void:
	if game == null:
		return
	var dt := minf(delta, 1.0 / 30)
	if _shot != "":
		_auto_play(delta)
	elif not _use_touch:
		_keyboard()
	game.step(inp, dt)
	game.sounds.clear()
	if game.status != "play" and game.end_t > 1.2 and not _ended:
		_show_end()

	# الكاميرا تلحق اللاعب
	var vw := _view_w()
	var target := clampf(game.me().x + Game.PW / 2 - vw / 2, 0, maxf(0, world.width - vw))
	cam.position.x += (target - cam.position.x) * minf(1.0, dt * 7)
	cam.offset = Vector2(randf_range(-0.5, 0.5), randf_range(-0.25, 0.25)) * game.shake * 30 if game.shake > 0 else Vector2.ZERO


func _keyboard() -> void:
	var k := func(a: Key, b := KEY_NONE) -> bool: return Input.is_physical_key_pressed(a) or (b != KEY_NONE and Input.is_physical_key_pressed(b))
	inp.move = (1.0 if k.call(KEY_D, KEY_RIGHT) else 0.0) - (1.0 if k.call(KEY_A, KEY_LEFT) else 0.0)
	inp.down = k.call(KEY_S, KEY_DOWN)
	var mouse_fire := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	inp.fire = mouse_fire or k.call(KEY_J)
	if _mouse_aim:
		var p := game.me()
		var chest := Vector2(p.x + Game.PW / 2, p.y + 40)
		inp.aim = (get_global_mouse_position() - chest).angle()
	else:
		inp.aim = null


func _unhandled_input(e: InputEvent) -> void:
	if game == null or _use_touch:
		return
	if e is InputEventMouseMotion or e is InputEventMouseButton:
		_mouse_aim = true
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_W, KEY_UP, KEY_SPACE:
				inp.jump = 0.15
			KEY_Q:
				inp.swap = true
			KEY_G:
				inp.throw = true
			KEY_R:
				inp.reload = true
			KEY_ESCAPE:
				_show_menu()
			KEY_A, KEY_D, KEY_LEFT, KEY_RIGHT:
				_mouse_aim = false
