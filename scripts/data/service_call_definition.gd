class_name ServiceCallDefinition
extends Resource
## A reusable kind of call, as data. The resource says what it's called, who
## it can happen to, how often, and what the customer says; a generation
## strategy picks the real equipment and makes the problem (or the wish)
## real. Several definitions can share one strategy, and one definition can
## have several underlying causes.
##
## Add a call by adding a .tres in res://data/jobs/ with a weight: the
## generator picks it up, no code needed (unless it needs a new strategy).

@export var definition_id := ""
@export var title := ""
## "troubleshooting", "installation"...
@export var category := "troubleshooting"
@export_multiline var complaint_templates: Array[String] = []
@export_range(1, 5, 1) var difficulty := 1
@export var base_compensation := 0
@export var generation_strategy := ""
@export_multiline var objective_templates: Array[String] = []

@export_group("Dispatch")
## How often this call comes up, against the other definitions' weights.
## 0: never on its own (a callback, say).
@export_range(0, 100, 0.5) var weight := 0.0
## The kinds of property it can happen at: "residential" (commercial and
## industrial later).
@export var property_types: Array[String] = ["residential"]
## What the property has to have, by name (see ServiceCallSpecs): every one
## must hold. "name:argument" for ones that take an argument.
@export var eligibility: Array[String] = []
## What the business has to have done first (see ServiceCallSpecs), such as
## "min_five_stars:10". Every one must hold.
@export var prerequisites: Array[String] = []
## The real causes it can have, and how likely each is: a fault name the
## strategy knows -> weight. Empty: the strategy's one cause.
@export var causes: Dictionary = {}
## "emergency" (go now, any hour), "standard" (business hours) or
## "appointment" (booked for a time).
@export_enum("emergency", "standard", "appointment") var urgency := "standard"
## Game hours it stays on the board before the customer gives up on you.
@export var expires_after_hours := 8.0

@export_group("Estimates")
## About how long a competent electrician takes, for the dispatch board.
@export var labor_minutes := 60
## Parts the job usually needs (part ids, see res://data/parts/).
@export var materials: Array[String] = []


## Fills named fields without exposing the actual fault to the customer.
func complaint(template: String, values: Dictionary) -> String:
	var out := template
	for key: String in values:
		out = out.replace("{%s}" % key, str(values[key]))
	return out


## One of `causes`, picked by weight with `rng`, from those `allowed` (all if empty).
func pick_cause(rng: RandomNumberGenerator, allowed: Array = []) -> String:
	var total := 0.0
	for cause: String in causes:
		if allowed.is_empty() or cause in allowed:
			total += float(causes[cause])
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total
	for cause: String in causes:
		if allowed.is_empty() or cause in allowed:
			roll -= float(causes[cause])
			if roll < 0.0:
				return cause
	return ""
