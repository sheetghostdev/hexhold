class_name MatchHost
extends RefCounted
## The authority for a match. It alone holds the true MatchState.
## Players send commands; the host applies them and answers each player
## with only what that player may know: the events they saw and a view of
## the board (fog of war is enforced here, never left to the client).
## Today it runs inside the app (vs AI); in milestone 7 the same host sits
## behind the network.

var m: MatchState
var _sent := {}   # player -> last event seq sent to them


func _init(state: MatchState) -> void:
	m = state


## {ok, error, events, view} for player p after their command.
func submit(p: int, cmd: Dictionary) -> Dictionary:
	var r := m.apply(p, cmd)
	var out := sync(p)
	out["ok"] = r["ok"]
	out["error"] = r["error"]
	return out


## Everything new for player p: {events, view}.
func sync(p: int) -> Dictionary:
	var evs := m.events_for(p, _sent.get(p, 0))
	_sent[p] = m.seq
	return { "events": evs, "view": m.to_view(p) }


## Lets every computer player whose turn it is take its turn (on the true
## state, through the same commands as everyone else).
func run_ai_turns() -> void:
	var guard := 0
	while m.winner < 0 and m.players[m.cur].ai and guard < 8:
		MatchAI.play_turn(m)
		m.apply(m.cur, { "type": "end_turn" })
		guard += 1
