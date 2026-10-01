class_name BuildingDef
extends Resource
## One building type. Edit the .tres files in res://data/buildings/ to rebalance.

@export var id := ""
@export var name := ""
@export var short := ""                 ## 2-4 letter label shown on the map
@export_enum("HQ", "Power", "Production", "Economy", "Defense") var category := "Production"
@export_multiline var description := ""
@export var hp := 20
@export var cost_alloy := 0
@export var cost_fuel := 0
@export var build_turns := 1
@export var power_supply := 0           ## power produced
@export var power_use := 0              ## power consumed
@export var territory := 1              ## hexes of territory around it
@export var vision := 2
@export var trains: Array[String] = []  ## unit ids it can train
@export var attack := 0.0               ## > 0: shoots enemies in range each turn
@export var attack_range := 0
@export var blocks_units := true
@export var buildable := true           ## false for the Home Base
@export var sort := 0
