class_name ObstacleDef
extends Resource
## Trees, rocks... Edit res://data/obstacles/*.tres to rebalance.

@export var id := ""
@export var name := ""
@export_enum("alloy", "fuel") var resource := "alloy"
@export var amount := 6                 ## resources inside the hex
@export var clear_turns := 2            ## engineer turns to clear it
@export var blocks_move := false
@export var defense_bonus := 1.0        ## for units standing in it
