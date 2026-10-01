class_name HostLink
extends MatchLink
## Online, and this browser is the host: it holds the true match, answers
## the guest's commands with only what the guest may know, and keeps the
## turn timer.

signal guest_joined

const GRACE_MS := 4000   # extra time before the host ends a silent guest's turn

var host: MatchHost
var net: NetPeer
var my_name := "Player 1"
var guest_name := "Player 2"
var started := false
var deadline := 0


func _init(peer: NetPeer, name: String) -> void:
	net = peer
	my_name = name
	me = 0


func _ready() -> void:
	net.received.connect(_on_msg)
	net.closed.connect(func(): status.emit("%s disconnected. Waiting for them to come back..." % guest_name, true))
	net.opened.connect(func(): if started: status.emit("%s is connected." % guest_name, false))


func _new_match() -> void:
	host = MatchHost.new(MatchGen.create({ "players": [
		{ "name": my_name, "color": 0 }, { "name": guest_name, "color": 1 }] }))
	started = true
	_reset_timer()


func first_sync() -> Dictionary:
	return host.sync(0)


func _reset_timer() -> void:
	deadline = Time.get_ticks_msec() + DB.rules.turn_seconds * 1000


func time_left() -> float:
	if not started or host.m.winner >= 0:
		return -1.0
	return maxf(0.0, (deadline - Time.get_ticks_msec()) / 1000.0)


func online() -> bool:
	return true


func opponent_name() -> String:
	return guest_name


func submit(cmd: Dictionary) -> Dictionary:
	var res := host.submit(0, cmd)
	if res["ok"]:
		_after(0, cmd)
	return res


func _after(p: int, cmd: Dictionary) -> void:
	var m := host.m
	if m.winner >= 0:
		if p == 0:
			_send_guest("turn")
		else:
			turn_started.emit(host.sync(0))
		return
	if cmd.get("type", "") != "end_turn":
		return
	_reset_timer()
	if m.cur == 1:
		_send_guest("turn")
	else:
		turn_started.emit(host.sync(0))


func _send_guest(kind: String) -> void:
	net.send({ "t": kind, "rep": host.sync(1), "time_left": time_left() })


func rematch() -> void:
	_new_match()
	net.send({ "t": "start", "rep": host.sync(1), "time_left": time_left(), "names": [my_name, guest_name] })
	restarted.emit(host.sync(0))


func _on_msg(msg: Dictionary) -> void:
	match msg.get("t", ""):
		"hello":
			guest_name = String(msg.get("name", "Player 2")).left(16)
			if not started:
				_new_match()
				guest_joined.emit()
			else:
				host.m.players[1].name = guest_name
			# (re)join: give the guest the full picture
			host._sent[1] = 0
			net.send({ "t": "start", "rep": host.sync(1), "time_left": time_left() })
		"cmd":
			if not started:
				return
			var cmd: Dictionary = msg.get("cmd", {})
			for k in cmd:
				if cmd[k] is float:
					cmd[k] = int(cmd[k])
			var res := host.submit(1, cmd)
			net.send({ "t": "res", "id": msg.get("id", 0), "res": res })
			if res["ok"]:
				_after(1, cmd)
		"rematch":
			if started and host.m.winner >= 0:
				rematch()


func _process(_delta: float) -> void:
	if not started or host.m.winner >= 0:
		return
	# the guest's clock runs out: the host ends their turn for them
	if host.m.cur == 1 and Time.get_ticks_msec() > deadline + GRACE_MS:
		host.submit(1, { "type": "end_turn" })
		_send_guest("update")
		_after(1, { "type": "end_turn" })
