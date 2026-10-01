class_name RulesDef
extends Resource
## Match-wide numbers. Edit res://data/rules.tres.

@export var map_radius := 5             ## hexagon map, radius in hexes
@export var start_alloy := 10
@export var start_fuel := 10
@export var hq_income_alloy := 2        ## trickle so nobody gets stuck
@export var hq_income_fuel := 1
@export var turn_seconds := 60
@export var turn_limit := 12            ## score decides after this many rounds
@export var unit_cap := 8               ## max units per player (keeps matches small)
@export var trees_share := 0.16         ## fraction of hexes with trees
@export var rocks_share := 0.12
@export var water_share := 0.05
@export var start_units: Array[String] = ["engineer", "rifleman"]
@export var start_buildings: Array[String] = ["power_plant", "barracks"]
