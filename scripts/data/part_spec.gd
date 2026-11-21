class_name PartSpec
extends Resource
## Something you can stock in the truck: what it's called, what the supply
## house charges, and how much room it takes. One file per part in
## res://data/parts/, editable in the inspector.

## The id jobs and boxes know it by: "breaker20", "GFCI", "Fan"...
@export var id := ""
@export var name := ""
@export var price := 0
## Room it takes up in the vehicle.
@export var size := 1
## For a breaker, its rating in amps; 0 for everything else.
@export var breaker_rating := 0
## Where it's shelved on the truck screen: "Devices", "Breakers", "Lighting"...
@export var category := ""
## A short name, for the job bag: "GFCI", "20 A breaker".
@export var short := ""
@export_multiline var description := ""

## The truck screen's shelves, in order.
const CATEGORIES: Array[String] = ["Devices", "Breakers", "Controls", "Lighting", "Life safety", "Water heater", "Boxes & cable"]

const DIR := "res://data/parts/"
## The order the supply house and the truck list them in.
const ORDER: Array[String] = ["breaker15", "breaker20", "breaker30", "Receptacle", "GFCI", "Switch", "Dimmer", "Range", "Fixture",
		"ThreeWay", "Fan", "Battery9V", "Smoke", "Element", "GardenHose", "OldWork", "Wafer", "Blank", "Romex", "GuardStrip"]


static func of(id_: String) -> PartSpec:
	return load(DIR + id_ + ".tres")


static func has(id_: String) -> bool:
	return id_ in ORDER


## Every part, in the order they're listed.
static func all() -> Array[PartSpec]:
	var out: Array[PartSpec] = []
	for id_ in ORDER:
		out.append(of(id_))
	return out


## The part id for a breaker of this rating: "breaker20".
static func breaker_id(rating: int) -> String:
	return "breaker%d" % rating


## What the supply house charges for a part, 0 if there's no such part.
static func price_of(id_: String) -> int:
	return of(id_).price if has(id_) else 0


func short_name() -> String:
	return short if short != "" else name
