class_name AftercareTuning
extends Resource
## Every number that decides what happens to a house after you drive away.
## The game uses res://data/aftercare_tuning.tres: open it in the Godot
## inspector and drag the sliders. Chances are percentages.

@export_group("Callbacks")
## Chance that a customer calls you back about a breaker tripping even though
## every circuit was left in perfect shape. 0 = good work never gets a callback.
@export_range(0, 100, 1, "suffix:%") var good_work_callback_percent := 10.0
## How many days of the customer's life get played out after each job.
@export_range(1, 7, 1) var days_played := 3

@export_group("Your mistakes coming back")
## Each day, chance that a box you left with a problem gets noticed and they call.
## (A box left dead or hanging out of the wall is always noticed on day one.)
@export_range(0, 100, 1, "suffix:%") var dead_box_callback_percent := 90.0
@export_range(0, 100, 1, "suffix:%") var burnt_wire_callback_percent := 12.0
@export_range(0, 100, 1, "suffix:%") var miswired_callback_percent := 5.0
@export_range(0, 100, 1, "suffix:%") var no_gfci_callback_percent := 3.0

@export_group("Inspections and fires")
## Chance an inspector visits a house where you left a code violation.
@export_range(0, 100, 1, "suffix:%") var inspection_percent := 35.0
## Fine per violation the inspector writes up.
@export var fine_per_violation := 150
## Each day an oversized breaker lets the wire run over its rating, chance the house catches fire.
@export_range(0, 100, 1, "suffix:%") var fire_percent := 25.0
@export var fire_fine := 5000
## How long your license is suspended after a fire.
@export var suspension_seconds := 240.0


## A roll of the dice: true `percent` % of the time.
static func roll(percent: float) -> bool:
	return randf() * 100.0 < percent
