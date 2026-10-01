class_name MatchHost
extends RefCounted
## The authority for a match. Players send commands; the host applies them
## and returns events. Today it runs inside the app (vs AI); in milestone 7
## the same host sits behind the network and filters events per player.

var m: MatchState


func _init(state: MatchState) -> void:
	m = state


func submit(p: int, cmd: Dictionary) -> Dictionary:
	return m.apply(p, cmd)


## Lets every computer player whose turn it is take its turn.
## Returns all events they produced.
func run_ai_turns() -> Array:
	var out: Array = []
	var guard := 0
	while m.winner < 0 and m.players[m.cur].ai and guard < 8:
		var before := m.events.size()
		MatchAI.play_turn(m)
		m.apply(m.cur, { "type": "end_turn" })
		out.append_array(m.events.slice(before))
		guard += 1
	return out
