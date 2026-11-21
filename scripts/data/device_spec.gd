class_name DeviceSpec
extends Resource
## What a kind of device is, electrically: which wires come into it, the
## terminals they can land on, and what it's for. Where those terminals sit on
## the model is presentation, and lives in BoxView.

@export var kind := ""
## "120" (plug), "240" (range), "switch", "ceiling" (light or fan), "jbox", "smoke".
@export var family := ""
## What it's called in sentences: "receptacle", "3-way switch"...
@export var word := ""
## The wires in the box and the terminal each lands on when it's done right.
## Order matters: it's the order the device looks for a source on a terminal.
@export var wires: Dictionary = {}
## Every terminal on the device, wired or not.
@export var terms: Array[String] = []
## Screws holding the cover plate on, and the device into the box.
@export var plate_screws := 0
@export var mounts := 2

static var _table := {}


static func of(kind_: String) -> DeviceSpec:
	if _table.is_empty():
		_build()
	return _table[kind_]


## Is this something that goes in a box? (A 9 V battery isn't.)
static func has(kind_: String) -> bool:
	if _table.is_empty():
		_build()
	return _table.has(kind_)


static func _add(kind_: String, family_: String, word_: String, wires_: Dictionary, terms_: Array[String], plate_screws_: int,
		mounts_ := 2) -> void:
	var s := DeviceSpec.new()
	s.kind = kind_
	s.family = family_
	s.word = word_
	s.wires = wires_
	s.terms = terms_
	s.plate_screws = plate_screws_
	s.mounts = mounts_
	_table[kind_] = s


static func _build() -> void:
	_add("Receptacle", "120", "receptacle", {"hot": "brass_top", "neutral": "silver_top", "ground": "green"},
			["brass_top", "brass_bottom", "silver_top", "silver_bottom", "green", "back_hot", "back_neutral"], 1)
	_add("GFCI", "120", "GFCI", {"hot": "line_brass", "neutral": "line_silver", "ground": "green"},
			["line_brass", "line_silver", "load_brass", "load_silver", "green"], 2)
	_add("Range", "240", "range receptacle", {"x": "x_lug", "y": "y_lug", "neutral": "w_lug", "ground": "g_lug"},
			["x_lug", "y_lug", "w_lug", "g_lug"], 2)
	_add("Switch", "switch", "switch", {"line": "s_top", "load": "s_bottom", "ground": "green"}, ["s_top", "s_bottom", "green"], 2)
	_add("Dimmer", "switch", "dimmer", {"line": "s_top", "load": "s_bottom", "ground": "green"}, ["s_top", "s_bottom", "green"], 2)
	_add("ThreeWay", "switch", "3-way switch", {"line": "common", "t1": "trav_a", "t2": "trav_b", "ground": "green"},
			["trav_a", "trav_b", "common", "green"], 2)
	_add("Fan", "ceiling", "ceiling fan", {"hot": "nut_black", "neutral": "nut_white", "ground": "f_ground"},
			["nut_black", "nut_white", "f_ground"], 0)
	# A wafer: the LED and its little snap-shut junction box on a flex lead.
	# Spring clips hold it in the drywall, so nothing screws it in.
	_add("Wafer", "ceiling", "wafer light", {"hot": "nut_black", "neutral": "nut_white", "ground": "f_ground"},
			["nut_black", "nut_white", "f_ground"], 0, 0)
	# A round blank on a ceiling box that's been spliced through: the light's
	# gone, the splices stay. Two screws hold the cover on.
	_add("Blank", "ceiling", "blank cover", {"hot": "nut_black", "neutral": "nut_white", "ground": "f_ground"},
			["nut_black", "nut_white", "f_ground"], 2, 0)
	_add("JBox", "jbox", "junction box", {"hot": "nut_hot", "hot_out": "nut_hot", "neutral": "nut_neutral", "neutral_out": "nut_neutral",
			"ground": "nut_ground", "ground_out": "nut_ground"}, ["nut_hot", "nut_neutral", "nut_ground"], 2, 0)
	_add("Smoke", "smoke", "smoke detector", {}, [], 0, 0)
	_add("Fixture", "ceiling", "light fixture", {"hot": "nut_black", "neutral": "nut_white", "ground": "f_ground"},
			["nut_black", "nut_white", "f_ground"], 0)
