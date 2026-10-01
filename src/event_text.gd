class_name EventText
extends RefCounted
## Turns logged events into friendly sentences for the turn summary.


static func _who(gs: GameState, p: int, viewer: int) -> String:
	if p < 0:
		return "[color=#c9a27a]Bandits[/color]"
	if p == viewer:
		return "[color=%s]You[/color]" % UI.color_hex(Defs.player_color(gs.players[p].color))
	return "[color=%s]%s[/color]" % [UI.color_hex(Defs.player_color(gs.players[p].color)), gs.players[p].name]


static func _whose(gs: GameState, p: int, viewer: int) -> String:
	if p < 0:
		return "a bandit"
	if p == viewer:
		return "your"
	return "%s's" % _who(gs, p, viewer)


static func _unit(t: int) -> String:
	return Defs.UNITS[t]["name"]


## Returns "" for events not worth showing to this viewer.
static func describe(gs: GameState, e: Array, viewer: int) -> String:
	var type: int = e[2]
	var a: Array = e.slice(3)
	match type:
		GameState.Ev.ATTACK:
			var att: int = a[0]
			var def: int = a[2]
			if att == viewer:
				return ""
			var s := "%s %s attacked %s %s for %d" % [_who(gs, att, viewer) if att >= 0 else "A bandit", "" if att < 0 else _unit(a[1]), _whose(gs, def, viewer), _unit(a[3]), a[4]]
			s = s.replace("  ", " ")
			if a[5] == 1:
				s += " [color=#ff7b72]and destroyed it[/color]"
			elif a[7] == 1:
				s += ", but [color=#7bd389]was destroyed in the counterattack[/color]"
			return s + "."
		GameState.Ev.CAPTURE:
			var p: int = a[0]
			var town: GameState.Town = gs.towns[a[1]] if a[1] < gs.towns.size() else null
			var tname := town.name if town else "a town"
			if a[2] == -1:
				if p == viewer:
					return ""
				return "%s claimed the village of %s." % [_who(gs, p, viewer), tname]
			return "%s [color=#ff7b72]captured %s[/color] from %s!" % [_who(gs, p, viewer), tname, _who(gs, a[2], viewer).replace("You", "you")]
		GameState.Ev.TOWER:
			if a[0] != viewer and a[1] != viewer:
				return ""
			var s := "%s tower shot %s %s for %d" % [_whose(gs, a[0], viewer).capitalize() if a[0] != viewer else "Your", _whose(gs, a[1], viewer), _unit(a[2]), a[3]]
			if a[4] == 1:
				s += " and destroyed it"
			return s + "."
		GameState.Ev.BANDIT:
			if a[0] != viewer:
				return ""
			var s := "Bandits ambushed your %s for %d" % [_unit(a[1]), a[2]]
			if a[3] == 1:
				s += " [color=#ff7b72]and killed it[/color]"
			return s + "."
		GameState.Ev.ELIMINATED:
			if a[0] == viewer:
				return "[color=#ff7b72]Your kingdom has fallen.[/color]"
			return "%s's kingdom [color=#ff7b72]has fallen[/color]!" % _who(gs, a[0], viewer)
		GameState.Ev.KEEP:
			if a[0] == viewer:
				return ""
			return "%s raised a %s." % [_who(gs, a[0], viewer), Defs.KEEP_NAMES[a[1]]]
		GameState.Ev.GROW:
			if a[0] != viewer:
				return ""
			var town: GameState.Town = gs.towns[a[1]]
			return "[color=#7bd389]%s grew to level %d![/color]" % [town.name, a[2]]
		GameState.Ev.STRUCT:
			if a[0] == viewer:
				return ""
			if a[1] != viewer:
				return ""
			if a[3] == 1:
				return "%s [color=#ff7b72]destroyed one of your walls[/color]." % _who(gs, a[0], viewer)
			return "%s battered your walls for %d." % [_who(gs, a[0], viewer), a[2]]
		GameState.Ev.WIN:
			if a[0] == viewer:
				return "[color=#f2b632]You are victorious![/color]"
			return "%s [color=#f2b632]has won the game![/color]" % _who(gs, a[0], viewer)
	return ""


static func summary(gs: GameState, viewer: int) -> Array[String]:
	var out: Array[String] = []
	if viewer < 0 or viewer >= gs.players.size():
		return out
	for e in gs.events_since(gs.players[viewer].seen_seq):
		var s := describe(gs, e, viewer)
		if s != "":
			out.append(s)
	return out
