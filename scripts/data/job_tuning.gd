class_name JobTuning
extends Resource
## The money and the phone: what a job pays, what mistakes cost, how often
## the work's a panel or a box, the van. The game uses res://data/job_tuning.tres:
## open it in the inspector and drag the sliders. Part prices are in
## res://data/parts/, one file each.

@export_group("Pay")
@export var starting_money := 150
## What every job pays before parts.
@export var call_out := 95
@export var labour := 110
## On top, for hanging a ceiling fan.
@export var fan_install_extra := 150
## On top, for each wafer light: layout, the hole, the pull and the splices.
@export var wafer_install_extra := 70

@export_group("Bonuses and penalties")
## Tested it dead before touching it.
@export var safe_bonus := 30
## Asked questions and measured volts and amps.
@export var thorough_bonus := 25
## First aid, per shock.
@export var shock_cost := 60
## Per arc flash or dead short.
@export var arc_cost := 120
## Water damage when you flood the laundry from the water heater.
@export var flood_cost := 400
## Real seconds the customer's gone to the hardware store for a part you couldn't afford.
@export var errand_seconds := 30.0
## The made-up price on the "your whole panel's shot" lie.
@export var scam_quote := 3400

@export_group("Dispatch")
## Calls kept waiting on the dispatch board. More means emergencies can
## jump the queue ahead of booked work. How often each kind of call comes up
## is its weight, in its own file in res://data/jobs/.
@export_range(1, 6, 1) var board_size := 2
## Chance, on a call, that the customer runs the kettle with the toaster and
## trips the kitchen counter breaker while you're there. Once a call at most.
@export_range(0, 100, 1, "suffix:%") var kitchen_overload_percent := 5.0
## Seconds before the first call of the day.
@export var first_job_delay := 4.0
## Seconds between finishing one job and the next call (longer with a bad rating).
@export var next_job_delay := 6.0
## While your license is suspended, how often dispatch checks again.
@export var suspended_retry := 15.0

@export_group("Shop")
@export var van_price := 2500
## What the supply house gives back on a return, of what you paid.
@export_range(0, 100, 1, "suffix:%") var return_percent := 90.0
## How close the vehicle has to be parked to the supply house to load it, in metres.
@export var supply_reach := 30.0

@export_group("Supply house credit")
## Five-star reviews you need (right now, not ever) before they'll open you an account.
@export_range(1, 500, 1) var credit_five_stars_needed := 50
## The most you can owe on the account.
@export var credit_limit := 1500
