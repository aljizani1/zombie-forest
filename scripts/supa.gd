# ════════ الاتصال بـ Supabase ════════
# - call_fn: نستدعي دوال قاعدة البيانات (إنشاء سيرفر، قائمة السيرفرات...) عبر HTTP.
# - Channel: قناة Realtime عبر WebSocket (مين داخل السيرفر + رسائل بين اللاعبين).
# نفس المشروع والدوال اللي تستعملها النسخة القديمة.
class_name Supa
extends Node

# مفاتيح عامة (مسموح تنحط باللعبة؛ الجدول محمي وما ينقرا إلا من الدوال)
const URL := "https://wyvandvmihjrrgtuatxn.supabase.co"
const KEY := "sb_publishable_ogbKVgx1dCxJWvMTfZQI1g_HJHRcXmq"


# يرجع الجواب (JSON) أو null إذا فشل
func call_fn(fn: String, args: Dictionary) -> Variant:
	var http := HTTPRequest.new()
	http.timeout = 10
	add_child(http)
	var err := http.request(URL + "/rest/v1/rpc/" + fn, PackedStringArray(["apikey: " + KEY, "Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(args))
	if err != OK:
		http.queue_free()
		return null
	var res: Array = await http.request_completed
	http.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] >= 300:
		return null
	var txt: String = (res[3] as PackedByteArray).get_string_from_utf8()
	if txt == "" or txt == "null":
		return true
	return JSON.parse_string(txt)


func channel(name: String, presence_key: String) -> Channel:
	var ch := Channel.new()
	add_child(ch)
	ch.open(name, presence_key)
	return ch


# ── قناة Realtime (بروتوكول Phoenix) ──
class Channel extends Node:
	signal joined
	signal broadcast(event: String, payload: Variant)
	signal presence_changed
	signal dropped

	var ws := WebSocketPeer.new()
	var topic := ""
	var key := ""
	var state := "closed" # connecting / joining / joined / closed
	var presence := {} # المفتاح ← بيانات اللاعب
	var _meta = null
	var _ref := 0
	var _join_ref := ""
	var _beat := 0.0

	func open(name: String, presence_key: String) -> void:
		topic = "realtime:" + name
		key = presence_key
		ws.inbound_buffer_size = 1 << 20
		ws.outbound_buffer_size = 1 << 20
		ws.connect_to_url(URL.replace("https://", "wss://") + "/realtime/v1/websocket?apikey=" + KEY + "&vsn=1.0.0")
		state = "connecting"

	func _next_ref() -> String:
		_ref += 1
		return str(_ref)

	func _send_raw(event: String, payload: Variant, t := topic) -> void:
		if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			return
		var msg := {topic = t, event = event, payload = payload, ref = _next_ref()}
		if t == topic and _join_ref != "":
			msg.join_ref = _join_ref
		ws.send_text(JSON.stringify(msg))

	# نعلن إحنا منو (يبين للكل بقائمة اللاعبين)
	func track(meta: Dictionary) -> void:
		_meta = meta
		if state == "joined":
			_send_raw("presence", {type = "presence", event = "track", payload = meta})

	func send(event: String, payload: Variant) -> void:
		if state == "joined":
			_send_raw("broadcast", {type = "broadcast", event = event, payload = payload})

	func close() -> void:
		if state == "closed":
			return
		if state == "joined":
			_send_raw("presence", {type = "presence", event = "untrack"})
			_send_raw("phx_leave", {})
		state = "closed"
		ws.close()
		queue_free()

	func _process(dt: float) -> void:
		if state == "closed":
			return
		ws.poll()
		var rs := ws.get_ready_state()
		if rs == WebSocketPeer.STATE_CLOSED:
			state = "closed"
			dropped.emit()
			queue_free()
			return
		if rs != WebSocketPeer.STATE_OPEN:
			return
		if state == "connecting":
			state = "joining"
			_join_ref = _next_ref()
			ws.send_text(JSON.stringify({topic = topic, event = "phx_join", ref = _join_ref, join_ref = _join_ref, payload = {
				config = {broadcast = {"self": false, "ack": false}, presence = {key = key, enabled = true}, postgres_changes = [], private = false},
			}}))
		_beat += dt
		if _beat > 25:
			_beat = 0
			_send_raw("heartbeat", {}, "phoenix")
		while ws.get_available_packet_count() > 0:
			var m = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if m is Dictionary:
				_handle(m)

	func _handle(m: Dictionary) -> void:
		if m.get("topic") != topic:
			return
		var p = m.get("payload", {})
		match m.get("event"):
			"phx_reply":
				if state == "joining" and m.get("ref") == _join_ref:
					if p is Dictionary and p.get("status") == "ok":
						state = "joined"
						if _meta != null:
							track(_meta)
						joined.emit()
					else:
						close()
						dropped.emit()
			"presence_state":
				presence.clear()
				for k in p:
					var metas: Array = p[k].get("metas", [])
					if metas.size():
						presence[k] = metas[0]
				presence_changed.emit()
			"presence_diff":
				for k in p.get("leaves", {}):
					presence.erase(k)
				var joins: Dictionary = p.get("joins", {})
				for k in joins:
					var metas: Array = joins[k].get("metas", [])
					if metas.size():
						presence[k] = metas[0]
				presence_changed.emit()
			"broadcast":
				if p is Dictionary:
					broadcast.emit(str(p.get("event", "")), p.get("payload"))
			"phx_close", "phx_error":
				state = "closed"
				ws.close()
				dropped.emit()
				queue_free()
