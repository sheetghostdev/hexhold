class_name Help
extends RefCounted
## How-to-play text, shared by the menu and the in-game kingdom screen.

const SECTIONS := [
	["Goal", "Take every enemy town. (Or pick [b]Glory[/b] for a 30-turn game where the highest score wins.)"],
	["Gold", "Gold is the only thing you spend. Every town makes gold each turn, and bigger towns make more."],
	["Grow towns", "Tap a field, forest or hill inside your border and build a [b]farm[/b], [b]lumber hut[/b] or [b]mine[/b]. Each one adds [b]people[/b] to that town (the green bar under its name). When the bar is full the town [b]levels up[/b]: more gold, room for one more soldier, and you pick a reward."],
	["Soldiers", "Tap your town to train soldiers. Tap a soldier to see where it can move (white dots) and what it can hit (red targets, with the damage shown). Each soldier moves once and attacks once per turn. Knights can attack first and then ride away."],
	["New towns", "Walk a soldier into a grey village and it's yours. To take an enemy town, a soldier has to [b]start a turn[/b] standing on it, then tap Capture."],
	["Roads & walls", "Tap [b]Roads[/b] and drag to draw a road: moving road-to-road is twice as fast, and a road from a town to your capital gives +1 gold. Tap [b]Walls[/b] and drag to wall off a border: enemies can't pass, and your soldiers on walls defend twice as well."],
	["Castle", "Upgrade your keep from the [b]Castle[/b] button. Stone Keep unlocks swordsmen, knights, markets and towers; Castle unlocks catapults."],
	["Playing over Discord", "In a link game, end your turn and tap [b]Share to Discord[/b]. Whoever's turn it is taps the link, plays, and sends the next one. Nobody has to be online at the same time."],
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
