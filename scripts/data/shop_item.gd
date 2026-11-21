class_name ShopItem
extends Resource
## Something you can order from TradesmanGear.com at the computer at home:
## truck gear, tools, safety gear. One file per item in res://data/shop/,
## editable in the inspector. It arrives the next morning and does what its
## `effect` says (see Upgrades).

@export var id := ""
@export var name := ""
## The small line under the name: "Low Profile, 71 in".
@export var sub := ""
## The site's menu: "Truck & Vehicle", "Tools", "Storage & Organization", "Workwear", "Safety".
@export var category := ""
@export var price := 0
## On sale: what it was. 0 if it isn't.
@export var was := 0
@export_range(0.0, 5.0, 0.1) var stars := 4.5
@export var reviews := 0
@export_multiline var description := ""

@export_group("What it does")
## "truck_space" (more room on the truck), "bag_slots" (a bigger job bag),
## "vehicle" (a new vehicle: `amount` unused, `vehicle` says which),
## "headlamp", "light_bar", "insulated_gloves", "work_boots".
@export var effect := ""
@export var amount := 0
@export var vehicle := ""
## The cheaper vehicle you trade up from can't be bought back once you've got the better one.
@export var buy_once := true

const DIR := "res://data/shop/"
## The site's menu, in order.
const CATEGORIES: Array[String] = ["Tools", "Power Tools", "Truck & Vehicle", "Storage & Organization", "Workwear", "Safety"]


static func of(id_: String) -> ShopItem:
	return load(DIR + id_ + ".tres")


## Every item, by id order of the files.
static func all() -> Array[ShopItem]:
	var out: Array[ShopItem] = []
	for file in DirAccess.get_files_at(DIR):
		file = file.trim_suffix(".remap")
		if file.ends_with(".tres"):
			out.append(of(file.get_basename()))
	out.sort_custom(func(a: ShopItem, b: ShopItem) -> bool: return a.category + a.name < b.category + b.name)
	return out
