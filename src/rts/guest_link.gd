class_name GuestLink
extends MatchLink
## Online, and the match runs in the host's browser. Commands go over the
## network; the host answers with what we may see.

signal got_res(id: int, res: Dictionary)
signal started_first(rep: Dictionary)

var net: NetPeer
var my_name := "Player 2"
var host_name := "Player 1"
var next_id := 1
var deadline := 0
var has_timer := false
var last_view := {}
var playing := false
var waiting := {}


func _init(peer: NetPeer, name: String) -> void:
	net = peer
	my_name = name
	me = 1


func _ready() -> void:
	net.received.connect(_on_msg)
	net.opened.connect(func(): net.send({ "t": "hello", "name": my_name }))
	net.closed.connect(_on_closed)


func _on_closed() -> void:
	status.emit("Lost the connection to %s." % host_name, true)
	for id in waiting.keys():
		got_res.emit(id, { "ok": false, "error": "Connection lost", "events": [], "view": last_view })


func _timer(msg: Dictionary) -> void:
	var t := float(msg.get("time_left", -1.0))
	has_timer = t >= 0.0
	deadline = Time.get_ticks_msec() + int(t * 1000.0)


func time_left() -> float:
	if not has_timer:
		return -1.0
	return maxf(0.0, (deadline - Time.get_ticks_msec()) / 1000.0)


func online() -> bool:
	return true


func opponent_name() -> String:
	return host_name


func submit(cmd: Dictionary) -> Dictionary:
	var id := next_id
	next_id += 1
	if not net.send({ "t": "cmd", "id": id, "cmd": cmd }):
		return { "ok": false, "error": "Not connected", "events": [], "view": last_view }
	waiting[id] = true
	while true:
		var r: Array = await got_res
		if r[0] == id:
			waiting.erase(id)
			return r[1]
	return {}


func rematch() -> void:
	net.send({ "t": "rematch" })


func _on_msg(msg: Dictionary) -> void:
	var rep: Dictionary = msg.get("rep", {})
	if rep.has("view"):
		last_view = rep["view"]
		host_name = String(rep["view"]["players"][0]["name"])
	match msg.get("t", ""):
		"start":
			_timer(msg)
			if not playing:
				playing = true
				started_first.emit(rep)
			else:
				restarted.emit(rep)
		"res":
			var res: Dictionary = msg.get("res", {})
			if res.has("view"):
				last_view = res["view"]
			got_res.emit(int(msg.get("id", 0)), res)
		"turn":
			_timer(msg)
			turn_started.emit(rep)
		"update":
			_timer(msg)
			updated.emit(rep)
