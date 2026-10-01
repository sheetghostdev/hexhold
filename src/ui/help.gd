class_name Help
extends RefCounted
## How-to-play text, shared by the menu and the in-game kingdom screen.

const SECTIONS := [
	["The goal", "Conquer every enemy town. Or pick [b]Glory[/b] when starting a game: the highest score after the turn limit wins."],
	["Your turn", "Tap a unit to see where it can go (white dots) and what it can attack (red rings). Tap a red ring once to see the battle forecast, tap again to attack. Each unit can move once and attack once per turn. Then press [b]End turn[/b]."],
	["Roads", "Tap [b]Road[/b], then drag your finger across tiles to draw a road. Roads link up automatically. Moving road to road costs half, so armies travel twice as far. Linking a town to your capital by road opens a [color=#f6c445]trade route: +1 gold[/color] every turn. You can build roads in your own land or no-man's land, and bridges over water."],
	["Walls & towers", "Tap [b]Wall[/b] and drag to draw a wall, like in Stronghold. Enemies can't pass walls, but your own troops can stand on them for [b]double defence[/b], and archers on walls shoot one tile further. Towers (Stone Keep) also shoot the nearest enemy every turn. Catapults ignore walls and smash them quickly."],
	["Towns & food", "Towns make gold. Build [b]farms[/b] nearby: food makes towns grow, and bigger towns make more gold, support more troops, and at level 3 claim more land. Short on food? Throw a [b]feast[/b]: spend gold for +3 food. Move a unit onto a grey village to claim it. To take an enemy town, start your turn standing on it, then tap [b]Capture[/b]."],
	["Resources", "[color=#f6c445]Gold[/color] pays for troops, and every soldier costs 1 gold a turn in wages. [color=#d29a62]Wood[/color] comes from lumber camps, [color=#c9c3b6]stone[/color] from quarries on hills. Markets earn gold for every farm, camp, quarry or mine next to them, so plan your layout!"],
	["Your keep", "Upgrade your keep in the [b]Kingdom[/b] menu. Stone Keep unlocks swordsmen, knights, towers and markets. Castle unlocks catapults. You can also set taxes: harsh taxes give more gold but slow growth."],
	["Combat", "Damage depends on attack, defence and health. Forests, hills, towns and walls protect defenders. Spearmen are tough against knights. Survivors strike back if they can reach. Units with 3 kills become veterans with more health. Units that rest a turn heal."],
	["Ruins & bandits", "Explore [b]ancient ruins[/b] for treasure, maps or a free veteran. Bandit camps guard loot: defeat the bandit, then step into the camp."],
	["Playing with friends", "In a [b]link game[/b], when you end your turn you get a link. Tap [b]Share[/b] and pick Discord, or copy it and paste it in your chat. Whoever's turn it is opens the link, plays, and sends the next one. Nobody has to be online at the same time, and every game is also saved under [b]Continue[/b]."],
]


static func build() -> Control:
	var box := UI.vbox(18)
	for s in SECTIONS:
		var head := UI.label(s[0], "Heading")
		head.add_theme_font_size_override("font_size", 28)
		head.add_theme_color_override("font_color", UI.ACCENT)
		box.add_child(head)
		var body := UI.rich(s[1])
		body.add_theme_font_size_override("normal_font_size", 23)
		body.add_theme_font_size_override("bold_font_size", 23)
		box.add_child(body)
	return box
