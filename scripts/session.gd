# ════════ جلسة LAN (Supabase + WebRTC) ════════
# - جدول rooms بـ Supabase = قائمة السيرفرات. سيرفرات LAN تبين بس للي على نفس الشبكة (نفس الواي فاي).
# - كل سيرفر = قناة Realtime للتحكم (مين داخل، بدء المرحلة، الرجوع للوبي) وللتعارف بين الأجهزة.
# - بعد التعارف الأجهزة تتصل ببعض مباشرة (WebRTC) والحركة تمشي على الواي فاي بدون ما تطلع للنت.
#   إذا الاتصال المباشر ما اشتغل، الرسائل تمشي عبر Supabase تلقائياً.
# - المضيف هو الحكم: يحرّك الزومبي ويحسب الضرب والقتل، والباقين يحرّكون لاعبهم بس.
class_name Session
extends Node

signal roster_changed
signal started(stage: int)
signal to_lobby(stage: int)
signal state_msg(m: Dictionary) # حالة لاعب
signal snap_msg(s: Dictionary) # سنابشوت المضيف
signal closed(why: String)

const MAX_PLAYERS := 5
const UNIFORMS := [Color("#8a7d4f"), Color("#b59b6a"), Color("#4f6a8a"), Color("#6d6f73"), Color("#7a5a8a")]
const ICE := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302"]}]}
# كم رسالة بالثانية عبر Supabase حسب عدد اللاعبين (حد Supabase المجاني 100 رسالة/ثانية)
const RATES := {1: [1, 1], 2: [10, 10], 3: [6, 8], 4: [4, 6], 5: [3, 5]}
const DIRECT_RATE := [20, 20] # الاتصال المباشر ما عليه حد

var supa: Supa
var ch: Supa.Channel
var code := ""
var room_name := ""
var is_host := false
var me := {} # {id, name, host, joinedAt}
var members: Array = [] # مرتبين حسب وقت الدخول
var stage := 0
var playing := false
var token := ""
var peers := {} # id ← {pc, dc, pending}
var _saw_host := false
var _closed := false
var _beat := 0.0
var _known := {}


static func new_id() -> String:
	var chars := "abcdefghijklmnopqrstuvwxyz0123456789"
	var s := ""
	for i in 8:
		s += chars[randi() % chars.length()]
	return s


# ── إنشاء سيرفر (يرجع رسالة خطأ أو "") ──
func create(s: Supa, player_name: String) -> String:
	supa = s
	var rows = await supa.call_fn("create_room", {p_name = ("سيرفر " + player_name).left(40), p_lan = true})
	if not (rows is Array) or rows.is_empty():
		return "ما گدرت أسوي سيرفر، تأكد من النت"
	code = rows[0].code
	token = rows[0].token
	room_name = ("سيرفر " + player_name).left(40)
	is_host = true
	return await _connect(player_name)


# ── الانضمام لسيرفر ──
func join(s: Supa, room_code: String, player_name: String) -> String:
	supa = s
	var rows = await supa.call_fn("room_info", {p_code = room_code})
	if not (rows is Array) or rows.is_empty():
		return "السيرفر مو موجود أو انسد"
	var info: Dictionary = rows[0]
	if int(info.players) >= MAX_PLAYERS:
		return "السيرفر ممتلي (%d/%d)" % [MAX_PLAYERS, MAX_PLAYERS]
	code = info.code
	room_name = info.name
	is_host = false
	var err := await _connect(player_name)
	if err != "":
		return err
	# ننطي المضيف شوية وقت يبين
	for i in 30:
		if host_member() != null:
			break
		await get_tree().create_timer(0.15).timeout
	if host_member() == null:
		leave()
		return "السيرفر مو موجود أو انسد"
	if index_of(me.id) >= MAX_PLAYERS:
		leave()
		return "السيرفر ممتلي"
	return ""


func _connect(player_name: String) -> String:
	me = {id = new_id(), name = player_name, host = is_host, joinedAt = Time.get_unix_time_from_system()}
	ch = supa.channel("sp:" + code, me.id)
	ch.track(me)
	ch.presence_changed.connect(_on_presence)
	ch.broadcast.connect(_on_broadcast)
	ch.dropped.connect(func(): _close("انقطع الاتصال بالسيرفر"))
	var t := 0.0
	while not _in_roster() and t < 8.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	if not _in_roster():
		leave()
		return "الاتصال بطيء، حاول مرة ثانية"
	if is_host:
		_heartbeat()
	return ""


func _in_roster() -> bool:
	return ch != null and ch.presence.has(me.get("id", ""))


func host_member():
	for m in members:
		if m.get("host", false):
			return m
	return null


func index_of(id: String) -> int:
	for i in members.size():
		if members[i].id == id:
			return i
	return -1


func uniform_of(id: String) -> Color:
	return UNIFORMS[maxi(0, index_of(id)) % UNIFORMS.size()]


func name_of(id: String) -> String:
	var i := index_of(id)
	return members[i].name if i >= 0 else "لاعب"


func who(id: String) -> Dictionary:
	return {id = id, name = name_of(id), uniform = uniform_of(id)}


# هل كل الاتصالات مباشرة؟
func direct() -> bool:
	var others := members.filter(func(m): return m.id != me.id)
	if others.is_empty():
		return false
	if is_host:
		return others.all(func(m): return _open(m.id))
	var h = host_member()
	return h != null and _open(h.id)


func rates() -> Array:
	if direct():
		return DIRECT_RATE
	return RATES[clampi(members.size(), 1, MAX_PLAYERS)]


func _open(id: String) -> bool:
	var p = peers.get(id)
	return p != null and p.dc != null and p.dc.get_ready_state() == WebRTCDataChannel.STATE_OPEN


# ── قائمة اللاعبين ──
func _on_presence() -> void:
	members = ch.presence.values().map(func(m): return {id = str(m.get("id", "")), name = str(m.get("name", "لاعب")), host = bool(m.get("host", false)), joinedAt = float(m.get("joinedAt", 0))})
	members.sort_custom(func(a, b): return a.joinedAt < b.joinedAt if a.joinedAt != b.joinedAt else a.id < b.id)
	var h = host_member()
	if h != null:
		_saw_host = true
		# اللاعب يبدي الاتصال المباشر ويا المضيف
		if not is_host and not peers.has(h.id):
			_rtc_connect(h.id)
	elif _saw_host and not is_host:
		_close("المضيف طلع من السيرفر")
		return
	# اللي طلعوا: نسكّر اتصالهم المباشر
	for id in peers.keys():
		if index_of(id) < 0:
			_drop_peer(id)
	if is_host:
		for m in members:
			if _known.has(m.id) or m.id == me.id:
				continue
			_known[m.id] = true
			# اللي ينضم واللعب شغّال يدخل وياهم بنفس المرحلة
			if playing:
				ch.send("start", {stage = stage, to = m.id})
			else:
				ch.send("lobby", {stage = stage, name = room_name})
		_heartbeat()
	roster_changed.emit()


func _on_broadcast(event: String, p: Variant) -> void:
	if _closed or not (p is Dictionary):
		return
	match event:
		"st":
			state_msg.emit(p)
		"snap":
			snap_msg.emit(p)
		"rtc":
			_on_signal(p)
		"start":
			if p.has("to") and p.to != me.id:
				return
			stage = int(p.stage)
			playing = true
			started.emit(stage)
		"lobby":
			stage = int(p.stage)
			if p.has("name"):
				room_name = p.name
			playing = false
			to_lobby.emit(stage)
		"bye":
			_close("المضيف سكّر السيرفر")


# ── إرسال حالة اللعب ──
func send_state(m: Dictionary) -> void:
	_send("st", m)


func send_snap(s: Dictionary) -> void:
	if is_host:
		_send("snap", s)


# مباشرة للي متصل، والباقي (إذا أكو) عبر Supabase
func _send(event: String, payload: Dictionary, except := "") -> void:
	var need_cloud := false
	var msg := JSON.stringify({e = event, p = payload}).to_utf8_buffer()
	var targets := members.filter(func(m): return m.id != me.id and m.id != except) if is_host else members.filter(func(m): return m.host)
	for m in targets:
		if _open(m.id):
			peers[m.id].dc.put_packet(msg)
		else:
			need_cloud = true
	if need_cloud and except == "":
		ch.send(event, payload)


# ── WebRTC ──
func _peer(id: String):
	if peers.has(id):
		return peers[id]
	# WebRTC موجود جاهز بالمتصفح بس؛ غير هيج نكمل عبر Supabase
	if not OS.has_feature("web"):
		return null
	var pc := WebRTCPeerConnection.new()
	if pc.initialize(ICE) != OK:
		return null # الجهاز ما يدعم WebRTC: نكمل عبر Supabase
	var p := {pc = pc, dc = null, pending = []}
	peers[id] = p
	pc.session_description_created.connect(func(type: String, sdp: String):
		pc.set_local_description(type, sdp)
		_signal(id, type, {sdp = sdp}))
	pc.ice_candidate_created.connect(func(media: String, index: int, cname: String):
		_signal(id, "ice", {media = media, index = index, name = cname}))
	pc.data_channel_received.connect(func(dc: WebRTCDataChannel): p.dc = dc)
	p.logged = false
	return p


func _rtc_connect(host_id: String) -> void:
	var p = _peer(host_id)
	if p == null:
		return
	p.dc = p.pc.create_data_channel("game", {"ordered": false, "maxRetransmits": 0})
	p.pc.create_offer()


func _signal(to: String, kind: String, data: Dictionary) -> void:
	ch.send("rtc", {from = me.id, to = to, kind = kind, data = data})


func _on_signal(s: Dictionary) -> void:
	if s.get("to") != me.id:
		return
	var from: String = s.get("from", "")
	var data: Dictionary = s.get("data", {})
	match s.get("kind"):
		"offer":
			if not is_host:
				return
			_drop_peer(from)
			var p = _peer(from)
			if p == null:
				return
			p.pc.set_remote_description("offer", data.sdp) # الجواب ينصنع تلقائياً
			p.remote = true
			for c in p.pending:
				p.pc.add_ice_candidate(c.media, int(c.index), c.name)
			p.pending.clear()
		"answer":
			var p = peers.get(from)
			if p == null:
				return
			p.pc.set_remote_description("answer", data.sdp)
			p.remote = true
			for c in p.pending:
				p.pc.add_ice_candidate(c.media, int(c.index), c.name)
			p.pending.clear()
		"ice":
			var p = peers.get(from)
			if p == null:
				return
			if p.get("remote", false):
				p.pc.add_ice_candidate(data.media, int(data.index), data.name)
			else:
				p.pending.append(data)


func _drop_peer(id: String) -> void:
	var p = peers.get(id)
	if p == null:
		return
	peers.erase(id)
	if p.dc != null:
		p.dc.close()
	p.pc.close()


func _process(dt: float) -> void:
	if _closed:
		return
	for id in peers.keys():
		var p = peers[id]
		p.pc.poll()
		if p.pc.get_connection_state() == WebRTCPeerConnection.STATE_FAILED:
			_drop_peer(id)
			continue
		var dc = p.dc
		if dc == null:
			continue
		dc.poll()
		# نطبع بالـ console لمن الاتصال المباشر يشتغل (للفحص)
		if not p.logged and dc.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			p.logged = true
			print("LAN: اتصال مباشر (WebRTC) ويا ", name_of(id))
		while dc.get_available_packet_count() > 0:
			var m = JSON.parse_string(dc.get_packet().get_string_from_utf8())
			if not (m is Dictionary):
				continue
			if m.e == "st":
				state_msg.emit(m.p)
				# المضيف يوصّل حركة كل لاعب للباقين
				if is_host:
					_send("st", m.p, id)
			elif m.e == "snap":
				snap_msg.emit(m.p)
	if is_host:
		_beat += dt
		if _beat > 10:
			_heartbeat()


# ── المضيف يتحكم ──
func start(st: int) -> void:
	if not is_host:
		return
	stage = st
	playing = true
	ch.send("start", {stage = st})
	_heartbeat()
	started.emit(st)


func back_to_lobby(st := -1) -> void:
	if not is_host:
		return
	if st >= 0:
		stage = st
	playing = false
	ch.send("lobby", {stage = stage, name = room_name})
	_heartbeat()
	to_lobby.emit(stage)


func _heartbeat() -> void:
	_beat = 0
	if not is_host or token == "" or _closed:
		return
	supa.call_fn("room_heartbeat", {p_code = code, p_token = token, p_players = members.size(), p_status = "playing" if playing else "lobby", p_stage = stage})


func _close(why: String) -> void:
	if _closed:
		return
	leave()
	closed.emit(why)


func leave() -> void:
	if _closed:
		return
	_closed = true
	for id in peers.keys():
		_drop_peer(id)
	if ch != null:
		if is_host:
			ch.send("bye", {})
			if token != "":
				supa.call_fn("close_room", {p_code = code, p_token = token})
		ch.close()
	queue_free()
