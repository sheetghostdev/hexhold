class_name UnitDef
extends Resource
## One unit type. Edit the .tres files in res://data/units/ to rebalance.

@export var id := ""
@export var name := ""
@export_multiline var role := ""        ## one-line description shown in menus
@export var hp := 10
@export var attack := 2.0
@export var defense := 2.0
@export var move := 2                   ## hexes per turn on open ground
@export var attack_range := 1
@export var vision := 2
@export var cost_alloy := 0
@export var cost_fuel := 0
@export var train_turns := 1            ## turns until the unit can act
@export var vs_buildings := 1.0         ## damage multiplier against buildings
@export var abilities: Array[String] = []   ## "build", "clear"
@export var sort := 0
