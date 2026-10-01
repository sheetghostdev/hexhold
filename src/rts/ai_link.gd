class_name AiLink
extends MatchLink
## You against the computer, all inside this app.

var host: MatchHost


func _init(state: MatchState) -> void:
	host = MatchHost.new(state)


func first_sync() -> Dictionary:
	return host.sync(me)


func submit(cmd: Dictionary) -> Dictionary:
	return host.submit(me, cmd)


func after_my_turn() -> void:
	host.run_ai_turns()
	turn_started.emit.call_deferred(host.sync(me))


func rematch() -> void:
	host = MatchHost.new(MatchGen.create({ "players": [
		{ "name": "You", "color": 0 }, { "name": "Enemy AI", "color": 1, "ai": true }] }))
	restarted.emit(host.sync(me))


func opponent_name() -> String:
	return "Enemy AI"
