class_name UpgradeDef
extends Resource
## One research option at the Home Base. Edit res://data/upgrades/*.tres.
## effects: {"<unit or building id>.<stat>": bonus}; "units.<stat>" = every unit.
## Stats: attack, defense, move, attack_range, vision, power_supply.

@export var id := ""
@export var name := ""
@export_multiline var description := ""
@export var cost_alloy := 0
@export var cost_fuel := 0
@export var turns := 2
@export var effects: Dictionary = {}
@export var sort := 0
