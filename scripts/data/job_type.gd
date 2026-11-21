class_name JobType
extends ServiceCallDefinition
## A kind of job the phone can ring with: what the customer says, what's
## actually wrong, and where. One file per job in res://data/jobs/, editable
## in the inspector. "%s" in the lines is filled in with the room (device
## jobs) or the circuit and its appliance (panel jobs).

@export var kind := ""
## "panel" (a breaker), "device" (a box in the house), "heater" (the water
## heater), or "callback".
@export var family := "device"

@export_group("What they say")
## The one-line problem on the dispatch message and the job card.
@export_multiline var issue := ""
## Their first words when you knock.
@export_multiline var greeting := ""
@export_multiline var answer_when := ""
@export_multiline var answer_touched := ""
@export_multiline var answer_new := ""
## False for jobs where there's nothing to diagnose (a dimmer, a fan): you
## can only ask where the panel is.
@export var asks_questions := true

@export_group("What's wrong")
## Device jobs: which box gets the fault. "outlet" (a receptacle, GFCI or range
## outlet, by the job), "switch", "fixture", "switch3" (one of a 3-way pair),
## "junction" (in the attic), "smoke". Heater jobs: "heater", and the fault
## is a WaterHeater fault ("upper_element", "lower_element", "eco").
@export var box := ""
## The fault put on that box (ElectricalDevice conditions), or "" for none.
@export var box_fault := ""
## A light job in a particular room, or "" for any.
@export var room := ""
## The part the job's quoted on, for the payout on the card.
@export var quote_part := ""
## A part the customer bought themselves, that you fit for free, or "".
@export var customer_part := ""

const DIR := "res://data/jobs/"


static func of(kind_: String) -> JobType:
	return load(DIR + kind_ + ".tres")


## Every definition dispatch can choose (a weight above 0), sorted by id so
## the order never depends on the file system.
static func dispatchable() -> Array[JobType]:
	var out: Array[JobType] = []
	for file in DirAccess.get_files_at(DIR):
		file = file.trim_suffix(".remap")       # exported builds list "x.tres.remap"
		if file.ends_with(".tres"):
			var d := of(file.get_basename())
			if d.weight > 0.0:
				out.append(d)
	out.sort_custom(func(a: JobType, b: JobType) -> bool: return a.definition_id < b.definition_id)
	return out


## The answer to one of the customer questions: "when", "touched" or "new".
func answer(question: String) -> String:
	match question:
		"when":
			return answer_when
		"touched":
			return answer_touched
		"new":
			return answer_new
	return ""


## A line with its "%s" filled in, if it has one.
static func fill(line: String, with: Variant) -> String:
	return line % with if line.contains("%s") else line
