class_name Hints
extends RefCounted
## Context-sensitive tips: "what should I do now?" in one sentence.


static func next(gs: GameState, p: int) -> String:
	var pl := gs.players[p]
	var my_units := gs.player_units(p)
	var idle := 0
	for u in my_units:
		if not u.moved and not u.fresh and not u.attacked:
			idle += 1
	var towns := gs.player_towns(p)
	var vis := gs.visible_for(p)

	# danger first
	for t in towns:
		for o in gs.units:
			if o.owner >= 0 and o.owner != p and vis[o.idx] and gs.dist(o.idx, t.idx) <= 2:
				return "[b]Enemies near %s![/b] Train defenders there, or draw [b]Walls[/b] to block the way." % t.name

	if gs.turn == 1 and idle > 0:
		return "Tap your [b]soldier[/b], then a [b]white dot[/b] to move. Walk into [b]grey villages[/b] to claim them."

	for t in towns:
		var has_building := false
		for j in gs.tiles_in_range(t.idx, gs.town_radius(t)):
			if gs.claim[j] > 0 and gs.towns[gs.claim[j] - 1] == t and gs.building[j] != Defs.B.NONE:
				has_building = true
				break
		if not has_building and pl.gold >= 2:
			return "Grow [b]%s[/b]: tap a field, forest or hill inside your border and build. Buildings add [b]people[/b], and a full town levels up." % t.name

	if pl.gold >= 3 and my_units.size() < mini(3, gs.unit_cap(p)):
		for t in towns:
			if gs.unit_on(t.idx) == null:
				return "Tap your town [b]%s[/b] to train more soldiers." % t.name

	if idle > 0:
		for t in gs.towns:
			if t.owner == -1 and vis[t.idx]:
				return "Grey villages are free: walk a soldier into [b]%s[/b] to claim it." % t.name

	if pl.keep == 1 and pl.gold >= Defs.KEEP_COST[2]:
		return "You can afford a [b]Stone Keep[/b]: tap [b]Castle[/b] to unlock knights, swordsmen and towers."

	if gs.turn >= 3 and gs.turn <= 6 and towns.size() >= 2 and gs.connected_towns(p).is_empty():
		return "Tip: tap [b]Roads[/b] and drag from a town to your capital. Roads double movement and give [b]+1 gold[/b] per linked town."
	return ""
