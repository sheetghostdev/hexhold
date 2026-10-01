class_name MatchLink
extends Node
## How a match screen reaches the authority. Three kinds:
##   AiLink    - the host runs in this app, the opponent is the computer
##   HostLink  - the host runs in this app, the opponent connects online
##   GuestLink - the host runs in the other player's browser
## The screen only uses this interface, so all three play the same way.

signal turn_started(rep: Dictionary)   # {events, view}: replay, then your turn (or game over)
signal updated(rep: Dictionary)        # new view without a replay
signal restarted(rep: Dictionary)      # a new match began (rematch)
signal status(text: String, bad: bool)

var me := 0


## Sends a command; returns {ok, error, events, view}. Awaitable.
func submit(_cmd: Dictionary) -> Dictionary:
	return {}


## Called after your end-turn has been played on screen.
func after_my_turn() -> void:
	pass


## Seconds left in the current turn, or -1 when there is no timer.
func time_left() -> float:
	return -1.0


func rematch() -> void:
	pass


func online() -> bool:
	return false


func opponent_name() -> String:
	return "Enemy"
